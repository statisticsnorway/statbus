package cmd

import (
	"context"
	"fmt"
	"os/exec"
	"path/filepath"
	"runtime"
	"time"

	"github.com/statisticsnorway/statbus/cli/internal/install"
	"github.com/statisticsnorway/statbus/cli/internal/upgrade"
)

// dispatchInstallState runs the terminal-state dispatch for runInstall.
// Returns (handled, err): handled=true means the caller should return err
// immediately (either the error or nil on success); handled=false means
// the state has no terminal dispatch and runInstall should fall through
// to acquireOrBypass + the step-table.
//
// Called twice in runInstall: once on the initial Detect result, and a
// second time after runCrashRecovery re-detects the state. Keeping the
// dispatch logic in one place avoids duplicating the error strings across
// the two call sites.
func dispatchInstallState(projDir string, state install.State, detail *install.Detail) (bool, error) {
	switch state {
	case install.StateLiveUpgrade:
		if detail.Flag != nil {
			return true, fmt.Errorf("upgrade in progress (PID %d, %s, started %s); wait for it to finish or re-run './sb install' if the process is dead",
				detail.Flag.PID, detail.Flag.Label(), detail.Flag.StartedAt.Format(time.RFC3339))
		}
		return true, fmt.Errorf("upgrade in progress; wait or re-run './sb install'")
	case install.StateScheduledUpgrade:
		return true, runInlineUpgradeScheduled(projDir, detail)
	case install.StateLegacyNoUpgradeTable:
		return true, fmt.Errorf("pre-1.0 install detected (public.upgrade table absent). Automatic upgrade from pre-1.0 is not yet implemented (tracked as #65.6). Contact support or follow the manual upgrade path in doc/CLOUD.md")
	}
	return false, nil
}

// runInlineUpgradeScheduled dispatches StateScheduledUpgrade through the
// same executeUpgrade pipeline the upgrade service uses. It is called from
// runInstall when install.Detect finds a pending scheduled row.
//
// The scheduled row is claimed atomically inside ExecuteUpgradeInline (UPDATE
// with state='scheduled' guard). If a running upgrade service's scheduled
// picker won the race between install.Detect and this call, the claim
// returns zero rows affected and this function surfaces a clear error — the
// operator can re-run ./sb install once the other path finishes.
//
// This path does NOT acquire the install flag-lock. executeUpgrade writes
// its own HolderService flag internally before any destructive step,
// serialising against any concurrent ./sb install or service via the kernel
// flock on tmp/upgrade-in-progress.json.
func runInlineUpgradeScheduled(projDir string, detail *install.Detail) error {
	ctx := context.Background()
	svc := upgrade.NewService(projDir, true /* verbose */, version, commit)
	defer svc.Close()

	if err := svc.LoadConfigAndConnect(ctx); err != nil {
		return fmt.Errorf("load upgrade config: %w", err)
	}

	fmt.Printf("Dispatching scheduled upgrade id=%d to %s (commit %s)\n",
		detail.ScheduledRowID, detail.TargetDisplayName,
		upgrade.ShortForDisplay(detail.TargetCommitSHA))

	if err := svc.ExecuteUpgradeInline(ctx, int(detail.ScheduledRowID), detail.TargetCommitSHA, detail.TargetDisplayName); err != nil {
		return err
	}
	restartUpgradeService(projDir)
	return nil
}

// restartUpgradeService kicks the systemd upgrade-service unit after a
// successful inline upgrade so the long-running service loads the new binary
// and migrations. Without this, the running service keeps the pre-upgrade
// code in memory (R3) until someone restarts it manually.
//
// Best-effort: non-Linux, non-systemd, and missing-instance cases are silent
// no-ops. If the service is not currently active we do NOT start it — an
// operator may have stopped it deliberately, and `./sb install` should not
// resurrect it. Restart errors log a warning but do not fail the install.
func restartUpgradeService(projDir string) {
	if runtime.GOOS != "linux" {
		return
	}
	instance := serviceInstance(projDir)
	if instance == "" {
		return
	}
	if err := exec.Command("systemctl", "--user", "is-active", "--quiet", instance).Run(); err != nil {
		return // not active — leave it alone
	}
	fmt.Printf("Restarting upgrade service %s to pick up new binary/migrations.\n", instance)
	if err := exec.Command("systemctl", "--user", "restart", instance).Run(); err != nil {
		fmt.Printf("Warning: systemctl --user restart %s failed: %v (upgrade succeeded; restart the service manually)\n", instance, err)
	}
}

// runCrashRecovery reconciles a crashed upgrade (StateCrashedUpgrade).
// The dead PID's kernel flock was released automatically by fd teardown;
// the on-disk JSON at tmp/upgrade-in-progress.json survives as the
// audit/reconciliation cue. RecoverFromFlag reads that JSON, updates the
// corresponding public.upgrade row to its terminal state, and removes
// the flag file. Safe to call concurrently — idempotent on a missing
// flag.
//
// After recovery the caller MUST re-run install.Detect before dispatching:
// recovery may have surfaced a freshly-scheduled row, restored the
// previous version on disk, or left the install otherwise consistent.
//
// PART 1 (engineer audit task #3 Q3): the looping upgrade unit must be
// stopped before recovery. NO/rune wedged because the systemd unit's
// auto-restart kept re-running the SAME flag-resume loop every ~2 min;
// even with the dead PID's flock released, the next restart re-acquired
// it and re-tripped the same WatchdogSec on archiveBackup. Recovery
// invoked by `./sb install` must STOP that loop so we can take the flock
// uncontested, do the work outside WatchdogSec, and then hand the unit
// back ONLY if it was enabled to begin with.
//
// PART 2 (engineer audit Q3 / scenarios 21+27): the prior in-flight
// upgrade can legitimately leave the db container stopped (preswap
// backup's volume rsync needs pg quiesced; post-swap intermediate state
// before applyPostSwap brings it back). On that legitimate state,
// EnsureDBReachable refuses with a category-3 diagnostic — but the right
// move is to `docker compose start db` the EXISTING container (not
// recreate it via `up -d`, which is still forbidden per rc.66 → rc.67)
// and retry. Refusal stays reserved for the "container is gone or stays
// unreachable after start" case, which IS the operator-investigate path.
func runCrashRecovery(projDir string) error {
	ctx := context.Background()
	svc := upgrade.NewService(projDir, true /* verbose */, version, commit)
	defer svc.Close()

	// PART 1: stop the looping upgrade unit before any recovery work.
	// stopRestartUpgradeUnit captures is-enabled, runs `systemctl --user
	// stop` + `reset-failed`, and returns a closure that restarts the
	// unit iff it was enabled when we entered. The closure is deferred
	// to fire only on successful recovery (no-op on early return errors)
	// so a failed recovery does not resurrect the unit into another loop.
	var restartIfEnabled func()
	recovered := false
	if runtime.GOOS == "linux" {
		instance := serviceInstance(projDir)
		if instance != "" {
			restartIfEnabled = stopRestartUpgradeUnit(instance)
			defer func() {
				if recovered && restartIfEnabled != nil {
					restartIfEnabled()
				}
			}()
		}
	}

	// Regenerate .env from .env.config so current-binary-expected keys
	// (e.g. COMMIT_SHORT added in rc.62) are present before EnsureDBReachable,
	// which uses .env's connection settings to verify the DB is reachable.
	sb := filepath.Join(projDir, "sb")
	if err := runCmdDir(projDir, sb, "config", "generate"); err != nil {
		return fmt.Errorf("crash recovery: regenerate config: %w", err)
	}

	// PART 2: connect-first, start-existing-on-fail, retry.
	//
	// Connect-only check (rc.67 trifecta fix). Operator-driven recovery
	// MUST NOT touch the container set with `docker compose up -d` — the
	// operator's binary's compose template may reference a different
	// image-tag scheme than what's actually running, so `up -d` would
	// silently swap the DB container to the operator's binary's image,
	// destroying resumePostSwap's containersAtFlagTarget self-heal
	// precondition. (Pre-rc.67 used EnsureDBUp here; that's the bug class
	// jo's 2026-04-28 deploy exposed.)
	//
	// But `docker compose start db` is the asymmetric-safe action: it
	// ONLY starts an existing stopped container — it never creates or
	// recreates. So on the legitimate "in-flight upgrade stopped db"
	// state (scenarios 21, 27), we can resume the container as-it-was
	// without touching its image tag. If the container is GONE (operator
	// `docker rm`-d it, or scenario diverged further), start errors
	// "no such service" and we fall through to EnsureDBReachable's
	// category-3 refusal — the real operator-investigate path.
	if err := svc.EnsureDBReachable(ctx); err != nil {
		fmt.Printf("crash recovery: DB not reachable, attempting `docker compose start db` (existing container, no recreate)…\n")
		if startErr := svc.StartDBForRecovery(ctx); startErr != nil {
			return fmt.Errorf("crash recovery: %w (start fallback: %v)", err, startErr)
		}
		if err := svc.EnsureDBReachable(ctx); err != nil {
			return fmt.Errorf("crash recovery: %w", err)
		}
	}

	// Schema-skew guard (rc.65 structural fix). Mirrors Service.Run() —
	// bring the schema to HEAD before any RecoverFromFlag query touches
	// public.upgrade. Without this, recoveryRollback's SELECT on a
	// renamed column (rc.63 commit_canonical_naming migration) fires
	// SQLSTATE 42703 against an unmigrated schema. Idempotent.
	if err := runCmdDir(projDir, sb, "migrate", "up", "--verbose"); err != nil {
		return fmt.Errorf("crash recovery: boot migrate up: %w", err)
	}

	if err := svc.LoadConfigAndConnect(ctx); err != nil {
		return fmt.Errorf("load upgrade config: %w", err)
	}
	if err := svc.RecoverFromFlag(ctx); err != nil {
		return fmt.Errorf("crash recovery: %w", err)
	}
	recovered = true
	return nil
}

// stopRestartUpgradeUnit is Part 1's primitive. It STOPS the (looping)
// upgrade unit and returns a closure that restarts it iff it was enabled
// at entry. Callers defer the closure to fire only on successful
// recovery — see runCrashRecovery.
//
// Why this exists separately from restartUpgradeService: restart() is
// is-active-gated (line 92) and would no-op after our stop. We need an
// unconditional explicit start, conditional only on the captured
// is-enabled state. Operators who deliberately disabled the unit see no
// surprise resurrection; operators who simply had it running get their
// loop replaced by a single clean start at the end.
//
// All errors are logged + swallowed — recovery itself is the load-bearing
// path; systemd plumbing is best-effort observability around it.
func stopRestartUpgradeUnit(instance string) func() {
	wasEnabled := exec.Command("systemctl", "--user", "is-enabled", "--quiet", instance).Run() == nil
	fmt.Printf("Crash recovery: stopping upgrade unit %s (was-enabled=%v) before reconciliation.\n", instance, wasEnabled)
	if err := exec.Command("systemctl", "--user", "stop", instance).Run(); err != nil {
		fmt.Printf("Warning: systemctl --user stop %s failed: %v (recovery proceeding)\n", instance, err)
	}
	if err := exec.Command("systemctl", "--user", "reset-failed", instance).Run(); err != nil {
		// reset-failed is a hygiene call; failure is harmless.
		fmt.Printf("Note: systemctl --user reset-failed %s: %v\n", instance, err)
	}
	if !wasEnabled {
		return func() {
			fmt.Printf("Crash recovery: upgrade unit %s was not enabled at entry — leaving it stopped.\n", instance)
		}
	}
	return func() {
		fmt.Printf("Crash recovery: restarting upgrade unit %s (explicit start; restartUpgradeService is is-active-gated and would no-op here).\n", instance)
		if err := exec.Command("systemctl", "--user", "start", instance).Run(); err != nil {
			fmt.Printf("Warning: systemctl --user start %s failed: %v (recovery succeeded; restart the service manually)\n", instance, err)
		}
	}
}

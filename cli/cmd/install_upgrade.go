package cmd

import (
	"context"
	"fmt"
	"os/exec"
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
				detail.Flag.PID, detail.Flag.DisplayName, detail.Flag.StartedAt.Format(time.RFC3339))
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

	shortSHA := detail.TargetCommitSHA
	if len(shortSHA) > 12 {
		shortSHA = shortSHA[:12]
	}
	fmt.Printf("Dispatching scheduled upgrade id=%d to %s (commit %s)\n",
		detail.ScheduledRowID, detail.TargetDisplayName, shortSHA)

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
func runCrashRecovery(projDir string) error {
	ctx := context.Background()
	svc := upgrade.NewService(projDir, true /* verbose */, version, commit)
	defer svc.Close()

	// The crashed flag may have Phase=post_swap, meaning the DB is
	// intentionally stopped (applyPostSwap step 2 stopped it for the
	// consistent backup; step 9 on the new binary is what restarts it —
	// but we never reached that step if the prior process died mid-flow).
	// LoadConfigAndConnect needs a reachable DB to query public.upgrade,
	// so start it here. Idempotent when the DB is already up (the
	// non-post-swap crash path).
	if err := svc.EnsureDBUp(ctx); err != nil {
		return fmt.Errorf("ensure DB up for crash recovery: %w", err)
	}

	if err := svc.LoadConfigAndConnect(ctx); err != nil {
		return fmt.Errorf("load upgrade config: %w", err)
	}
	svc.RecoverFromFlag(ctx)
	return nil
}

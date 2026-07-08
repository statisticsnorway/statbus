package cmd

import (
	"context"
	"fmt"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"time"

	"github.com/statisticsnorway/statbus/cli/internal/install"
	"github.com/statisticsnorway/statbus/cli/internal/migrate"
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
	if runtime.GOOS == "linux" {
		// Unit name for the per-dispatch NRestarts reset (STATBUS-039
		// review finding 2) — the inline path resets too, so the takeover
		// gate counts only the current upgrade on every dispatch route.
		svc.SetUnitInstance(serviceInstance(projDir))
	}

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
// it and re-tripped the same WatchdogSec on the resumed upgrade. Recovery
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
			restartIfEnabled = stopRestartUpgradeUnit(projDir, instance)
			defer func() {
				if recovered && restartIfEnabled != nil {
					restartIfEnabled()
				}
			}()
		}
	}

	// Restore the target working tree before config-generate + boot-migrate,
	// for FORWARD recovery phases ONLY (post_swap / resuming) — mirror
	// Service.Run's gate (STATBUS-060 + STATBUS-061 part ii). executeUpgrade
	// defers the target checkout to the recovery boot so the OLD binary never
	// materializes target-compose; on the inline syscall.Exec resume the tree
	// may still be the source's. A forward resume needs the target tree BEFORE
	// config-generate (emits target keys) and BEFORE boot-migrate-up below
	// (schema-skew guard). Idempotent if already at target; git checkout errors
	// on a bad ref. flag.CommitSHA is the upgrade target.
	//
	// A PreSwap flag is GATED OUT: it rolls back, and the rollback's
	// restoreGitState owns the tree (→ OLD). Checking out the target here would
	// advance the tree forward and make the boot-migrate below apply the TARGET
	// migrations to a DB about to be rolled back (git=OLD + schema=TARGET skew).
	if flag, _, ferr := upgrade.ReadFlagFile(projDir); ferr == nil && flag.IsServiceForwardRecovery() {
		if err := runCmdDir(projDir, "git", "-c", "advice.detachedHead=false", "checkout", flag.CommitSHA); err != nil {
			return fmt.Errorf("crash recovery: git checkout target %s: %w", upgrade.ShortForDisplay(flag.CommitSHA), err)
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

	// Connect FIRST — moved ahead of the boot migrate (STATBUS-044 comment #6). Both
	// the un-park below and RecoveryBudgetGuard need a live DB connection, and both
	// must run BEFORE the boot migrate so a boot-migrate death self-counts against the
	// crash-resume budget (the r12 window where resume-time migrations actually run).
	if err := svc.LoadConfigAndConnect(ctx); err != nil {
		return fmt.Errorf("load upgrade config: %w", err)
	}
	// STATBUS-046 (architect option (a) + pin 1): `./sb install` is one of the two
	// deliberate un-park triggers. A PARKED row stays in_progress with its flag on
	// disk, so recovery reaches here — but resumePostSwap would SKIP it
	// (parked-skip) without this. Un-park (clear the marker + reset the death
	// budget) BEFORE the boot migrate + RecoverFromFlag so the deliberate resume
	// proceeds with a FRESH budget (and the guard below re-counts from 1). PARKED-ONLY:
	// a crashed-but-not-parked row keeps its count (so install-driven crash cycles
	// still park). Row-update only — never touches the flag handshake; RecoverFromFlag
	// keeps sole flag ownership. A self-resume never runs this path, so the machine
	// never un-parks itself.
	if flag, _, ferr := upgrade.ReadFlagFile(projDir); ferr == nil && flag != nil && flag.Holder == upgrade.HolderService && flag.ID != 0 {
		// HARD-FAIL on error (STATBUS-046): the operator's deliberate ./sb install
		// must never silently no-op into a still-parked row that resumePostSwap
		// then skips — that would strand the box. An actionable stop is the correct
		// fail-fast.
		unparked, oldReason, uerr := svc.UnparkByID(ctx, flag.ID)
		if uerr != nil {
			return fmt.Errorf("crash recovery: could not clear the park marker for upgrade id=%d: %w — "+
				"if this upgrade is parked, install cannot resume it; fix DB access and re-run ./sb install", flag.ID, uerr)
		}
		if unparked {
			reason := oldReason
			if reason == "" {
				reason = "(no reason recorded)"
			}
			fmt.Printf("crash recovery: UN-PARKED upgrade id=%d (was parked: %s) — ./sb install grants ONE fresh attempt with a reset budget.\n", flag.ID, reason)
			// STATBUS-044 comment #6 (architect F2): UnparkByID reset the ROW's
			// recovery_attempts, but the flag's frozen Step + PriorDeathStep survive on
			// disk — a same-step-twice park would otherwise INSTA-RE-PARK the fresh
			// attempt at attempts==1, breaking the "one fresh attempt" contract. Clear
			// the flag's death history too (the unit is quiesced here → flock free).
			if cerr := svc.ClearFlagStepHistory(); cerr != nil {
				fmt.Printf("crash recovery: warning — could not clear the flag's death history for upgrade id=%d after un-park: %v (a fresh attempt may re-park via same-step-twice; re-run ./sb install)\n", flag.ID, cerr)
			}
		}
	}

	// STATBUS-044 comment #6 — count the crash-resume attempt BEFORE the boot migrate
	// and stamp StepBootMigrate on the flag so a death IN the boot migrate self-counts
	// (mirrors Service.Run). For a still-PARKED row it returns skip=true and we do NOT
	// re-run the killer migration; here the un-park above normally cleared the marker,
	// so the guard continues with the fresh budget. No-op (false) when there is no
	// service-held forward-recovery flag.
	skipBootMigrate := svc.RecoveryBudgetGuard(ctx)

	// Schema-skew guard (rc.65 structural fix). Mirrors Service.Run() —
	// bring the schema to HEAD before any RecoverFromFlag query touches
	// public.upgrade. Without this, recoveryRollback's SELECT on a
	// renamed column (rc.63 commit_canonical_naming migration) fires
	// SQLSTATE 42703 against an unmigrated schema. Idempotent.
	//
	// Bounded by the shared migrate timeout (STATBUS-012). The inline path
	// has no systemd watchdog (no NOTIFY_SOCKET → sdNotify no-ops), so the
	// gap here was UNBOUNDEDNESS: runCmdDir had no timeout at all.
	//
	// STATBUS-145: `--to DaemonSchemaFloor` — the crash-recovery boot-migrate
	// catches the schema up only to the daemon floor, NOT to HEAD. Pre-145 it
	// carried the full delta (post-swap exec hands off to a fresh `./sb install`
	// whose crash-recovery lands here); under 145 the delta runs at the guarded
	// applyPostSwap step. The operator's DELIBERATE install still applies
	// everything — the step-table Migrations step (cmd/install.go) stays apply-all;
	// only this crash-recovery pre-step is bounded to the floor. On timeout the
	// operator gets an actionable error; the conn is live now (LoadConfigAndConnect
	// ran above) but this path does not #14-terminate an orphan — the orphan
	// self-resolves on client-gone, or the next service start's boot-migrate
	// timeout handler reaps it.
	if !skipBootMigrate {
		if err := runCmdDirTimeout(projDir, upgrade.MigrateUpTimeout, sb, "migrate", "up", "--to", strconv.FormatInt(migrate.DaemonSchemaFloor, 10), "--verbose"); err != nil {
			// STATBUS-017: symmetric to service.go's boot-migrate-up handler. A
			// service-held in-progress flag means the guard can't re-apply the
			// half-applied migration; defer to RecoverFromFlag (snapshot restore) below
			// instead of aborting crash recovery — aborting here boot-loops the
			// operator's `./sb install`. Keep the refuse for the no-flag / install-held
			// case (no recovery owner / no snapshot to restore).
			if flag, _, ferr := upgrade.ReadFlagFile(projDir); ferr == nil && flag != nil && flag.Holder == upgrade.HolderService {
				fmt.Printf("crash recovery: boot migrate up failed but a service-held flag is present "+
					"(id=%d, phase=%q) — deferring to RecoverFromFlag (STATBUS-017): %v\n", flag.ID, flag.Phase, err)
				// fall through to svc.RecoverFromFlag below
			} else {
				return fmt.Errorf("crash recovery: boot migrate up: %w", err)
			}
		}
	}

	if err := svc.RecoverFromFlag(ctx); err != nil {
		recoveryErr := fmt.Errorf("crash recovery: %w", err)
		// STATBUS-147: a re-park on this deliberate un-park path is SAFE (the
		// parked-skip in RecoveryBudgetGuard + resumePostSwap makes every future
		// boot alive-idle by construction, unlike a genuinely broken recovery,
		// which must not resurrect a crash loop) and NECESSARY (the eventual fix
		// release can only arrive via schedule → NOTIFY → daemon claim, which
		// cannot happen with the unit down — the 144 argument verbatim: a dead
		// daemon can repair nothing). Re-read the park state — the flag survives
		// a park untouched, so its ID is still valid — and restart anyway when
		// parked; a non-park failure keeps the conservative no-restart arm below.
		// install's own non-zero exit is unchanged either way: the attempt did fail.
		if flag, _, ferr := upgrade.ReadFlagFile(projDir); ferr == nil && flag != nil && flag.ID != 0 {
			parked, parkReason, perr := svc.UpgradeParkedReason(ctx, flag.ID)
			if shouldRestartAfterFailedRecovery(parked, perr) {
				fmt.Printf("crash recovery: upgrade %d re-parked (%s) — restarting the upgrade daemon alive-idle regardless: parked-skip makes every boot safe by construction, and the daemon must stay reachable to claim the eventual fix release.\n", flag.ID, parkReason)
				recovered = true
			}
		}
		return recoveryErr
	}
	recovered = true
	return nil
}

// shouldRestartAfterFailedRecovery is runCrashRecovery's STATBUS-147 decision,
// extracted pure so both branches are unit-testable without a live daemon/DB:
// restart the quiesced upgrade unit despite RecoverFromFlag's error ONLY when
// the row is genuinely PARKED (parked-skip makes every future boot alive-idle
// by construction) and the park-state read itself succeeded. Any other case —
// not parked, or the read failed — keeps the conservative no-restart arm: a
// genuinely broken recovery must not resurrect a crash loop.
func shouldRestartAfterFailedRecovery(parked bool, parkStateReadErr error) bool {
	return parkStateReadErr == nil && parked
}

// stopRestartUpgradeUnit is Part 1's primitive. It QUIESCES the (possibly
// looping) upgrade unit SIGKILL-class and returns a closure that restarts
// it iff it was enabled at entry. Callers defer the closure to fire only
// on successful recovery — see runCrashRecovery.
//
// SIGKILL-class, never SIGTERM (STATBUS-039 safe takeover). `systemctl
// stop` sends SIGTERM, and an in-flight upgrade process — old binary or
// new — catches TERM, cancels the upgrade context, and ROLLS BACK
// (postSwapFailure → rollback → restore). The unit's TimeoutStopSec=15min
// exists precisely because stop→rollback→pg_restore is real (a prior rune
// incident). The window is live even on the crashed-upgrade path: between
// install.Detect (flock free, dead RestartSec window) and this call, the
// unit can respawn and be seconds into a resume. SIGKILL runs no handlers
// — the crash-only architecture (flag + kernel flock release, aside-rename
// backups, atomic tars, transactional row writes) makes it safe by design;
// rune absorbed ~10k watchdog SIGABRTs over 18 days with zero data loss
// precisely because nothing rolled back.
//
// Sequence (race-free under mask; TIMING-BOUNDED if mask fails — see the
// invariant below):
//  1. capture is-enabled (BEFORE mask — a masked unit reports "masked").
//  2. mask --runtime: a masked unit cannot start, so Restart=always cannot
//     respawn between our kill and stop. Runtime-scoped: self-clears on
//     reboot, so a crashed takeover can never leave the box permanently
//     unable to run its upgrade service.
//  3. kill --signal=SIGKILL: whole-cgroup kill (KillMode default), no
//     handlers run, kernel releases the flock on fd teardown.
//  4. poll MainPID==0 (≤10s): verify actually dead before touching state.
//  5. stop: nothing is alive to signal — this only cancels any pending
//     auto-restart job and lands the unit administratively inactive.
//  6. reset-failed: clears the failure state + NRestarts counter.
//  7. unmask: the unit is startable again — but nothing starts it until
//     the returned closure (or the operator) does.
//
// TIMING-BOUNDED invariant for the mask-FAILED fallback (not structural —
// STATBUS-039 review): without the mask, a respawn fires RestartSec after
// the kill, and the trailing stop would SIGTERM it. Safety then rests on
// RestartSec (30s, ops/statbus-upgrade.service) exceeding the kill→poll→
// stop window (≤10s) — the pending respawn never fires before stop cancels
// it. Anyone shortening RestartSec below ~10s voids this bound. Defense in
// depth only: the correctness serializer against a concurrent destructive
// restore is the recoveryRollback flock gate (finding 3), which holds
// regardless of mask/stop/timing.
//
// Why this exists separately from restartUpgradeService: restart() is
// is-active-gated and would no-op after our quiesce. We need an
// unconditional explicit start, conditional only on the captured
// is-enabled state. Operators who deliberately disabled the unit see no
// surprise resurrection; operators who simply had it running get their
// loop replaced by a single clean start at the end.
//
// All errors are logged + swallowed — recovery itself is the load-bearing
// path; systemd plumbing is best-effort observability around it.
func stopRestartUpgradeUnit(projDir, instance string) func() {
	wasEnabled := exec.Command("systemctl", "--user", "is-enabled", "--quiet", instance).Run() == nil

	// Diagnostic WHO for the audit log. PID/Holder is DIAGNOSTIC ONLY — liveness
	// is decided by the flock below, never by the PID (service.go:241-244).
	who := instance
	if flag, _, ferr := upgrade.ReadFlagFile(projDir); ferr == nil && flag != nil {
		who = fmt.Sprintf("%s (holder=%s, pid=%d, started=%s)", instance, flag.Holder, flag.PID, flag.StartedAt.Format(time.RFC3339))
	}
	fmt.Printf("Crash recovery: quiescing upgrade unit %s SIGKILL-class (was-enabled=%v) before reconciliation — never SIGTERM (TERM triggers the in-flight upgrade's rollback handler).\n", who, wasEnabled)
	if err := exec.Command("systemctl", "--user", "mask", "--runtime", instance).Run(); err != nil {
		fmt.Printf("Warning: systemctl --user mask --runtime %s failed: %v (proceeding — quiesce is then TIMING-BOUNDED: safe while RestartSec(30s) > kill→stop window(≤10s); the recoveryRollback flock gate covers correctness regardless)\n", instance, err)
	}
	if err := exec.Command("systemctl", "--user", "kill", "--signal=SIGKILL", instance).Run(); err != nil {
		// Factual: the kill command returned non-zero. This does NOT establish
		// liveness — kill can fail on a unit-name miss / dbus error, or because
		// the unit was already inactive. Death is confirmed via the flock below,
		// not from this exit status.
		fmt.Printf("Note: systemctl --user kill -s SIGKILL %s returned: %v (liveness confirmed below via the flock, not this exit status)\n", instance, err)
	}
	// Confirm the holder is actually gone via the AUTHORITATIVE signal: the
	// kernel flock on the upgrade flag file (IsFlockHeld). The kernel releases it
	// the instant the killed holder's fd is torn down, so a free flock means no
	// live upgrade — the same signal Detect (state.go) and recoveryRollback
	// (service.go) key on. Race-free and PID-reuse-immune, unlike a pidAlive/proc
	// check (which the service's post-swap PID survival makes unreliable —
	// service.go:784-789). OBSERVER, not gate: if the flock is still held at the
	// deadline we narrate loudly and PROCEED — recoveryRollback's flock gate is
	// the single authoritative serializer and yields rather than risk a
	// concurrent destructive restore, so correctness holds either way (and
	// halting here would force operator investigation, against the
	// unattended-self-heal goal).
	if confirmUpgradeDeathViaFlock(projDir, flockConfirmTimeout) {
		fmt.Printf("Crash recovery: confirmed dead — upgrade flock on %s released; proceeding with takeover.\n", instance)
	} else {
		fmt.Printf("WARNING: upgrade flock STILL HELD %s after SIGKILL of %s — the upgrade holder may still be alive (%s). Proceeding anyway: recoveryRollback's flock gate is the authoritative serializer and will yield rather than risk a concurrent destructive restore; if recovery then yields, investigate the surviving process.\n", flockConfirmTimeout, instance, who)
	}
	if err := exec.Command("systemctl", "--user", "stop", instance).Run(); err != nil {
		// Nothing alive to signal — stop here only cancels a pending
		// auto-restart job and lands the unit inactive.
		fmt.Printf("Warning: systemctl --user stop %s failed: %v (recovery proceeding)\n", instance, err)
	}
	if err := exec.Command("systemctl", "--user", "reset-failed", instance).Run(); err != nil {
		// reset-failed is a hygiene call; failure is harmless.
		fmt.Printf("Note: systemctl --user reset-failed %s: %v\n", instance, err)
	}
	if err := exec.Command("systemctl", "--user", "unmask", "--runtime", instance).Run(); err != nil {
		fmt.Printf("Warning: systemctl --user unmask --runtime %s failed: %v (a reboot clears the runtime mask)\n", instance, err)
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

// flockConfirmTimeout bounds how long the quiesce waits for the SIGKILL'd
// upgrade holder's kernel flock to be released (matches the prior MainPID-poll
// budget). flockConfirmPollInterval is the poll cadence.
const (
	flockConfirmTimeout      = 10 * time.Second
	flockConfirmPollInterval = 500 * time.Millisecond
)

// confirmUpgradeDeathViaFlock polls the AUTHORITATIVE upgrade flock until it is
// released or `timeout` elapses. Returns true iff the flock was observed FREE
// within the window — the killed holder's fd torn down by the kernel ⇒ no live
// upgrade. This is the same signal Detect (upgrade.IsFlockHeld) and
// recoveryRollback (acquireFlock) key on: race-free and PID-reuse-immune (a
// recycled PID cannot inherit a dead holder's flock), unlike a pidAlive/proc
// check — which the service's post-swap PID survival makes unreliable
// (service.go:784-789). Extracted as a pure helper (no systemd) so it is
// unit-testable with a real Flock fixture.
func confirmUpgradeDeathViaFlock(projDir string, timeout time.Duration) bool {
	deadline := time.Now().Add(timeout)
	for {
		if !upgrade.IsFlockHeld(projDir) {
			return true // flock free → holder gone → confirmed dead
		}
		if !time.Now().Before(deadline) {
			return false // still held at deadline → caller narrates (observer)
		}
		time.Sleep(flockConfirmPollInterval)
	}
}

// upgradeUnitCrashLooping reports whether the upgrade unit is in a crash
// loop: NRestarts at or beyond the threshold. A healthy upgrade restarts
// the unit ONCE by design (the exit-42 binary-swap handoff; Restart=always
// catches it) and perhaps once more on a planned resume — three or more
// restarts means the unit is cycling, not progressing (rune sat at
// NRestarts=10229). Used by the StateLiveUpgrade takeover arm: a genuinely
// progressing upgrade (low restart count, flock held) keeps today's
// refusal; a crash-looping one is taken over.
//
// Conservative on any probe failure: returns false → the refusal path.
func upgradeUnitCrashLooping(projDir string) (string, bool) {
	if runtime.GOOS != "linux" {
		return "", false
	}
	instance := serviceInstance(projDir)
	if instance == "" {
		return "", false
	}
	out, err := exec.Command("systemctl", "--user", "show", instance, "-p", "NRestarts", "--value").Output()
	if err != nil {
		return instance, false
	}
	n, err := strconv.Atoi(strings.TrimSpace(string(out)))
	if err != nil {
		return instance, false
	}
	const crashLoopThreshold = 3
	if n >= crashLoopThreshold {
		fmt.Printf("Upgrade unit %s is crash-looping (NRestarts=%d ≥ %d) — taking over recovery instead of refusing.\n",
			instance, n, crashLoopThreshold)
		return instance, true
	}
	return instance, false
}

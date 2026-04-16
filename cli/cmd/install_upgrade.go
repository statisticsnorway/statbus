package cmd

import (
	"context"
	"fmt"
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
			return true, fmt.Errorf("upgrade in progress (PID %d, %s, started %s); wait for it to finish or run './sb upgrade recover' if the process is dead",
				detail.Flag.PID, detail.Flag.DisplayName, detail.Flag.StartedAt.Format(time.RFC3339))
		}
		return true, fmt.Errorf("upgrade in progress; wait or run './sb upgrade recover'")
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
	svc := upgrade.NewService(projDir, true /* verbose */, version)
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

	return svc.ExecuteUpgradeInline(ctx, int(detail.ScheduledRowID), detail.TargetCommitSHA, detail.TargetDisplayName)
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
	svc := upgrade.NewService(projDir, true /* verbose */, version)
	defer svc.Close()
	if err := svc.LoadConfigAndConnect(ctx); err != nil {
		return fmt.Errorf("load upgrade config: %w", err)
	}
	svc.RecoverFromFlag(ctx)
	return nil
}

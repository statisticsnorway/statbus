package cmd

import (
	"context"
	"fmt"

	"github.com/statisticsnorway/statbus/cli/internal/install"
	"github.com/statisticsnorway/statbus/cli/internal/upgrade"
)

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

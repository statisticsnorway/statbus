package cmd

import (
	"fmt"

	"github.com/statisticsnorway/statbus/cli/internal/installcmd"
)

// upgraderStoppedForInstallNotice is what a failed install prints when it
// stopped the upgrader and leaves it stopped; dir is the checkout, so the
// command it names works from any directory.
func upgraderStoppedForInstallNotice(dir string) string {
	return "The upgrader stays stopped until the installation finishes successfully: " + installcmd.Local(dir)
}

// stopUpgraderForInstall is the STATBUS-382 decision (owner, 2026-10-23/26,
// built 2026-10-31): once ./sb install holds the upgrade lock it stops the
// upgrader, and only a successful install starts it again.
//
// Why: a running upgrader keeps the program it loaded. An install that
// replaces ./sb underneath it leaves it applying old logic to a newer
// checkout (Norway 2026-09-22: an rc.18 daemon on an rc.20 box retried a bug
// rc.19 had fixed). Stopping it under the lock means the install never runs
// beside it, a successful install starts it on the installed ./sb (the
// queued start runs at install exit, see dispatchUpgradeDaemonFinalAction),
// and a failed install leaves a stopped upgrader rather than a stale one
// until the next successful ./sb install.
//
// Stopping cannot interrupt an upgrade: the install holds the upgrade lock, so
// none is in flight. The upgrader's own post-upgrade install (bypass) never
// stops it; that path hands over by exit 42 and the unit handoff. Boxes
// without systemd have no upgrader to stop.
//
// It returns whether it stopped a running upgrader.
func stopUpgraderForInstall(bypass bool) (bool, error) {
	if bypass || installServicePlatform != "linux" {
		return false, nil
	}
	instance := resolveUpgraderInstance()
	if instance == "" || !upgraderUnitActive(instance) {
		return false, nil
	}
	fmt.Println("Stopping the upgrader while the installation runs; it starts again when the installation succeeds.")
	if err := stopUpgraderUnitAndWait(instance); err != nil {
		return false, fmt.Errorf("stop the upgrader before installing: %w", err)
	}
	return true, nil
}

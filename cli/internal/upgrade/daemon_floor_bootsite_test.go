package upgrade

import (
	"os"
	"strings"
	"testing"
)

// STATBUS-145 slice 2 — the geometry: BOTH boot sites migrate only to the daemon
// floor, while the applyNewSbUpgrading pipeline step still applies the full delta to
// HEAD. This structural test pins that split (the atomicity flip depends on it:
// boot-to-floor leaves the delta pending → mid-delta failure reads Behind → one-
// shot rollback) and the flagless loud line.

func TestDaemonBootMigrateBoundedToFloor(t *testing.T) {
	src, err := os.ReadFile(thisRepoFile(t, "cli/internal/upgrade/service.go"))
	if err != nil {
		t.Fatalf("read service.go: %v", err)
	}
	body := string(src)

	// (1) The daemon boot-migrate call is bounded to the floor.
	if !strings.Contains(body, `"migrate", "up", "--to", strconv.FormatInt(migrate.DaemonSchemaFloor, 10), "--verbose"`) {
		t.Error("daemon boot-migrate (service.go) must run `migrate up --to DaemonSchemaFloor --verbose` — the STATBUS-145 bounded form")
	}
	// (2) THE FLIP INVARIANT: the applyNewSbUpgrading migrate step stays apply-all (no
	// --to) — it is the ONE site that applies the upgrade delta. If this ever
	// gains --to, the delta would never apply and every upgrade would stall.
	if !strings.Contains(body, `progress.bump, filepath.Join(projDir, "sb"), "migrate", "up", "--verbose")`) {
		t.Error("the applyNewSbUpgrading migrate step must stay apply-all (`migrate up --verbose`, NO --to) — it is the single delta-application site (STATBUS-145)")
	}
	// (3) The flagless loud line names the deferred delta via HasPendingAbove.
	if !strings.Contains(body, "migrate.HasPendingAbove(d.projDir, migrate.DaemonSchemaFloor)") {
		t.Error("a flagless boot must report migrations pending beyond the floor via migrate.HasPendingAbove (the STATBUS-145 loud line)")
	}
}

func TestInstallCrashLadderBoundedToFloor(t *testing.T) {
	src, err := os.ReadFile(thisRepoFile(t, "cli/cmd/install_upgrade.go"))
	if err != nil {
		t.Fatalf("read install_upgrade.go: %v", err)
	}
	if !strings.Contains(string(src), `"migrate", "up", "--to", strconv.FormatInt(migrate.DaemonSchemaFloor, 10), "--verbose"`) {
		t.Error("the install crash-recovery boot-migrate (install_upgrade.go) must run `migrate up --to DaemonSchemaFloor` — the deliberate step-table Migrations step stays apply-all separately (STATBUS-145)")
	}
}

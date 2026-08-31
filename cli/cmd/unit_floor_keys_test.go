package cmd

import (
	"os"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/upgrade"
)

// STATBUS-308: the Go writer and the admin UI agree on these key names by
// nothing but convention — they are strings on one side and strings on the
// other, with a database in between that will happily store a typo forever.
//
// A mismatch fails in the worst possible way for this particular feature: the
// page finds no row, renders nothing, and looks exactly like a healthy box. The
// warning that exists to break a silence would itself be silent. So the names
// are pinned here, at the seam.
func TestAdminPageReadsTheKeysTheServiceWrites(t *testing.T) {
	page, err := os.ReadFile(thisRepoFile(t, "app/src/app/admin/upgrades/page.tsx"))
	if err != nil {
		t.Fatalf("read upgrades page: %v", err)
	}
	body := string(page)

	for _, key := range []string{
		upgrade.UnitFloorStateKey,
		upgrade.UnitFloorDetailKey,
		upgrade.UnitFloorIntervalKey,
	} {
		if !strings.Contains(body, `"`+key+`"`) {
			t.Errorf("the admin upgrades page does not read %q — the service writes it and nothing displays it, so a floor breach would render as a healthy box", key)
		}
	}
}

// The staleness threshold must be DERIVED from the interval the writer records,
// never a hardcoded duration. If the poll cadence ever changes, a hardcoded
// threshold keeps measuring against a cadence that no longer exists — a warning
// that silently stops matching reality is its own defect.
func TestStalenessThresholdIsDerivedNotHardcoded(t *testing.T) {
	page, err := os.ReadFile(thisRepoFile(t, "app/src/app/admin/upgrades/page.tsx"))
	if err != nil {
		t.Fatalf("read upgrades page: %v", err)
	}
	body := string(page)

	if !strings.Contains(body, "STALE_INTERVAL_MULTIPLE") {
		t.Error("expected a named multiple of the recorded interval")
	}
	if !strings.Contains(body, "intervalSeconds * STALE_INTERVAL_MULTIPLE") {
		t.Error("the threshold must be computed from the interval the writer recorded, not from a fixed duration")
	}
	// The yardstick must be shown beside the fact, so an operator can judge
	// severity instead of being told only that something is old.
	if !strings.Contains(body, "expected") || !strings.Contains(body, "formatInterval") {
		t.Error("the staleness message must print the expected cadence alongside the observed age")
	}
}

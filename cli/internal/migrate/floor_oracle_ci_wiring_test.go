package migrate

import (
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"testing"
)

// TestFloorOracleWiredInCI (STATBUS-182) is the TEETH that moved out of
// TestDaemonFloorSchemaSufficient's DSN-unset fail-loud. It is a PURE-lane test
// (no cluster, no Docker) that asserts the cross-lane invariant as tested
// machinery rather than trust: the empirical floor oracle has a STANDING CI HOME
// (the fast-tests "Daemon floor oracle" step) AND that step derives the floor
// value from this package's single source of truth. Deleting the CI step, or
// hardcoding the floor in the workflow, reddens THIS test by construction — the
// same source-shape-assert genre as upgrade/persistent_rsync_test.
//
// Two assertions:
//
//	(i)  fast-tests.yaml invokes `-run TestDaemonFloorSchemaSufficient` with
//	     STATBUS_FLOOR_TEST_DSN — the oracle actually runs standing in CI.
//	(ii) the workflow DERIVES the floor from daemon_floor.go's DaemonSchemaFloor
//	     (never hardcoded), and the canonical constant shape the derivation relies
//	     on genuinely matches daemon_floor.go and yields the DaemonSchemaFloor value.
func TestFloorOracleWiredInCI(t *testing.T) {
	root := repoRoot(t)

	wfPath := filepath.Join(root, ".github", "workflows", "fast-tests.yaml")
	wfBytes, err := os.ReadFile(wfPath)
	if err != nil {
		t.Fatalf("read %s: %v", wfPath, err)
	}
	wf := string(wfBytes)

	// (i) The oracle invocation is present and strict.
	if !strings.Contains(wf, "-run TestDaemonFloorSchemaSufficient") {
		t.Errorf("fast-tests.yaml does not invoke the empirical floor oracle (`-run TestDaemonFloorSchemaSufficient`) — the oracle has no standing CI home; a green master would no longer prove floor sufficiency")
	}
	if !strings.Contains(wf, "STATBUS_FLOOR_TEST_DSN") {
		t.Errorf("fast-tests.yaml does not set STATBUS_FLOOR_TEST_DSN — the oracle would skip vacuously instead of running against a provisioned floor DB")
	}

	// (ii) The workflow derives the floor from the source of truth, not a literal.
	if !strings.Contains(wf, "daemon_floor.go") || !strings.Contains(wf, "DaemonSchemaFloor") {
		t.Errorf("fast-tests.yaml does not derive the floor from cli/internal/migrate/daemon_floor.go's DaemonSchemaFloor — a hardcoded floor value would silently go stale (exactly how the recipe comment did before STATBUS-182)")
	}
	// A hardcoded 14-digit floor timestamp in the workflow is the anti-pattern this
	// forbids: the value must be grepped from daemon_floor.go, never inlined.
	if regexp.MustCompile(`--to[= ]+2\d{13}`).Match(wfBytes) {
		t.Errorf("fast-tests.yaml appears to hardcode a floor timestamp in `--to` — derive it from daemon_floor.go's DaemonSchemaFloor instead (grep the constant), so it can never go stale")
	}

	// The canonical constant shape the workflow's grep relies on must genuinely match
	// daemon_floor.go and extract exactly the DaemonSchemaFloor value the test binary
	// compiled against. If the declaration form ever changes so the grep can't find
	// it, this fails alongside the workflow — they break together, by design.
	floorPath := filepath.Join(root, "cli", "internal", "migrate", "daemon_floor.go")
	floorBytes, err := os.ReadFile(floorPath)
	if err != nil {
		t.Fatalf("read %s: %v", floorPath, err)
	}
	m := regexp.MustCompile(`DaemonSchemaFloor\s+int64\s*=\s*(\d+)`).FindSubmatch(floorBytes)
	if m == nil {
		t.Fatalf("could not extract the DaemonSchemaFloor constant from daemon_floor.go with the canonical `DaemonSchemaFloor int64 = <n>` shape — the workflow's floor-derivation grep relies on this shape")
	}
	derived, err := strconv.ParseInt(string(m[1]), 10, 64)
	if err != nil {
		t.Fatalf("parse derived floor %q: %v", string(m[1]), err)
	}
	if derived != DaemonSchemaFloor {
		t.Errorf("the grep-derivable floor (%d, from daemon_floor.go source) != the compiled DaemonSchemaFloor constant (%d) — the workflow would provision the wrong waypoint", derived, DaemonSchemaFloor)
	}
}

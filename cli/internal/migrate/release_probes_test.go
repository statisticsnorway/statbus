package migrate

import (
	"os"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/release"
	"github.com/statisticsnorway/statbus/cli/internal/testguard"
)

// TestMain wires the REAL release probes exactly as main.go does, so every
// guard test in this package keeps exercising the production answer to "is
// this migration released" against a real git repository with real tags,
// not a stub. (A _test.go file may import internal/release; the STATBUS-352
// architecture rule forbids only the PRODUCTION edge, which
// cmd/release/architecture_test.go pins.)
func TestMain(m *testing.M) {
	if err := os.Setenv("STATBUS_CLI_UNIT_TEST_GUARD", "1"); err != nil {
		panic(err)
	}
	cleanup, err := testguard.Install()
	if err != nil {
		panic(err)
	}
	ReleaseProbe = ReleaseProbes{
		BaselineTag:            release.CurrentImmutabilityBaselineTag,
		MigrationExistsInTag:   release.MigrationExistsInTag,
		MigrationInReleasedTag: release.MigrationInReleasedTag,
		FileIsDirty:            release.FileIsDirty,
	}
	code := m.Run()
	cleanup()
	os.Exit(code)
}

// TestReleasedMigrationDownGuard_UnwiredProbesRefuse_STATBUS352: the guard's
// safety must not depend on main.go remembering to wire the probes. An
// unwired process REFUSES to revert anything with a diagnostic naming the
// bug; it never concludes "nothing is released".
func TestReleasedMigrationDownGuard_UnwiredProbesRefuse_STATBUS352(t *testing.T) {
	wired := ReleaseProbe
	t.Cleanup(func() { ReleaseProbe = wired })

	for name, partial := range map[string]ReleaseProbes{
		"all nil":             {},
		"baseline only":       {BaselineTag: wired.BaselineTag},
		"missing FileIsDirty": {BaselineTag: wired.BaselineTag, MigrationExistsInTag: wired.MigrationExistsInTag, MigrationInReleasedTag: wired.MigrationInReleasedTag},
	} {
		ReleaseProbe = partial
		err := releasedMigrationDownGuard(t.TempDir(), []int64{20260101000000})
		if err == nil || !strings.Contains(err.Error(), "release probes are not wired") {
			t.Fatalf("%s: unwired probes must refuse loudly, got %v", name, err)
		}
	}

	// Zero versions is still a no-op even unwired: nothing to protect.
	ReleaseProbe = ReleaseProbes{}
	if err := releasedMigrationDownGuard(t.TempDir(), nil); err != nil {
		t.Fatalf("empty revert set must remain a no-op: %v", err)
	}
}

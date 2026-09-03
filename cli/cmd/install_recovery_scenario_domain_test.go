package cmd

// STATBUS-199 comment #6 duplication guard. checkInstallRecoveryHarnessGate
// reproduces test/install-recovery/run.sh's default-suite exclusion rule
// (a scenario file containing release.FleetSkipDefaultMarker is
// excluded from the blank-selector full suite) as its own Go constant,
// rather than shelling out to run.sh at gate time — the architect's ruling
// requires commit-accurate reproduction (git show <commit>:<path>, never a
// checkout), which only a second copy of the marker string can give. A
// second copy can drift from the original; this test pins them together so
// a changed harness marker fails LOUDLY here instead of the gate silently
// stopping recognizing exclusions.

import (
	"github.com/statisticsnorway/statbus/cli/internal/release"
	"os"
	"strings"
	"testing"
)

func TestInstallRecoveryHarnessSkipDefaultMarkerMatchesHarness(t *testing.T) {
	data, err := os.ReadFile(thisRepoFile(t, "test/install-recovery/run.sh"))
	if err != nil {
		t.Fatalf("cannot read run.sh: %v", err)
	}
	want := `SKIP_DEFAULT_MARKER="` + release.FleetSkipDefaultMarker + `"`
	if !strings.Contains(string(data), want) {
		t.Fatalf("test/install-recovery/run.sh no longer declares %s — "+
			"release.FleetSkipDefaultMarker in cli/cmd/release.go has drifted from the harness's own marker; "+
			"update the Go constant to match run.sh's SKIP_DEFAULT_MARKER", want)
	}
}

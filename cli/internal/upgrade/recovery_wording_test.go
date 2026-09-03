package upgrade

import (
	"strings"
	"testing"
)

// The planned post-swap handoff must NOT describe itself as a crash. This is
// the finding from the first human-canary run: the operator read "Recovering an
// interrupted upgrade" while the upgrade was proceeding exactly as designed.
func TestPlannedHandoffOpeningIsSuppressed(t *testing.T) {
	line := recoveryOpeningLine(UpgradeFlag{
		ID:        42,
		Phase:     PhaseNewSbSwapped,
		InvokedBy: "service",
	}, HolderService)

	if line != "" {
		t.Fatalf("the startup opening must be suppressed so resumeNewSb emits the one canonical continuation line, got %q", line)
	}
}

// The word has to stay meaningful for the cases that ARE crashes.
func TestGenuineCrashesKeepRecoveryLanguage(t *testing.T) {
	for _, tc := range []struct {
		name  string
		phase string
	}{
		{"resume died after the swap", PhaseNewSbUpgrading},
		{"crash before the swap", PhaseOldSbUpgrading},
	} {
		t.Run(tc.name, func(t *testing.T) {
			line := recoveryOpeningLine(UpgradeFlag{
				ID:        7,
				Phase:     tc.phase,
				InvokedBy: "service",
			}, HolderService)

			if !strings.Contains(line, "Recovering an interrupted upgrade") {
				t.Errorf("a genuine crash must keep recovery language:\n  %s", line)
			}
			if strings.Contains(line, "planned handoff") {
				t.Errorf("a crash must not be described as planned:\n  %s", line)
			}
			if !strings.Contains(line, "id=7") {
				t.Errorf("detail suffix missing:\n  %s", line)
			}
		})
	}
}

// Only the swapped phase suppresses the recovery opening. Pinned as a table so
// a future phase cannot quietly inherit the suppression by falling through.
func TestOnlySwappedPhaseSuppressesRecoveryOpening(t *testing.T) {
	suppressed := map[string]bool{
		PhaseNewSbSwapped:   true,
		PhaseNewSbUpgrading: false,
		PhaseOldSbUpgrading: false,
	}
	for phase, wantSuppressed := range suppressed {
		line := recoveryOpeningLine(UpgradeFlag{ID: 1, Phase: phase}, HolderService)
		gotSuppressed := line == ""
		if gotSuppressed != wantSuppressed {
			t.Errorf("phase %q: suppressed=%v, want %v\n  %s", phase, gotSuppressed, wantSuppressed, line)
		}
	}
}

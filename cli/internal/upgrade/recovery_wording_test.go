package upgrade

import (
	"strings"
	"testing"
)

// The planned post-swap handoff must NOT describe itself as a crash. This is
// the finding from the first human-canary run: the operator read "Recovering an
// interrupted upgrade" while the upgrade was proceeding exactly as designed.
func TestPlannedHandoffDoesNotClaimInterruption(t *testing.T) {
	line := recoveryOpeningLine(UpgradeFlag{
		ID:        42,
		Phase:     PhaseNewSbSwapped,
		InvokedBy: "service",
	}, HolderService)

	if strings.Contains(line, "interrupted") {
		t.Errorf("the planned handoff must not call itself interrupted:\n  %s", line)
	}
	if strings.Contains(strings.ToLower(line), "recovering") {
		t.Errorf("the planned handoff must not use recovery language:\n  %s", line)
	}
	if !strings.Contains(line, "planned handoff") {
		t.Errorf("the planned handoff must name itself as planned:\n  %s", line)
	}
	// Zoom principle: the plain statement leads, the identifiers still follow.
	if !strings.Contains(line, "id=42") || !strings.Contains(line, "invoked_by=service") {
		t.Errorf("the detail suffix must survive the rewording:\n  %s", line)
	}
	if idx := strings.Index(line, "(detail:"); idx == -1 || idx == 0 {
		t.Errorf("high level must come first, detail after:\n  %s", line)
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

// Only the swapped phase is planned. Pinned as a table so a future phase added
// to the enum cannot quietly inherit "planned" by falling through.
func TestOnlySwappedPhaseIsPlanned(t *testing.T) {
	planned := map[string]bool{
		PhaseNewSbSwapped:   true,
		PhaseNewSbUpgrading: false,
		PhaseOldSbUpgrading: false,
	}
	for phase, wantPlanned := range planned {
		line := recoveryOpeningLine(UpgradeFlag{ID: 1, Phase: phase}, HolderService)
		gotPlanned := strings.Contains(line, "planned handoff")
		if gotPlanned != wantPlanned {
			t.Errorf("phase %q: planned=%v, want %v\n  %s", phase, gotPlanned, wantPlanned, line)
		}
	}
}

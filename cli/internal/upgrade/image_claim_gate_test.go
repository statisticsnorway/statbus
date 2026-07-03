package upgrade

import (
	"testing"
	"time"
)

// STATBUS-046 slice 3c — pins evaluateImageClaimGate against the three real
// public.docker_images_status_type enum labels (confirmed live against the
// dev DB: building/ready/failed) crossed with elapsed-vs-grace, covering all
// four decision outcomes the two claim sites branch on.

func TestEvaluateImageClaimGate_Ready(t *testing.T) {
	now := time.Now()
	got := evaluateImageClaimGate("ready", now.Add(-time.Hour), now, 20*time.Minute)
	if got != imageClaimReady {
		t.Errorf("ready (well past grace) = %v, want imageClaimReady", got)
	}
	// ready is unconditional — grace/elapsed must never override it.
	got = evaluateImageClaimGate("ready", now, now, 20*time.Minute)
	if got != imageClaimReady {
		t.Errorf("ready (zero elapsed) = %v, want imageClaimReady", got)
	}
}

func TestEvaluateImageClaimGate_Failed(t *testing.T) {
	now := time.Now()
	got := evaluateImageClaimGate("failed", now, now, 20*time.Minute)
	if got != imageClaimFailed {
		t.Errorf("failed (zero elapsed) = %v, want imageClaimFailed", got)
	}
	// failed is permanent — no grace-based override, unlike building.
	got = evaluateImageClaimGate("failed", now.Add(-24*time.Hour), now, 20*time.Minute)
	if got != imageClaimFailed {
		t.Errorf("failed (24h elapsed) = %v, want imageClaimFailed (no grace override)", got)
	}
}

func TestEvaluateImageClaimGate_BuildingWithinGrace(t *testing.T) {
	now := time.Now()
	scheduledAt := now.Add(-5 * time.Minute)
	got := evaluateImageClaimGate("building", scheduledAt, now, 20*time.Minute)
	if got != imageClaimWait {
		t.Errorf("building (5m elapsed, 20m grace) = %v, want imageClaimWait", got)
	}
}

func TestEvaluateImageClaimGate_BuildingPastGrace(t *testing.T) {
	now := time.Now()
	scheduledAt := now.Add(-21 * time.Minute)
	got := evaluateImageClaimGate("building", scheduledAt, now, 20*time.Minute)
	if got != imageClaimPastGrace {
		t.Errorf("building (21m elapsed, 20m grace) = %v, want imageClaimPastGrace", got)
	}
}

func TestEvaluateImageClaimGate_BuildingExactlyAtGrace(t *testing.T) {
	// now.Sub(scheduledAt) == grace exactly — the boundary uses strict `>`
	// (matches verifyArtifacts's own `if age > manifestTimeout`), so exactly
	// at the boundary is still WAIT, not past-grace.
	now := time.Now()
	scheduledAt := now.Add(-20 * time.Minute)
	got := evaluateImageClaimGate("building", scheduledAt, now, 20*time.Minute)
	if got != imageClaimWait {
		t.Errorf("building (elapsed == grace exactly) = %v, want imageClaimWait (strict > boundary)", got)
	}
}

func TestEvaluateImageClaimGate_UnrecognisedValueDefaultsToBuildingShape(t *testing.T) {
	// A future/unknown enum value (or a NULL surfacing as "") must NEVER
	// silently claim — falls through to the same building/wait-or-past-grace
	// handling as a defensive default, never a bare imageClaimReady.
	now := time.Now()
	got := evaluateImageClaimGate("", now, now, 20*time.Minute)
	if got != imageClaimWait {
		t.Errorf("unrecognised value (zero elapsed) = %v, want imageClaimWait (conservative default)", got)
	}
	got = evaluateImageClaimGate("some-future-value", now.Add(-time.Hour), now, 20*time.Minute)
	if got != imageClaimPastGrace {
		t.Errorf("unrecognised value (1h elapsed) = %v, want imageClaimPastGrace (conservative default, grace still applies)", got)
	}
}

package upgrade

import (
	"testing"
	"time"
)

// Liveness backstop (plan piece #7, LOAD-BEARING). An EXTERNAL sidecar timer
// runs `sb upgrade liveness-check` every 5 min; livenessDecision is its pure
// core. It converts a SLOW upgrade LOOP (hung-migrate/reconnect retrying every
// ~2.5 min, each cycle under the #3 per-cycle bounds so they never individually
// trip) into a terminal TRIP once the unit has been NOT-healthy-stable for a
// cumulative N=30 min — measured by an OBSERVER-owned last_healthy_at that
// survives the upgrade unit's own restarts (NRestarts/ActiveEnterTimestamp
// can't give cumulative-activating; a fresh heartbeat each cycle defeats
// staleness detection — hence the external observer).
//
// These guards pin the decision; the systemctl read / state-file I/O / unit-stop
// / Slack-fire / sentinel wrap it (exercised by the real-systemd harness).

func TestLivenessDecision_HealthyStableRecords(t *testing.T) {
	now := time.Unix(1_000_000, 0)
	// active+running, up for 10 min, no stuck row → HEALTHY-STABLE.
	in := livenessInput{
		unit:            unitStatus{ActiveState: "active", SubState: "running", ActiveEnter: now.Add(-10 * time.Minute)},
		dbReachable:     true,
		stuckInProgress: 0,
		state:           livenessState{LastHealthyAt: now.Add(-3 * time.Minute)},
		tripped:         false,
	}
	act, st := livenessDecision(now, in, livenessStallThreshold)
	if act.kind != livenessHealthy {
		t.Fatalf("active+running+stable+no-stuck-row must be HEALTHY, got %v", act.kind)
	}
	if !st.LastHealthyAt.Equal(now) {
		t.Errorf("HEALTHY must record last_healthy_at=now; got %v", st.LastHealthyAt)
	}
	// No prior sentinel → nothing to clear.
	if act.clearSentinel {
		t.Error("HEALTHY with no prior trip must not request a sentinel clear")
	}
}

// TestLivenessDecision_HealthyAfterTripClearsSentinel: a unit that recovered
// (became healthy-stable) AFTER a previous trip must clear the tripped sentinel
// so the observer re-arms (a future loop can trip + notify again).
func TestLivenessDecision_HealthyAfterTripClearsSentinel(t *testing.T) {
	now := time.Unix(1_000_000, 0)
	in := livenessInput{
		unit:        unitStatus{ActiveState: "active", SubState: "running", ActiveEnter: now.Add(-10 * time.Minute)},
		dbReachable: true,
		state:       livenessState{LastHealthyAt: now.Add(-40 * time.Minute)},
		tripped:     true, // a prior trip left the sentinel
	}
	act, _ := livenessDecision(now, in, livenessStallThreshold)
	if act.kind != livenessHealthy {
		t.Fatalf("a recovered (healthy-stable) unit must be HEALTHY even after a prior trip; got %v", act.kind)
	}
	if !act.clearSentinel {
		t.Error("HEALTHY after a prior trip MUST clear the sentinel so the observer re-arms")
	}
}

func TestLivenessDecision_JustWentActiveIsNotStable(t *testing.T) {
	now := time.Unix(1_000_000, 0)
	// active+running but only up 30s — NOT yet stable (clears the mid-cycle
	// transient where a looping unit briefly shows active).
	in := livenessInput{
		unit:        unitStatus{ActiveState: "active", SubState: "running", ActiveEnter: now.Add(-30 * time.Second)},
		dbReachable: true,
		state:       livenessState{LastHealthyAt: now.Add(-10 * time.Minute)},
	}
	act, _ := livenessDecision(now, in, livenessStallThreshold)
	if act.kind == livenessHealthy {
		t.Error("active for only 30s must NOT count as healthy-stable (mid-loop transient)")
	}
}

func TestLivenessDecision_SlowLoopTripsAfterN(t *testing.T) {
	now := time.Unix(1_000_000, 0)
	// activating (a restart cycle), last healthy 31 min ago > N=30 → TRIP.
	in := livenessInput{
		unit:        unitStatus{ActiveState: "activating", SubState: "start", ActiveEnter: now.Add(-20 * time.Second)},
		dbReachable: true,
		state:       livenessState{LastHealthyAt: now.Add(-31 * time.Minute)},
		tripped:     false,
	}
	act, _ := livenessDecision(now, in, livenessStallThreshold)
	if act.kind != livenessTrip {
		t.Fatalf("a slow loop NOT-healthy-stable for >N=30min must TRIP; got %v", act.kind)
	}
}

func TestLivenessDecision_NotHealthyWithinNWaits(t *testing.T) {
	now := time.Unix(1_000_000, 0)
	// activating, but only 10 min since last healthy < N → WAIT (legit transient,
	// e.g. a DB restart during maintenance with a few quick retries).
	in := livenessInput{
		unit:        unitStatus{ActiveState: "activating", SubState: "start", ActiveEnter: now.Add(-20 * time.Second)},
		dbReachable: true,
		state:       livenessState{LastHealthyAt: now.Add(-10 * time.Minute)},
	}
	act, _ := livenessDecision(now, in, livenessStallThreshold)
	if act.kind != livenessWait {
		t.Fatalf("NOT-healthy but within N must WAIT (legit transient, no false trip); got %v", act.kind)
	}
}

// TestLivenessDecision_LegitRetryThenStabilizeNoTrip: the no-flaky boundary. A
// unit that did a few quick restarts (e.g. DB restart during maintenance) and
// then went active+running for >2min must be HEALTHY — never tripped — even if
// the retries happened recently.
func TestLivenessDecision_LegitRetryThenStabilizeNoTrip(t *testing.T) {
	now := time.Unix(1_000_000, 0)
	in := livenessInput{
		unit:            unitStatus{ActiveState: "active", SubState: "running", ActiveEnter: now.Add(-3 * time.Minute)},
		dbReachable:     true,
		stuckInProgress: 0,
		// last_healthy was a while ago (during the retries it wasn't healthy),
		// but it is healthy-stable NOW → record, don't trip.
		state: livenessState{LastHealthyAt: now.Add(-12 * time.Minute)},
	}
	act, st := livenessDecision(now, in, livenessStallThreshold)
	if act.kind != livenessHealthy {
		t.Fatalf("a unit that stabilized (active+running>2min) must be HEALTHY, not tripped; got %v", act.kind)
	}
	if !st.LastHealthyAt.Equal(now) {
		t.Errorf("stabilized unit must refresh last_healthy_at; got %v", st.LastHealthyAt)
	}
}

func TestLivenessDecision_AlreadyTrippedDedups(t *testing.T) {
	now := time.Unix(1_000_000, 0)
	// Stale + a sentinel already present → must NOT re-trip (notify+stop once).
	in := livenessInput{
		unit:        unitStatus{ActiveState: "failed", SubState: "failed", ActiveEnter: now.Add(-40 * time.Minute)},
		dbReachable: true,
		state:       livenessState{LastHealthyAt: now.Add(-40 * time.Minute)},
		tripped:     true,
	}
	act, _ := livenessDecision(now, in, livenessStallThreshold)
	if act.kind != livenessWait {
		t.Fatalf("an already-tripped unit (sentinel present) must NOT re-trip — dedup; got %v", act.kind)
	}
}

func TestLivenessDecision_StuckInProgressRowIsNotStable(t *testing.T) {
	now := time.Unix(1_000_000, 0)
	// Unit looks active+running+old, but a public.upgrade row is stuck
	// in_progress → NOT healthy-stable (an upgrade is wedged even if the unit
	// process looks up). Within N here → WAIT (will trip once N lapses).
	in := livenessInput{
		unit:            unitStatus{ActiveState: "active", SubState: "running", ActiveEnter: now.Add(-10 * time.Minute)},
		dbReachable:     true,
		stuckInProgress: 1,
		state:           livenessState{LastHealthyAt: now.Add(-5 * time.Minute)},
	}
	act, _ := livenessDecision(now, in, livenessStallThreshold)
	if act.kind == livenessHealthy {
		t.Error("a stuck-in_progress row means NOT healthy-stable even if the unit process looks up")
	}
}

// TestLivenessDecision_DBUnreachableWithinNWaits: DB down alone must not trip
// (DB-down != upgrade loop); the staleness timer is the arbiter. Within N →
// WAIT; the slow-loop test covers the >N trip.
func TestLivenessDecision_DBUnreachableWithinNWaits(t *testing.T) {
	now := time.Unix(1_000_000, 0)
	in := livenessInput{
		unit:        unitStatus{ActiveState: "active", SubState: "running", ActiveEnter: now.Add(-10 * time.Minute)},
		dbReachable: false, // can't confirm clean
		state:       livenessState{LastHealthyAt: now.Add(-9 * time.Minute)},
	}
	act, _ := livenessDecision(now, in, livenessStallThreshold)
	if act.kind == livenessTrip {
		t.Error("DB-unreachable within N must NOT trip (DB-down is not itself an upgrade loop)")
	}
}

// TestParseUnitStatus pins the systemctl-show parse the observer depends on,
// including systemd's "Dow YYYY-MM-DD HH:MM:SS TZ" ActiveEnterTimestamp format.
func TestParseUnitStatus(t *testing.T) {
	out := "ActiveState=active\nSubState=running\nActiveEnterTimestamp=Tue 2026-05-27 21:30:00 UTC\n"
	u := parseUnitStatus(out)
	if u.ActiveState != "active" || u.SubState != "running" {
		t.Errorf("ActiveState/SubState parse: got %q/%q", u.ActiveState, u.SubState)
	}
	want := time.Date(2026, 5, 27, 21, 30, 0, 0, time.UTC)
	if !u.ActiveEnter.Equal(want) {
		t.Errorf("ActiveEnterTimestamp parse: got %v, want %v", u.ActiveEnter, want)
	}
}

// TestParseUnitStatus_EmptyTimestamp: a unit that never entered active prints an
// empty ActiveEnterTimestamp → zero time (treated as not-stable, the safe way).
func TestParseUnitStatus_EmptyTimestamp(t *testing.T) {
	u := parseUnitStatus("ActiveState=activating\nSubState=start\nActiveEnterTimestamp=\n")
	if !u.ActiveEnter.IsZero() {
		t.Errorf("empty ActiveEnterTimestamp must parse to zero time; got %v", u.ActiveEnter)
	}
	// And a zero ActiveEnter makes isHealthyStable false regardless of state.
	in := livenessInput{unit: u, dbReachable: true}
	if in.isHealthyStable(time.Now()) {
		t.Error("a unit with zero ActiveEnter (never active) must not be healthy-stable")
	}
}

// TestLivenessStateRoundTrip: the observer's persisted anchor round-trips
// through write+read (atomic .tmp+rename), and a missing file reports ok=false
// (→ caller seeds, never trips a fresh box).
func TestLivenessStateRoundTrip(t *testing.T) {
	dir := t.TempDir()
	if _, ok := readLivenessState(dir); ok {
		t.Error("missing state file must report ok=false (fresh box → seed)")
	}
	want := livenessState{LastHealthyAt: time.Unix(1_700_000_000, 0)}
	if err := writeLivenessState(dir, want); err != nil {
		t.Fatalf("writeLivenessState: %v", err)
	}
	got, ok := readLivenessState(dir)
	if !ok || !got.LastHealthyAt.Equal(want.LastHealthyAt) {
		t.Errorf("round-trip: got %v ok=%v, want %v", got.LastHealthyAt, ok, want.LastHealthyAt)
	}
}

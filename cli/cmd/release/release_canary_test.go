package releasecmd

import (
	"os"
	"strings"
	"testing"
)

// STATBUS-245: the canary gate must say whether to wait, watch, ask, or
// investigate. Four situations used to collapse into "no completed row", and an
// unexplained silence teaches people to re-run the gate and then hunt for a
// fault in the wrong place.

// TestCanaryOutcome_FiveNamedStates_STATBUS245 is AC#2, plus the two
// classifications that are easy to get wrong.
func TestCanaryOutcome_FiveNamedStates_STATBUS245(t *testing.T) {
	cases := []struct {
		name  string
		probe canaryProbe
		want  canaryOutcome
	}{
		{"no row at all", canaryProbe{}, canaryNotOffered},
		{"offered", canaryProbe{found: true, state: "available"}, canaryAwaitingOperator},
		{"scheduled", canaryProbe{found: true, state: "scheduled"}, canaryOperatorStarted},
		{"in progress", canaryProbe{found: true, state: "in_progress"}, canaryOperatorStarted},
		{"completed", canaryProbe{found: true, state: "completed"}, canaryCompleted},
		{"failed", canaryProbe{found: true, state: "failed"}, canaryAttemptFailed},
		{"rolled back", canaryProbe{found: true, state: "rolled_back"}, canaryAttemptFailed},
		// A parked row is state='in_progress' with recovery_parked_at set. It is
		// STOPPED and will not resume on its own, so classifying it as "started"
		// would tell the reader to wait for something that never moves.
		{"parked", canaryProbe{found: true, state: "in_progress", recoveryParked: "2026-08-19 09:00:00+00"}, canaryAttemptFailed},
		// An unrecognised state is not quietly treated as patience.
		{"unknown state", canaryProbe{found: true, state: "wat"}, canaryAttemptFailed},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := tc.probe.outcome(); got != tc.want {
				t.Errorf("got %q, want %q", got, tc.want)
			}
		})
	}
}

// TestCanaryGate_OnlyCompletedPasses_STATBUS245 is AC#7 and AC#8 together: the
// gate adds explanation, never permission, and the wait can never age into a
// pass. Exactly one outcome may be treated as success.
func TestCanaryGate_OnlyCompletedPasses_STATBUS245(t *testing.T) {
	all := []canaryOutcome{
		canaryNotOffered, canaryAwaitingOperator, canaryOperatorStarted,
		canaryAttemptFailed, canaryCompleted,
	}
	passing := 0
	for _, o := range all {
		if o == canaryCompleted {
			passing++
		}
	}
	if passing != 1 {
		t.Fatalf("exactly one outcome may pass the gate; %d do", passing)
	}

	// The refusal path must contain NO duration/threshold that could turn a long
	// wait into a pass. Stated as a source property because the hazard is a
	// future edit ("it's been waiting three days, just let it through"), which is
	// precisely the step the human canary exists to perform.
	src := readCanarySource(t)
	for _, forbidden := range []string{"time.Since(start) >", "waitedTooLong", "assumePassed", "timeout && return true"} {
		if strings.Contains(src, forbidden) {
			t.Errorf("the canary wait must never resolve itself into a pass; found %q", forbidden)
		}
	}
}

// TestCanaryExplanation_RoleAwareReading_STATBUS245 is AC#4 — the same row, read
// against the slot's role, must produce OPPOSITE readings.
func TestCanaryExplanation_RoleAwareReading_STATBUS245(t *testing.T) {
	probe := canaryProbe{found: true, state: "available", discoveredAt: "2026-08-18 09:00:00+00"}

	norway := captureStdout(t, func() {
		printCanaryExplanation(canarySlots[1], canaryAwaitingOperator, probe, "v2026.08.0-rc.09")
	})
	dev := captureStdout(t, func() {
		printCanaryExplanation(canarySlots[0], canaryAwaitingOperator, probe, "v2026.08.0-rc.09")
	})

	if !strings.Contains(norway, "NOTHING IS WRONG") {
		t.Errorf("awaiting-operator is Norway's EXPECTED resting state and must not read as a malfunction; got:\n%s", norway)
	}
	if strings.Contains(norway, "FAULT") {
		t.Errorf("Norway waiting for a person must never be called a fault; got:\n%s", norway)
	}
	if !strings.Contains(dev, "FAULT") {
		t.Errorf("the SAME state on dev is a fault — the chain should already have installed it; got:\n%s", dev)
	}
	if strings.Contains(dev, "NOTHING IS WRONG") {
		t.Errorf("dev waiting for a person is not fine; got:\n%s", dev)
	}
}

// TestCanaryExplanation_EveryOutcomeHandsOverANextMove_STATBUS245 is the King's
// AC#9 test, applied to every refusing outcome on both roles: the reader must
// end knowing their next move, never just the system's state.
func TestCanaryExplanation_EveryOutcomeHandsOverANextMove_STATBUS245(t *testing.T) {
	probes := map[canaryOutcome]canaryProbe{
		canaryNotOffered:       {checkInterval: "6h", lastDiscoveryAt: "2026-08-18 09:00:00+00"},
		canaryAwaitingOperator: {found: true, state: "available", discoveredAt: "2026-08-18 09:00:00+00"},
		canaryOperatorStarted:  {found: true, state: "in_progress", startedAt: "2026-08-19 09:00:00+00"},
		canaryAttemptFailed:    {found: true, state: "failed", errorText: "MIGRATION_FAILED: boom"},
	}
	for _, slot := range canarySlots {
		for outcome, probe := range probes {
			out := captureStdout(t, func() { printCanaryExplanation(slot, outcome, probe, "v2026.08.0-rc.09") })
			if !strings.Contains(out, "Your next move") {
				t.Errorf("[%s/%s] every outcome must hand the reader their next move; got:\n%s", slot.label, outcome, out)
			}
			// The handle must be concrete: a command to run, or a person to ask.
			hasCommand := strings.Contains(out, "./sb ") || strings.Contains(out, "ssh ")
			hasPerson := strings.Contains(out, "ask ") || strings.Contains(out, "look at ")
			if !hasCommand && !hasPerson {
				t.Errorf("[%s/%s] the next move must be a concrete command, person, or place — not a bare state name; got:\n%s", slot.label, outcome, out)
			}
		}
	}
}

// TestCanaryProbe_QueriesByCommitNotByCompleted_STATBUS245 is AC#1, and it is
// the structural change the other eight rest on. The old query carried
// `AND state = 'completed'`, which is exactly what collapsed four situations
// into "no row": the box knew whether it was offered, started, or failed, and
// the filter threw that away before it could be read.
//
// Pinned at the source because reinstating the filter would not fail any
// behavioural test — every classification below it would simply stop being
// reachable, and the gate would quietly return to reporting absence.
func TestCanaryProbe_QueriesByCommitNotByCompleted_STATBUS245(t *testing.T) {
	src := readCanarySource(t)
	if strings.Contains(src, "state = 'completed'") {
		t.Error("the probe must query the row BY COMMIT and report its actual state — filtering to completed is what made 'not offered', 'awaiting operator', 'started' and 'failed' indistinguishable (AC#1)")
	}
	// It must actually ask for the fields the five outcomes are derived from;
	// a query that fetched only the state could not distinguish parked, nor
	// attach a duration to the wait.
	for _, field := range []string{"recovery_parked_at", "discovered_at", "started_at", "upgrade_check_interval"} {
		if !strings.Contains(src, field) {
			t.Errorf("the probe must read %s — without it an outcome or its duration cannot be derived", field)
		}
	}
}

// TestCanaryExplanation_NoDeployBranchAdvice_STATBUS245: the deploy branches
// were deleted from origin (STATBUS-244a). A hint telling someone to push one
// would send them to a ref that no longer exists — worse than no hint, because
// it looks authoritative.
func TestCanaryExplanation_NoDeployBranchAdvice_STATBUS245(t *testing.T) {
	src := readCanarySource(t)
	for _, gone := range []string{"ops/cloud/deploy", "ops/standalone/deploy", "master-to-", "push -f origin"} {
		if strings.Contains(src, gone) {
			t.Errorf("no hint may point at a deploy branch — they are gone from origin; found %q", gone)
		}
	}
}

// TestCanaryExplanation_FailureNeverReadsLikeWaiting_STATBUS245 is AC#5.
func TestCanaryExplanation_FailureNeverReadsLikeWaiting_STATBUS245(t *testing.T) {
	failed := captureStdout(t, func() {
		printCanaryExplanation(canarySlots[1], canaryAttemptFailed,
			canaryProbe{found: true, state: "failed", errorText: "MIGRATION_FAILED: boom"}, "v2026.08.0-rc.09")
	})
	if !strings.Contains(failed, "ACTION, not time") {
		t.Errorf("a failed attempt must be called out as needing action rather than time; got:\n%s", failed)
	}
	if strings.Contains(failed, "NOTHING IS WRONG") || strings.Contains(failed, "Wait,") {
		t.Errorf("a failure must never be rendered in the waiting shape; got:\n%s", failed)
	}
	if !strings.Contains(failed, "boom") {
		t.Errorf("the box's own reason must be surfaced — it is the most actionable line available; got:\n%s", failed)
	}

	parked := captureStdout(t, func() {
		printCanaryExplanation(canarySlots[1], canaryAttemptFailed,
			canaryProbe{found: true, state: "in_progress", recoveryParked: "2026-08-19 09:00:00+00"}, "v2026.08.0-rc.09")
	})
	if !strings.Contains(parked, "PARKED") || !strings.Contains(parked, "will NOT resume on its own") {
		t.Errorf("a parked row must say it will not resume on its own, or the reader waits forever; got:\n%s", parked)
	}
}

// TestCanaryNotOffered_CarriesADuration_STATBUS245 is AC#6, including the
// honesty constraint: the box records DISCOVERIES, not checks, so the line must
// not claim to know when it last checked.
func TestCanaryNotOffered_CarriesADuration_STATBUS245(t *testing.T) {
	out := captureStdout(t, func() {
		printCanaryExplanation(canarySlots[1], canaryNotOffered,
			canaryProbe{checkInterval: "6h", lastDiscoveryAt: "2026-08-18 09:00:00+00"}, "v2026.08.0-rc.09")
	})
	if !strings.Contains(out, "every 6h") {
		t.Errorf("the refusal must report the box's check interval; got:\n%s", out)
	}
	if !strings.Contains(out, "not the last check") {
		t.Errorf("the line must not let a DISCOVERY time be read as a CHECK time — a check that finds nothing leaves no record; got:\n%s", out)
	}
}

// TestParseCanaryProbeOutput_STATBUS245 pins the wire format, including an error
// string containing the field separator.
func TestParseCanaryProbeOutput_STATBUS245(t *testing.T) {
	p := parseCanaryProbeOutput(
		"ROW|failed|||2026-08-18 09:00:00+00||MIGRATION_FAILED: a|b|c\nCTX|6h|2026-08-18 09:00:00+00\n")
	if !p.found || p.state != "failed" {
		t.Fatalf("row not parsed: %+v", p)
	}
	if p.errorText != "MIGRATION_FAILED: a|b|c" {
		t.Errorf("error text must survive containing the separator; got %q", p.errorText)
	}
	if p.checkInterval != "6h" {
		t.Errorf("context line not parsed; got %q", p.checkInterval)
	}

	// No ROW line = the box has no row for this commit. Absence IS the answer,
	// which is why the query is asked in labelled lines.
	if parseCanaryProbeOutput("CTX|6h|\n").found {
		t.Error("a missing ROW line must read as NOT OFFERED, not as a parsed row")
	}
}

// TestCanarySlots_TopologyIsDevAndNorwayOnly_STATBUS245: demo tracks stable, so
// it can only confirm a release AFTER promotion — too late to gate on.
func TestCanarySlots_TopologyIsDevAndNorwayOnly_STATBUS245(t *testing.T) {
	if len(canarySlots) != 2 {
		t.Fatalf("the canary topology is exactly dev + no; got %d slots", len(canarySlots))
	}
	if canarySlots[0].label != "dev" || canarySlots[0].role != roleAutomatic {
		t.Errorf("dev must be the AUTOMATIC canary; got %+v", canarySlots[0])
	}
	if canarySlots[1].label != "no" || canarySlots[1].role != roleOperator {
		t.Errorf("no (Norway) must be the OPERATOR canary; got %+v", canarySlots[1])
	}
	for _, s := range canarySlots {
		if s.label == "demo" {
			t.Error("demo must not be a canary slot — it tracks stable and can only confirm after promotion")
		}
		if s.askWho == "" {
			t.Errorf("slot %s has no human handle — AC#9 requires the gate to say who to ask", s.label)
		}
	}
}

func readCanarySource(t *testing.T) string {
	t.Helper()
	b, err := os.ReadFile(thisRepoFile(t, "cli/cmd/release/release_canary.go"))
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

// TestCanaryOutcome_NotTriedIsNotFailed_STATBUS245B is MUST-FIX 1. Three real
// upgrade states — superseded, skipped, dismissed — used to fall through to the
// default and render as "THE INSTALL WAS TRIED AND DID NOT SUCCEED". None of
// them was tried, and the failure text sends the reader to an upgrade log to
// find a failure that never happened.
//
// STATBUS-250's dev reset DISMISSES the candidate it reset away from, on
// purpose, so this also stops a healthy reset from looking like a broken box.
func TestCanaryOutcome_NotTriedIsNotFailed_STATBUS245B(t *testing.T) {
	for _, tc := range []struct {
		state string
		want  canaryOutcome
	}{
		{"superseded", canarySuperseded},
		{"skipped", canarySetAside},
		{"dismissed", canarySetAside},
	} {
		got := canaryProbe{found: true, state: tc.state}.outcome()
		if got == canaryAttemptFailed {
			t.Errorf("state %q renders as a FAILED INSTALL — nothing was tried; the reader is sent to hunt a failure that never happened", tc.state)
		}
		if got != tc.want {
			t.Errorf("state %q: got %q, want %q", tc.state, got, tc.want)
		}
	}

	// The policy for genuinely unknown states is UNCHANGED and still failed.
	if (canaryProbe{found: true, state: "some-future-state"}).outcome() != canaryAttemptFailed {
		t.Error("an unrecognised state must still be treated as a fault, not as patience")
	}

	// Neither new outcome may pass the gate.
	for _, o := range []canaryOutcome{canarySuperseded, canarySetAside} {
		if o == canaryCompleted {
			t.Errorf("%q must not pass the gate", o)
		}
	}
}

// TestCanaryExplanation_NotTriedReadsTrue_STATBUS245B: the message must carry
// the TRUE reason, and must not send the reader to failure archaeology.
func TestCanaryExplanation_NotTriedReadsTrue_STATBUS245B(t *testing.T) {
	sup := captureStdout(t, func() {
		printCanaryExplanation(canarySlots[1], canarySuperseded,
			canaryProbe{found: true, state: "superseded"}, "v2026.08.0-rc.09")
	})
	if !strings.Contains(sup, "MOVED PAST") || !strings.Contains(sup, "nothing failed") {
		t.Errorf("superseded must say the box moved past the candidate and that nothing failed; got:\n%s", sup)
	}
	if strings.Contains(sup, "Read the box's upgrade log") {
		t.Errorf("superseded must NOT send the reader to failure archaeology; got:\n%s", sup)
	}

	aside := captureStdout(t, func() {
		printCanaryExplanation(canarySlots[0], canarySetAside,
			canaryProbe{found: true, state: "dismissed"}, "v2026.08.0-rc.09")
	})
	if !strings.Contains(aside, "DELIBERATELY SET ASIDE") || !strings.Contains(aside, "not a failure") {
		t.Errorf("skipped/dismissed must read as a deliberate act, not a failure; got:\n%s", aside)
	}
	if !strings.Contains(aside, "reset") {
		t.Errorf("the dev-reset case must be named, or a healthy reset looks like a broken box; got:\n%s", aside)
	}
}

// TestCanaryExplanation_CommandNamesTheCandidate_STATBUS245B is MUST-FIX 2. The
// printed command must install THIS candidate. A latest-on-channel command
// installs whatever is newest, so once a newer RC exists the operator follows
// the instruction, installs a different version, and the gate goes on refusing
// with no explanation they can act on.
func TestCanaryExplanation_CommandNamesTheCandidate_STATBUS245B(t *testing.T) {
	const tag = "v2026.08.0-rc.09"
	for _, slot := range canarySlots {
		for _, outcome := range []canaryOutcome{canaryAwaitingOperator, canarySuperseded, canarySetAside} {
			out := captureStdout(t, func() {
				printCanaryExplanation(slot, outcome, canaryProbe{found: true, state: "available"}, tag)
			})
			if !strings.Contains(out, tag) {
				t.Errorf("[%s/%s] the install instruction must NAME the candidate %s; got:\n%s", slot.label, outcome, tag, out)
			}
			if strings.Contains(out, "apply-latest") {
				t.Errorf("[%s/%s] the gate must not tell the operator to install the LATEST — it waits on a specific candidate, and following that would install a different version; got:\n%s", slot.label, outcome, out)
			}
			if !strings.Contains(out, "upgrade register") || !strings.Contains(out, "upgrade schedule") {
				t.Errorf("[%s/%s] the instruction must be register-then-schedule against the named target (schedule requires the candidate row to exist); got:\n%s", slot.label, outcome, out)
			}
		}
	}
}

// STATBUS-247/King's ruling (v2026.08.1 promotion, "It should be enough that
// the Norwegian installation has been done and was a success, and that is
// it"): the observation-card check was RETIRED as a promotion gate. Recording
// the observation is expected discipline, offered at the moment of the
// operator's offer (see TestCanaryExplanation_AwaitingOperatorUnaffectedByObservationGate_STATBUS247
// below), never something checkOneCanary refuses on. This test pins the
// retirement structurally: the completed branch must not be able to quietly
// regrow the gate by referencing the removed helper or the doc/observations
// path.
func TestCheckOneCanary_CompletedBranchHasNoObservationGate_STATBUS247(t *testing.T) {
	src := readCanarySource(t)
	completedIdx := strings.Index(src, "if outcome == canaryCompleted {")
	if completedIdx < 0 {
		t.Fatal("checkOneCanary must branch on outcome == canaryCompleted — test is stale or the code regressed")
	}
	// The next case in the outer switch/if-chain bounds the completed
	// branch's body; everything below is the WHOLE rest of the file, so
	// scanning within a generous window after completedIdx is sufficient
	// without needing full brace-matching.
	window := src[completedIdx:]
	if idx := strings.Index(window, "\n\tcase "); idx > 0 {
		window = window[:idx]
	}
	if !strings.Contains(window, "return true") {
		t.Error("the completed branch must unconditionally return true — completed is a pass for every slot now")
	}
	if strings.Contains(window, "missingObservationCardReason") {
		t.Error("the completed branch must not call missingObservationCardReason — the King retired the observation-card gate; a completed install passes on its own")
	}
	if strings.Contains(window, "doc/observations") {
		t.Error("the completed branch must not reference doc/observations at all — that check belongs to a retired gate, not to completing")
	}
	if _, ok := funcSet(src)["missingObservationCardReason"]; ok {
		t.Error("missingObservationCardReason must be deleted, not merely uncalled — a dead gate function reads as 'could still be right'")
	}
}

// funcSet returns the set of top-level func names declared in src, used to
// assert a retired helper is actually gone rather than just unreferenced.
func funcSet(src string) map[string]bool {
	out := map[string]bool{}
	for _, line := range strings.Split(src, "\n") {
		line = strings.TrimSpace(line)
		if !strings.HasPrefix(line, "func ") {
			continue
		}
		rest := strings.TrimPrefix(line, "func ")
		if idx := strings.Index(rest, "("); idx > 0 {
			out[strings.TrimSpace(rest[:idx])] = true
		}
	}
	return out
}

// TestCanaryExplanation_AwaitingOperatorUnaffectedByObservationGate_STATBUS247
// confirms the awaiting-operator branch's own verdict shape is untouched by
// the gate's retirement — it still reads as Norway's legitimate resting
// state. The print still names the observation card's path as discipline to
// follow through on, just never as something that will be checked — this
// test confirms that line, not a regression.
func TestCanaryExplanation_AwaitingOperatorUnaffectedByObservationGate_STATBUS247(t *testing.T) {
	norway := canarySlots[0]
	for _, s := range canarySlots {
		if s.role == roleOperator {
			norway = s
			break
		}
	}
	out := captureStdout(t, func() {
		printCanaryExplanation(norway, canaryAwaitingOperator, canaryProbe{found: true, state: "available", discoveredAt: "2026-08-18 09:00:00+00"}, "v2026.08.0-rc.17")
	})
	if !strings.Contains(out, "NOTHING IS WRONG") {
		t.Error("awaiting-operator on the operator slot must still read as the legitimate resting state, unrelated to the observation-card gate")
	}
	if !strings.Contains(out, "doc/observations/v2026.08.0-rc.17.md") {
		t.Error("the offer explanation should print the observation card's path for this candidate (kept from the earlier design)")
	}
}

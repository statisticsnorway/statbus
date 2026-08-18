package cmd

// STATBUS-226 oracles for apply-latest's already-at-latest decision.
//
// The defect: the skip compared the resolved target against the RUNNING BINARY's
// compiled-in commit. That answers "what code is executing", not "did this box
// converge" — and a box parked after a post-swap failure whose era guard REFUSED
// the source restoration has the target's binary AND a parked row at once. The
// operator asking to apply that version was told "nothing to apply" while the
// services sat behind the maintenance page.
//
// RED against the pre-226 logic: the parked arm below returns Skip, because a
// binary-only comparison cannot see the park. That is the whole bug in one
// assertion.

import (
	"strings"
	"testing"
)

const (
	testTargetCommit = "abcdef1234567890abcdef1234567890abcdef12"
	testSameBinary   = "abcdef1234567890abcdef1234567890abcdef12"
	testOtherBinary  = "99999999999999999999999999999999deadbeef"
)

func TestDecideApplyLatest_STATBUS226(t *testing.T) {
	for _, tc := range []struct {
		name       string
		resolved   string
		build      string
		row        applyLatestRow
		wantAction applyLatestAction
		wantInMsg  string
		why        string
	}{
		{
			name:       "PARKED at target: must NOT say nothing-to-apply",
			resolved:   testTargetCommit,
			build:      testSameBinary,
			row:        applyLatestRow{Found: true, State: "in_progress", Parked: true, ParkedReason: "disk nearly full: 4 GB free (< 5 GB needed) before image-pull"},
			wantAction: applyLatestRefuse,
			wantInMsg:  "PARKED",
			why:        "the swap happened so the binary IS the target, but the row is parked and the box is dark — this is the STATBUS-226 defect",
		},
		{
			name:       "parked message names the remedy",
			resolved:   testTargetCommit,
			build:      testSameBinary,
			row:        applyLatestRow{Found: true, State: "in_progress", Parked: true, ParkedReason: "some reason"},
			wantAction: applyLatestRefuse,
			wantInMsg:  "un-park",
			why:        "AC#2: an operator must be told what to DO, not merely that something is wrong",
		},
		{
			name:       "converged: row completed at target → skip (no no-op pipeline)",
			resolved:   testTargetCommit,
			build:      testSameBinary,
			row:        applyLatestRow{Found: true, State: "completed"},
			wantAction: applyLatestSkip,
			wantInMsg:  "nothing to apply",
			why:        "AC#4: the healthy case must still short-circuit",
		},
		{
			name:       "genuinely behind: different commit → proceed",
			resolved:   testTargetCommit,
			build:      testOtherBinary,
			row:        applyLatestRow{Found: true, State: "completed"},
			wantAction: applyLatestProceed,
			why:        "the row of a DIFFERENT commit says nothing about this target",
		},
		{
			name:       "unknown build commit → proceed",
			resolved:   testTargetCommit,
			build:      "unknown",
			row:        applyLatestRow{Found: true, State: "completed"},
			wantAction: applyLatestProceed,
			why:        "AC#3: a local `go run` build cannot be compared; never a false skip",
		},
		{
			name:       "unresolvable target → proceed",
			resolved:   "",
			build:      testSameBinary,
			row:        applyLatestRow{Found: true, State: "completed"},
			wantAction: applyLatestProceed,
			why:        "AC#3: a resolve error NEVER causes a skip",
		},
		{
			name:       "no row / unreadable row at target → proceed",
			resolved:   testTargetCommit,
			build:      testSameBinary,
			row:        applyLatestRow{Found: false},
			wantAction: applyLatestProceed,
			why:        "convergence unproven: a wasted pipeline is cheap, a false all-clear on a dark box is not",
		},
		{
			name:       "at-target binary, row still scheduled → proceed",
			resolved:   testTargetCommit,
			build:      testSameBinary,
			row:        applyLatestRow{Found: true, State: "scheduled"},
			wantAction: applyLatestProceed,
			why:        "AC#1: only a COMPLETED row earns the skip; the normal path's own guards handle the rest",
		},
		{
			name:       "at-target binary, row in_progress (not parked) → proceed",
			resolved:   testTargetCommit,
			build:      testSameBinary,
			row:        applyLatestRow{Found: true, State: "in_progress"},
			wantAction: applyLatestProceed,
			why:        "an upgrade is running; promoteExistingCandidate refuses to clobber a LIVE row, so the normal path is the right handler",
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			got := decideApplyLatest("v2026.08.0", tc.resolved, tc.build, tc.row)
			if got.Action != tc.wantAction {
				t.Errorf("action = %v, want %v — %s\n  message: %s", got.Action, tc.wantAction, tc.why, got.Message)
			}
			if tc.wantInMsg != "" && !strings.Contains(got.Message, tc.wantInMsg) {
				t.Errorf("message must contain %q, got: %s", tc.wantInMsg, got.Message)
			}
			if got.Action == applyLatestProceed && got.Message != "" {
				t.Errorf("a proceed verdict must carry no message (the register+schedule path speaks for itself), got: %s", got.Message)
			}
		})
	}
}

// TestDecideApplyLatest_NeverSkipsWithoutACompletedRow_STATBUS226 is the
// one-directional discipline stated as its own property: across every row shape,
// a Skip may ONLY be returned when the row is found, unparked, and completed.
// The pre-226 logic violated this for the parked row; any future edit that
// widens the skip fails here rather than at an operator's console.
func TestDecideApplyLatest_NeverSkipsWithoutACompletedRow_STATBUS226(t *testing.T) {
	rows := []applyLatestRow{
		{Found: false},
		{Found: true, State: "available"},
		{Found: true, State: "scheduled"},
		{Found: true, State: "in_progress"},
		{Found: true, State: "failed"},
		{Found: true, State: "rolled_back"},
		{Found: true, State: "in_progress", Parked: true, ParkedReason: "post-swap health park"},
		{Found: true, State: "completed", Parked: true, ParkedReason: "parked despite completed"},
	}
	for _, row := range rows {
		got := decideApplyLatest("v2026.08.0", testTargetCommit, testSameBinary, row)
		if got.Action == applyLatestSkip {
			t.Errorf("row %+v earned a SKIP — only a found, unparked, COMPLETED row may. A skip tells the operator the box is fine; on any other row that claim is unproven", row)
		}
	}
	// And the one shape that MUST skip, so this property cannot be satisfied by
	// simply never skipping.
	converged := applyLatestRow{Found: true, State: "completed"}
	if got := decideApplyLatest("v2026.08.0", testTargetCommit, testSameBinary, converged); got.Action != applyLatestSkip {
		t.Error("a found, unparked, completed row at the target MUST skip — otherwise every converged box pays for a no-op upgrade pipeline")
	}
}

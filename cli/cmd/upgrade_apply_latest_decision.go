package cmd

import (
	"context"
	"fmt"

	"github.com/statisticsnorway/statbus/cli/internal/upgrade"
)

// STATBUS-226: the already-at-latest decision, extracted from apply-latest's
// RunE so the parked-at-target case can be pinned without a box.

// applyLatestAction is what apply-latest does about the target it resolved.
type applyLatestAction int

const (
	// applyLatestProceed: register + schedule normally. This is the DEFAULT for
	// every uncertainty — an unknown build commit, an unresolvable target, a
	// missing row, an unreadable row. Uncertainty must never produce a skip.
	applyLatestProceed applyLatestAction = iota
	// applyLatestSkip: the box is provably converged at the target; doing nothing
	// is correct, and a no-op upgrade pipeline would be pure waste.
	applyLatestSkip
	// applyLatestRefuse: the box carries the target's BINARY but has NOT
	// converged — parked, above all. Saying "nothing to apply" here tells an
	// operator the box is fine while it sits behind the maintenance page.
	applyLatestRefuse
)

// applyLatestVerdict pairs the action with the exact operator-facing line.
type applyLatestVerdict struct {
	Action  applyLatestAction
	Message string
}

// applyLatestRow is what the decision needs to know about the target's upgrade
// row. Found=false covers BOTH "no row" and "could not read it" — deliberately
// the same to the decision, because they mean the same thing here: convergence
// is not proven, so do not skip.
type applyLatestRow struct {
	Found        bool
	State        string
	Parked       bool
	ParkedReason string
}

// decideApplyLatest answers "is there anything to apply?" from the ROW, not from
// the running binary alone.
//
// STATBUS-226: the old check compared the resolved target against the binary's
// compiled-in commit and returned "Already at X — nothing to apply" on a match.
// That answers "what code is executing", which is NOT "did this box converge".
// A box parked after a post-swap failure whose era guard REFUSED the source
// restoration has exactly this shape — the swap already happened, so the binary
// IS the target, while the row sits parked and the services stay behind the
// maintenance page. The two states are indistinguishable to a binary-only check,
// and the operator was told the reassuring one.
//
// The fall-through discipline is unchanged and still one-directional: every
// uncertainty proceeds to register+schedule, so no path here can produce a FALSE
// skip. Only a row that is positively `completed` earns the skip.
func decideApplyLatest(latestVersion, resolvedCommit, buildCommit string, row applyLatestRow) applyLatestVerdict {
	// Cannot compare → proceed (pre-226 behaviour, unchanged).
	if buildCommit == "" || buildCommit == "unknown" || resolvedCommit == "" {
		return applyLatestVerdict{Action: applyLatestProceed}
	}
	if len(resolvedCommit) < 8 || len(buildCommit) < 8 || resolvedCommit[:8] != buildCommit[:8] {
		return applyLatestVerdict{Action: applyLatestProceed} // genuinely behind
	}

	// The binary is at the target. Now ask the ROW whether the BOX is.
	if !row.Found {
		// No row, or unreadable: convergence unproven. Proceed — a wasted no-op
		// pipeline is cheap; a false "nothing to apply" on a dark box is not.
		return applyLatestVerdict{Action: applyLatestProceed}
	}
	if row.Parked {
		reason := row.ParkedReason
		if reason == "" {
			reason = "(no reason recorded)"
		}
		return applyLatestVerdict{
			Action: applyLatestRefuse,
			Message: fmt.Sprintf(
				"%s is the running binary, but this box has NOT converged: its upgrade row is PARKED (%s).\n"+
					"  Services stay behind the maintenance page until the park is resolved — this is not \"nothing to apply\".\n"+
					"  Fix: run ./sb install to un-park it for one fresh attempt, or schedule a fix release to supersede the park.",
				latestVersion, reason),
		}
	}
	if row.State == "completed" {
		return applyLatestVerdict{
			Action:  applyLatestSkip,
			Message: fmt.Sprintf("Already at %s (commit %s, row completed) — nothing to apply.", latestVersion, buildCommit[:8]),
		}
	}
	// At-target binary with a row in any other state (available / scheduled /
	// in_progress / failed / rolled_back): not converged, and the normal
	// register+schedule path with its own guards is the right handler — e.g.
	// promoteExistingCandidate refuses to clobber a LIVE in_progress row.
	return applyLatestVerdict{Action: applyLatestProceed}
}

// applyLatestRowState reads the target commit's row for the decision above.
// EVERY failure — no row, no DB, a malformed answer — collapses to Found=false,
// which decideApplyLatest treats as "convergence unproven, proceed". That is the
// one-directional discipline the pre-226 fall-throughs already had: an error may
// cost a redundant pipeline, never a false skip.
func applyLatestRowState(ctx context.Context, svc *upgrade.Service, resolvedCommit string) applyLatestRow {
	if svc == nil || resolvedCommit == "" {
		return applyLatestRow{}
	}
	state, parked, reason, err := svc.RowStateForCommit(ctx, resolvedCommit)
	if err != nil {
		return applyLatestRow{}
	}
	return applyLatestRow{Found: true, State: state, Parked: parked, ParkedReason: reason}
}

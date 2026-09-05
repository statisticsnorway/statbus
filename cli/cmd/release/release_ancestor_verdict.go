package releasecmd

import (
	"fmt"

	"github.com/statisticsnorway/statbus/cli/internal/release"
	"github.com/statisticsnorway/statbus/cli/internal/upgrade"
)

// STATBUS-256: the gate's refusal vocabulary had two words for a four-state
// world.
//
// A workflow can be GREEN, RED, RUNNING or ABSENT, and those demand four
// different things from an operator — pass, investigate, wait, dispatch. The
// gate said "green" or "has not run". Both faces of the gap were found live from
// the operator's chair in a single sitting:
//
//   - go-test had gone RED at d59f5e06d; the preflight at a board-only tip
//     reported "has not run… no green run" and prescribed a manual trigger;
//   - images was IN PROGRESS at 0d83061c6, created automatically on push and
//     green minutes later; the preflight told the operator to start it by hand.
//
// The verdicts were right both times. The WORDS lied about the world, and the
// prescribed action was wrong in both cases — re-running a red without a
// diagnosis is the re-run-until-green anti-pattern in the gate's own mouth, and
// dispatching a duplicate of a running job wastes a runner and teaches the
// operator the gate does not know what it is looking at.
//
// The detector already distinguished all four states; nothing was ever missing
// from it. What was missing is that the exempt-ride walk THREW AWAY the state it
// found at an ancestor, keeping only "not green".

// ancestorVerdict is a workflow verdict found at an ancestor whose diff to the
// tip is EXEMPT-ONLY — that is, a verdict about the tip's own code, reached at a
// different commit.
type ancestorVerdict struct {
	Commit string
	// CommitsSince is how many commits the tip has moved past it. Carried so the
	// message can say it rather than gesture at it.
	CommitsSince int
	Result       release.WorkflowCheckResult
}

// printAncestorVerdict renders the state the walk actually found. Each arm gets
// its own true sentence and its own next move, because the moves are opposites.
func printAncestorVerdict(label, tipShort string, v *ancestorVerdict) {
	who := upgrade.ShortForDisplay(v.Commit)
	switch v.Result.Status {
	case release.WorkflowCheckFailed:
		fmt.Printf("  ✗ %s FAILED at %s (conclusion: %s)\n", label, who, v.Result.Detail)
		fmt.Printf("    That commit's code IS this commit's code — the %d commit(s) since it change\n", v.CommitsSince)
		fmt.Println("    only test-irrelevant paths, so this is a red verdict on what you are releasing.")
		fmt.Printf("    Run: %s\n", v.Result.RunURL)
		fmt.Printf("    See: gh run view %d --log-failed\n", v.Result.RunID)
		fmt.Println("    Fix: INVESTIGATE THE FAILURE. Do not simply re-run it.")
		fmt.Println("      Every failure has a real cause. A green re-run without a diagnosis")
		fmt.Println("      proves nothing except that the second attempt behaved differently,")
		fmt.Println("      and it green-washes a real bug just as readily as a flaky one.")
		fmt.Println("      If the cause is the test rather than the code, fix the test and push")
		fmt.Println("      that fix — the gate wants a green it can believe.")
	case release.WorkflowCheckPending:
		fmt.Printf("  ✗ %s is IN PROGRESS at %s — its verdict on this code is not in yet\n", label, who)
		fmt.Printf("    Run:   %s\n", v.Result.RunURL)
		fmt.Printf("    Follow: gh run view %d\n", v.Result.RunID)
		fmt.Println("    Fix: wait for it to finish, then re-run prerelease.")
		fmt.Println("      Do NOT trigger another run — one is already running for this code.")
	default:
		// Reached only if the walk ever records a state these arms do not name.
		// Say so plainly rather than printing a confident wrong arm — inventing
		// advice for an unknown state is the defect this file exists to remove.
		fmt.Printf("  ✗ %s at %s reported status %q, which this gate has no advice for\n",
			label, who, v.Result.Status)
		if v.Result.RunURL != "" {
			fmt.Printf("    Run: %s\n", v.Result.RunURL)
		}
		fmt.Println("    Fix: read the run above and decide by hand; then report this message,")
		fmt.Println("      because a gate that cannot name a state it encountered is incomplete.")
	}
	fmt.Printf("    (The tip %s has no run of its own. The verdict above is the most recent one\n", tipShort)
	fmt.Println("     reached on identical code, which is why it is reported instead.)")
}

package cmd

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/statisticsnorway/statbus/cli/internal/migrate"
	"github.com/statisticsnorway/statbus/cli/internal/release"
	"github.com/statisticsnorway/statbus/cli/internal/upgrade"
)

// fastTestStampPath is the on-disk record that the fast suite RAN at a SHA.
// Built in one place because two code paths now read and write it — the
// stamp branch in checkPrerelease and the CI escape below — and two
// hand-built paths that drift apart would fail open, silently.
func fastTestStampPath(projDir string) string {
	return filepath.Join(projDir, "tmp", "fast-test-passed-sha")
}

// driftCoveredByCIGreen decides whether a drift the LOCAL stamp cannot cover
// is nevertheless covered, and prints the verdict. It is consulted at each
// drift-refusal site immediately before that site refuses: green here means
// pass, anything else means the refusal proceeds exactly as before.
//
// THE ARGUMENT, STATED AS A DECISION RATHER THAN LEFT TO BE RE-DERIVED.
//
// The local stamp answers "did the fast suite run at this SHA, on this
// machine". When it is stale, the drift checks correctly say the operator's
// last local run does not cover what changed since. But a green pg_regress
// run at HEAD answers a strictly stronger question: CI checked out THIS
// COMMITTED TREE and ran the suite against it. Whatever drifted between the
// stamp's SHA and HEAD was therefore already exercised — not by inference,
// but by construction, because the thing CI tested IS the tree being
// released.
//
// These baselines drift per environment. CI is the reference environment a
// release is cut for, so its verdict on them is the one that governs the cut.
// That is the decision; it is recorded here so a later reader inherits it
// rather than re-arguing it.
//
// WHAT THIS DOES NOT DO. It does not lift, weaken, or stand in for any test
// gate. It applies only where a gate has ALREADY been satisfied — a green
// pg_regress run — and only to the question of whether a stale local stamp
// still forces a re-run. A red or missing pg_regress is untouched by this
// path: it refuses here exactly as it refuses everywhere else. Nothing here
// lets a failing test through.
//
// Still refuses, unchanged: a stale stamp AND no CI green. Both halves have
// to fail before the operator is sent back to `./dev.sh migrate-and-test
// fast`, which is the toll this removes — it was being charged for drift
// that CI had already covered.
//
// stampFromRide carries the one distinction that must survive into here: a
// stamp SYNTHESIZED from an exempt-ancestor ride is deliberately not
// persisted (release.go, the ride case — an inference re-derived in under a
// second must never become on-disk evidence that outlives the green
// justifying it). The escape honours that: it refreshes the stamp on the
// escape path only, never on the ride path.
//
// The second return value is the WorkflowCheckResult this call actually
// consulted (STATBUS-277). On a refusal the caller prints it verbatim so the
// operator sees BOTH halves of the either/or and which one is missing,
// instead of the old refusal alone, which read as if the local run were the
// only acceptable proof. Its Status is the zero value ("") in the one case
// where CI was never even asked — no resolvable HEAD — so the caller can
// tell "declined" from "not consulted" apart.
func driftCoveredByWorkflowGreen(projDir, workflow, what, drifted string, stampFromRide bool) (bool, release.WorkflowCheckResult) {
	headOut, headErr := upgrade.RunCommandOutput(projDir, "git", "rev-parse", "HEAD")
	headFull := strings.TrimSpace(headOut)
	// A check that examines nothing must refuse, not pass. With no HEAD there
	// is no commit to ask CI about, so there is no coverage to claim.
	//
	// THE ERROR IS CHECKED, NOT JUST THE EMPTINESS, and that distinction is
	// load-bearing: RunCommandOutput returns CombinedOutput, so a failed
	// `git rev-parse` hands back git's own message ("fatal: not a git
	// repository…") as the OUTPUT. Testing only for "" would take that text
	// for a SHA, ask CI about it, and — since a garbage commit is not green —
	// usually refuse for an incoherent reason, but on any stub or cache that
	// answered green it would claim coverage at a commit that does not exist.
	// A relaxation must fail closed on its own confusion. (Caught by
	// TestDriftEscapeRefusesWithoutAHead, which failed exactly this way before
	// the error check was added.)
	if headErr != nil || headFull == "" {
		return false, release.WorkflowCheckResult{}
	}
	headShort := headFull
	if len(headShort) > 12 {
		headShort = headShort[:12]
	}

	result := checkWorkflowAtCommit(workflow, headFull)
	if result.Status != release.WorkflowCheckGreen {
		return false, result
	}

	fmt.Printf("  ✓ Fast tests cover %s (pg_regress green in CI at %s)\n", what, headShort)
	for _, f := range strings.Split(drifted, "\n") {
		if f != "" {
			fmt.Printf("      %s\n", f)
		}
	}
	fmt.Println("    Covered by construction: CI ran the suite against this committed tree,")
	fmt.Println("    which is the tree being released, so the drift above was exercised there.")
	fmt.Printf("    Run: %s\n", result.RunURL)

	if stampFromRide {
		fmt.Println("    Local stamp not refreshed: this run's stamp was inferred from an")
		fmt.Println("    exempt-ancestor ride, and an inference must not be written to disk.")
		return true, result
	}

	// Refresh the local stamp so the next invocation short-circuits through
	// the fast path instead of paying for this GitHub read again. Same
	// two-line content and best-effort handling as the CI-green branch in
	// checkPrerelease: a write failure only costs a re-check next time.
	latestMig, _ := migrate.LatestOnDiskMigrationVersion(projDir)
	stampPath := fastTestStampPath(projDir)
	_ = os.MkdirAll(filepath.Dir(stampPath), 0755)
	_ = os.WriteFile(stampPath, []byte(headFull+"\n"+latestMig+"\n"), 0644)
	fmt.Printf("    Local stamp refreshed to %s (source version %s)\n", headShort, latestMig)
	return true, result
}

// printDriftEitherOrRefusal is called at each drift-refusal site immediately
// before the site's own unchanged refusal, when driftCoveredByCIGreen has
// just declined (STATBUS-277). Without it, the refusal below reads as if the
// local stamp were the ONLY acceptable proof, when the gate is actually
// either/or: a green pg_regress run at HEAD satisfies it exactly as well as
// a fresh local run. This says which half is missing and, when CI was
// actually consulted, exactly what it saw there — status, and a run URL or
// API-error detail — so the operator does not have to guess whether waiting
// on a pending run is even worthwhile.
func printDriftEitherOrRefusal(ciResult release.WorkflowCheckResult) {
	if ciResult.Status == "" {
		// CI was never consulted — driftCoveredByCIGreen could not resolve a
		// HEAD to ask about (see its own doc comment). Say so plainly rather
		// than implying an answer that was never sought.
		fmt.Println("    Local stamp is stale, and pg_regress could not be consulted (no resolvable HEAD).")
		fmt.Println("    Either a green CI run at this commit or the local run below satisfies this check.")
		return
	}
	detail := string(ciResult.Status)
	switch {
	case ciResult.RunURL != "":
		detail += ", run: " + ciResult.RunURL
	case ciResult.Detail != "":
		detail += ", detail: " + ciResult.Detail
	}
	fmt.Printf("    Local stamp is stale AND pg_regress is not green at HEAD (status: %s);\n", detail)
	fmt.Println("    either a green CI run at this commit or the local run below satisfies this check.")
}

// driftCoveredByCIGreen is the entry point for the two file-drift refusals:
// new-migrations and test-expected drift. Their question is "was this tree's
// suite exercised", and pg_regress is the workflow that answers it.
func driftCoveredByCIGreen(projDir, what, drifted string, stampFromRide bool) (bool, release.WorkflowCheckResult) {
	return driftCoveredByWorkflowGreen(projDir, release.WorkflowPgRegress, what, drifted, stampFromRide)
}

// staleTemplateCoveredByFastTestsGreen is the entry point for the STALE-TEMPLATE
// refusal, and it deliberately asks a DIFFERENT workflow.
//
// WHY THE WORKFLOW CHOICE IS THE WHOLE POINT HERE. That branch fires because the
// local suite ran against a template built from OLDER migrations. Closing it
// requires evidence that a suite actually EXECUTED against a database built from
// HEAD's migrations — and a workflow run can be green without having executed
// anything, because a run may ride an ancestor's stamp and still conclude
// "success".
//
// The two workflows can be green at one commit and mean different things.
// Observed on 2026-08-27 at a3988e163: fast-tests.yaml had really run (89/89,
// and its log recorded the very stamp content this check wants), while
// pg_regress.yaml at that same SHA concluded "success" as a stamp-ride
// inherited from b319ae4be, with zero tests executed in the run itself.
//
// That observation is not offered as proof the ride was WRONG — it may well
// have been legitimate, since a ride is exactly the right answer when the
// content it covers has not changed, and nothing here establishes that
// migrations differed between those two commits. What it establishes is the
// weaker and sufficient point: a green tells you a run concluded successfully,
// not that this commit's suite executed.
//
// The argument therefore rests on what a ride IS, not on that incident. Gating
// a STALENESS check on inherited evidence defeats the check by construction: a
// ride's green attests that a suite passed SOMEWHERE EARLIER, which is exactly
// the claim staleness disputes.
//
// So this asks fast-tests.yaml, whose green at HEAD is direct execution evidence
// of the property the branch guards.
func staleTemplateCoveredByFastTestsGreen(projDir, what, drifted string, stampFromRide bool) (bool, release.WorkflowCheckResult) {
	return driftCoveredByWorkflowGreen(projDir, release.WorkflowFastTests, what, drifted, stampFromRide)
}

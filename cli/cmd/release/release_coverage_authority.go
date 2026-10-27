package releasecmd

import (
	"fmt"
	"sort"
	"strings"

	"github.com/statisticsnorway/statbus/cli/internal/release"
)

// scenarioEvidence is release.ScenarioEvidence held as a package-level seam —
// the same pattern checkWorkflowAtCommit/workflowJobsComplete already use
// (release.go:~1918) — so a test can substitute synthetic per-scenario
// evidence instead of hitting the live GitHub API. Production never
// reassigns it.
var scenarioEvidence = release.ScenarioEvidence

// coverageAuthorityScenario is one scenario's outcome from the walk below,
// kept alongside its own error (a hard failure to even evaluate it, distinct
// from CoverageNotCovered — which IS an answer, not a failure to get one).
type coverageAuthorityScenario struct {
	Scenario string
	Verdict  release.CoverageVerdict
	Err      error
}

// coverageBlockedGroup is one distinct refusal detail: an evidence anchor plus
// the exact set of sensitive files changed since it. Many scenarios normally
// share one group, so the detail belongs to the workflow refusal, not to every
// scenario line (STATBUS-346).
type coverageBlockedGroup struct {
	Anchor           string
	SensitiveChanges []release.SensitiveChange
}

// runCoverageAuthority remains the per-scenario promotion authority for
// checkUpgradeArcHarnessGate and checkSmokeGate. The LXD fleet intentionally
// does NOT call it: its comparison.tsv is an artifact, not GitHub job marks,
// so the fault-suite gate checks one successful full workflow at the RC SHA.
// The historical VM Fleet scenario home remains readable for old evidence.
//
// THE THREE PRECONDITIONS THIS SATISFIES (STATBUS-252 ticket description):
//
//  1. DOMAIN FROM THE TARGET COMMIT, NEVER FROM EVIDENCE FOUND. Both callers
//     derive the domain with release.ScenariosAt from rcCommit's own tree; each
//     Scenario.Home identifies its harness workflow (git-ls-tree reads, no API)
//     BEFORE calling this function — this function never derives its own
//     domain. A newly added scenario is therefore never inheritable (no
//     historical run can contain it) and never silently absent (an empty
//     domain from either deriver is itself a refusal, STATBUS-216).
//
//  2. PER-COMMIT CACHE, VERIFIED NOT ASSUMED. scenarioEvidence (production:
//     release.ScenarioEvidence) composes release.ScenarioProvenInCI, which
//     reads through runsAtCommitMemoized/jobsForRunMemoized (evidence.go) —
//     the SAME process-lifetime memo, keyed on (apiBase, workflow, commit)
//     and (apiBase, runID), that the STATBUS-252 shadow phase already proved
//     collapses ~560 calls to ~20 across real cuts. Every scenario in the
//     domain below asks Evidence(rcCommit) FIRST (DecideCoverage step 1) —
//     identical key, so the first scenario's call populates the cache and
//     every other scenario's identical query is served from memory. The walk
//     for OLDER candidates shares the same property: every scenario walks
//     the SAME candidate tag list (priorCandidateTags(rcCommit) is
//     commit-invariant per gate run) and the SAME per-candidate commit, so a
//     candidate that N scenarios all check costs one real call, not N. This
//     is inherited behavior, not new code — the switch changes WHO the
//     answer binds, not how it is fetched.
//
//  3. REFUSALS NAME WHAT THEY EXAMINED. Per scenario: a covered-by verdict
//     names its Anchor; blocked scenarios are counted in the workflow summary
//     (named inline when few, under --verbose when many) while the summary
//     names the shared anchor and changed-file count, and the offered git
//     commands inspect that anchor→target range with the same hard-coded
//     pathspec the check itself watches (STATBUS-532); a not-covered verdict
//     with no BlockedBy says how many candidates were walked and found
//     nothing; any EvidenceErrors (candidates that could not be read) are named
//     on their own line, whether or not the scenario ultimately resolved — an
//     operator auditing a refusal must be able to tell "nothing was there" from
//     "something could not be read."
//
// Arc scenarios run on independent throwaway VMs. Smoke scenarios also
// have independent VM jobs. Their per-scenario marks may be inherited only
// under the sensitivity policy below; the LXD fork suite is a different
// whole-run evidence domain and does not borrow historical VM marks.
//
// requiredScenarios MUST already be derived from the TARGET commit's own
// tree by the caller — see precondition 1. An empty domain refuses here too
// (defense in depth; both current callers already refuse earlier via their
// own domain derivation, which is itself an error on empty rather than an
// empty slice, so this branch is a backstop, not the live path).
func runCoverageAuthority(projDir, rcTag, rcCommit, rcShort string, domain release.Domain) gateVerdict {
	workflow := domain.Workflow.String()
	requiredScenarios := domain.Scenarios
	if len(requiredScenarios) == 0 {
		fmt.Printf("  ✗ %s: the scenario domain at %s is EMPTY — refusing rather than trivially passing (STATBUS-216)\n", workflow, rcShort)
		fmt.Println("    A per-scenario check over zero scenarios is trivially yes. The domain derivation is broken, not the evidence.")
		return gateFailed
	}

	evaluator, evalErr := newCoverageEvaluator(projDir, rcCommit)
	if evalErr != nil {
		fmt.Printf("  ✗ %s: could not initialize the scenario check\n", workflow)
		fmt.Printf("    Error: %v\n", evalErr)
		return gateFailed
	}

	results := make([]coverageAuthorityScenario, 0, len(requiredScenarios))
	for _, scenario := range requiredScenarios {
		v, err := evaluator.Decide(scenario)
		results = append(results, coverageAuthorityScenario{Scenario: scenario.Name, Verdict: v, Err: err})
	}
	sort.Slice(results, func(i, j int) bool { return results[i].Scenario < results[j].Scenario })

	var provenHere, coveredBy, notCovered, errored []coverageAuthorityScenario
	for _, r := range results {
		switch {
		case r.Err != nil:
			errored = append(errored, r)
		case r.Verdict.Kind == release.CoverageProvenHere:
			provenHere = append(provenHere, r)
		case r.Verdict.Kind == release.CoverageCoveredBy:
			coveredBy = append(coveredBy, r)
		default:
			notCovered = append(notCovered, r)
		}
	}
	passed := len(notCovered) == 0 && len(errored) == 0
	blockedGroups, blockedCount, blockedAnchors := groupBlockedCoverage(notCovered)
	coveredCount := len(provenHere) + len(coveredBy)

	// A concluded run at the TARGET commit decides which icon the not-passed
	// state wears: still running → pending (⏳); concluded non-success → an
	// observed failure (✗). Checked once per invocation, only when there is
	// something left to explain, and only against the target commit — an
	// in-flight or failed run at an older anchor is not actionable here.
	//
	// NOT free via the evidence memo: checkWorkflowAtCommit issues its own
	// unconditional HTTP GET against .../actions/workflows/{workflow}/runs
	// (see the STATBUS-256 note this comment replaces for the verification).
	// It is still cheap: one call, at most once per gate invocation, spent
	// only on the not-passed path.
	var targetRun *release.WorkflowCheckResult
	if len(notCovered) > 0 {
		if r := checkWorkflowAtCommit(workflow, rcCommit); r.Status == release.WorkflowCheckPending || r.Status == release.WorkflowCheckFailed {
			rc := r
			targetRun = &rc
		}
	}

	if passed {
		fmt.Printf("  ✓ %s: %d/%d scenarios have passed at %s (%d at this commit, %d inherited from a prior RC)\n",
			workflow, coveredCount, len(requiredScenarios), rcShort, len(provenHere), len(coveredBy))
	} else {
		mark := "⏳"
		if len(errored) > 0 || (targetRun != nil && targetRun.Status == release.WorkflowCheckFailed) {
			mark = "✗"
		}
		var summary strings.Builder
		fmt.Fprintf(&summary, "  %s %s: %d/%d scenarios have passed at %s",
			mark, workflow, coveredCount, len(requiredScenarios), rcShort)
		anchors := sortedAnchors(blockedAnchors)
		switch {
		case blockedCount == 0:
			// Plain not-covered: no anchor was ever found rideable.
		case len(anchors) == 1:
			fmt.Fprintf(&summary, ". Results from %s cannot be reused because %s used by these scenarios changed.",
				anchors[0], pluralFiles(countDistinctBlockedPaths(blockedGroups)))
		default:
			fmt.Fprintf(&summary, ". Results from earlier RCs cannot be reused because files used by these scenarios changed since %s.",
				strings.Join(anchors, ", "))
		}
		fmt.Println(summary.String())
	}

	// Unreadable candidates are named regardless of how the scenario
	// ultimately resolved (precondition 3) — including proven-here, where
	// DecideCoverage populates no EvidenceErrors today (step 1 short-
	// circuits before any candidate is walked) but a future change to that
	// order must not let one go unmentioned here by construction.
	for _, r := range provenHere {
		for _, e := range r.Verdict.EvidenceErrors {
			fmt.Printf("        (%s: unreadable candidate: %s)\n", r.Scenario, e)
		}
	}
	// Inheriting evidence is never silent — matches the pre-switch RIDE
	// print's own rule (STATBUS-199): name every scenario riding a prior
	// anchor and which anchor it rides.
	for _, r := range coveredBy {
		fmt.Printf("    ✓ %s: covered by %s\n", r.Scenario, r.Verdict.Anchor)
		for _, e := range r.Verdict.EvidenceErrors {
			fmt.Printf("        (unreadable candidate skipped en route to this anchor: %s)\n", e)
		}
	}

	// Not-passed scenarios render in plain words by state (STATBUS-532).
	// Blocked names COLLAPSE: the 2026-10-26 preflight printed all 33 arc
	// names with a ✗ each plus a repeated changed-file count per scenario.
	// The count is in the summary; a handful of names fit on one line;
	// anything longer is listed under --verbose.
	var blockedNames, inProgress []string
	for _, r := range notCovered {
		switch {
		case r.Verdict.BlockedBy != "":
			name := r.Scenario
			if len(blockedAnchors) > 1 {
				name += " (anchor " + r.Verdict.BlockedBy + ")"
			}
			blockedNames = append(blockedNames, name)
		case targetRun != nil && targetRun.Status == release.WorkflowCheckPending:
			inProgress = append(inProgress, r.Scenario)
		case r.Verdict.MustRunReason != "":
			fmt.Printf("    ⏳ %s: no result yet — %s\n", r.Scenario, r.Verdict.MustRunReason)
		default:
			fmt.Printf("    ⏳ %s: no result yet — no passed run at this commit or any of the %d earlier RC(s) checked\n", r.Scenario, r.Verdict.CandidatesSeen)
		}
		for _, e := range r.Verdict.EvidenceErrors {
			fmt.Printf("        (unreadable candidate: %s)\n", e)
		}
	}
	switch {
	case len(blockedNames) > 4 && verboseFlag():
		for _, name := range blockedNames {
			fmt.Printf("    ⏳ %s\n", name)
		}
	case len(blockedNames) > 4:
		// The summary's count carries them; --verbose lists every name.
	case len(blockedNames) > 0:
		fmt.Printf("    ⏳ not passed yet: %s\n", strings.Join(blockedNames, ", "))
	}
	switch {
	case len(inProgress) > 4:
		fmt.Printf("    … a run is in progress at %s covering these %d scenarios — wait for it, do not trigger another\n", rcShort, len(inProgress))
	default:
		for _, name := range inProgress {
			fmt.Printf("    … %s: a run is in progress at %s — wait for it, do not trigger another\n", name, rcShort)
		}
	}

	// The changed files are inspectable, not enumerated: one git command block
	// per distinct anchor, with the same hard-coded pathspec the check itself
	// watches (release.DisplayPathspec). --verbose keeps the literal list.
	for _, group := range blockedGroups {
		if verboseFlag() {
			fmt.Printf("    Changed files since %s:\n", group.Anchor)
			for _, change := range group.SensitiveChanges {
				fmt.Printf("        %s\n", change)
			}
		}
	}
	if !verboseFlag() {
		for _, anchor := range sortedAnchors(blockedAnchors) {
			printReviewCommands(projDir, domain.Workflow, anchor, rcShort)
		}
	}
	for _, r := range errored {
		fmt.Printf("    ✗ %s: could not be evaluated: %v\n", r.Scenario, r.Err)
	}

	if passed {
		return gatePassed
	}
	switch {
	case targetRun != nil && targetRun.Status == release.WorkflowCheckPending:
		fmt.Printf("    Watch: gh run watch %d\n", targetRun.RunID)
		fmt.Printf("    URL:   %s\n", targetRun.RunURL)
		fmt.Println("    Next: wait for the run to complete, then re-run stable")
		return gatePending
	case targetRun != nil && targetRun.Status == release.WorkflowCheckFailed:
		fmt.Printf("    The run at this commit failed (conclusion: %s) — an observed failure, not pending work.\n", targetRun.Detail)
		fmt.Printf("    See: gh run view %d --log-failed\n", targetRun.RunID)
		fmt.Printf("    URL: %s\n", targetRun.RunURL)
		fmt.Println("    Next: fix the cause and push (a new RC follows), then re-run stable;")
		fmt.Printf("      for a transient failure, retry: gh run rerun --failed %d\n", targetRun.RunID)
		return gateFailed
	case len(errored) > 0:
		fmt.Println("    Next: resolve the evaluation error above, then re-run stable")
		return gateFailed
	default:
		// Nothing has started. Whether a manual trigger is the right nudge
		// depends on the orchestrator's own state for this RC.
		predecessor := "its dev-canary step"
		if domain.Workflow == release.WorkflowSmoke {
			predecessor = "its smoke step"
		}
		printOrchestratorGuidance(workflow, rcTag, rcCommit, predecessor)
		return gatePending
	}
}

// groupBlockedCoverage returns one entry per distinct (anchor, file-set), plus
// counts used by the one-line workflow summary. Paths are copied and sorted so
// a file set deduplicates even if two verdicts happened to report it in a
// different order. Scenario verdicts themselves are not changed.
func groupBlockedCoverage(results []coverageAuthorityScenario) ([]coverageBlockedGroup, int, map[string]struct{}) {
	groups := make([]coverageBlockedGroup, 0)
	seen := make(map[string]struct{})
	anchors := make(map[string]struct{})
	blockedCount := 0

	for _, result := range results {
		if result.Verdict.BlockedBy == "" {
			continue
		}
		blockedCount++
		anchors[result.Verdict.BlockedBy] = struct{}{}
		changes := append([]release.SensitiveChange(nil), result.Verdict.SensitiveChanges...)
		sort.Slice(changes, func(i, j int) bool {
			if changes[i].Path == changes[j].Path {
				return changes[i].Reason < changes[j].Reason
			}
			return changes[i].Path < changes[j].Path
		})
		parts := make([]string, 0, len(changes)*2)
		for _, change := range changes {
			parts = append(parts, change.Path, string(change.Reason))
		}
		key := result.Verdict.BlockedBy + "\x00" + strings.Join(parts, "\x00")
		if _, ok := seen[key]; ok {
			continue
		}
		seen[key] = struct{}{}
		groups = append(groups, coverageBlockedGroup{
			Anchor:           result.Verdict.BlockedBy,
			SensitiveChanges: changes,
		})
	}

	return groups, blockedCount, anchors
}

func countDistinctBlockedPaths(groups []coverageBlockedGroup) int {
	paths := make(map[string]struct{})
	for _, group := range groups {
		for _, change := range group.SensitiveChanges {
			paths[change.Path] = struct{}{}
		}
	}
	return len(paths)
}

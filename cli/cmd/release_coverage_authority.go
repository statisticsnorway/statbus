package cmd

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
	Anchor       string
	ChangedPaths []string
}

// runCoverageAuthority is STATBUS-252's SWITCH: the per-scenario decision
// (release.DecideCoverage) is now the promotion gate's OWN authority for
// checkUpgradeArcHarnessGate and checkInstallRecoveryHarnessGate, replacing
// the whole-suite completeness check (a single run's job list covering every
// required scenario) that gated until now. The shadow that ran this same
// algorithm advisorily beside the old authority (runShadowCoverage,
// STATBUS-252 shadow half) is retired along with it — its job is done, and
// its own log would only ever show "always agrees" from here on, which is
// not a finding.
//
// THE THREE PRECONDITIONS THIS SATISFIES (STATBUS-252 ticket description):
//
//  1. DOMAIN FROM THE TARGET COMMIT, NEVER FROM EVIDENCE FOUND. Both callers
//     derive requiredScenarios from rcCommit's own tree (upgradeArcNamesAtCommit
//     / installRecoveryScenarioNamesAtCommit, both git-ls-tree reads, no API)
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
//     names its Anchor; blocked scenarios stay individually named while the
//     workflow summary names the shared anchor and file count, with each
//     distinct (anchor, file-set) listed once under --verbose; a not-covered
//     verdict with no BlockedBy says how many candidates were walked and found
//     nothing; any EvidenceErrors (candidates that could not be read) are named
//     on their own line, whether or not the scenario ultimately resolved — an
//     operator auditing a refusal must be able to tell "nothing was there" from
//     "something could not be read."
//
// AC#6 — THE INDEPENDENCE ARGUMENT, recorded here because this is the switch
// site it must travel with: treating N scenarios as independently provable
// is sound ONLY because both harnesses run every scenario on its own
// throwaway VM with NO shared state between them (install-recovery-harness.yaml
// and upgrade-arc-harness.yaml are both one-VM-per-scenario matrices) — so
// "the whole suite passed" has never meant more than "each of the N passed
// on its own," which is exactly what per-scenario coverage checks one at a
// time, just without requiring they all happened in the same run. THIS
// REASONING MUST BE RE-EXAMINED if either suite ever gains inter-scenario
// dependencies (a shared fixture, an ordering requirement, state carried
// between matrix jobs) — there, a scenario proven in isolation would no
// longer imply it holds when run alongside the others, and per-scenario
// coverage would silently drop the "passed together" property whole-suite
// used to carry for free.
//
// requiredScenarios MUST already be derived from the TARGET commit's own
// tree by the caller — see precondition 1. An empty domain refuses here too
// (defense in depth; both current callers already refuse earlier via their
// own domain derivation, which is itself an error on empty rather than an
// empty slice, so this branch is a backstop, not the live path).
func runCoverageAuthority(projDir, workflow, rcTag, rcCommit, rcShort string, requiredScenarios []string) bool {
	if len(requiredScenarios) == 0 {
		fmt.Printf("  ✗ %s: the scenario domain at %s is EMPTY — refusing rather than trivially passing (STATBUS-216)\n", workflow, rcShort)
		fmt.Println("    A per-scenario coverage decision over zero scenarios is trivially yes. The domain derivation is broken, not the coverage.")
		return false
	}

	sensitivePaths, sErr := loadUpgradeSensitivePaths(projDir)
	if sErr != nil {
		fmt.Printf("  ✗ %s: could not load the sensitivity-path list needed for the coverage walk\n", workflow)
		fmt.Printf("    Error: %v\n", sErr)
		return false
	}

	results := make([]coverageAuthorityScenario, 0, len(requiredScenarios))
	for _, scenario := range requiredScenarios {
		v, err := release.DecideCoverage(scenario, rcCommit, release.CoverageDeps{
			PriorCandidatesNewestFirst: func() ([]string, error) { return priorCandidateTags(projDir, rcCommit) },
			TagCommit:                  func(tag string) (string, error) { return tagTargetCommit(projDir, tag) },
			Evidence:                   scenarioEvidence(projDir, workflow, scenario),
			DiffTouches: func(from, to string) (bool, []string, error) {
				return diffTouchesSensitivePath(projDir, from, to, sensitivePaths)
			},
		})
		results = append(results, coverageAuthorityScenario{Scenario: scenario, Verdict: v, Err: err})
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

	mark, verb := "✓", "PASSES"
	if !passed {
		mark, verb = "✗", "REFUSES"
	}
	coveredCount := len(provenHere) + len(coveredBy)
	switch {
	case passed || blockedCount == 0:
		// Green output and non-blocked refusal vocabulary are intentionally
		// unchanged. STATBUS-346 only reshapes the noisy blocked-by-diff case.
		fmt.Printf("  %s %s %s: %d/%d scenario(s) covered at %s (%d proven here, %d inherited from a prior anchor)\n",
			mark, workflow, verb, coveredCount, len(requiredScenarios), rcShort, len(provenHere), len(coveredBy))
	case len(blockedGroups) == 1:
		group := blockedGroups[0]
		fmt.Printf("  ✗ %s REFUSES: %d/%d scenario(s) covered at %s (%d blocked by %s, %d sensitive files changed since it)\n",
			workflow, coveredCount, len(requiredScenarios), rcShort, blockedCount, group.Anchor, len(group.ChangedPaths))
	case len(blockedAnchors) == 1:
		fmt.Printf("  ✗ %s REFUSES: %d/%d scenario(s) covered at %s (%d blocked by %s, %d distinct sensitive files changed since it across %d file sets)\n",
			workflow, coveredCount, len(requiredScenarios), rcShort, blockedCount, firstBlockedAnchor(blockedAnchors), countDistinctBlockedPaths(blockedGroups), len(blockedGroups))
	default:
		fmt.Printf("  ✗ %s REFUSES: %d/%d scenario(s) covered at %s (%d blocked across %d anchors, %d distinct sensitive files changed since them)\n",
			workflow, coveredCount, len(requiredScenarios), rcShort, blockedCount, len(blockedAnchors), countDistinctBlockedPaths(blockedGroups))
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

	// STATBUS-256 regression guard (architect, 2026-08-31): if a scenario is
	// not covered because its run at the target commit is still IN PROGRESS,
	// telling the operator to trigger another run dispatches a DUPLICATE of
	// one already going — exactly the anti-pattern 256 removed from the
	// exempt-ride gate. Checked ONCE per invocation, only when there is
	// something to refuse (never spent on a clean pass), and only against
	// the TARGET commit — an in-flight run at an older anchor is not
	// actionable for THIS gate invocation.
	//
	// NOT free via the evidence memo, corrected from the architect's
	// hypothesis: checkWorkflowAtCommit (workflow_check.go's checkWorkflowAt)
	// issues its own unconditional HTTP GET against
	// .../actions/workflows/{workflow}/runs?head_sha=... — it does not read
	// through runsAtCommitMemoized/jobsForRunMemoized (evidence.go), whose
	// memo those functions alone populate. Verified by reading both call
	// paths, not assumed. It is still cheap: one extra call, at most once per
	// gate invocation, spent only on the refusal path.
	var targetPending *release.WorkflowCheckResult
	if len(notCovered) > 0 {
		if r := checkWorkflowAtCommit(workflow, rcCommit); r.Status == release.WorkflowCheckPending {
			rc := r
			targetPending = &rc
		}
	}

	for _, r := range notCovered {
		switch {
		case r.Verdict.BlockedBy != "":
			if len(blockedAnchors) == 1 {
				fmt.Printf("    ✗ %s\n", r.Scenario)
			} else {
				fmt.Printf("    ✗ %s (anchor %s)\n", r.Scenario, r.Verdict.BlockedBy)
			}
		case targetPending != nil:
			fmt.Printf("    … %s: a run is IN PROGRESS at %s — WAIT for it, do not trigger another\n", r.Scenario, rcShort)
		default:
			fmt.Printf("    ✗ %s: NOT COVERED — no evidence found within %d candidate(s) walked\n", r.Scenario, r.Verdict.CandidatesSeen)
		}
		for _, e := range r.Verdict.EvidenceErrors {
			fmt.Printf("        (unreadable candidate: %s)\n", e)
		}
	}
	for _, group := range blockedGroups {
		if verbose {
			fmt.Printf("    Changed files since %s:\n", group.Anchor)
			for _, path := range group.ChangedPaths {
				fmt.Printf("        %s\n", path)
			}
		} else {
			fmt.Printf("    (%d changed files — re-run with --verbose to list them)\n", len(group.ChangedPaths))
		}
	}
	for _, r := range errored {
		fmt.Printf("    ✗ %s: COULD NOT BE EVALUATED: %v\n", r.Scenario, r.Err)
	}

	if !passed {
		if targetPending != nil {
			fmt.Printf("    Watch: gh run watch %d\n", targetPending.RunID)
			fmt.Printf("    URL:   %s\n", targetPending.RunURL)
			fmt.Println("    Fix: wait for the run to complete, then re-run stable")
		} else {
			fmt.Printf("    Trigger: %s\n", release.WorkflowTriggerCommand(workflow, rcTag))
			fmt.Printf("    Watch:   %s\n", release.WorkflowURL(workflow))
			fmt.Println("    Fix: run the trigger command above (or dispatch the specific scenario), wait for green, re-run stable")
		}
	}
	return passed
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
		paths := append([]string(nil), result.Verdict.ChangedPaths...)
		sort.Strings(paths)
		key := result.Verdict.BlockedBy + "\x00" + strings.Join(paths, "\x00")
		if _, ok := seen[key]; ok {
			continue
		}
		seen[key] = struct{}{}
		groups = append(groups, coverageBlockedGroup{
			Anchor:       result.Verdict.BlockedBy,
			ChangedPaths: paths,
		})
	}

	return groups, blockedCount, anchors
}

func countDistinctBlockedPaths(groups []coverageBlockedGroup) int {
	paths := make(map[string]struct{})
	for _, group := range groups {
		for _, path := range group.ChangedPaths {
			paths[path] = struct{}{}
		}
	}
	return len(paths)
}

func firstBlockedAnchor(anchors map[string]struct{}) string {
	for anchor := range anchors {
		return anchor
	}
	return ""
}

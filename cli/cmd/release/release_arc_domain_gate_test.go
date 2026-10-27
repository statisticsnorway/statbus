package releasecmd

// STATBUS-216 gate-level pins for the two harness coverage gates, plus
// STATBUS-252's switch-era replacements for what used to be the STATBUS-217
// whole-suite-completeness pins.
//
// 216: an empty scenario domain must REFUSE, never print a 0/0 pass. The
// assertion is on the gate's own boolean — a helper-level test would not
// catch a gate that ignored the error and passed anyway. UNCHANGED by the
// switch: both gates still derive their domain from the tree BEFORE calling
// runCoverageAuthority, and both domain-derivation functions still refuse
// (return an error) on an empty result.
//
// 252: the switch replaced whole-suite completeness (one run's job list
// covering every scenario) with per-scenario coverage (release.DecideCoverage
// per scenario). The OLD STATBUS-217 tests here asserted the JobsCompleteness
// two-bucket vocabulary (MISSING vs DID NOT RUN) that no longer decides
// anything — that PROPERTY (a present-but-skipped/cancelled job is not proof)
// is still enforced, just one layer down, in release.ScenarioProvenInCI
// (internal/release/evidence_test.go's TestScenarioEvidence_UnsuccessfulJobIsNotAMark_STATBUS249).
// What replaces them here is coverage of the new vocabulary these gates now
// render: proven-here, covered-by (with its anchor named), not-covered (with
// candidates-walked or blocked-by named), and the "no evidence anywhere"
// refusal that is the switch's own defining case.

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/release"
)

// stubWorkflowSeams swaps the two GitHub-API seams for the duration of a
// test and restores them afterwards. Still used by the STATBUS-219
// exempt-ride tests (release_ci_exempt_ride_test.go) — checkWorkflowAtCommit
// remains that mechanism's own authority; workflowJobsComplete is kept alive
// here for its signature only (the two arc/install-recovery gates no longer
// call it after the STATBUS-252 switch).
func stubWorkflowSeams(
	t *testing.T,
	check func(workflow, commitSHA string) release.WorkflowCheckResult,
	jobs func(runID int64, requiredJobNames []string) (release.JobsCompleteness, error),
) {
	t.Helper()
	oldCheck, oldJobs := checkWorkflowAtCommit, workflowJobsComplete
	checkWorkflowAtCommit, workflowJobsComplete = check, jobs
	t.Cleanup(func() {
		checkWorkflowAtCommit, workflowJobsComplete = oldCheck, oldJobs
	})
}

// trivialComplete is the pre-STATBUS-216 reading of the completeness check —
// kept alive for release_ci_exempt_ride_test.go's stubWorkflowSeams calls,
// which stub both seams even though findExemptRide only consults
// checkWorkflowAtCommit.
func trivialComplete(runID int64, requiredJobNames []string) (release.JobsCompleteness, error) {
	return release.JobsCompleteness{Complete: true}, nil
}

// arcFixture builds a git repo containing exactly the given repo-relative
// files and returns (dir, HEAD sha). Every fixture also carries one default
// fleet scenario and the real runner (via writeAndCommit): the shared coverage
// evaluator now runs the target commit's own harness validation as its
// prerequisite (STATBUS-352), and a repository whose fleet domain is EMPTY is
// itself a refusal (STATBUS-216), never a passable arc-only world.
func arcFixture(t *testing.T, paths ...string) (string, string) {
	t.Helper()
	dir := t.TempDir()
	runGitInCmd(t, dir, "init", "-q")
	writeAndCommit(t, dir, "fixture", append([]string{"test/install-recovery/scenarios/fixture-default.sh"}, paths...)...)
	return dir, runGitInCmd(t, dir, "rev-parse", "HEAD")
}

// writeSensitivePathsFile writes ops/release/upgrade-sensitive-paths.txt
// directly to disk (runCoverageAuthority's loadUpgradeSensitivePaths reads it
// with a plain os.ReadFile, not from git, so it need not be committed). Every
// test that reaches runCoverageAuthority needs this file to exist — a
// missing file is itself a distinct refusal path, not this helper's concern.
func writeSensitivePathsFile(t *testing.T, dir string, paths ...string) {
	t.Helper()
	if len(paths) == 0 {
		paths = []string{"cli/"}
	}
	lines := make([]string, 0, len(paths)+2)
	for _, p := range paths {
		if strings.HasSuffix(p, "/") {
			lines = append(lines, "directory | box payload | "+strings.TrimSuffix(p, "/"))
		} else {
			lines = append(lines, "exact | box payload | "+p)
		}
	}
	lines = append(lines,
		"directory | proof interpreter | cli/internal/release",
		"exact | proof interpreter | "+release.SensitivePathsFile,
	)
	full := filepath.Join(dir, release.SensitivePathsFile)
	if err := os.MkdirAll(filepath.Dir(full), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(full, []byte(strings.Join(lines, "\n")+"\n"), 0644); err != nil {
		t.Fatal(err)
	}
	// This fixture policy is a working-tree input to the evaluator, not part of
	// the synthetic history unless a test explicitly commits one. Excluding it
	// keeps a later `git add .` from inventing a proof-interpreter change.
	exclude := filepath.Join(dir, ".git", "info", "exclude")
	f, err := os.OpenFile(exclude, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := fmt.Fprintln(f, release.SensitivePathsFile); err != nil {
		_ = f.Close()
		t.Fatal(err)
	}
	if err := f.Close(); err != nil {
		t.Fatal(err)
	}
}

// addOriginRemote configures a local bare "origin" so
// release.ReleaseTagsNewestFirst (git ls-remote --tags origin) succeeds
// against this fixture — STATBUS-199/252's candidate walk reads a REMOTE,
// not local tags, so a fixture with no remote at all would ERROR here rather
// than cleanly report "no candidates". Tags created locally before this call
// are invisible to ls-remote until pushTags sends them.
func addOriginRemote(t *testing.T, dir string) {
	t.Helper()
	origin := t.TempDir()
	runGitInCmd(t, origin, "init", "--bare", "-q")
	runGitInCmd(t, dir, "remote", "add", "origin", origin)
}

// pushTags pushes every local tag to the fixture's origin remote (see
// addOriginRemote) so release.ReleaseTagsNewestFirst can see them.
func pushTags(t *testing.T, dir string) {
	t.Helper()
	runGitInCmd(t, dir, "push", "origin", "--tags")
}

// stubScenarioEvidence overrides the scenarioEvidence seam (release_coverage_authority.go)
// for the duration of a test. evidence maps scenario -> the set of commits at
// which it has evidence — a direct, synthetic stand-in for
// release.ScenarioEvidence's real (local-mark-or-CI) answer, with no network
// or filesystem mark involved.
func stubScenarioEvidence(t *testing.T, evidence map[string]map[string]bool) {
	t.Helper()
	old := scenarioEvidence
	scenarioEvidence = func(projDir string, scenario release.Scenario) release.EvidenceAt {
		return func(commit string) (bool, string, error) {
			if evidence[scenario.Name][commit] {
				return true, "synthetic evidence for " + scenario.Name + " at " + commit[:7], nil
			}
			return false, "", nil
		}
	}
	t.Cleanup(func() { scenarioEvidence = old })
}

// TestUpgradeArcHarnessGate_EmptyArcDomainRefuses is STATBUS-216 AC#2. The
// arcs directory is absent at the commit (the "renamed one directory"
// state). The gate must refuse before ever reaching the coverage walk.
func TestUpgradeArcHarnessGate_EmptyArcDomainRefuses(t *testing.T) {
	dir, head := arcFixture(t, "doc/readme.md")

	var verdict gateVerdict
	out := captureStdout(t, func() {
		verdict = checkUpgradeArcHarnessGate(dir, "v2026.08.0-rc.01", head, head[:7])
	})
	if verdict == gatePassed {
		t.Fatalf("the arc gate PASSED with an empty arc domain — a 0/0 decision proves "+
			"nothing and must never promote a release (STATBUS-216); output:\n%s", out)
	}
	if !strings.Contains(out, "arc domain") {
		t.Errorf("the refusal must name the arc domain as the cause; output:\n%s", out)
	}
	if !strings.Contains(out, upgradeArcDir) {
		t.Errorf("the refusal must print the path it looked in (%s) so the operator can see the "+
			"rename; output:\n%s", upgradeArcDir, out)
	}
	if strings.Contains(out, "0/0") {
		t.Errorf("the gate still printed a 0/0 line — that is the exact bogus success STATBUS-216 "+
			"removes; output:\n%s", out)
	}
}

// TestUpgradeArcHarnessGate_ProvenAtTargetPasses is the positive control:
// evidence exists at the target commit itself for every required arc, so the
// gate passes without ever needing the anchor walk (DecideCoverage's step 1).
func TestUpgradeArcHarnessGate_ProvenAtTargetPasses(t *testing.T) {
	dir, head := arcFixture(t, "doc/readme.md", upgradeArcDir+"working"+upgradeArcSuffix)
	writeSensitivePathsFile(t, dir)
	stubScenarioEvidence(t, map[string]map[string]bool{
		"working": {head: true},
	})

	var verdict gateVerdict
	out := captureStdout(t, func() {
		verdict = checkUpgradeArcHarnessGate(dir, "v2026.08.0-rc.01", head, head[:7])
	})
	if verdict != gatePassed {
		t.Fatalf("the arc gate refused a scenario proven at the target itself; output:\n%s", out)
	}
	if !strings.Contains(out, "1/1 scenarios have passed") {
		t.Errorf("the pass report must count the passed scenarios; output:\n%s", out)
	}
}

// TestUpgradeArcHarnessGate_NoEvidenceAnywhereRefuses is STATBUS-252's
// defining case for the switch: a required scenario has NO evidence at the
// target and NO evidence at any candidate the walk examines — the gate must
// refuse, by name, rather than trivially passing or silently skipping it.
//
// RED-verified (reported to foreman): with runCoverageAuthority's call
// removed from checkUpgradeArcHarnessGate (reverting to a bare `return true`
// after domain derivation), this test fails because the gate passes with no
// evidence at all; restoring the call makes it pass again.
func TestUpgradeArcHarnessGate_NoEvidenceAnywhereRefuses(t *testing.T) {
	dir, head := arcFixture(t, "doc/readme.md", upgradeArcDir+"working"+upgradeArcSuffix)
	writeSensitivePathsFile(t, dir)
	addOriginRemote(t, dir) // no tags pushed: the walk finds zero candidates
	stubScenarioEvidence(t, map[string]map[string]bool{})
	stubWorkflowSeams(t, func(string, string) release.WorkflowCheckResult {
		return release.WorkflowCheckResult{Status: release.WorkflowCheckMissing}
	}, trivialComplete)

	var verdict gateVerdict
	out := captureStdout(t, func() {
		verdict = checkUpgradeArcHarnessGate(dir, "v2026.08.0-rc.01", head, head[:7])
	})
	if verdict == gatePassed {
		t.Fatalf("the arc gate PASSED a required scenario with NO evidence anywhere — this is exactly "+
			"the case the STATBUS-252 switch must refuse; output:\n%s", out)
	}
	if !strings.Contains(out, "no result yet") || !strings.Contains(out, "working") {
		t.Errorf("the refusal must name the scenario that has no result; output:\n%s", out)
	}
}

// TestUpgradeArcHarnessGate_RunInProgressPrescribesWaitNotTrigger is the
// architect's MUST-FIX (2026-08-31, STATBUS-256 regression): a scenario has
// no evidence YET because its run at the TARGET commit has not concluded —
// the refusal must say so and prescribe WAITING, never triggering a
// duplicate of a run already going. Before this fix the gate printed
// "NOT COVERED" + "Trigger: gh workflow run ..." for this exact case,
// reintroducing the anti-pattern STATBUS-256 removed from the exempt-ride
// gate.
func TestUpgradeArcHarnessGate_RunInProgressPrescribesWaitNotTrigger(t *testing.T) {
	dir, head := arcFixture(t, "doc/readme.md", upgradeArcDir+"working"+upgradeArcSuffix)
	writeSensitivePathsFile(t, dir)
	addOriginRemote(t, dir)
	stubScenarioEvidence(t, map[string]map[string]bool{}) // nothing has concluded yet
	stubWorkflowSeams(t, func(workflow, sha string) release.WorkflowCheckResult {
		return release.WorkflowCheckResult{
			Status: release.WorkflowCheckPending,
			RunID:  99,
			RunURL: "https://github.com/statisticsnorway/statbus/actions/runs/99",
		}
	}, trivialComplete)

	var verdict gateVerdict
	out := captureStdout(t, func() {
		verdict = checkUpgradeArcHarnessGate(dir, "v2026.08.0-rc.01", head, head[:7])
	})
	if verdict == gatePassed {
		t.Fatalf("a run still in progress is not evidence — the gate must still refuse; output:\n%s", out)
	}
	if verdict != gatePending {
		t.Errorf("a run in progress is pending work, not an observed failure; output:\n%s", out)
	}
	if !strings.Contains(out, "a run is in progress") || !strings.Contains(out, "wait") {
		t.Errorf("the refusal must say a run is in progress and prescribe waiting; output:\n%s", out)
	}
	if strings.Contains(out, "Trigger:") {
		t.Errorf("the refusal must NOT prescribe triggering another run while one is already in progress "+
			"(STATBUS-256 regression); output:\n%s", out)
	}
	if !strings.Contains(out, "gh run watch 99") {
		t.Errorf("the refusal must point at the SPECIFIC in-progress run so the operator can watch it; output:\n%s", out)
	}
}

// The LXD gate cannot inherit historical VM scenario marks. A missing whole
// LXD workflow run at this exact RC commit must refuse promotion.
func TestLXDFleetGate_MissingRunRefuses(t *testing.T) {
	const commit = "1234567890123456789012345678901234567890"
	stubWorkflowSeams(t, func(workflow, sha string) release.WorkflowCheckResult {
		if workflow == release.WorkflowFleetOrchestrator {
			// No orchestrator run is managing this RC, so nothing schedules
			// the fleet on its own: the manual trigger is the right guidance.
			return release.WorkflowCheckResult{Status: release.WorkflowCheckMissing}
		}
		if workflow != release.WorkflowLXDFleet || sha != commit {
			t.Fatalf("wrong evidence identity: %s at %s", workflow, sha)
		}
		return release.WorkflowCheckResult{Status: release.WorkflowCheckMissing}
	}, trivialComplete)
	var verdict gateVerdict
	out := captureStdout(t, func() {
		verdict = checkInstallRecoveryHarnessGate("", "v2026.08.0-rc.01", commit, commit[:7])
	})
	if verdict == gatePassed || !strings.Contains(out, "gh workflow run lxd-fleet.yaml") {
		t.Fatalf("missing LXD suite must refuse with trigger guidance: %s", out)
	}
}

// TestUpgradeArcHarnessGate_CoveredByPriorAnchorPasses is STATBUS-252
// precondition 3's positive half: a scenario not proven at the target but
// proven at an older RC anchor, with nothing sensitive changed since, is
// COVERED — and the gate's pass report must name the anchor it rode.
func TestUpgradeArcHarnessGate_CoveredByPriorAnchorPasses(t *testing.T) {
	dir, _ := arcFixture(t, "doc/readme.md", upgradeArcDir+"working"+upgradeArcSuffix)
	writeSensitivePathsFile(t, dir, "cli/internal/upgrade/")

	anchor := runGitInCmd(t, dir, "rev-parse", "HEAD")
	runGitInCmd(t, dir, "tag", "-a", "v2026.08.0-rc.01", "-m", "Pre-release v2026.08.0-rc.01")

	writeAndCommit(t, dir, "unrelated doc change", "doc/other.md")
	target := runGitInCmd(t, dir, "rev-parse", "HEAD")
	runGitInCmd(t, dir, "tag", "-a", "v2026.08.0-rc.02", "-m", "Pre-release v2026.08.0-rc.02")

	addOriginRemote(t, dir)
	pushTags(t, dir)

	stubScenarioEvidence(t, map[string]map[string]bool{
		"working": {anchor: true}, // evidence only at the anchor, not the target
	})

	var verdict gateVerdict
	out := captureStdout(t, func() {
		verdict = checkUpgradeArcHarnessGate(dir, "v2026.08.0-rc.02", target, target[:7])
	})
	if verdict != gatePassed {
		t.Fatalf("the gate refused though the anchor is covered and nothing sensitive changed since; output:\n%s", out)
	}
	if !strings.Contains(out, "covered by v2026.08.0-rc.01") {
		t.Errorf("the pass report must name the anchor ridden; output:\n%s", out)
	}
}

// TestUpgradeArcHarnessGate_BlockedByAnchorRefuses is STATBUS-252
// precondition 3's other named case: an anchor has evidence, but a
// sensitive file changed between it and the target — the ride is blocked.
// STATBUS-532 reshaped the refusal: the summary says how many scenarios have
// passed and why the anchor's results cannot be reused, and git commands over
// the anchor→target range replace the per-scenario noise. The literal changed
// path still stays behind --verbose.
func TestUpgradeArcHarnessGate_BlockedByAnchorRefuses(t *testing.T) {
	dir, _ := arcFixture(t, "doc/readme.md", upgradeArcDir+"working"+upgradeArcSuffix)
	writeSensitivePathsFile(t, dir, "cli/internal/upgrade/")

	anchor := runGitInCmd(t, dir, "rev-parse", "HEAD")
	runGitInCmd(t, dir, "tag", "-a", "v2026.08.0-rc.01", "-m", "Pre-release v2026.08.0-rc.01")

	writeAndCommit(t, dir, "sensitive change", "cli/internal/upgrade/service.go")
	target := runGitInCmd(t, dir, "rev-parse", "HEAD")
	runGitInCmd(t, dir, "tag", "-a", "v2026.08.0-rc.02", "-m", "Pre-release v2026.08.0-rc.02")

	addOriginRemote(t, dir)
	pushTags(t, dir)

	stubScenarioEvidence(t, map[string]map[string]bool{
		"working": {anchor: true},
	})
	stubWorkflowSeams(t, func(string, string) release.WorkflowCheckResult {
		return release.WorkflowCheckResult{Status: release.WorkflowCheckMissing}
	}, trivialComplete)

	var verdict gateVerdict
	out := captureStdout(t, func() {
		verdict = checkUpgradeArcHarnessGate(dir, "v2026.08.0-rc.02", target, target[:7])
	})
	if verdict == gatePassed {
		t.Fatalf("the gate PASSED though a sensitive file changed since the only anchor with evidence; output:\n%s", out)
	}
	if !strings.Contains(out, "0/1 scenarios have passed at "+target[:7]+
		". Results from v2026.08.0-rc.01 cannot be reused because 1 file used by these scenarios changed.") {
		t.Errorf("the refusal must say how many scenarios passed and why the anchor cannot be reused; output:\n%s", out)
	}
	if !strings.Contains(out, "not passed yet: working") {
		t.Errorf("a single blocked scenario is named inline; output:\n%s", out)
	}
	if !strings.Contains(out, "git diff v2026.08.0-rc.01.."+target[:7]+" -- ") {
		t.Errorf("the refusal must offer a diff over the anchor→target range; output:\n%s", out)
	}
	if strings.Contains(out, "service.go") {
		t.Errorf("the compact refusal exposed the changed path without --verbose; output:\n%s", out)
	}
}

// TestUpgradeArcHarnessGate_SharedBlockedDetailsPrintOnce is STATBUS-346's
// regression case, reshaped by STATBUS-532: many scenarios commonly share the
// same evidence anchor and therefore the same target diff. The refusal must
// collapse that shared noise — a count and one names line, one git command
// block — instead of printing every scenario with its own count. Verbose
// output keeps the literal shared file set, printed at most once.
func TestUpgradeArcHarnessGate_SharedBlockedDetailsPrintOnce(t *testing.T) {
	dir, _ := arcFixture(t,
		"doc/readme.md",
		upgradeArcDir+"alpha"+upgradeArcSuffix,
		upgradeArcDir+"beta"+upgradeArcSuffix,
		upgradeArcDir+"gamma"+upgradeArcSuffix,
	)
	writeSensitivePathsFile(t, dir, "cli/internal/upgrade/")

	anchor := runGitInCmd(t, dir, "rev-parse", "HEAD")
	runGitInCmd(t, dir, "tag", "-a", "v2026.08.0-rc.01", "-m", "Pre-release v2026.08.0-rc.01")

	const changedPath = "cli/internal/upgrade/service.go"
	writeAndCommit(t, dir, "sensitive change", changedPath)
	target := runGitInCmd(t, dir, "rev-parse", "HEAD")
	runGitInCmd(t, dir, "tag", "-a", "v2026.08.0-rc.02", "-m", "Pre-release v2026.08.0-rc.02")

	addOriginRemote(t, dir)
	pushTags(t, dir)
	stubScenarioEvidence(t, map[string]map[string]bool{
		"alpha": {anchor: true},
		"beta":  {anchor: true},
		"gamma": {anchor: true},
	})
	stubWorkflowSeams(t, func(workflow, sha string) release.WorkflowCheckResult {
		return release.WorkflowCheckResult{Status: release.WorkflowCheckMissing}
	}, trivialComplete)

	oldVerbose := verboseFlag
	t.Cleanup(func() { verboseFlag = oldVerbose })

	run := func(wantVerbose bool) string {
		verboseFlag = func() bool { return wantVerbose }
		var verdict gateVerdict
		out := captureStdout(t, func() {
			verdict = checkUpgradeArcHarnessGate(dir, "v2026.08.0-rc.02", target, target[:7])
		})
		if verdict == gatePassed {
			t.Fatalf("the gate PASSED though all three scenarios are blocked by a sensitive change; output:\n%s", out)
		}
		return out
	}

	compact := run(false)
	wantSummary := "  ⏳ upgrade-arc-harness.yaml: 0/3 scenarios have passed at " + target[:7] +
		". Results from v2026.08.0-rc.01 cannot be reused because 1 file used by these scenarios changed."
	if !strings.Contains(compact, wantSummary) {
		t.Errorf("compact refusal summary mismatch; want %q in output:\n%s", wantSummary, compact)
	}
	if !strings.Contains(compact, "not passed yet: alpha, beta, gamma") {
		t.Errorf("few blocked scenarios fit on ONE names line; output:\n%s", compact)
	}
	if got := strings.Count(compact, changedPath); got != 0 {
		t.Errorf("non-verbose refusal printed the literal changed path %d time(s), want 0; output:\n%s", got, compact)
	}
	if strings.Contains(compact, "changed files") {
		t.Errorf("the repeated changed-file count pointer must not appear — the git commands replaced it; output:\n%s", compact)
	}
	if got := strings.Count(compact, "git log --oneline v2026.08.0-rc.01.."+target[:7]+" -- "); got != 1 {
		t.Errorf("the shared review command must print exactly once, got %d; output:\n%s", got, compact)
	}
	// No orchestrator run in this stub → the manual trigger is offered.
	if !strings.Contains(compact, "gh workflow run upgrade-arc-harness.yaml --ref v2026.08.0-rc.02") {
		t.Errorf("with the orchestrator absent, the manual trigger is the next move; output:\n%s", compact)
	}

	detailed := run(true)
	if got := strings.Count(detailed, changedPath); got != 1 {
		t.Errorf("verbose refusal printed the shared changed path %d time(s), want exactly 1; output:\n%s", got, detailed)
	}
	if !strings.Contains(detailed, "Changed files since v2026.08.0-rc.01:") {
		t.Errorf("verbose refusal must list the literal changed files per anchor; output:\n%s", detailed)
	}
}

// TestUpgradeArcHarnessGate_DifferingBlockedAnchorsNameEachAnchor pins the
// multi-anchor shape: the summary names every anchor, each scenario's name
// carries its own anchor, and the git command blocks are printed once per
// anchor so each range is inspectable.
func TestUpgradeArcHarnessGate_DifferingBlockedAnchorsNameEachAnchor(t *testing.T) {
	dir, _ := arcFixture(t,
		"doc/readme.md",
		upgradeArcDir+"alpha"+upgradeArcSuffix,
		upgradeArcDir+"beta"+upgradeArcSuffix,
	)
	writeSensitivePathsFile(t, dir, "cli/internal/upgrade/")

	anchorOne := runGitInCmd(t, dir, "rev-parse", "HEAD")
	runGitInCmd(t, dir, "tag", "-a", "v2026.08.0-rc.01", "-m", "Pre-release v2026.08.0-rc.01")
	writeAndCommit(t, dir, "first sensitive change", "cli/internal/upgrade/service.go")
	anchorTwo := runGitInCmd(t, dir, "rev-parse", "HEAD")
	runGitInCmd(t, dir, "tag", "-a", "v2026.08.0-rc.02", "-m", "Pre-release v2026.08.0-rc.02")
	writeAndCommit(t, dir, "second sensitive change", "cli/internal/upgrade/exec.go")
	target := runGitInCmd(t, dir, "rev-parse", "HEAD")
	runGitInCmd(t, dir, "tag", "-a", "v2026.08.0-rc.03", "-m", "Pre-release v2026.08.0-rc.03")

	addOriginRemote(t, dir)
	pushTags(t, dir)
	stubScenarioEvidence(t, map[string]map[string]bool{
		"alpha": {anchorOne: true},
		"beta":  {anchorTwo: true},
	})
	stubWorkflowSeams(t, func(workflow, sha string) release.WorkflowCheckResult {
		return release.WorkflowCheckResult{Status: release.WorkflowCheckMissing}
	}, trivialComplete)

	oldVerbose := verboseFlag
	t.Cleanup(func() { verboseFlag = oldVerbose })

	run := func(wantVerbose bool) string {
		verboseFlag = func() bool { return wantVerbose }
		var verdict gateVerdict
		out := captureStdout(t, func() {
			verdict = checkUpgradeArcHarnessGate(dir, "v2026.08.0-rc.03", target, target[:7])
		})
		if verdict == gatePassed {
			t.Fatalf("the gate PASSED though both scenarios are blocked by sensitive changes; output:\n%s", out)
		}
		return out
	}

	out := run(false)
	if !strings.Contains(out, "0/2 scenarios have passed at "+target[:7]+
		". Results from earlier RCs cannot be reused because files used by these scenarios changed since v2026.08.0-rc.01, v2026.08.0-rc.02.") {
		t.Errorf("multi-anchor summary must name both anchors; output:\n%s", out)
	}
	for _, line := range []string{
		"alpha (anchor v2026.08.0-rc.01)",
		"beta (anchor v2026.08.0-rc.02)",
	} {
		if !strings.Contains(out, line) {
			t.Errorf("differing-anchor refusal omitted %q; output:\n%s", line, out)
		}
	}
	for _, anchor := range []string{"v2026.08.0-rc.01", "v2026.08.0-rc.02"} {
		if got := strings.Count(out, "git log --oneline "+anchor+".."+target[:7]+" -- "); got != 1 {
			t.Errorf("the review command for %s must print exactly once, got %d; output:\n%s", anchor, got, out)
		}
	}

	detailed := run(true)
	firstHeading := strings.Index(detailed, "    Changed files since v2026.08.0-rc.01:")
	firstExecPath := strings.Index(detailed, "        cli/internal/upgrade/exec.go")
	firstServicePath := strings.Index(detailed, "        cli/internal/upgrade/service.go")
	secondHeading := strings.Index(detailed, "    Changed files since v2026.08.0-rc.02:")
	secondExecPath := -1
	if secondHeading >= 0 {
		if rel := strings.Index(detailed[secondHeading:], "        cli/internal/upgrade/exec.go"); rel >= 0 {
			secondExecPath = secondHeading + rel
		}
	}
	if firstHeading < 0 || firstExecPath < firstHeading || firstServicePath < firstExecPath ||
		secondHeading < firstServicePath || secondExecPath < secondHeading {
		t.Errorf("verbose multi-anchor details are missing or nondeterministically ordered; output:\n%s", detailed)
	}
}

// A PASSED full LXD workflow is sufficient, while superseded/failure cannot
// masquerade as green through a per-scenario historical mark.
func TestLXDFleetGate_WorkflowResultAndBypass(t *testing.T) {
	for _, tc := range []struct {
		status release.WorkflowCheckStatus
		want   bool
	}{
		{release.WorkflowCheckGreen, true},
		{release.WorkflowCheckFailed, false},
		{release.WorkflowCheckPending, false},
		{release.WorkflowCheckUnknown, false},
	} {
		t.Run(string(tc.status), func(t *testing.T) {
			stubWorkflowSeams(t, func(workflow, sha string) release.WorkflowCheckResult {
				if workflow != release.WorkflowLXDFleet || sha != "sha" {
					t.Fatalf("wrong query %s %s", workflow, sha)
				}
				return release.WorkflowCheckResult{Status: tc.status, Detail: "superseded", RunURL: "https://example.invalid/run/1"}
			}, trivialComplete)
			var verdict gateVerdict
			captureStdout(t, func() { verdict = checkInstallRecoveryHarnessGate("", "rc", "sha", "sha") })
			if got := verdict == gatePassed; got != tc.want {
				t.Fatalf("status %s: got passed=%t, want %t", tc.status, got, tc.want)
			}
		})
	}
	t.Setenv("SKIP_INSTALL_RECOVERY", "1")
	out := captureStdout(t, func() {
		if checkInstallRecoveryHarnessGate("", "rc", "sha", "sha") != gatePassed {
			t.Fatal("explicit bypass must permit operator override")
		}
	})
	if !strings.Contains(out, "lxd-fleet SKIPPED") {
		t.Fatalf("bypass must name LXD gate: %s", out)
	}
}

// TestUpgradeArcDomainPathMatchesWorkflow is STATBUS-216 AC#4: the gate
// and the workflow's discover job read the SAME folder, from two separate
// copies of the path. This pins the Go constants against both the
// workflow file and the real tree, so a move that empties one reader fails
// here — loudly, with the paths named — instead of silently disarming the
// gate (the STATBUS-199 comment #6 duplication-guard pattern).
func TestUpgradeArcDomainPathMatchesWorkflow(t *testing.T) {
	const workflowFile = ".github/workflows/upgrade-arc-harness.yaml"
	data, err := os.ReadFile(thisRepoFile(t, workflowFile))
	if err != nil {
		t.Fatalf("cannot read %s: %v", workflowFile, err)
	}
	yaml := string(data)
	// The COMPOSED glob, not the two pieces separately: this is the exact
	// string the discover job enumerates the matrix with, so a folder move
	// cannot satisfy the pin by leaving the directory named in one place
	// and the suffix in another.
	wantGlob := upgradeArcDir + "*" + upgradeArcSuffix
	if !strings.Contains(yaml, wantGlob) {
		t.Fatalf("%s no longer contains the glob %q — the gate's arc domain "+
			"(upgradeArcDir/upgradeArcSuffix in cli/cmd/release.go) has drifted from the workflow's "+
			"discover job. The two must read ONE folder: update the Go constants to match the "+
			"workflow, or the workflow to match them", workflowFile, wantGlob)
	}

	entries, err := os.ReadDir(thisRepoFile(t, upgradeArcDir))
	if err != nil {
		t.Fatalf("the gate's arc directory %s does not exist in this tree: %v", upgradeArcDir, err)
	}
	arcs := 0
	for _, e := range entries {
		if strings.HasSuffix(e.Name(), upgradeArcSuffix) {
			arcs++
		}
	}
	if arcs == 0 {
		t.Fatalf("no *%s files under %s — the gate would derive an empty arc domain from this tree",
			upgradeArcSuffix, filepath.Clean(upgradeArcDir))
	}
}

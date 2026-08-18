package cmd

// STATBUS-216 / STATBUS-217 gate-level pins for the two harness
// completeness gates.
//
// 216: an empty scenario domain must REFUSE, never print a 0/0 pass. The
// assertion is on the gate's own boolean — a helper-level test would not
// catch a gate that ignored the error and passed anyway.
//
// 217: a required job that is present but concluded skipped/cancelled is
// not proof, and the refusal must name it distinctly from a job that was
// missing entirely (their operator remedies differ).
//
// The stubs below supply the GitHub API's answers through the release.go
// seam vars. They are deliberately the MOST PERMISSIVE answers possible —
// green run, "yes, complete" — so that a passing gate could only be
// passing on the strength of the empty domain itself. Without the seam
// these tests would run against the live API and return false for lack of
// network, pinning nothing.

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/release"
)

// stubWorkflowSeams swaps the two GitHub-API seams for the duration of a
// test and restores them afterwards.
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

// alwaysGreen answers every workflow query with a green run.
func alwaysGreen(workflow, commitSHA string) release.WorkflowCheckResult {
	return release.WorkflowCheckResult{
		Status: release.WorkflowCheckGreen,
		RunID:  42,
		RunURL: "https://github.com/statisticsnorway/statbus/actions/runs/42",
	}
}

// trivialComplete is the pre-STATBUS-216 reading of the completeness
// check: "is every required job present?" answered against whatever list
// it is handed — including an empty one, where the answer is trivially
// yes. A gate that passes with this stub and an empty domain is passing
// on the strength of nothing at all.
func trivialComplete(runID int64, requiredJobNames []string) (release.JobsCompleteness, error) {
	return release.JobsCompleteness{Complete: true}, nil
}

// arcFixture builds a git repo containing exactly the given repo-relative
// files and returns (dir, HEAD sha).
func arcFixture(t *testing.T, paths ...string) (string, string) {
	t.Helper()
	dir := t.TempDir()
	runGitInCmd(t, dir, "init", "-q")
	writeAndCommit(t, dir, "fixture", paths...)
	return dir, runGitInCmd(t, dir, "rev-parse", "HEAD")
}

// TestUpgradeArcHarnessGate_EmptyArcDomainRefuses is STATBUS-216 AC#2. The
// arcs directory is absent at the commit (the "renamed one directory"
// state), the run is green, and the completeness check would happily say
// "complete". The gate must still refuse.
func TestUpgradeArcHarnessGate_EmptyArcDomainRefuses(t *testing.T) {
	dir, head := arcFixture(t, "doc/readme.md")
	stubWorkflowSeams(t, alwaysGreen, trivialComplete)

	var passed bool
	out := captureStdout(t, func() {
		passed = checkUpgradeArcHarnessGate(dir, "v2026.08.0-rc.01", head, head[:7])
	})
	if passed {
		t.Fatalf("the arc gate PASSED with an empty arc domain — a 0/0 completeness check proves "+
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

// TestUpgradeArcHarnessGate_PopulatedDomainPasses is the positive control
// for the test above: with the SAME stubs and one real arc present, the
// gate passes. Without this arm, the refusal test could pass for an
// unrelated reason (a broken fixture, a stub that never gets consulted).
func TestUpgradeArcHarnessGate_PopulatedDomainPasses(t *testing.T) {
	dir, head := arcFixture(t, "doc/readme.md", upgradeArcDir+"working"+upgradeArcSuffix)

	var sawRequired []string
	stubWorkflowSeams(t, alwaysGreen,
		func(runID int64, requiredJobNames []string) (release.JobsCompleteness, error) {
			sawRequired = requiredJobNames
			return release.JobsCompleteness{Complete: true}, nil
		})

	var passed bool
	out := captureStdout(t, func() {
		passed = checkUpgradeArcHarnessGate(dir, "v2026.08.0-rc.01", head, head[:7])
	})
	if !passed {
		t.Fatalf("the arc gate refused a green, complete run over a populated arc domain; output:\n%s", out)
	}
	if len(sawRequired) != 1 || sawRequired[0] != "working" {
		t.Errorf("the gate must ask about the arc names derived from the commit, got %v (want [working])", sawRequired)
	}
}

// TestUpgradeArcHarnessGate_SkippedArcJobRefuses is STATBUS-217 AC#3 at
// the arc gate: the required job was present but concluded `skipped`,
// which leaves the run GREEN. That is not a full-suite proof, so the gate
// must not accept the run — and the refusal must say the job did not run,
// not that it was missing.
func TestUpgradeArcHarnessGate_SkippedArcJobRefuses(t *testing.T) {
	dir, head := arcFixture(t, "doc/readme.md", upgradeArcDir+"working"+upgradeArcSuffix)
	stubWorkflowSeams(t, alwaysGreen,
		func(runID int64, requiredJobNames []string) (release.JobsCompleteness, error) {
			return release.JobsCompleteness{
				Complete:     false,
				Unsuccessful: []release.UnsuccessfulJob{{Name: "working", Conclusion: "skipped"}},
			}, nil
		})

	var passed bool
	out := captureStdout(t, func() {
		passed = checkUpgradeArcHarnessGate(dir, "v2026.08.0-rc.01", head, head[:7])
	})
	if passed {
		t.Fatalf("the arc gate PASSED a green run whose only required arc job was SKIPPED — "+
			"a skipped job never executed the scenario (STATBUS-217); output:\n%s", out)
	}
	if !strings.Contains(out, "DID NOT RUN") || !strings.Contains(out, "skipped") {
		t.Errorf("the refusal must report the arc as present-but-not-run, naming its conclusion; output:\n%s", out)
	}
}

// TestInstallRecoveryHarnessGate_EmptyScenarioDomainRefuses is the same
// STATBUS-216 hole on the second consumer of the shared helper. This gate
// has no path-sensitivity walk-back, so the empty domain is decisive on
// its own.
func TestInstallRecoveryHarnessGate_EmptyScenarioDomainRefuses(t *testing.T) {
	dir, head := arcFixture(t, "doc/readme.md")
	stubWorkflowSeams(t, alwaysGreen, trivialComplete)

	var passed bool
	out := captureStdout(t, func() {
		passed = checkInstallRecoveryHarnessGate(dir, "v2026.08.0-rc.01", head, head[:7])
	})
	if passed {
		t.Fatalf("the install-recovery gate PASSED with an empty scenario domain (STATBUS-216); output:\n%s", out)
	}
	if !strings.Contains(out, "scenario domain") {
		t.Errorf("the refusal must name the scenario domain as the cause; output:\n%s", out)
	}
}

// TestInstallRecoveryHarnessGate_MissingAndSkippedReportedApart is
// STATBUS-217 AC#2 + AC#4: the second caller of the shared helper gets the
// same strengthening, and its refusal separates the two buckets — one job
// never in the run, one present but skipped.
func TestInstallRecoveryHarnessGate_MissingAndSkippedReportedApart(t *testing.T) {
	dir, head := arcFixture(t,
		"test/install-recovery/scenarios/working.sh",
		"test/install-recovery/scenarios/failing.sh",
	)
	stubWorkflowSeams(t, alwaysGreen,
		func(runID int64, requiredJobNames []string) (release.JobsCompleteness, error) {
			return release.JobsCompleteness{
				Complete:     false,
				Missing:      []string{"failing"},
				Unsuccessful: []release.UnsuccessfulJob{{Name: "working", Conclusion: "skipped"}},
			}, nil
		})

	var passed bool
	out := captureStdout(t, func() {
		passed = checkInstallRecoveryHarnessGate(dir, "v2026.08.0-rc.01", head, head[:7])
	})
	if passed {
		t.Fatalf("the install-recovery gate PASSED an incomplete job set; output:\n%s", out)
	}
	missingIdx := strings.Index(out, "MISSING (never in the run): failing")
	skippedIdx := strings.Index(out, "DID NOT RUN (present, no green): working (conclusion: skipped)")
	if missingIdx < 0 || skippedIdx < 0 {
		t.Fatalf("the refusal must report the two buckets under distinct labels — a job absent from "+
			"the run and a job that was skipped need different fixes (STATBUS-217 AC#2); output:\n%s", out)
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

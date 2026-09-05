package cmd

import (
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/release"
)

// TestCoverageAuthority_StructuralViolationIsUndecidable_STATBUS352 is the
// Work A review's finding 1, reproduced through the REAL interfaces. An
// EXCLUDED (HARNESS_SKIP_DEFAULT) sibling gains a forbidden fabrication call.
// Every required scenario is unchanged and marked at the anchor, so before
// this fix `covered-subset` returned exit 0 with empty stdout (all covered)
// and stable promotion accepted inherited evidence, while the runner itself
// would have refused the repository.
//
// Now the target commit's own run.sh validation is a prerequisite of the
// shared evaluator: covered-subset exits 2 with NO partial stdout (the
// orchestrator dispatches the full suite), `covered` exits 2, and the
// promotion authority refuses. The clean sibling control proves the same
// fixture is covered when the sibling is merely edited, not forbidden.
func TestCoverageAuthority_StructuralViolationIsUndecidable_STATBUS352(t *testing.T) {
	api := emptyEvidenceServer(t)

	build := func(t *testing.T, siblingContent string) (dir, anchor, binary string) {
		t.Helper()
		dir, anchor, target := realCoverageFixture(t, "doc/readme.md")
		// Add the excluded sibling AFTER the anchor so its content is the only
		// diff; it is outside the default fleet domain either way.
		writeFixtureFile(t, dir, "test/install-recovery/scenarios/known-red.sh", siblingContent)
		runGitInCmd(t, dir, "add", ".")
		runGitInCmd(t, dir, "commit", "-q", "-m", "excluded sibling")
		target = runGitInCmd(t, dir, "rev-parse", "HEAD")
		for _, name := range []string{"a", "b", "0-happy-install", "0-happy-upgrade"} {
			markScenarioAt(t, dir, release.Scenario{Name: name, Home: release.WorkflowFleet}, anchor)
		}
		return dir, anchor, buildSBForCoverageInterface(t, target)
	}

	t.Run("clean excluded sibling stays covered (control)", func(t *testing.T) {
		dir, _, binary := build(t, "#!/bin/bash\n# HARNESS_SKIP_DEFAULT: deliberate known-red\necho red\n")
		subset := runBuiltCoverage(t, binary, dir, api.URL, "release", "covered-subset", release.WorkflowFleet.String(), "HEAD")
		if subset.exit != exitCovered || subset.stdout != "" {
			t.Fatalf("control subset exit=%d stdout=%q stderr=%q", subset.exit, subset.stdout, subset.stderr)
		}
	})

	t.Run("forbidden excluded sibling is undecidable everywhere", func(t *testing.T) {
		dir, _, binary := build(t, "#!/bin/bash\n# HARNESS_SKIP_DEFAULT: deliberate known-red\nfabricate_forbidden_state \"$VM_NAME\"\n")

		subset := runBuiltCoverage(t, binary, dir, api.URL, "release", "covered-subset", release.WorkflowFleet.String(), "HEAD")
		if subset.exit != exitUndecided || subset.stdout != "" || !strings.Contains(subset.stderr, "FABRICATION") {
			t.Fatalf("subset must be undecidable with no partial stdout and the runner's diagnostic; exit=%d stdout=%q stderr=%q", subset.exit, subset.stdout, subset.stderr)
		}
		one := runBuiltCoverage(t, binary, dir, api.URL, "release", "covered", "--workflow", release.WorkflowFleet.String(), "a", "HEAD")
		if one.exit != exitUndecided {
			t.Fatalf("covered must be undecidable; exit=%d stdout=%q stderr=%q", one.exit, one.stdout, one.stderr)
		}
		// Arc coverage shares the evaluator, so it is undecidable too: the
		// structural doctrine spans both directories.
		arcs := runBuiltCoverage(t, binary, dir, api.URL, "release", "covered-subset", release.WorkflowArcs.String(), "HEAD")
		if arcs.exit != exitUndecided || arcs.stdout != "" {
			t.Fatalf("arc subset must be undecidable; exit=%d stdout=%q stderr=%q", arcs.exit, arcs.stdout, arcs.stderr)
		}

		// Promotion authority (the in-process gate) must refuse, not pass.
		head := runGitInCmd(t, dir, "rev-parse", "HEAD")
		domain, err := release.ScenariosAt(dir, head, release.WorkflowFleet)
		if err != nil {
			t.Fatal(err)
		}
		var passed bool
		out := captureStdout(t, func() {
			passed = runCoverageAuthority(dir, "v2026.09.0-rc.02", head, head[:7], domain)
		})
		if passed || !strings.Contains(out, "structural validation") {
			t.Fatalf("promotion authority must refuse on a structural violation; passed=%v output:\n%s", passed, out)
		}
	})
}

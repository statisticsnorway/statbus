package releasecmd

import (
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/release"
)

// The active arc coverage evaluator still validates every scenario file at
// the target commit before answering: an excluded but forbidden sibling
// makes covered-subset undecidable, while a clean sibling preserves coverage.
func TestCoverageAuthority_StructuralViolationIsUndecidable_STATBUS352(t *testing.T) {
	api := emptyEvidenceServer(t)
	for _, tc := range []struct {
		name, sibling string
		invalid       bool
	}{
		{"clean excluded sibling", "#!/bin/bash\n# HARNESS_SKIP_DEFAULT: deliberate known-red\necho red\n", false},
		{"forbidden excluded sibling", "#!/bin/bash\n# HARNESS_SKIP_DEFAULT: deliberate known-red\nfabricate_forbidden_state \"$VM_NAME\"\n", true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			dir, anchor, _ := realCoverageFixture(t, "doc/readme.md")
			writeFixtureFile(t, dir, "test/install-recovery/scenarios/known-red.sh", tc.sibling)
			runGitInCmd(t, dir, "add", ".")
			runGitInCmd(t, dir, "commit", "-q", "-m", "excluded sibling")
			target := runGitInCmd(t, dir, "rev-parse", "HEAD")
			for _, name := range []string{"working", "failing", "deploy-status-proof"} {
				markScenarioAt(t, dir, release.Scenario{Name: name, Home: release.WorkflowArcs}, anchor)
			}
			binary := buildSBForCoverageInterface(t, target)
			result := runBuiltCoverage(t, binary, dir, api.URL, "release", "covered-subset", release.WorkflowArcs.String(), "HEAD")
			if tc.invalid {
				if result.exit != exitUndecided || result.stdout != "" || !strings.Contains(result.stderr, "FABRICATION") {
					t.Fatalf("invalid sibling must block arc coverage: exit=%d stdout=%q stderr=%q", result.exit, result.stdout, result.stderr)
				}
			} else if result.exit != exitCovered || result.stdout != "" {
				t.Fatalf("clean sibling must preserve covered arcs: exit=%d stdout=%q stderr=%q", result.exit, result.stdout, result.stderr)
			}
		})
	}
}

package cmd

import (
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/release"
)

// The `./sb release covered` call site must look a scenario up under the
// workflow that actually runs it — the same domain listing each promotion gate
// uses — not under one hardcoded workflow. Observed live at v2026.09.0-rc.12:
// install-recovery-harness run 33734979777 was green on all 15 fleet scenarios,
// yet `covered <fleet-scenario> <rc.12>` reported "no evidence found" because
// it asked the arc harness. The two call sites of DecideCoverage are supposed to
// be the same by design (STATBUS-249); this pins that they consult the same
// workflow identity for the same scenario.
func TestScenarioHomeWorkflowAtCommit_FollowsTheScenarioDirectory(t *testing.T) {
	dir, head := arcFixture(t,
		"doc/readme.md",
		upgradeArcDir+"postswap-mid-tx-kill"+upgradeArcSuffix,
		"test/install-recovery/scenarios/5-install-stage-e-worker-busy.sh",
	)

	cases := []struct {
		scenario string
		want     string
	}{
		{"postswap-mid-tx-kill", release.WorkflowUpgradeArcHarness},
		{"5-install-stage-e-worker-busy", release.WorkflowInstallRecoveryHarness},
	}
	for _, c := range cases {
		got, err := scenarioHomeWorkflowAtCommit(dir, c.scenario, head)
		if err != nil {
			t.Fatalf("%s: %v", c.scenario, err)
		}
		if got != c.want {
			t.Errorf("%s: home workflow = %q, want %q", c.scenario, got, c.want)
		}
	}

	if _, err := scenarioHomeWorkflowAtCommit(dir, "no-such-scenario", head); err == nil {
		t.Fatal("an unknown scenario name must be refused, not looked up under a guessed workflow")
	} else if !strings.Contains(err.Error(), "not a scenario at") {
		t.Errorf("refusal must name the problem; got: %v", err)
	}
}

// decideScenarioCoverage wires the seam the gate uses (scenarioEvidence), so a
// test stub sees exactly which workflow the covered command asked under.
func TestDecideScenarioCoverage_AsksTheScenarioHomeWorkflow(t *testing.T) {
	dir, head := arcFixture(t,
		"doc/readme.md",
		upgradeArcDir+"working"+upgradeArcSuffix,
		"test/install-recovery/scenarios/0-happy-install.sh",
	)
	writeSensitivePathsFile(t, dir, "cli/internal/upgrade/")
	addOriginRemote(t, dir)

	asked := map[string]string{}
	old := scenarioEvidence
	scenarioEvidence = func(projDir, workflow, scenario string) release.EvidenceAt {
		asked[scenario] = workflow
		return func(commit string) (bool, string, error) { return true, "stub", nil }
	}
	t.Cleanup(func() { scenarioEvidence = old })

	for _, scenario := range []string{"working", "0-happy-install"} {
		if _, err := decideScenarioCoverage(dir, scenario, head); err != nil {
			t.Fatalf("%s: %v", scenario, err)
		}
	}
	if asked["working"] != release.WorkflowUpgradeArcHarness {
		t.Errorf("arc scenario asked under %q, want %q", asked["working"], release.WorkflowUpgradeArcHarness)
	}
	if asked["0-happy-install"] != release.WorkflowInstallRecoveryHarness {
		t.Errorf("fleet scenario asked under %q, want %q", asked["0-happy-install"], release.WorkflowInstallRecoveryHarness)
	}
}

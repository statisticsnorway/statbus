package cmd

import (
	"os"
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
func TestParseScenario_FollowsTheScenarioDirectory(t *testing.T) {
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
		got, err := release.ParseScenario(dir, head, c.scenario)
		if err != nil {
			t.Fatalf("%s: %v", c.scenario, err)
		}
		if got.Home.String() != c.want {
			t.Errorf("%s: home workflow = %q, want %q", c.scenario, got.Home, c.want)
		}
	}

	if _, err := release.ParseScenario(dir, head, "no-such-scenario"); err == nil {
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
	scenarioEvidence = func(projDir string, scenario release.Scenario) release.EvidenceAt {
		asked[scenario.Name] = scenario.Home.String()
		return func(commit string) (bool, string, error) { return true, "stub", nil }
	}
	t.Cleanup(func() { scenarioEvidence = old })

	if _, err := decideScenarioCoverage(dir, "working", head); err != nil {
		t.Fatalf("working: %v", err)
	}
	if _, err := decideScenarioCoverageInWorkflow(dir, "0-happy-install", release.WorkflowFleet, head); err != nil {
		t.Fatalf("fleet happy install: %v", err)
	}
	if _, err := decideScenarioCoverageInWorkflow(dir, "0-happy-install", release.WorkflowSmoke, head); err != nil {
		t.Fatalf("smoke happy install: %v", err)
	}
	if _, err := decideScenarioCoverage(dir, "0-happy-install", head); err == nil || !strings.Contains(err.Error(), "ambiguous") {
		t.Fatalf("bare same-name scenario must be ambiguous, got %v", err)
	}
	if asked["working"] != release.WorkflowUpgradeArcHarness {
		t.Errorf("arc scenario asked under %q, want %q", asked["working"], release.WorkflowUpgradeArcHarness)
	}
	if asked["0-happy-install"] != release.WorkflowInstallRecoveryHarness {
		// The last explicit decision above is Smoke, proving the seam receives the
		// requested full identity rather than re-parsing the slug as Fleet.
		if asked["0-happy-install"] != release.WorkflowTestSmoke {
			t.Errorf("same-name scenario asked under %q, want final explicit %q", asked["0-happy-install"], release.WorkflowTestSmoke)
		}
	}
}

func TestDecideWorkflowCoverage_ReturnsOnlyTheWorkflowDomain_STATBUS351(t *testing.T) {
	dir, head := arcFixture(t,
		upgradeArcDir+"covered-one"+upgradeArcSuffix,
		upgradeArcDir+"must-run"+upgradeArcSuffix,
		"test/install-recovery/scenarios/fleet-only.sh",
	)
	writeSensitivePathsFile(t, dir, "cli/internal/upgrade/")
	addOriginRemote(t, dir)

	old := scenarioEvidence
	scenarioEvidence = func(_ string, scenario release.Scenario) release.EvidenceAt {
		return func(commit string) (bool, string, error) {
			return scenario.Name == "covered-one", "stub at " + commit, nil
		}
	}
	t.Cleanup(func() { scenarioEvidence = old })

	results, err := decideWorkflowCoverage(dir, release.WorkflowArcs, head)
	if err != nil {
		t.Fatal(err)
	}
	if got := uncoveredScenarioNames(results); len(got) != 1 || got[0] != "must-run" {
		t.Fatalf("uncovered arc selectors = %v, want [must-run]", got)
	}
	for _, result := range results {
		if result.Scenario.Name == "fleet-only" {
			t.Fatal("arc workflow subset must not include a fleet scenario")
		}
	}
}

func TestCoveredSubsetDetail_NamesCoveredAnchor_STATBUS351(t *testing.T) {
	result := workflowCoverageResult{
		Scenario: release.Scenario{Name: "postswap-health-park", Home: release.WorkflowArcs},
		Verdict: release.CoverageVerdict{
			Scenario: "postswap-health-park",
			Kind:     release.CoverageCoveredBy,
			Anchor:   "v2026.09.0-rc.14",
		},
	}
	got := coveredSubsetDetail(result)
	if !strings.Contains(got, "SKIPPED") || !strings.Contains(got, "v2026.09.0-rc.14") {
		t.Fatalf("covered summary must name SKIPPED and its anchor; got %q", got)
	}
}

// TestGuardExitNeverCollidesWithCoveredVerdicts pins the exit-code contract
// the orchestrator branches on: the staleness guard's refusal is 69
// (EX_UNAVAILABLE) and `covered`'s three verdicts are 0/1/2. Before this, both
// used 2, and a stale build rendered as "undecidable → must run".
func TestGuardExitNeverCollidesWithCoveredVerdicts(t *testing.T) {
	if exitBinaryUnusable == exitCovered || exitBinaryUnusable == exitMustRun || exitBinaryUnusable == exitUndecided {
		t.Fatalf("exitBinaryUnusable=%d collides with a covered verdict code", exitBinaryUnusable)
	}
	if exitBinaryUnusable != 69 {
		t.Fatalf("exitBinaryUnusable = %d, want 69 (EX_UNAVAILABLE); the orchestrator's case arm is written for 69", exitBinaryUnusable)
	}
	src, err := os.ReadFile("root.go")
	if err != nil {
		t.Fatal(err)
	}
	guard := extractGuardBody(t, string(src))
	if strings.Contains(guard, "os.Exit(2)") {
		t.Fatal("stalenessGuard still exits 2 somewhere; that is a covered verdict code")
	}
}

func extractGuardBody(t *testing.T, src string) string {
	t.Helper()
	start := strings.Index(src, "func stalenessGuard(")
	if start < 0 {
		t.Fatal("stalenessGuard not found")
	}
	end := strings.Index(src[start:], "\n}\n")
	return src[start : start+end]
}

package cmd

import (
	"os"
	"strings"
	"testing"
)

const authoritativeHarnessDomainValidation = "./dev.sh test-install-recovery --print-selected >/dev/null"

func stepIndexByName(t *testing.T, steps []map[string]any, name string) int {
	t.Helper()
	for i, step := range steps {
		if got, _ := step["name"].(string); got == name {
			return i
		}
	}
	t.Fatalf("no workflow step named %q", name)
	return -1
}

func TestSupersededCandidateStopsBeforeEachVMAndPropagatesFleetVerdict_STATBUS416(t *testing.T) {
	guard := workflowDoc(t, ".github/actions/scenario-superseded/action.yml")
	guardSteps := guard["runs"].(map[string]any)["steps"].([]any)
	if guardSteps[1].(map[string]any)["uses"] != "actions/upload-artifact@v4" {
		t.Fatal("every scenario must publish its freshness marker inside the first composite action")
	}
	aggregate := workflowDoc(t, ".github/actions/scenario-fleet-verdict/action.yml")
	if aggregate["runs"].(map[string]any)["steps"].([]any)[2].(map[string]any)["with"].(map[string]any)["name"] != "fleet-verdict" {
		t.Fatal("child fleet verdict must be available as a named artifact to workflow_dispatch parent")
	}
	for _, tc := range []struct{ file, job, selector string }{
		{".github/workflows/test-smoke.yaml", "smoke", "select"},
		{".github/workflows/install-recovery-harness.yaml", "run-scenario", "discover"},
		{".github/workflows/upgrade-arc-harness.yaml", "run-arc", "discover"},
	} {
		t.Run(tc.job, func(t *testing.T) {
			doc := workflowDoc(t, tc.file)
			lock := doc["concurrency"].(map[string]any)
			if lock["group"] != "hetzner-vm-fleet" || lock["cancel-in-progress"] != false || lock["queue"] != "max" {
				t.Fatalf("%s must retain shared non-cancelling VM capacity lock: %v", tc.file, lock)
			}
			steps := jobSteps(t, tc.file, tc.job)
			if len(steps) < 3 || steps[0]["uses"] != "actions/checkout@v4" || steps[1]["uses"] != "./.github/actions/scenario-superseded" || steps[1]["id"] != "freshness" {
				t.Fatalf("%s must check freshness as first post-checkout VM job step", tc.job)
			}
			with := steps[1]["with"].(map[string]any)
			if with["candidate-ref"] != "${{ github.ref_name }}" || with["scenario"] != "${{ matrix.scenario }}" {
				t.Fatalf("%s freshness guard must receive its candidate tag and scenario: %v", tc.job, with)
			}
			for _, step := range steps[2:] {
				condition, _ := step["if"].(string)
				if !strings.Contains(condition, "steps.freshness.outputs.superseded != 'true'") {
					t.Errorf("%s step %v can run after supersession: if=%q", tc.job, step["name"], condition)
				}
			}
			jobs := doc["jobs"].(map[string]any)
			verdict := jobs["fleet-verdict"].(map[string]any)
			if !strings.Contains(verdict["if"].(string), "always()") || verdict["outputs"].(map[string]any)["superseded"] != "${{ steps.verdict.outputs.superseded }}" {
				t.Fatalf("%s must aggregate even after scenario failure and expose superseded: %v", tc.file, verdict)
			}
			vsteps := jobSteps(t, tc.file, "fleet-verdict")
			if vsteps[1]["uses"] != "./.github/actions/scenario-fleet-verdict" ||
				!strings.Contains(vsteps[1]["with"].(map[string]any)["matrix-json"].(string), "needs."+tc.selector+".outputs.matrix") {
				t.Fatalf("%s must aggregate the exact selected matrix", tc.file)
			}
		})
	}

	dispatch, err := os.ReadFile(thisRepoFile(t, ".github/actions/dispatch-fleet-and-wait/dispatch.sh"))
	if err != nil {
		t.Fatal(err)
	}
	for _, required := range []string{"gh run download \"$run_id\" --name fleet-verdict", "SUPERSEDED)", "superseded=true", "Missing fleet verdict"} {
		if !strings.Contains(string(dispatch), required) {
			t.Errorf("dispatch must distinguish child supersession and reject success without verdict: missing %q", required)
		}
	}
	orchestrator := workflowDoc(t, ".github/workflows/release-fleet-orchestrator.yaml")
	jobs := orchestrator["jobs"].(map[string]any)
	for _, job := range []string{"smoke", "install-recovery-harness", "upgrade-arc-harness"} {
		outputs := jobs[job].(map[string]any)["outputs"].(map[string]any)
		if outputs["superseded"] != "${{ steps.dispatch.outputs.superseded }}" {
			t.Errorf("%s must expose child fleet verdict", job)
		}
	}
	if !strings.Contains(jobs["dev-canary"].(map[string]any)["if"].(string), "needs['smoke'].outputs.superseded != 'true'") ||
		!strings.Contains(jobs["upgrade-arc-harness"].(map[string]any)["if"].(string), "needs['install-recovery-harness'].outputs.superseded != 'true'") {
		t.Fatal("a superseded child fleet must not dispatch the next fleet")
	}
	final := jobSteps(t, ".github/workflows/release-fleet-orchestrator.yaml", "fleet-verdict")
	check := final[1]["run"].(string)
	if !strings.Contains(check, `[ "$SMOKE_SUPERSEDED" = true ]`) ||
		!strings.Contains(check, `[ "$INSTALL_SUPERSEDED" = true ]`) ||
		!strings.Contains(check, `[ "$UPGRADE_SUPERSEDED" = true ]`) ||
		!strings.Contains(check, `echo "obsolete=true" >> "$GITHUB_OUTPUT"`) {
		t.Fatal("final verdict must honor child-observed supersession when its own tag refresh fails")
	}
}

func stepIndexByRunContains(t *testing.T, steps []map[string]any, command string) int {
	t.Helper()
	for i, step := range steps {
		if run, _ := step["run"].(string); strings.Contains(run, command) {
			return i
		}
	}
	t.Fatalf("no workflow step runs %q", command)
	return -1
}

func TestHarnessDomainValidationPrecedesCoverageAndPaidEligibility_STATBUS352(t *testing.T) {
	t.Run("orchestrator validates both target domains before coverage", func(t *testing.T) {
		// Every paid joint, including the FIRST one (smoke): an all-covered
		// answer that dispatches nothing must still have passed validation.
		for _, job := range []string{"smoke", "install-recovery-harness", "upgrade-arc-harness"} {
			steps := jobSteps(t, ".github/workflows/release-fleet-orchestrator.yaml", job)
			validation := stepIndexByRunContains(t, steps, authoritativeHarnessDomainValidation)
			coverage := stepIndexByName(t, steps, "Decision point: which scenarios are uncovered?")
			if validation >= coverage {
				t.Fatalf("%s validates the scenario/arc domain at step %d, not before covered-subset at step %d", job, validation, coverage)
			}
			script, _ := steps[validation]["run"].(string)
			if strings.Count(script, authoritativeHarnessDomainValidation) != 1 {
				t.Fatalf("%s must invoke the one authoritative runner validator exactly once, got:\n%s", job, script)
			}
		}
	})

	t.Run("smoke matrix eligibility follows admission then validation", func(t *testing.T) {
		steps := jobSteps(t, ".github/workflows/test-smoke.yaml", "select")
		admission := -1
		for i, step := range steps {
			if uses, _ := step["uses"].(string); uses == "./.github/actions/orchestrator-fleet-admission" {
				admission = i
			}
		}
		if admission < 0 {
			t.Fatal("test-smoke select must revalidate orchestrated admission")
		}
		validation := stepIndexByRunContains(t, steps, authoritativeHarnessDomainValidation)
		matrix := stepIndexByName(t, steps, "Validate selectors and build matrix")
		if admission >= validation || validation >= matrix {
			t.Fatalf("test-smoke select order must be admission (%d) < domain validation (%d) < matrix (%d)", admission, validation, matrix)
		}
		script, _ := steps[validation]["run"].(string)
		if strings.Count(script, authoritativeHarnessDomainValidation) != 1 {
			t.Fatalf("test-smoke select must invoke the one authoritative runner validator exactly once, got:\n%s", script)
		}

		doc := workflowDoc(t, ".github/workflows/test-smoke.yaml")
		jobs := doc["jobs"].(map[string]any)
		smoke := jobs["smoke"].(map[string]any)
		needs, ok := smoke["needs"].([]any)
		if !ok || len(needs) != 1 || needs[0] != "select" {
			t.Fatalf("paid smoke matrix must depend only on the validated select job; needs=%v", smoke["needs"])
		}
	})

	t.Run("install matrix uses exact mode only after successful discovery", func(t *testing.T) {
		steps := jobSteps(t, ".github/workflows/install-recovery-harness.yaml", "run-scenario")
		scripts := runScriptsWithoutComments(steps)
		if !strings.Contains(scripts, `./dev.sh test-install-recovery --exact "$SCENARIO"`) {
			t.Fatalf("paid install-recovery matrix job does not use the explicit exact boundary:\n%s", scripts)
		}

		doc := workflowDoc(t, ".github/workflows/install-recovery-harness.yaml")
		jobs := doc["jobs"].(map[string]any)
		runJob := jobs["run-scenario"].(map[string]any)
		condition, _ := runJob["if"].(string)
		for _, required := range []string{"needs.discover.result == 'success'", "needs.discover.outputs.count != '0'"} {
			if !strings.Contains(condition, required) {
				t.Errorf("paid install-recovery matrix lost discovery gate %q: if=%q", required, condition)
			}
		}
	})

	t.Run("upgrade arc discovery validates before matrix enumeration", func(t *testing.T) {
		steps := jobSteps(t, ".github/workflows/upgrade-arc-harness.yaml", "discover")
		validation := stepIndexByRunContains(t, steps, authoritativeHarnessDomainValidation)
		enumeration := stepIndexByName(t, steps, "Enumerate arc scenarios into the matrix")
		if validation >= enumeration {
			t.Fatalf("upgrade-arc discover validates at step %d, not before matrix enumeration at step %d", validation, enumeration)
		}
		script, _ := steps[validation]["run"].(string)
		if strings.Count(script, authoritativeHarnessDomainValidation) != 1 {
			t.Fatalf("upgrade-arc discover must invoke the one authoritative runner validator exactly once, got:\n%s", script)
		}
	})

	t.Run("upgrade arc construction waits for validated nonzero discovery", func(t *testing.T) {
		doc := workflowDoc(t, ".github/workflows/upgrade-arc-harness.yaml")
		jobs := doc["jobs"].(map[string]any)
		construct := jobs["construct"].(map[string]any)

		needs, ok := construct["needs"].([]any)
		if !ok || len(needs) != 1 || needs[0] != "discover" {
			t.Fatalf("construct must depend only on successful authoritative discover before fixture/image side effects; needs=%v", construct["needs"])
		}
		condition, _ := construct["if"].(string)
		for _, required := range []string{"!cancelled()", "needs.discover.result == 'success'", "needs.discover.outputs.count != '0'"} {
			if !strings.Contains(condition, required) {
				t.Errorf("construct lost discovery gate %q: if=%q", required, condition)
			}
		}

		steps := jobSteps(t, ".github/workflows/upgrade-arc-harness.yaml", "construct")
		if len(steps) < 2 {
			t.Fatalf("construct has fewer than checkout + admission steps: %v", steps)
		}
		checkout, _ := steps[0]["uses"].(string)
		admission, _ := steps[1]["uses"].(string)
		if checkout != "actions/checkout@v4" || admission != "./.github/actions/orchestrator-fleet-admission" {
			t.Fatalf("eligible construct must keep checkout then shared admission as its first side-effectful guard; first uses=%q second uses=%q", checkout, admission)
		}
	})
}

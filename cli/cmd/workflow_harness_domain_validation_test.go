package cmd

import (
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

func TestHarnessDomainValidationPrecedesCoverageAndPaidEligibility_STATBUS352(t *testing.T) {
	t.Run("orchestrator validates both target domains before coverage", func(t *testing.T) {
		for _, job := range []string{"install-recovery-harness", "upgrade-arc-harness"} {
			steps := jobSteps(t, ".github/workflows/release-fleet-orchestrator.yaml", job)
			validation := stepIndexByName(t, steps, "Validate install-recovery and upgrade-arc domains")
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
		validation := stepIndexByName(t, steps, "Validate install-recovery and upgrade-arc domains")
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

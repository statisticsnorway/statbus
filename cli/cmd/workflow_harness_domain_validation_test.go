package cmd

import (
	"fmt"
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
	for _, job := range []string{"smoke", "upgrade-arc-harness"} {
		outputs := jobs[job].(map[string]any)["outputs"].(map[string]any)
		if outputs["superseded"] != "${{ steps.dispatch.outputs.superseded }}" {
			t.Errorf("%s must expose child fleet verdict", job)
		}
	}
	if !strings.Contains(jobs["dev-canary"].(map[string]any)["if"].(string), "needs['smoke'].outputs.superseded != 'true'") ||
		!strings.Contains(jobs["upgrade-arc-harness"].(map[string]any)["if"].(string), "needs['dev-canary'].result == 'success'") ||
		!strings.Contains(jobs["lxd-fleet"].(map[string]any)["if"].(string), "needs['dev-canary'].result == 'success'") {
		t.Fatal("a superseded child fleet must not dispatch the next fleet")
	}
	// STATBUS-425 M4: faults and arcs are siblings after dev. Neither may be
	// serialized behind the other (the previous chain was smoke>dev>faults>arcs).
	for job, other := range map[string]string{"upgrade-arc-harness": "lxd-fleet", "lxd-fleet": "upgrade-arc-harness"} {
		j := jobs[job].(map[string]any)
		if strings.Contains(fmt.Sprint(j["needs"]), other) || strings.Contains(j["if"].(string), other) {
			t.Fatalf("%s must not depend on %s: faults and arcs run concurrently", job, other)
		}
	}
	final := jobSteps(t, ".github/workflows/release-fleet-orchestrator.yaml", "fleet-verdict")
	// LXD supersession joins the surviving VM fleet verdicts.
	check := ""
	for _, step := range final {
		if run, _ := step["run"].(string); strings.Contains(run, `[ "$SMOKE_SUPERSEDED" = true ]`) {
			check = run
			break
		}
	}
	if !strings.Contains(check, `[ "$SMOKE_SUPERSEDED" = true ]`) ||
		!strings.Contains(check, `[ "$LXD_SUPERSEDED" = true ]`) ||
		!strings.Contains(check, `[ "$UPGRADE_SUPERSEDED" = true ]`) ||
		!strings.Contains(check, `echo "obsolete=true" >> "$GITHUB_OUTPUT"`) {
		t.Fatal("final verdict must honor child-observed supersession when its own tag refresh fails")
	}
}

func TestFleetHcloudInstallRetriesAreShared(t *testing.T) {
	installer, err := os.ReadFile(thisRepoFile(t, ".github/scripts/install-hcloud.sh"))
	if err != nil {
		t.Fatal(err)
	}
	for _, required := range []string{"for attempt in 1 2 3 4 5", "sleep $((attempt * 10))", "hcloud version", "::error title=hcloud CLI install failed::", "not a scenario finding"} {
		if !strings.Contains(string(installer), required) {
			t.Errorf("shared hcloud installer missing %q", required)
		}
	}
	for _, tc := range []struct{ file, job, step string }{
		// STATBUS-425 M2' moved the paid host-ramp step (the only place
		// test-smoke.yaml still shells out to hcloud) off the per-scenario
		// "smoke" job onto the single shared "ramp" job (review B1): a
		// second per-job up.sh call would race itself hardening the same
		// host. The step keeps its historical name there.
		{".github/workflows/test-smoke.yaml", "ramp", "Install hcloud CLI (fleet host discovery only)"},
		// STATBUS-425 M4: arcs ramp the shared box once in their own "ramp" job
		// (discovery only); the per-arc job and the old global sweep no longer
		// touch hcloud.
		{".github/workflows/upgrade-arc-harness.yaml", "ramp", "Install hcloud CLI (fleet host discovery only)"},
	} {
		steps := jobSteps(t, tc.file, tc.job)
		install := steps[stepIndexByName(t, steps, tc.step)]
		if install["run"] != "bash .github/scripts/install-hcloud.sh" {
			t.Errorf("%s must use shared retry installer: %v", tc.file, install)
		}
	}
	arcJobs := workflowDoc(t, ".github/workflows/upgrade-arc-harness.yaml")["jobs"].(map[string]any)
	if _, exists := arcJobs["cleanup"]; exists {
		t.Error("the global Hetzner orphan sweep is retired: arc forks are reaped per job and by the host sweep")
	}
	for _, step := range jobSteps(t, ".github/workflows/upgrade-arc-harness.yaml", "run-arc") {
		if strings.Contains(fmt.Sprint(step), "hcloud") || strings.Contains(fmt.Sprint(step), "STATBUS_CI_SSH_PRIVATE_KEY") {
			t.Errorf("run-arc must not use Hetzner tooling or the Hetzner CI key: %v", step["name"])
		}
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
		for _, job := range []string{"smoke", "upgrade-arc-harness"} {
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
		// STATBUS-425 M2' (review B1): the paid host-ramp step moved off the
		// per-scenario "smoke" job onto its own single "ramp" job so the
		// warm host is prepared once, not raced by each matrix entry. "smoke"
		// now depends on BOTH: "select" for its validated matrix, "ramp" for
		// the warm host IP it needs to reach. The invariant this guards —
		// every paid job's eligibility traces back through the validated
		// select job, never around it — still holds: "ramp" itself depends
		// only on "select" and runs no paid VM/LXD step before it.
		ramp := jobs["ramp"].(map[string]any)
		rampNeeds, ok := ramp["needs"].([]any)
		if !ok || len(rampNeeds) != 1 || rampNeeds[0] != "select" {
			t.Fatalf("paid ramp job must depend only on the validated select job; needs=%v", ramp["needs"])
		}
		rampSteps := jobSteps(t, ".github/workflows/test-smoke.yaml", "ramp")
		if rampSteps[0]["uses"] != "actions/checkout@v4" {
			t.Fatalf("ramp job must checkout before any paid step: %v", rampSteps[0])
		}
		for _, step := range rampSteps[1:] {
			if uses, _ := step["uses"].(string); uses == "./.github/actions/orchestrator-fleet-admission" {
				t.Fatal("ramp must not re-admit; it relies on select's validation, not its own")
			}
		}

		smoke := jobs["smoke"].(map[string]any)
		needs, ok := smoke["needs"].([]any)
		if !ok || len(needs) != 2 || needs[0] != "select" || needs[1] != "ramp" {
			t.Fatalf("paid smoke matrix must depend only on the validated select job and the shared ramp job; needs=%v", smoke["needs"])
		}
	})

	t.Run("LXD fault fleet is a full-suite gate without a subset selector", func(t *testing.T) {
		doc := workflowDoc(t, ".github/workflows/lxd-fleet.yaml")
		if _, ok := doc["on"].(map[string]any)["workflow_dispatch"].(map[string]any)["inputs"]; ok {
			t.Fatal("LXD gate must not expose a subset input")
		}
		steps := jobSteps(t, ".github/workflows/lxd-fleet.yaml", "parity")
		final := steps[len(steps)-1]["run"].(string)
		if !strings.Contains(final, `[ "$FLEET_STATUS" = PASSED ]`) {
			t.Fatal("only a PASSED full-suite status may conclude green")
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

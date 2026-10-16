package cmd

import (
	"bufio"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// STATBUS-416 AC2: the LXD fault fleet follows the supersession rule. It checks
// freshness before any paid operation and again after waiting for the box, every
// paid step is gated on both checks, and a superseded run's verdict is
// SUPERSEDED, distinct from FAILED and never green.
func TestLXDFleetSupersessionStopsBeforePaidWorkAndIsItsOwnVerdict_STATBUS416(t *testing.T) {
	const wf = ".github/workflows/lxd-fleet.yaml"
	steps := jobSteps(t, wf, "parity")
	idx := func(name string) int { return stepIndexByName(t, steps, name) }

	first := idx("Check freshness before any paid operation")
	drain := idx("Wait only for a DIFFERENT candidate on the box (bounded 20 minutes)")
	again := idx("Recheck newest RC after occupancy wait")
	ramp := idx("Ramp warm box")
	driver := idx("Run all fork scenarios (batch-boundary supersession)")
	if first >= drain || drain >= again || again >= ramp || ramp >= driver {
		t.Fatalf("order must be freshness < drain < recheck < ramp < driver, got %d %d %d %d %d", first, drain, again, ramp, driver)
	}
	for _, i := range []int{first, again} {
		if steps[i]["uses"] != "./.github/actions/scenario-superseded" {
			t.Errorf("step %v must be the shared freshness check, uses=%v", steps[i]["name"], steps[i]["uses"])
		}
		if with := steps[i]["with"].(map[string]any); with["candidate-ref"] != "${{ github.ref_name }}" {
			t.Errorf("step %v must check this run's candidate tag: %v", steps[i]["name"], with)
		}
	}
	gate := func(i int, conds ...string) {
		c, _ := steps[i]["if"].(string)
		for _, want := range conds {
			if !strings.Contains(c, want) {
				t.Errorf("step %v must be gated on %q, if=%q", steps[i]["name"], want, c)
			}
		}
	}
	firstOK := "steps.freshness.outputs.superseded != 'true'"
	againOK := "steps.after-wait.outputs.superseded != 'true'"
	gate(drain, firstOK)
	gate(again, firstOK)
	gate(ramp, firstOK, againOK)
	gate(driver, firstOK, againOK)

	collect := steps[idx("Collect workflow phase outcome")]["run"].(string)
	verdict := steps[idx("State LXD verdict")]["run"].(string)
	repo := filepath.Dir(thisRepoFile(t, "test/install-recovery/lxd/fleet-status.sh"))

	type outcome struct {
		name        string
		env         map[string]string
		driverWrote string
		wantStatus  string
		wantGreen   bool
	}
	ok := map[string]string{"CHECKOUT": "success", "TOOLING": "success", "SETUP": "success", "DRAIN": "success", "RECHECK": "success", "RAMP": "success", "BASE": "skipped", "DRIVER": "success", "FIRST": "false", "AFTER_WAIT": "false"}
	with := func(over map[string]string) map[string]string {
		m := map[string]string{}
		for k, v := range ok {
			m[k] = v
		}
		for k, v := range over {
			m[k] = v
		}
		return m
	}
	skippedAfterFirst := map[string]string{"FIRST": "true", "AFTER_WAIT": "", "DRAIN": "skipped", "RECHECK": "skipped", "RAMP": "skipped", "DRIVER": "skipped"}
	skippedAfterWait := map[string]string{"AFTER_WAIT": "true", "RAMP": "skipped", "DRIVER": "skipped"}
	for _, c := range []outcome{
		{"superseded at the first check", with(skippedAfterFirst), "", "SUPERSEDED", false},
		{"superseded after the occupancy wait", with(skippedAfterWait), "", "SUPERSEDED", false},
		{"superseded at a fork batch boundary", ok, "STATUS=SUPERSEDED\nDETAIL=newer tag v9.9.9-rc.9\n", "SUPERSEDED", false},
		{"a scenario failed, no newer tag", with(map[string]string{"DRIVER": "failure"}), "STATUS=FAILED\n", "FAILED", false},
		{"the ramp failed, no newer tag", with(map[string]string{"RAMP": "failure", "DRIVER": "skipped"}), "", "FAILED", false},
		{"every scenario passed", ok, "STATUS=PASSED\n", "PASSED", true},
		{"the driver left no status", ok, "", "ERROR", false},
	} {
		t.Run(c.name, func(t *testing.T) {
			work := t.TempDir()
			lib := filepath.Join(work, "test", "install-recovery", "lxd")
			if err := os.MkdirAll(lib, 0o755); err != nil {
				t.Fatal(err)
			}
			src, err := os.ReadFile(filepath.Join(repo, "fleet-status.sh"))
			if err != nil {
				t.Fatal(err)
			}
			if err := os.WriteFile(filepath.Join(lib, "fleet-status.sh"), src, 0o644); err != nil {
				t.Fatal(err)
			}
			artifacts := filepath.Join(work, "artifacts")
			if err := os.MkdirAll(artifacts, 0o755); err != nil {
				t.Fatal(err)
			}
			if c.driverWrote != "" {
				if err := os.WriteFile(filepath.Join(artifacts, "fleet-status.txt"), []byte(c.driverWrote), 0o644); err != nil {
					t.Fatal(err)
				}
			}
			env := append(os.Environ(), "LXD_FLEET_ARTIFACT_DIR="+artifacts, "GITHUB_STEP_SUMMARY="+filepath.Join(work, "summary.md"))
			for k, v := range c.env {
				env = append(env, k+"="+v)
			}
			run := func(script string) error {
				cmd := exec.Command("bash", "-c", script)
				cmd.Dir, cmd.Env = work, env
				out, err := cmd.CombinedOutput()
				if err != nil {
					t.Logf("%s", out)
				}
				return err
			}
			if err := run(collect); err != nil {
				t.Fatalf("collector failed: %v", err)
			}
			status, err := os.ReadFile(filepath.Join(artifacts, "fleet-status.txt"))
			if err != nil {
				t.Fatal(err)
			}
			sc := bufio.NewScanner(strings.NewReader(string(status)))
			sc.Scan()
			if got := sc.Text(); got != "STATUS="+c.wantStatus {
				t.Errorf("fleet status = %q, want STATUS=%s", got, c.wantStatus)
			}
			if green := run(verdict) == nil; green != c.wantGreen {
				t.Errorf("verdict step green = %v, want %v (only PASSED is green)", green, c.wantGreen)
			}
		})
	}
}

package cmd

import (
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"sort"
	"strings"
	"testing"

	"gopkg.in/yaml.v3"
)

func parsedYAMLMap(t *testing.T, rel string) map[string]any {
	t.Helper()
	b, err := os.ReadFile(thisRepoFile(t, rel))
	if err != nil {
		t.Fatal(err)
	}
	var doc map[string]any
	if err := yaml.Unmarshal(b, &doc); err != nil {
		t.Fatalf("%s: %v", rel, err)
	}
	return doc
}

func TestPaidFleetWorkflowConcurrencyExactSet_STATBUS350(t *testing.T) {
	want := []string{"install-recovery-harness.yaml", "test-smoke.yaml", "upgrade-arc-harness.yaml"}
	entries, err := os.ReadDir(thisRepoFile(t, ".github/workflows"))
	if err != nil {
		t.Fatal(err)
	}
	var got []string
	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".yaml") {
			continue
		}
		rel := filepath.Join(".github/workflows", entry.Name())
		doc := parsedYAMLMap(t, rel)
		raw, ok := doc["concurrency"]
		if !ok {
			continue
		}
		if _, ok := raw.(map[string]any); !ok {
			continue // unrelated workflows may use the shorthand string form
		}
		concurrency := asStringMap(t, rel, "concurrency", raw)
		if concurrency["group"] != "hetzner-vm-fleet" {
			continue
		}
		got = append(got, entry.Name())
		if concurrency["cancel-in-progress"] != false {
			t.Errorf("%s cancel-in-progress = %#v, want false", rel, concurrency["cancel-in-progress"])
		}
		if concurrency["queue"] != "max" {
			t.Errorf("%s queue = %#v, want max", rel, concurrency["queue"])
		}
	}
	sort.Strings(got)
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("paid fleet workflow set = %v, want exactly %v", got, want)
	}
}

func TestSmokeWorkflowFixedSelectedMatrix_STATBUS350(t *testing.T) {
	doc := parsedYAMLMap(t, ".github/workflows/test-smoke.yaml")
	jobs := asStringMap(t, "test-smoke.yaml", "jobs", doc["jobs"])
	smoke := asStringMap(t, "test-smoke.yaml", "jobs.smoke", jobs["smoke"])
	if smoke["name"] != "${{ matrix.scenario }}" {
		t.Fatalf("smoke job name = %#v; evidence marks must be exact scenario names", smoke["name"])
	}
	text, _ := os.ReadFile(thisRepoFile(t, ".github/workflows/test-smoke.yaml"))
	for _, scenario := range []string{"0-happy-install", "0-happy-upgrade"} {
		if !strings.Contains(string(text), scenario) {
			t.Errorf("fixed smoke domain missing %s", scenario)
		}
	}
}

func TestFleetDispatcherClassificationAndExactRaceCancellation_STATBUS350(t *testing.T) {
	script := thisRepoFile(t, ".github/actions/dispatch-fleet-and-wait/dispatch.sh")
	for _, workflow := range []string{"test-smoke.yaml", "install-recovery-harness.yaml", "upgrade-arc-harness.yaml"} {
		cmd := exec.Command("bash", script)
		cmd.Env = append(os.Environ(), "STATBUS_DISPATCH_TEST_MODE=classify", "WORKFLOW_FILE="+workflow)
		if out, err := cmd.CombinedOutput(); err != nil {
			t.Fatalf("%s not classified as paid fleet: %v\n%s", workflow, err, out)
		}
	}
	cmd := exec.Command("bash", script)
	cmd.Env = append(os.Environ(), "STATBUS_DISPATCH_TEST_MODE=classify", "WORKFLOW_FILE=deploy-to-dev.yaml")
	if err := cmd.Run(); err == nil {
		t.Fatal("non-fleet deploy-to-dev must not be classified for group API queries")
	}

	dir := t.TempDir()
	log := filepath.Join(dir, "gh.log")
	mock := `#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$GH_TEST_LOG"
if [ "$1" = api ]; then
  cat <<'JSON'
{"group_members":[{"run_id":111,"run_name":"owner","status":"in_progress","run_html_url":"https://runs/111"},{"run_id":222,"run_name":"ours","status":"pending","run_html_url":"https://runs/222"}]}
JSON
elif [ "$1 $2" = "run cancel" ]; then
  exit 0
elif [ "$1 $2" = "run view" ]; then
  echo 'completed cancelled'
else
  exit 9
fi
`
	mockPath := filepath.Join(dir, "gh")
	if err := os.WriteFile(mockPath, []byte(mock), 0o755); err != nil {
		t.Fatal(err)
	}
	cmd = exec.Command("bash", script)
	cmd.Env = append(os.Environ(), "PATH="+dir+":"+os.Getenv("PATH"), "GH_TEST_LOG="+log,
		"GH_REPO=statisticsnorway/statbus", "WORKFLOW_FILE=test-smoke.yaml",
		"STATBUS_DISPATCH_TEST_MODE=preflight")
	preflightOut, preflightErr := cmd.CombinedOutput()
	if preflightErr == nil {
		t.Fatalf("occupied group must refuse before dispatch\n%s", preflightOut)
	}
	preflightText := string(preflightOut)
	ownerAt := strings.Index(preflightText, "position=1 id=111 name=owner status=in_progress url=https://runs/111")
	waiterAt := strings.Index(preflightText, "position=2 id=222 name=ours status=pending url=https://runs/222")
	if ownerAt < 0 || waiterAt < 0 || ownerAt > waiterAt {
		t.Fatalf("preflight did not name ordered owner then waiter:\n%s", preflightText)
	}

	cmd = exec.Command("bash", script)
	cmd.Env = append(os.Environ(), "PATH="+dir+":"+os.Getenv("PATH"), "GH_TEST_LOG="+log,
		"GH_REPO=statisticsnorway/statbus", "WORKFLOW_FILE=test-smoke.yaml",
		"STATBUS_DISPATCH_TEST_MODE=postflight", "RUN_ID=222")
	out, err := cmd.CombinedOutput()
	if err == nil {
		t.Fatalf("race cleanup must fail after cancelling its own waiter\n%s", out)
	}
	calls, _ := os.ReadFile(log)
	if !strings.Contains(string(calls), "run cancel 222") {
		t.Fatalf("exact pending run was not cancelled; calls:\n%s", calls)
	}
	if strings.Contains(string(calls), "run cancel 111") {
		t.Fatalf("owner was cancelled; calls:\n%s", calls)
	}
}

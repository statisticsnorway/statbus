package cmd

import (
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"sort"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/testgit"
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

func TestFleetDispatcherClassificationRefusalAndNoCancellation_STATBUS350(t *testing.T) {
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
	  printf '%s\n' "$GH_RESPONSE"
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
		`GH_RESPONSE={"group_name":"hetzner-vm-fleet","group_url":"https://api.github.com/repos/statisticsnorway/statbus/actions/concurrency_groups/hetzner-vm-fleet","total_count":2,"group_members":[{"run_id":111,"run_name":"owner","run_url":"https://api.github.com/runs/111","run_html_url":"https://runs/111","status":"in_progress"},{"run_id":222,"run_name":"ours","run_url":"https://api.github.com/runs/222","run_html_url":"https://runs/222","status":"pending"}]}`,
		"STATBUS_DISPATCH_TEST_MODE=preflight")
	preflightOut, preflightErr := cmd.CombinedOutput()
	if preflightErr == nil {
		t.Fatalf("occupied group must refuse before dispatch\n%s", preflightOut)
	}
	preflightText := string(preflightOut)
	ownerAt := strings.Index(preflightText, "order=1 id=111 name=owner status=in_progress url=https://runs/111")
	waiterAt := strings.Index(preflightText, "order=2 id=222 name=ours status=pending url=https://runs/222")
	if ownerAt < 0 || waiterAt < 0 || ownerAt > waiterAt {
		t.Fatalf("preflight did not name ordered owner then waiter:\n%s", preflightText)
	}

	cmd = exec.Command("bash", script)
	cmd.Env = append(os.Environ(), "PATH="+dir+":"+os.Getenv("PATH"), "GH_TEST_LOG="+log,
		"GH_REPO=statisticsnorway/statbus", "WORKFLOW_FILE=test-smoke.yaml",
		`GH_RESPONSE={"group_name":"hetzner-vm-fleet","group_url":"https://api.github.com/repos/statisticsnorway/statbus/actions/concurrency_groups/hetzner-vm-fleet","total_count":2,"group_members":[{"run_id":111,"run_name":"owner","run_url":"https://api.github.com/runs/111","run_html_url":"https://runs/111","status":"in_progress"},{"run_id":222,"run_name":"ours","run_url":"https://api.github.com/runs/222","run_html_url":"https://runs/222","status":"pending"}]}`,
		"STATBUS_DISPATCH_TEST_MODE=postflight", "RUN_ID=222")
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("rare race must remain in native queue without automatic cancellation: %v\n%s", err, out)
	}
	calls, _ := os.ReadFile(log)
	if strings.Contains(string(calls), "run cancel") {
		t.Fatalf("dispatcher must never cancel automatically; calls:\n%s", calls)
	}
	if !strings.Contains(string(out), "continuing to poll without automatic cancellation") {
		t.Fatalf("post-correlation queue report missing:\n%s", out)
	}
}

func TestFleetDispatcherRejectsMalformedSuccessfulGroupResponses_STATBUS350(t *testing.T) {
	script := thisRepoFile(t, ".github/actions/dispatch-fleet-and-wait/dispatch.sh")
	for _, response := range []string{`{"group_name":"hetzner-vm-fleet","group_url":"https://api.github.com/repos/statisticsnorway/statbus/actions/concurrency_groups/hetzner-vm-fleet","total_count":0,"group_members":[]}`} {
		dir := t.TempDir()
		mock := "#!/usr/bin/env bash\nprintf '%s\\n' \"$GH_RESPONSE\"\n"
		if err := os.WriteFile(filepath.Join(dir, "gh"), []byte(mock), 0o755); err != nil {
			t.Fatal(err)
		}
		cmd := exec.Command("bash", script)
		cmd.Env = append(os.Environ(), "PATH="+dir+":"+os.Getenv("PATH"), "GH_REPO=statisticsnorway/statbus",
			"WORKFLOW_FILE=test-smoke.yaml", "STATBUS_DISPATCH_TEST_MODE=preflight", "GH_RESPONSE="+response)
		if out, err := cmd.CombinedOutput(); err != nil {
			t.Fatalf("valid explicit empty group rejected: %v\n%s", err, out)
		}
	}
	{
		dir := t.TempDir()
		mock := "#!/usr/bin/env bash\nprintf '%s\\n' \"$GH_RESPONSE\"\n"
		if err := os.WriteFile(filepath.Join(dir, "gh"), []byte(mock), 0o755); err != nil {
			t.Fatal(err)
		}
		cmd := exec.Command("bash", script)
		cmd.Env = append(os.Environ(), "PATH="+dir+":"+os.Getenv("PATH"), "GH_REPO=statisticsnorway/statbus",
			"WORKFLOW_FILE=test-smoke.yaml", "STATBUS_DISPATCH_TEST_MODE=preflight",
			`GH_RESPONSE={"group_name":"hetzner-vm-fleet","group_url":"https://api.github.com/repos/statisticsnorway/statbus/actions/concurrency_groups/hetzner-vm-fleet","total_count":1,"group_members":[{"run_id":1,"run_name":"owner","run_url":null,"run_html_url":null,"status":"in_progress"}]}`)
		out, err := cmd.CombinedOutput()
		if err == nil || strings.Contains(string(out), "Malformed fleet concurrency response") || !strings.Contains(string(out), "url=<unavailable>") {
			t.Fatalf("schema-valid nullable URLs must report occupied with a fallback URL: err=%v\n%s", err, out)
		}
	}
	{
		dir := t.TempDir()
		mock := "#!/usr/bin/env bash\necho 'gh: HTTP 404' >&2\nexit 1\n"
		if err := os.WriteFile(filepath.Join(dir, "gh"), []byte(mock), 0o755); err != nil {
			t.Fatal(err)
		}
		cmd := exec.Command("bash", script)
		cmd.Env = append(os.Environ(), "PATH="+dir+":"+os.Getenv("PATH"), "GH_REPO=statisticsnorway/statbus",
			"WORKFLOW_FILE=test-smoke.yaml", "STATBUS_DISPATCH_TEST_MODE=preflight")
		if out, err := cmd.CombinedOutput(); err != nil {
			t.Fatalf("HTTP 404 must be the sole empty-group transport: %v\n%s", err, out)
		}
	}
	bad := []string{
		`{}`,
		`{"group_members":null}`,
		`{"group_members":{}}`,
		`{"group_name":"wrong","group_url":"https://api.github.com/group","total_count":0,"group_members":[]}`,
		`{"group_name":"hetzner-vm-fleet","group_url":"not-a-url","total_count":0,"group_members":[]}`,
		`{"group_name":"hetzner-vm-fleet","group_url":"https://api.github.com/group","total_count":1,"group_members":[]}`,
		`{"group_name":"hetzner-vm-fleet","group_url":"https://api.github.com/group","total_count":1,"group_members":[{"run_id":0,"run_name":"owner","run_url":"https://api.github.com/runs/1","run_html_url":"https://runs/1","status":"in_progress"}]}`,
		`{"group_name":"hetzner-vm-fleet","group_url":"https://api.github.com/group","total_count":1,"group_members":[{"run_id":1,"run_name":"","run_url":"https://api.github.com/runs/1","run_html_url":"https://runs/1","status":"in_progress"}]}`,
		`{"group_name":"hetzner-vm-fleet","group_url":"https://api.github.com/group","total_count":1,"group_members":[{"run_id":1,"run_name":"owner","run_url":"https://api.github.com/runs/1","run_html_url":"https://runs/1","status":"completed"}]}`,
		`{"group_name":"hetzner-vm-fleet","group_url":"https://api.github.com/group","total_count":1,"group_members":[{"run_id":1,"run_name":"owner","run_url":"https://api.github.com/runs/1","run_html_url":"not-a-url","status":"pending"}]}`,
		`{"group_name":"hetzner-vm-fleet","group_url":"https://api.github.com/group","total_count":1,"group_members":[{"run_id":1,"run_name":"owner","run_html_url":"https://runs/1","status":"pending"}]}`,
	}
	for _, response := range bad {
		t.Run(response, func(t *testing.T) {
			dir := t.TempDir()
			mock := "#!/usr/bin/env bash\nprintf '%s\\n' \"$GH_RESPONSE\"\n"
			if err := os.WriteFile(filepath.Join(dir, "gh"), []byte(mock), 0o755); err != nil {
				t.Fatal(err)
			}
			cmd := exec.Command("bash", script)
			cmd.Env = append(os.Environ(), "PATH="+dir+":"+os.Getenv("PATH"), "GH_REPO=statisticsnorway/statbus",
				"WORKFLOW_FILE=test-smoke.yaml", "STATBUS_DISPATCH_TEST_MODE=preflight", "GH_RESPONSE="+response)
			out, err := cmd.CombinedOutput()
			if err == nil || !strings.Contains(string(out), "Malformed fleet concurrency response") {
				t.Fatalf("malformed successful response must fail loud: err=%v\n%s", err, out)
			}
		})
	}
}

func TestPaidFleetSharedAdmissionAndManualCompatibility_STATBUS350(t *testing.T) {
	paid := []string{"test-smoke.yaml", "install-recovery-harness.yaml", "upgrade-arc-harness.yaml"}
	for _, name := range paid {
		text, err := os.ReadFile(thisRepoFile(t, filepath.Join(".github/workflows", name)))
		if err != nil {
			t.Fatal(err)
		}
		s := string(text)
		if strings.Count(s, "uses: ./.github/actions/orchestrator-fleet-admission") != 1 {
			t.Errorf("%s must invoke the shared admission exactly once", name)
		}
		if !strings.Contains(s, "orchestrator-run-id:") || !strings.Contains(s, "default: ''") {
			t.Errorf("%s must keep direct manual dispatch blank-compatible", name)
		}
		checkout := strings.Index(s, "uses: actions/checkout@v4")
		admission := strings.Index(s, "uses: ./.github/actions/orchestrator-fleet-admission")
		if checkout < 0 || admission < checkout {
			t.Errorf("%s admission must be immediately after its first checkout", name)
		}
		between := s[checkout:admission]
		if strings.Count(between, "      - name:") > 1 {
			t.Errorf("%s has a step between first checkout and shared admission", name)
		}
	}
	dispatcher, _ := os.ReadFile(thisRepoFile(t, ".github/actions/dispatch-fleet-and-wait/dispatch.sh"))
	if strings.Contains(string(dispatcher), "gh run cancel") {
		t.Fatal("dispatcher must contain no automatic gh run cancel call")
	}
	if !strings.Contains(string(dispatcher), `dispatch_args+=(-f "orchestrator-run-id=${GITHUB_RUN_ID}")`) {
		t.Fatal("dispatcher must add parent run ID to classified paid workflows")
	}
	admit, _ := os.ReadFile(thisRepoFile(t, ".github/actions/orchestrator-fleet-admission/admit.sh"))
	for _, required := range []string{".status == \"in_progress\"", ".event == \"push\"", ".head_sha == $sha", ".path == \".github/workflows/release-fleet-orchestrator.yaml\"", "CANDIDATE_REF", "git rev-parse HEAD"} {
		if !strings.Contains(string(admit), required) {
			t.Errorf("shared admission missing %q", required)
		}
	}
	cmd := exec.Command("bash", thisRepoFile(t, ".github/actions/orchestrator-fleet-admission/admit.sh"))
	cmd.Env = append(os.Environ(), "ORCHESTRATOR_RUN_ID=", "CANDIDATE_REF=manual", "CANDIDATE_SHA=manual")
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("blank manual input rejected: %v\n%s", err, out)
	}
}

func TestOrchestratorFleetAdmissionExecutesProvenanceAndSupersessionChecks_STATBUS350(t *testing.T) {
	repo := t.TempDir()
	runGit := func(dir string, args ...string) string {
		t.Helper()
		cmd := exec.Command("git", testgit.Args(args...)...)
		cmd.Dir = dir
		cmd.Env = append(os.Environ(), testgit.Env()...)
		out, err := cmd.CombinedOutput()
		if err != nil {
			t.Fatalf("git %v: %v\n%s", args, err, out)
		}
		return strings.TrimSpace(string(out))
	}
	runGit(repo, "init")
	if err := os.WriteFile(filepath.Join(repo, "seed.txt"), []byte("seed\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	runGit(repo, "add", "seed.txt")
	runGit(repo, "commit", "-m", "seed")
	const candidate = "v2026.09.1-rc.1"
	runGit(repo, "tag", candidate)
	sha := runGit(repo, "rev-parse", "HEAD")
	remote := filepath.Join(t.TempDir(), "origin.git")
	runGit(repo, "init", "--bare", remote)
	runGit(repo, "remote", "add", "origin", remote)
	runGit(repo, "push", "origin", "HEAD", "--tags")

	bin := t.TempDir()
	mock := "#!/usr/bin/env bash\nset -euo pipefail\nprintf '%s\\n' \"$GH_PARENT\"\n"
	if err := os.WriteFile(filepath.Join(bin, "gh"), []byte(mock), 0o755); err != nil {
		t.Fatal(err)
	}
	script := thisRepoFile(t, ".github/actions/orchestrator-fleet-admission/admit.sh")
	parent := `{"id":123,"status":"in_progress","event":"push","head_sha":"` + sha + `","path":".github/workflows/release-fleet-orchestrator.yaml","html_url":"https://github.com/statisticsnorway/statbus/actions/runs/123"}`
	runAdmission := func(parentJSON string) ([]byte, error) {
		t.Helper()
		cmd := exec.Command("bash", script)
		cmd.Dir = repo
		env := append(os.Environ(), testgit.Env()...)
		cmd.Env = append(env,
			"PATH="+bin+":"+os.Getenv("PATH"), "GH_PARENT="+parentJSON,
			"ORCHESTRATOR_RUN_ID=123", "GH_REPO=statisticsnorway/statbus",
			"CANDIDATE_REF="+candidate, "CANDIDATE_SHA="+sha)
		return cmd.CombinedOutput()
	}
	if out, err := runAdmission(parent); err != nil {
		t.Fatalf("valid parent and newest candidate rejected: %v\n%s", err, out)
	}
	completedParent := strings.Replace(parent, `"status":"in_progress"`, `"status":"completed"`, 1)
	if out, err := runAdmission(completedParent); err == nil || !strings.Contains(string(out), "Stale or invalid orchestrator parent") {
		t.Fatalf("completed parent must refuse before side effects: err=%v\n%s", err, out)
	}
	runGit(repo, "tag", "v2026.09.1-rc.2")
	runGit(repo, "push", "origin", "v2026.09.1-rc.2")
	if out, err := runAdmission(parent); err == nil || !strings.Contains(string(out), "Superseded queued fleet run") {
		t.Fatalf("superseded queued candidate must refuse before side effects: err=%v\n%s", err, out)
	}
}

func TestOrchestratorSmokeShapeAndMultilineDiagnostics_STATBUS350(t *testing.T) {
	text, err := os.ReadFile(thisRepoFile(t, ".github/workflows/release-fleet-orchestrator.yaml"))
	if err != nil {
		t.Fatal(err)
	}
	s := string(text)
	if strings.Count(s, "workflow-file: test-smoke.yaml") != 1 {
		t.Fatal("orchestrator must dispatch smoke exactly once")
	}
	if !strings.Contains(s, "needs: [decide-obsolete, smoke]") {
		t.Fatal("dev must depend on consolidated smoke")
	}
	if !strings.Contains(s, "needs.smoke.outputs.coverage_error") {
		t.Fatal("health must consume consolidated smoke diagnostics")
	}
	if !strings.Contains(s, "coverage_error<<STATBUS_352_ERROR") || !strings.Contains(s, `cat "$ERRORS"`) {
		t.Fatal("coverage_error must use multiline GITHUB_OUTPUT syntax and preserve covered-subset stderr")
	}
}

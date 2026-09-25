package cmd

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestFleetDispatchWaitsOnlyForOlderOrchestratedCandidates(t *testing.T) {
	script := thisRepoFile(t, ".github/actions/dispatch-fleet-and-wait/dispatch.sh")
	dir := t.TempDir()
	mock := "#!/usr/bin/env bash\nprintf '%s\\n' \"$RUN_JSON\"\n"
	if err := os.WriteFile(filepath.Join(dir, "gh"), []byte(mock), 0o755); err != nil {
		t.Fatal(err)
	}
	const ref = "v2026.09.3-rc.04"
	const sha = "2a27caf85"
	for _, tc := range []struct {
		name, branch, actor, event, want string
	}{
		{"older rc", "v2026.09.3-rc.03", "github-actions[bot]", "workflow_dispatch", "wait"},
		{"same rc", ref, "github-actions[bot]", "workflow_dispatch", "refuse"},
		{"newer rc", "v2026.09.3-rc.05", "github-actions[bot]", "workflow_dispatch", "refuse"},
		{"manual older rc", "v2026.09.3-rc.03", "operator", "workflow_dispatch", "refuse"},
		{"push older rc", "v2026.09.3-rc.03", "github-actions[bot]", "push", "refuse"},
		{"unknown ref", "master", "github-actions[bot]", "workflow_dispatch", "refuse"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			run := fmt.Sprintf(`{"id":111,"head_branch":%q,"head_sha":%q,"event":%q,"actor":{"login":%q}}`, tc.branch, sha, tc.event, tc.actor)
			cmd := exec.Command("bash", script)
			cmd.Stdin = strings.NewReader(`{"id":111}`)
			cmd.Env = append(os.Environ(), "PATH="+dir+":"+os.Getenv("PATH"), "RUN_JSON="+run,
				"GH_REPO=statisticsnorway/statbus", "STATBUS_DISPATCH_TEST_MODE=classify-member",
				"REF="+ref, "COMMIT_SHA="+sha)
			out, err := cmd.CombinedOutput()
			if err != nil || strings.TrimSpace(string(out)) != tc.want {
				t.Fatalf("classification = %q, error %v; want %q", out, err, tc.want)
			}
		})
	}

	// A tag ref can be re-pointed. Only an ancestor commit on the same RC
	// line is older, not an unrelated commit or the identical candidate.
	git := exec.Command("git", "rev-parse", "HEAD", "HEAD~1")
	git.Dir = filepath.Dir(filepath.Dir(filepath.Dir(filepath.Dir(script))))
	out, err := git.Output()
	if err != nil {
		t.Fatal(err)
	}
	commits := strings.Fields(string(out))
	for _, tc := range []struct{ old, want string }{{commits[1], "wait"}, {commits[0], "refuse"}} {
		run := fmt.Sprintf(`{"id":111,"head_branch":%q,"head_sha":%q,"event":"workflow_dispatch","actor":{"login":"github-actions[bot]"}}`, ref, tc.old)
		cmd := exec.Command("bash", script)
		cmd.Dir = git.Dir
		cmd.Stdin = strings.NewReader(`{"id":111}`)
		cmd.Env = append(os.Environ(), "PATH="+dir+":"+os.Getenv("PATH"), "RUN_JSON="+run,
			"GH_REPO=statisticsnorway/statbus", "STATBUS_DISPATCH_TEST_MODE=classify-member",
			"REF="+ref, "COMMIT_SHA="+commits[0])
		result, err := cmd.CombinedOutput()
		if err != nil || strings.TrimSpace(string(result)) != tc.want {
			t.Fatalf("same-ref %s classification = %q, error %v; want %q", tc.old, result, err, tc.want)
		}
	}
}

func TestFleetDispatchDrainsOlderOwnerBeforeDispatch(t *testing.T) {
	dir := t.TempDir()
	group := `{"group_name":"hetzner-vm-fleet","group_url":"https://api.github.com/group","total_count":1,"group_members":[{"run_id":111,"run_name":"older","run_url":null,"run_html_url":null,"status":"in_progress"}]}`
	mock := `#!/usr/bin/env bash
set -euo pipefail
if [ "$1" = api ] && [[ "$2" == */concurrency_groups/* ]]; then
  if [ -e "$COUNT_FILE" ]; then
    echo '{"group_name":"hetzner-vm-fleet","group_url":"https://api.github.com/group","total_count":0,"group_members":[]}'
  else
    touch "$COUNT_FILE"
    printf '%s\n' "$GROUP_JSON"
  fi
elif [ "$1" = api ]; then
  echo '{"id":111,"head_branch":"v2026.09.3-rc.03","head_sha":"ca5f44c275464e3a49b778797c7084492bd6e5e1","event":"workflow_dispatch","actor":{"login":"github-actions[bot]"}}'
else
  echo 'cleanup' # gh run view --json jobs --jq
fi
`
	if err := os.WriteFile(filepath.Join(dir, "gh"), []byte(mock), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "sleep"), []byte("#!/bin/sh\nexit 0\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	summary := filepath.Join(dir, "summary.md")
	cmd := exec.Command("bash", thisRepoFile(t, ".github/actions/dispatch-fleet-and-wait/dispatch.sh"))
	cmd.Env = append(os.Environ(), "PATH="+dir+":"+os.Getenv("PATH"), "GROUP_JSON="+group,
		"COUNT_FILE="+filepath.Join(dir, "count"), "GITHUB_STEP_SUMMARY="+summary,
		"STATBUS_DISPATCH_TEST_MODE=preflight", "GH_REPO=statisticsnorway/statbus",
		"WORKFLOW_FILE=test-smoke.yaml", "REF=v2026.09.3-rc.04", "COMMIT_SHA=2a27caf85")
	out, err := cmd.CombinedOutput()
	if err != nil || !strings.Contains(string(out), "Fleet drained; dispatching") {
		t.Fatalf("preflight did not wait and proceed: %v\n%s", err, out)
	}
	text, err := os.ReadFile(summary)
	if err != nil || !strings.Contains(string(text), "remaining jobs: cleanup") || !strings.Contains(string(text), "Fleet drained") {
		t.Fatalf("drain not visible in summary: %v\n%s", err, text)
	}
}

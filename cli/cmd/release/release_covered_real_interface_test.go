package releasecmd

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/release"
)

type builtCoverageResult struct {
	stdout string
	stderr string
	exit   int
}

func buildSBForCoverageInterface(t *testing.T, commit string) string {
	t.Helper()
	gomod := strings.TrimSpace(runCommandForTest(t, "", "go", "env", "GOMOD"))
	binary := filepath.Join(t.TempDir(), "sb")
	ldflags := fmt.Sprintf("-X github.com/statisticsnorway/statbus/cli/cmd.version=dev -X github.com/statisticsnorway/statbus/cli/cmd.commit=%s", commit)
	cmd := exec.Command("go", "build", "-ldflags", ldflags, "-o", binary, ".")
	cmd.Dir = filepath.Dir(gomod)
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("build sb: %v\n%s", err, out)
	}
	return binary
}

func runCommandForTest(t *testing.T, dir, name string, args ...string) string {
	t.Helper()
	cmd := exec.Command(name, args...)
	if dir != "" {
		cmd.Dir = dir
	}
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("%s %s: %v\n%s", name, strings.Join(args, " "), err, out)
	}
	return string(out)
}

func emptyEvidenceServer(t *testing.T) *httptest.Server {
	t.Helper()
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !strings.Contains(r.URL.Path, "/actions/workflows/") {
			http.Error(w, "unexpected "+r.URL.Path, http.StatusNotFound)
			return
		}
		_ = json.NewEncoder(w).Encode(map[string]any{"workflow_runs": []any{}})
	}))
	t.Cleanup(server.Close)
	return server
}

func realCoverageFixture(t *testing.T, changedPaths ...string) (dir, anchor, target string) {
	t.Helper()
	dir = t.TempDir()
	runGitInCmd(t, dir, "init", "-q")

	realRunner, err := os.ReadFile(thisRepoFile(t, "test/install-recovery/run.sh"))
	if err != nil {
		t.Fatalf("read the real harness runner: %v", err)
	}

	baseFiles := map[string]string{
		".statbus":                                              "\n",
		release.SensitivePathsFile:                              realInterfacePolicy,
		"test/install-recovery/scenarios/a.sh":                  "base\n",
		"test/install-recovery/scenarios/b.sh":                  "base\n",
		"test/install-recovery/scenarios/0-happy-install.sh":    "base\n",
		"test/install-recovery/scenarios/0-happy-upgrade.sh":    "base\n",
		"test/install-recovery/arcs/working-arc.sh":             "base\n",
		"test/install-recovery/arcs/failing-arc.sh":             "base\n",
		"test/install-recovery/arcs/deploy-status-proof-arc.sh": "base\n",
		".github/workflows/install-recovery-harness.yaml":       "base\n",
		".github/workflows/upgrade-arc-harness.yaml":            "base\n",
		".github/workflows/test-smoke.yaml":                     "base\n",
		".github/workflows/test-install.yaml":                   "base\n",
		"test/install-recovery/run.sh":                          string(realRunner),
		"test/install-recovery/lib/assertions.sh":               "base\n",
		"test/install-recovery/fixtures/stage-head.sh":          "base\n",
		"ops/ci-deploy-status.sh":                               "base\n",
		"ops/niue/sshdo":                                        "base\n",
		"ops/niue/sshdoers":                                     "base\n",
		"cli/internal/upgrade/service.go":                       "base\n",
		"cli/internal/release/sensitivity.go":                   "base\n",
		"doc/readme.md":                                         "base\n",
	}
	for file, content := range baseFiles {
		writeFixtureFile(t, dir, file, content)
	}
	runGitInCmd(t, dir, "add", ".")
	runGitInCmd(t, dir, "commit", "-q", "-m", "anchor")
	anchor = runGitInCmd(t, dir, "rev-parse", "HEAD")
	runGitInCmd(t, dir, "tag", "-a", "v2026.09.0-rc.01", "-m", "anchor")

	for _, file := range changedPaths {
		if file == "test/install-recovery/run.sh" {
			// The runner must stay a real validator at the target too, so the
			// "changed runner" case appends a comment rather than replacing it.
			writeFixtureFile(t, dir, file, string(realRunner)+"\n# changed\n")
			continue
		}
		writeFixtureFile(t, dir, file, "changed\n")
	}
	runGitInCmd(t, dir, "add", ".")
	runGitInCmd(t, dir, "commit", "-q", "-m", "target")
	target = runGitInCmd(t, dir, "rev-parse", "HEAD")

	origin := t.TempDir()
	runGitInCmd(t, origin, "init", "--bare", "-q")
	runGitInCmd(t, dir, "remote", "add", "origin", origin)
	runGitInCmd(t, dir, "push", "-q", "origin", "--tags")
	return dir, anchor, target
}

const realInterfacePolicy = `directory | box payload | cli
exact | shared controller | dev.sh
directory | shared harness input | test/install-recovery/lib
directory | shared harness input | test/install-recovery/fixtures
directory | proof interpreter | cli/internal/release
exact | proof interpreter | ops/release/upgrade-sensitive-paths.txt
`

func writeFixtureFile(t *testing.T, dir, file, content string) {
	t.Helper()
	full := filepath.Join(dir, file)
	if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(full, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

func markScenarioAt(t *testing.T, dir string, scenario release.Scenario, commit string) {
	t.Helper()
	if err := release.WriteLocalMark(dir, scenario, commit); err != nil {
		t.Fatal(err)
	}
}

func runBuiltCoverage(t *testing.T, binary, dir, apiURL string, args ...string) builtCoverageResult {
	t.Helper()
	cmd := exec.Command(binary, args...)
	cmd.Dir = dir
	cmd.Env = append(os.Environ(), "GITHUB_API_URL="+apiURL, "GITHUB_TOKEN=test", "GH_TOKEN=test")
	var stdout, stderr strings.Builder
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	err := cmd.Run()
	exit := 0
	if err != nil {
		var exitErr *exec.ExitError
		if !strings.Contains(fmt.Sprintf("%T", err), "ExitError") {
			t.Fatalf("run built sb: %v", err)
		}
		exitErr, _ = err.(*exec.ExitError)
		exit = exitErr.ExitCode()
	}
	return builtCoverageResult{stdout: stdout.String(), stderr: stderr.String(), exit: exit}
}

func TestBuiltReleaseCoveredAndSubset_CurrentDomains(t *testing.T) {
	api := emptyEvidenceServer(t)
	dir, anchor, target := realCoverageFixture(t, "test/install-recovery/arcs/working-arc.sh")
	binary := buildSBForCoverageInterface(t, target)
	for _, name := range []string{"working", "failing", "deploy-status-proof"} {
		markScenarioAt(t, dir, release.Scenario{Name: name, Home: release.WorkflowArcs}, anchor)
	}
	own := runBuiltCoverage(t, binary, dir, api.URL, "release", "covered", "--workflow", release.WorkflowArcs.String(), "working", "HEAD")
	if own.exit != exitMustRun || !strings.Contains(own.stdout, "working-arc.sh — own scenario") {
		t.Fatalf("arc own result exit=%d stdout=%q stderr=%q", own.exit, own.stdout, own.stderr)
	}
	sibling := runBuiltCoverage(t, binary, dir, api.URL, "release", "covered", "--workflow", release.WorkflowArcs.String(), "failing", "HEAD")
	if sibling.exit != exitCovered {
		t.Fatalf("arc sibling result exit=%d stdout=%q stderr=%q", sibling.exit, sibling.stdout, sibling.stderr)
	}
	details := filepath.Join(dir, "tmp", "details.md")
	subset := runBuiltCoverage(t, binary, dir, api.URL, "release", "covered-subset", "--details-file", details, release.WorkflowArcs.String(), "HEAD")
	if subset.exit != exitCovered || strings.TrimSpace(subset.stdout) != "working" {
		t.Fatalf("arc subset exit=%d stdout=%q stderr=%q", subset.exit, subset.stdout, subset.stderr)
	}
	body, err := os.ReadFile(details)
	if err != nil || !strings.Contains(string(body), "own scenario") {
		t.Fatalf("details=%q err=%v", body, err)
	}
	retired := runBuiltCoverage(t, binary, dir, api.URL, "release", "covered-subset", release.WorkflowFleet.String(), "HEAD")
	if retired.exit == exitCovered || !strings.Contains(retired.stderr, "VM fault workflow") || !strings.Contains(retired.stderr, "LXD fleet") {
		t.Fatalf("retired VM subset exit=%d stdout=%q stderr=%q", retired.exit, retired.stdout, retired.stderr)
	}
}

func TestBuiltFreshInstallCoverage_STATBUS369(t *testing.T) {
	api := emptyEvidenceServer(t)
	dir, anchor, target := realCoverageFixture(t, "doc/readme.md")
	runGitInCmd(t, dir, "tag", "v2026.09.0-rc.02")
	binary := buildSBForCoverageInterface(t, target)
	for _, home := range []release.Workflow{release.WorkflowSmoke} {
		install := release.Scenario{Name: "0-happy-install", Home: home}
		markScenarioAt(t, dir, install, anchor)
		markScenarioAt(t, dir, release.Scenario{Name: "0-happy-upgrade", Home: home}, anchor)
		result := runBuiltCoverage(t, binary, dir, api.URL, "release", "covered", "--workflow", home.String(), install.Name, "HEAD")
		if result.exit != exitMustRun || !strings.Contains(result.stdout, "candidate version") {
			t.Fatalf("%s: exit=%d stdout=%q stderr=%q", home, result.exit, result.stdout, result.stderr)
		}
		subset := runBuiltCoverage(t, binary, dir, api.URL, "release", "covered-subset", home.String(), "HEAD")
		if subset.exit != exitCovered || !strings.Contains(subset.stdout, "0-happy-install\n") || strings.Contains(subset.stdout, "0-happy-upgrade") {
			t.Fatalf("%s subset: exit=%d stdout=%q stderr=%q", home, subset.exit, subset.stdout, subset.stderr)
		}
		markScenarioAt(t, dir, install, target)
		direct := runBuiltCoverage(t, binary, dir, api.URL, "release", "covered", "--workflow", home.String(), install.Name, "HEAD")
		if direct.exit != exitCovered || !strings.Contains(direct.stdout, "ran and passed") {
			t.Fatalf("%s direct: exit=%d stdout=%q stderr=%q", home, direct.exit, direct.stdout, direct.stderr)
		}
	}
}

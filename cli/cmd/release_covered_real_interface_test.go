package cmd

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
		"test/install-recovery/run.sh":                          "base\n",
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

func TestBuiltReleaseCoveredAndSubset_ScenarioAwareSensitivity_STATBUS352(t *testing.T) {
	api := emptyEvidenceServer(t)
	newFixture := func(t *testing.T, changedPaths ...string) (string, string, string) {
		t.Helper()
		dir, anchor, target := realCoverageFixture(t, changedPaths...)
		return dir, anchor, buildSBForCoverageInterface(t, target)
	}

	t.Run("own versus sibling and reasoned details", func(t *testing.T) {
		dir, anchor, binary := newFixture(t, "test/install-recovery/scenarios/a.sh")
		markScenarioAt(t, dir, release.Scenario{Name: "a", Home: release.WorkflowFleet}, anchor)
		markScenarioAt(t, dir, release.Scenario{Name: "b", Home: release.WorkflowFleet}, anchor)
		markScenarioAt(t, dir, release.Scenario{Name: "0-happy-install", Home: release.WorkflowFleet}, anchor)
		markScenarioAt(t, dir, release.Scenario{Name: "0-happy-upgrade", Home: release.WorkflowFleet}, anchor)

		own := runBuiltCoverage(t, binary, dir, api.URL, "release", "covered", "--workflow", release.WorkflowFleet.String(), "a", "HEAD")
		if own.exit != exitMustRun || !strings.Contains(own.stdout, "test/install-recovery/scenarios/a.sh — own scenario") {
			t.Fatalf("own result exit=%d stdout=%q stderr=%q", own.exit, own.stdout, own.stderr)
		}
		sibling := runBuiltCoverage(t, binary, dir, api.URL, "release", "covered", "--workflow", release.WorkflowFleet.String(), "b", "HEAD")
		if sibling.exit != exitCovered || !strings.Contains(sibling.stdout, "already covered by") {
			t.Fatalf("sibling result exit=%d stdout=%q stderr=%q", sibling.exit, sibling.stdout, sibling.stderr)
		}

		details := filepath.Join(dir, "tmp", "details.md")
		subset := runBuiltCoverage(t, binary, dir, api.URL, "release", "covered-subset", "--details-file", details, release.WorkflowFleet.String(), "HEAD")
		if subset.exit != exitCovered || strings.TrimSpace(subset.stdout) != "a" {
			t.Fatalf("subset exit=%d stdout=%q stderr=%q", subset.exit, subset.stdout, subset.stderr)
		}
		body, err := os.ReadFile(details)
		if err != nil || !strings.Contains(string(body), "own scenario") {
			t.Fatalf("details=%q err=%v", body, err)
		}
	})

	t.Run("same-name fleet and smoke use different wrappers", func(t *testing.T) {
		dir, anchor, binary := newFixture(t, ".github/workflows/install-recovery-harness.yaml")
		fleetHappy := release.Scenario{Name: "0-happy-install", Home: release.WorkflowFleet}
		smokeHappy := release.Scenario{Name: "0-happy-install", Home: release.WorkflowSmoke}
		markScenarioAt(t, dir, fleetHappy, anchor)
		markScenarioAt(t, dir, smokeHappy, anchor)
		markScenarioAt(t, dir, release.Scenario{Name: "0-happy-upgrade", Home: release.WorkflowSmoke}, anchor)

		fleetResult := runBuiltCoverage(t, binary, dir, api.URL, "release", "covered", "--workflow", release.WorkflowFleet.String(), fleetHappy.Name, "HEAD")
		if fleetResult.exit != exitMustRun || !strings.Contains(fleetResult.stdout, "shared controller") {
			t.Fatalf("fleet result exit=%d stdout=%q stderr=%q", fleetResult.exit, fleetResult.stdout, fleetResult.stderr)
		}
		smokeResult := runBuiltCoverage(t, binary, dir, api.URL, "release", "covered", "--workflow", release.WorkflowSmoke.String(), smokeHappy.Name, "HEAD")
		if smokeResult.exit != exitCovered {
			t.Fatalf("smoke result exit=%d stdout=%q stderr=%q", smokeResult.exit, smokeResult.stdout, smokeResult.stderr)
		}
		smokeSubset := runBuiltCoverage(t, binary, dir, api.URL, "release", "covered-subset", release.WorkflowSmoke.String(), "HEAD")
		if smokeSubset.exit != exitCovered || smokeSubset.stdout != "" {
			t.Fatalf("smoke subset exit=%d stdout=%q stderr=%q", smokeSubset.exit, smokeSubset.stdout, smokeSubset.stderr)
		}
		ambiguous := runBuiltCoverage(t, binary, dir, api.URL, "release", "covered", smokeHappy.Name, "HEAD")
		if ambiguous.exit != exitUndecided || !strings.Contains(ambiguous.stderr, "ambiguous") {
			t.Fatalf("ambiguous exit=%d stdout=%q stderr=%q", ambiguous.exit, ambiguous.stdout, ambiguous.stderr)
		}
	})

	for _, tc := range []struct {
		name       string
		changed    string
		scenario   release.Scenario
		wantReason release.SensitivityReason
	}{
		{"shared runner", "test/install-recovery/run.sh", release.Scenario{Name: "working", Home: release.WorkflowArcs}, release.ReasonSharedController},
		{"shared library", "test/install-recovery/lib/assertions.sh", release.Scenario{Name: "a", Home: release.WorkflowFleet}, release.ReasonSharedHarnessInput},
		{"shared fixture", "test/install-recovery/fixtures/stage-head.sh", release.Scenario{Name: "0-happy-upgrade", Home: release.WorkflowSmoke}, release.ReasonSharedHarnessInput},
		{"arc deploy status", "ops/ci-deploy-status.sh", release.Scenario{Name: "failing", Home: release.WorkflowArcs}, release.ReasonSharedHarnessInput},
		{"arc sshdo", "ops/niue/sshdoers", release.Scenario{Name: "deploy-status-proof", Home: release.WorkflowArcs}, release.ReasonSharedHarnessInput},
		{"broad cli", "cli/internal/upgrade/service.go", release.Scenario{Name: "a", Home: release.WorkflowFleet}, release.ReasonBoxPayload},
		{"proof interpreter", "cli/internal/release/sensitivity.go", release.Scenario{Name: "a", Home: release.WorkflowFleet}, release.ReasonProofInterpreter},
	} {
		t.Run(tc.name, func(t *testing.T) {
			dir, anchor, binary := newFixture(t, tc.changed)
			markScenarioAt(t, dir, tc.scenario, anchor)
			result := runBuiltCoverage(t, binary, dir, api.URL, "release", "covered", "--workflow", tc.scenario.Home.String(), tc.scenario.Name, "HEAD")
			if result.exit != exitMustRun || !strings.Contains(result.stdout, tc.changed+" — "+string(tc.wantReason)) {
				t.Fatalf("exit=%d stdout=%q stderr=%q", result.exit, result.stdout, result.stderr)
			}
		})
	}

	t.Run("arc helper subset is scoped to its actual callers", func(t *testing.T) {
		dir, anchor, binary := newFixture(t, "ops/ci-deploy-status.sh")
		for _, name := range []string{"working", "failing", "deploy-status-proof"} {
			markScenarioAt(t, dir, release.Scenario{Name: name, Home: release.WorkflowArcs}, anchor)
		}
		result := runBuiltCoverage(t, binary, dir, api.URL, "release", "covered-subset", release.WorkflowArcs.String(), "HEAD")
		if result.exit != exitCovered || strings.TrimSpace(result.stdout) != "deploy-status-proof\nfailing" {
			t.Fatalf("arc subset exit=%d stdout=%q stderr=%q", result.exit, result.stdout, result.stderr)
		}
	})

	t.Run("anchored false match stays covered", func(t *testing.T) {
		dir, anchor, binary := newFixture(t, "tools/cli/example.go", "x/docker-compose.yml", "test/install-recovery/scenarios/a.sh.backup", "ops/niue/sshdo-not-used")
		scenario := release.Scenario{Name: "a", Home: release.WorkflowFleet}
		markScenarioAt(t, dir, scenario, anchor)
		result := runBuiltCoverage(t, binary, dir, api.URL, "release", "covered", "--workflow", scenario.Home.String(), scenario.Name, "HEAD")
		if result.exit != exitCovered {
			t.Fatalf("exit=%d stdout=%q stderr=%q", result.exit, result.stdout, result.stderr)
		}
	})

	t.Run("undecidable policy emits no partial subset", func(t *testing.T) {
		dir, anchor, binary := newFixture(t, "doc/readme.md")
		markScenarioAt(t, dir, release.Scenario{Name: "a", Home: release.WorkflowFleet}, anchor)
		writeFixtureFile(t, dir, release.SensitivePathsFile, "old-substring-format\n")

		one := runBuiltCoverage(t, binary, dir, api.URL, "release", "covered", "--workflow", release.WorkflowFleet.String(), "a", "HEAD")
		if one.exit != exitUndecided || !strings.Contains(one.stderr, "could not decide") {
			t.Fatalf("covered exit=%d stdout=%q stderr=%q", one.exit, one.stdout, one.stderr)
		}
		subset := runBuiltCoverage(t, binary, dir, api.URL, "release", "covered-subset", release.WorkflowFleet.String(), "HEAD")
		if subset.exit != exitUndecided || subset.stdout != "" || !strings.Contains(subset.stderr, "sensitivity policy") {
			t.Fatalf("subset exit=%d stdout=%q stderr=%q", subset.exit, subset.stdout, subset.stderr)
		}
	})
}

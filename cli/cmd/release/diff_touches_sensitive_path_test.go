package releasecmd

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/release"
	"github.com/statisticsnorway/statbus/cli/internal/testgit"
)

func runGitInCmd(t *testing.T, dir string, args ...string) string {
	t.Helper()
	cmd := exec.Command("git", testgit.Args(args...)...)
	cmd.Dir = dir
	cmd.Env = testgit.Env()
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("git %s failed: %v\n%s", strings.Join(args, " "), err, out)
	}
	return strings.TrimSpace(string(out))
}

func writeAndCommit(t *testing.T, dir, message string, paths ...string) {
	t.Helper()
	for _, p := range paths {
		full := filepath.Join(dir, p)
		if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(full, []byte("placeholder\n"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	installRealHarnessRunner(t, dir)
	runGitInCmd(t, dir, "add", ".")
	runGitInCmd(t, dir, "commit", "-q", "-m", message)
}

// installRealHarnessRunner copies THIS repository's test/install-recovery/run.sh
// into a fixture that has a harness tree but no runner of its own. The shared
// coverage evaluator runs the target commit's run.sh --print-selected as its
// structural prerequisite (STATBUS-352), so a fixture without a runner is
// undecidable by design; the real runner keeps fixtures faithful instead of
// stubbing the doctrine. A fixture that deliberately writes its own run.sh
// (placeholder or otherwise) is left alone.
func installRealHarnessRunner(t *testing.T, dir string) {
	t.Helper()
	harness := filepath.Join(dir, "test", "install-recovery")
	if _, err := os.Stat(harness); err != nil {
		return
	}
	dest := filepath.Join(harness, "run.sh")
	if _, err := os.Stat(dest); err == nil {
		return
	}
	src, err := os.ReadFile(thisRepoFile(t, "test/install-recovery/run.sh"))
	if err != nil {
		t.Fatalf("read the real harness runner: %v", err)
	}
	if err := os.WriteFile(dest, src, 0o755); err != nil {
		t.Fatal(err)
	}
}

func TestDiffSensitiveChanges_FullScenarioAndAnchoredPaths_STATBUS352(t *testing.T) {
	t.Run("own scenario matches while sibling and substring false positives do not", func(t *testing.T) {
		dir := t.TempDir()
		runGitInCmd(t, dir, "init", "-q")
		writeAndCommit(t, dir, "base", "doc/readme.md", "test/install-recovery/scenarios/base.sh")
		base := runGitInCmd(t, dir, "rev-parse", "HEAD")
		writeAndCommit(t, dir, "advance",
			"test/install-recovery/scenarios/a.sh",
			"test/install-recovery/scenarios/b.sh",
			"doc/install.sh-notes",
			"tools/cli/example.go",
			"x/docker-compose.yml",
		)
		writeSensitivePathsFile(t, dir)

		changes, err := release.DiffSensitiveChanges(dir, base, "HEAD", release.Scenario{Name: "a", Home: release.WorkflowFleet})
		if err != nil {
			t.Fatal(err)
		}
		want := []release.SensitiveChange{{Path: "test/install-recovery/scenarios/a.sh", Reason: release.ReasonOwnScenario}}
		if !equalSensitiveChanges(changes, want) {
			t.Fatalf("changes=%v, want %v", changes, want)
		}
	})

	t.Run("rename cannot escape through the safe destination", func(t *testing.T) {
		dir := t.TempDir()
		runGitInCmd(t, dir, "init", "-q")
		writeAndCommit(t, dir, "base", "cli/internal/release/old.go")
		base := runGitInCmd(t, dir, "rev-parse", "HEAD")
		if err := os.MkdirAll(filepath.Join(dir, "doc"), 0o755); err != nil {
			t.Fatal(err)
		}
		runGitInCmd(t, dir, "mv", "cli/internal/release/old.go", "doc/old.go")
		runGitInCmd(t, dir, "commit", "-q", "-m", "rename")
		writeSensitivePathsFile(t, dir)

		changes, err := release.DiffSensitiveChanges(dir, base, "HEAD", release.Scenario{Name: "a", Home: release.WorkflowFleet})
		if err != nil {
			t.Fatal(err)
		}
		want := []release.SensitiveChange{{Path: "cli/internal/release/old.go", Reason: release.ReasonProofInterpreter}}
		if !equalSensitiveChanges(changes, want) {
			t.Fatalf("rename changes=%v, want old sensitive path %v", changes, want)
		}
	})

	t.Run("git failure is undecidable", func(t *testing.T) {
		dir := t.TempDir()
		runGitInCmd(t, dir, "init", "-q")
		writeAndCommit(t, dir, "base", "doc/readme.md")
		writeSensitivePathsFile(t, dir)
		if _, err := release.DiffSensitiveChanges(dir, "missing-anchor", "HEAD", release.Scenario{Name: "a", Home: release.WorkflowFleet}); err == nil {
			t.Fatal("missing anchor was treated as a sensitivity answer")
		}
	})
}

func equalSensitiveChanges(a, b []release.SensitiveChange) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

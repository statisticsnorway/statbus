package releasecmd

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/testgit"
)

func TestCheckWorkingTreeCleanReportsUntrackedFiles(t *testing.T) {
	dir := t.TempDir()
	runGitForWorkingTreeTest(t, dir, "init", "-q")
	runGitForWorkingTreeTest(t, dir, "config", "user.name", "Release Test")
	runGitForWorkingTreeTest(t, dir, "config", "user.email", "release-test@example.invalid")

	tracked := filepath.Join(dir, "tracked.txt")
	if err := os.WriteFile(tracked, []byte("tracked\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	runGitForWorkingTreeTest(t, dir, "add", "tracked.txt")
	runGitForWorkingTreeTest(t, dir, "commit", "-qm", "fixture")

	if out := captureStdout(t, func() {
		if !checkWorkingTreeClean(dir) {
			t.Error("clean fixture was reported dirty")
		}
	}); !strings.Contains(out, "✓ Working tree is clean") {
		t.Fatalf("clean verdict missing; output:\n%s", out)
	}
	for _, relPath := range []string{
		"test/expected/explain/local.out",
		"test/expected/performance/local.out",
	} {
		path := filepath.Join(dir, filepath.FromSlash(relPath))
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte("environment baseline\n"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	if out := captureStdout(t, func() {
		if !checkWorkingTreeClean(dir) {
			t.Error("excluded explain/performance baselines were reported dirty")
		}
	}); !strings.Contains(out, "✓ Working tree is clean") {
		t.Fatalf("excluded-baseline clean verdict missing; output:\n%s", out)
	}

	const sentinel = ".release-preflight-untracked"
	if err := os.WriteFile(filepath.Join(dir, sentinel), []byte("sentinel\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	out := captureStdout(t, func() {
		if checkWorkingTreeClean(dir) {
			t.Error("untracked file was reported clean")
		}
	})
	if !strings.Contains(out, "✗ Working tree is clean") {
		t.Fatalf("dirty verdict missing; output:\n%s", out)
	}
	if !strings.Contains(out, sentinel) {
		t.Fatalf("dirty verdict did not name %s; output:\n%s", sentinel, out)
	}
}

func runGitForWorkingTreeTest(t *testing.T, dir string, args ...string) {
	t.Helper()
	cmd := exec.Command("git", testgit.Args(args...)...)
	cmd.Dir = dir
	cmd.Env = testgit.Env()
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("git %s: %v\n%s", strings.Join(args, " "), err, out)
	}
}

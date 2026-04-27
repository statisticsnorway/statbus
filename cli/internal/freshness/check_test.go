package freshness

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// TestIsStale_EmptyCommit covers the silent-skip path for builds without
// ldflags (local `go run`, fresh-clone CI without -X cmd.commit). The
// guard must produce no diagnostic in that case — the runtime can't
// answer the question, and a warning would be noise during daily dev.
func TestIsStale_EmptyCommit(t *testing.T) {
	if got := IsStale(t.TempDir(), ""); got != "" {
		t.Errorf("empty commit: got %q, want empty", got)
	}
}

// TestIsStale_UnknownCommit covers the same skip for the explicit
// sentinel string used in cli/cmd/root.go's default.
func TestIsStale_UnknownCommit(t *testing.T) {
	if got := IsStale(t.TempDir(), "unknown"); got != "" {
		t.Errorf("unknown commit: got %q, want empty", got)
	}
}

// TestIsStale_NoGitRepo covers the silent-skip path when projDir isn't
// a git checkout (sparse install, tarball deploy). A real exit error
// from git that isn't "differences found" must not surface as stale.
func TestIsStale_NoGitRepo(t *testing.T) {
	if got := IsStale(t.TempDir(), "abcdef1234567890"); got != "" {
		t.Errorf("non-git dir: got %q, want empty (silent skip)", got)
	}
}

// TestIsStale_FreshTree covers the happy path: git diff finds no
// changes between the build commit and the worktree's cli/, returns
// exit 0, IsStale returns "".
func TestIsStale_FreshTree(t *testing.T) {
	dir, head := setupGitRepoWithCli(t)
	if got := IsStale(dir, head); got != "" {
		t.Errorf("fresh tree: got %q, want empty", got)
	}
}

// TestIsStale_DriftedCli covers the positive case: cli/ has been edited
// since the build commit. git diff exits 1; IsStale returns the
// diagnostic with the short build commit.
func TestIsStale_DriftedCli(t *testing.T) {
	dir, head := setupGitRepoWithCli(t)

	// Modify a file inside cli/ without committing.
	cliFile := filepath.Join(dir, "cli", "main.go")
	if err := os.WriteFile(cliFile, []byte("package main\n// drifted\n"), 0644); err != nil {
		t.Fatal(err)
	}

	got := IsStale(dir, head)
	if got == "" {
		t.Fatal("drifted cli/: got empty, want diagnostic")
	}
	short := head
	if len(short) > 8 {
		short = short[:8]
	}
	if !strings.Contains(got, "./sb is stale") {
		t.Errorf("diagnostic missing prefix: %q", got)
	}
	if !strings.Contains(got, short) {
		t.Errorf("diagnostic missing short commit %q: %q", short, got)
	}
	if !strings.Contains(got, "Rebuild:") {
		t.Errorf("diagnostic missing remediation: %q", got)
	}
}

// TestIsStale_NonCliChangeIgnored covers the scope rule: edits OUTSIDE
// cli/ (e.g. in migrations/, doc/) must not trigger the guard. The
// guard only cares about the binary's source.
func TestIsStale_NonCliChangeIgnored(t *testing.T) {
	dir, head := setupGitRepoWithCli(t)

	// Modify a file OUTSIDE cli/ without committing.
	outFile := filepath.Join(dir, "doc", "data-model.md")
	if err := os.MkdirAll(filepath.Dir(outFile), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(outFile, []byte("# drifted\n"), 0644); err != nil {
		t.Fatal(err)
	}

	if got := IsStale(dir, head); got != "" {
		t.Errorf("non-cli change: got %q, want empty (cli/-only scope)", got)
	}
}

// TestIsStale_NonexistentCommit covers the silent-skip path when the
// build commit isn't in the local repo (sparse fetch, depth-1 clone,
// reset to a different upstream). git diff returns a non-1 exit code;
// IsStale must NOT return a diagnostic — the comparison is uncertain.
func TestIsStale_NonexistentCommit(t *testing.T) {
	dir, _ := setupGitRepoWithCli(t)
	bogus := "0000000000000000000000000000000000000000"
	if got := IsStale(dir, bogus); got != "" {
		t.Errorf("nonexistent commit: got %q, want empty (silent skip)", got)
	}
}

// setupGitRepoWithCli creates a temp dir initialised as a git repo,
// adds a cli/ subdirectory with a single file, commits it, and returns
// the dir + the head SHA. Used by the positive-path tests.
func setupGitRepoWithCli(t *testing.T) (dir, head string) {
	t.Helper()
	dir = t.TempDir()

	runGit := func(args ...string) string {
		t.Helper()
		cmd := exec.Command("git", args...)
		cmd.Dir = dir
		cmd.Env = append(os.Environ(),
			"GIT_AUTHOR_NAME=test", "GIT_AUTHOR_EMAIL=test@example.com",
			"GIT_COMMITTER_NAME=test", "GIT_COMMITTER_EMAIL=test@example.com",
		)
		out, err := cmd.CombinedOutput()
		if err != nil {
			t.Fatalf("git %s failed: %v\n%s", strings.Join(args, " "), err, out)
		}
		return strings.TrimSpace(string(out))
	}

	runGit("init", "-q")

	if err := os.MkdirAll(filepath.Join(dir, "cli"), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "cli", "main.go"), []byte("package main\n"), 0644); err != nil {
		t.Fatal(err)
	}

	runGit("add", ".")
	runGit("commit", "-q", "-m", "initial")
	head = runGit("rev-parse", "HEAD")
	return dir, head
}

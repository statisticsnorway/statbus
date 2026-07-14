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

// TestIsStale_UncommittedIgnored is the canonical-guard behavior: the binary was
// built from the current HEAD (commit matches), and cli/ has uncommitted (WIP)
// changes. The guard can't tell whether those bytes are in the binary — its
// identity is commit-based — so it must NOT flag staleness. Running ./sb while
// editing cli/ is allowed; only committed drift is flagged.
func TestIsStale_UncommittedIgnored(t *testing.T) {
	dir, head := setupGitRepoWithCli(t)

	// Modify a file inside cli/ without committing → uncommitted (WIP) only.
	cliFile := filepath.Join(dir, "cli", "main.go")
	if err := os.WriteFile(cliFile, []byte("package main\n// drifted\n"), 0644); err != nil {
		t.Fatal(err)
	}

	if got := IsStale(dir, head); got != "" {
		t.Errorf("uncommitted (WIP) cli/ edits on a HEAD-matching binary must be fresh; got %q", got)
	}
}

// TestIsStale_CommittedDrift covers the case where the binary was built
// from a commit OLDER than HEAD, and cli/ has been changed by commits
// landed since. The diagnostic must name the HEAD commit (so the
// operator knows what they need to rebuild against) and not falsely
// imply uncommitted work.
func TestIsStale_CommittedDrift(t *testing.T) {
	dir, oldHead := setupGitRepoWithCli(t)

	// Add a SECOND commit that modifies cli/. The binary remains
	// "built from oldHead" while HEAD advances.
	cliFile := filepath.Join(dir, "cli", "main.go")
	if err := os.WriteFile(cliFile, []byte("package main\n// later\n"), 0644); err != nil {
		t.Fatal(err)
	}
	runGitIn(t, dir, "add", "cli/main.go")
	runGitIn(t, dir, "commit", "-q", "-m", "advance cli")

	got := IsStale(dir, oldHead)
	if got == "" {
		t.Fatal("committed drift: got empty, want diagnostic")
	}
	short := oldHead
	if len(short) > 8 {
		short = short[:8]
	}
	if !strings.Contains(got, "./sb is stale") {
		t.Errorf("diagnostic missing prefix: %q", got)
	}
	if !strings.Contains(got, short) {
		t.Errorf("diagnostic missing short build commit %q: %q", short, got)
	}
	if !strings.Contains(got, "HEAD is now") {
		t.Errorf("diagnostic should name HEAD (so operator knows the target): %q", got)
	}
	// Operator must not see "uncommitted" wording in the committed-only
	// case — that would re-introduce the conflation we just fixed.
	if strings.Contains(got, "uncommitted") {
		t.Errorf("committed-only drift leaked 'uncommitted' wording: %q", got)
	}
	if !strings.Contains(got, "./dev.sh build-sb") {
		t.Errorf("diagnostic missing fast rebuild option: %q", got)
	}
}

// TestIsStale_CommittedDriftWithWip: committed drift WITH an uncommitted change
// on top. Committed drift dominates — the binary is genuinely from an older
// commit — so the guard flags it as stale. The uncommitted change is not
// separately mentioned; the guard's only concern is the build commit vs HEAD.
func TestIsStale_CommittedDriftWithWip(t *testing.T) {
	dir, oldHead := setupGitRepoWithCli(t)

	// Commit-advance cli/ (committed drift vs oldHead).
	cliFile := filepath.Join(dir, "cli", "main.go")
	if err := os.WriteFile(cliFile, []byte("package main\n// later\n"), 0644); err != nil {
		t.Fatal(err)
	}
	runGitIn(t, dir, "add", "cli/main.go")
	runGitIn(t, dir, "commit", "-q", "-m", "advance cli")

	// AND a further uncommitted change on top.
	if err := os.WriteFile(cliFile, []byte("package main\n// later\n// wip\n"), 0644); err != nil {
		t.Fatal(err)
	}

	got := IsStale(dir, oldHead)
	if got == "" {
		t.Fatal("committed drift (with WIP on top): got empty, want stale diagnostic")
	}
	if !strings.Contains(got, "HEAD is now") {
		t.Errorf("diagnostic missing committed-drift phrasing: %q", got)
	}
	if strings.Contains(got, "uncommitted") {
		t.Errorf("committed-drift verdict should not mention uncommitted: %q", got)
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

// TestIsStale_NonexistentCommit covers the surface-the-failure path
// when the build commit isn't in the local repo (sparse fetch,
// depth-1 clone, reset to a different upstream). `git diff` returns
// a non-1 exit code (typically 128, "fatal: bad revision"). IsStale
// MUST return a diagnostic naming the exit code + stderr — silent
// skip would let mutating commands proceed against a broken
// freshness check, violating fail-fast.
//
// Behavior change from commit 5's initial implementation: previously
// silent-skipped (returned ""); now surfaces the failure.
func TestIsStale_NonexistentCommit(t *testing.T) {
	dir, _ := setupGitRepoWithCli(t)
	bogus := "0000000000000000000000000000000000000000"
	got := IsStale(dir, bogus)
	if got == "" {
		t.Fatal("nonexistent commit: got empty, want diagnostic")
	}
	if !strings.Contains(got, "freshness check failed") {
		t.Errorf("diagnostic missing prefix: %q", got)
	}
	if !strings.Contains(got, "exited") {
		t.Errorf("diagnostic missing exit-code label: %q", got)
	}
	short := bogus[:8]
	if !strings.Contains(got, short) {
		t.Errorf("diagnostic missing short build commit %q: %q", short, got)
	}
}

// TestIsStale_ExecFailure covers the exec-error path: git itself
// can't be run (not installed, PATH broken, permission denied). The
// !ok branch must surface a "freshness check could not run git"
// diagnostic — same fail-fast principle as the non-1 exit case.
func TestIsStale_ExecFailure(t *testing.T) {
	dir, head := setupGitRepoWithCli(t)

	// Point PATH at an empty directory so the git binary isn't
	// resolvable. Restore on cleanup.
	emptyDir := t.TempDir()
	prevPath, hadPath := os.LookupEnv("PATH")
	_ = os.Setenv("PATH", emptyDir)
	t.Cleanup(func() {
		if hadPath {
			_ = os.Setenv("PATH", prevPath)
		} else {
			_ = os.Unsetenv("PATH")
		}
	})

	got := IsStale(dir, head)
	if got == "" {
		t.Fatal("exec failure: got empty, want diagnostic")
	}
	if !strings.Contains(got, "freshness check could not run git") {
		t.Errorf("diagnostic missing prefix: %q", got)
	}
}

// runGitIn invokes git in dir with deterministic author/committer env
// so commits are reproducible regardless of the operator's git config.
// Returns trimmed stdout; fails the test on non-zero exit.
//
// Shared across freshness tests (committed-drift, both-drifts) that
// need to make additional commits on top of setupGitRepoWithCli's
// initial state.
func runGitIn(t *testing.T, dir string, args ...string) string {
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

// setupGitRepoWithCli creates a temp dir initialised as a git repo,
// adds a cli/ subdirectory with a single file, commits it, and returns
// the dir + the head SHA. Used by the positive-path tests.
func setupGitRepoWithCli(t *testing.T) (dir, head string) {
	t.Helper()
	dir = t.TempDir()

	runGitIn(t, dir, "init", "-q")

	if err := os.MkdirAll(filepath.Join(dir, "cli"), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "cli", "main.go"), []byte("package main\n"), 0644); err != nil {
		t.Fatal(err)
	}

	runGitIn(t, dir, "add", ".")
	runGitIn(t, dir, "commit", "-q", "-m", "initial")
	head = runGitIn(t, dir, "rev-parse", "HEAD")
	return dir, head
}

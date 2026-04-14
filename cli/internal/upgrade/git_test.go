package upgrade

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// gitRepoFixture builds a minimal repo with two commits + a tag on the
// first one, returns the projDir + the two commit SHAs (oldest first).
type gitRepoFixture struct {
	dir              string
	oldSHA, newSHA   string
	tagOnOld         string
	branchOnOld      string
}

func newGitRepoFixture(t *testing.T) *gitRepoFixture {
	t.Helper()
	if _, err := exec.LookPath("git"); err != nil {
		t.Skip("git not on PATH")
	}
	dir := t.TempDir()
	run := func(args ...string) string {
		t.Helper()
		cmd := exec.Command("git", args...)
		cmd.Dir = dir
		// Disable signing for the test repo regardless of the operator's
		// global config — we don't want to fail on missing signing keys.
		cmd.Env = append(os.Environ(),
			"GIT_AUTHOR_NAME=test",
			"GIT_AUTHOR_EMAIL=test@example.com",
			"GIT_COMMITTER_NAME=test",
			"GIT_COMMITTER_EMAIL=test@example.com",
		)
		out, err := cmd.CombinedOutput()
		if err != nil {
			t.Fatalf("git %s: %v\n%s", strings.Join(args, " "), err, out)
		}
		return strings.TrimSpace(string(out))
	}

	run("init", "-q", "-b", "main")
	run("config", "commit.gpgsign", "false")
	run("config", "tag.gpgSign", "false")

	if err := os.WriteFile(filepath.Join(dir, "README.md"), []byte("v1\n"), 0644); err != nil {
		t.Fatal(err)
	}
	run("add", ".")
	run("commit", "-q", "-m", "commit 1")
	oldSHA := run("rev-parse", "HEAD")
	run("tag", "v0.1.0")
	run("branch", "statbus/pre-upgrade", "HEAD")

	if err := os.WriteFile(filepath.Join(dir, "README.md"), []byte("v2\n"), 0644); err != nil {
		t.Fatal(err)
	}
	run("add", ".")
	run("commit", "-q", "-m", "commit 2")
	newSHA := run("rev-parse", "HEAD")

	return &gitRepoFixture{
		dir:         dir,
		oldSHA:      oldSHA,
		newSHA:      newSHA,
		tagOnOld:    "v0.1.0",
		branchOnOld: "statbus/pre-upgrade",
	}
}

func discardLog(format string, args ...interface{}) {}

func TestRestoreGitState_HappyPathByTag(t *testing.T) {
	fix := newGitRepoFixture(t)

	if err := restoreGitStateFn(fix.dir, fix.tagOnOld, discardLog); err != nil {
		t.Fatalf("restoreGitStateFn: %v", err)
	}

	out, err := exec.Command("git", "-C", fix.dir, "rev-parse", "HEAD").Output()
	if err != nil {
		t.Fatalf("post rev-parse: %v", err)
	}
	got := strings.TrimSpace(string(out))
	if got != fix.oldSHA {
		t.Errorf("HEAD = %s, want %s (oldSHA)", got, fix.oldSHA)
	}
}

func TestRestoreGitState_HappyPathBySHA(t *testing.T) {
	fix := newGitRepoFixture(t)

	if err := restoreGitStateFn(fix.dir, fix.oldSHA, discardLog); err != nil {
		t.Fatalf("restoreGitStateFn: %v", err)
	}
}

func TestRestoreGitState_BogusRefNoFallback(t *testing.T) {
	fix := newGitRepoFixture(t)
	// Remove the fallback branch so we exercise the pure-failure path.
	exec.Command("git", "-C", fix.dir, "branch", "-D", fix.branchOnOld).Run()

	err := restoreGitStateFn(fix.dir, "v999.999.999", discardLog)
	if err == nil {
		t.Fatal("restoreGitStateFn returned nil, want error")
	}
	if !strings.Contains(err.Error(), "neither v999.999.999 nor statbus/pre-upgrade resolves") {
		t.Errorf("error %q does not name both refs", err)
	}

	// Working tree must be unchanged.
	out, _ := exec.Command("git", "-C", fix.dir, "rev-parse", "HEAD").Output()
	if got := strings.TrimSpace(string(out)); got != fix.newSHA {
		t.Errorf("HEAD changed to %s after failed restore (want unchanged %s)", got, fix.newSHA)
	}
}

func TestRestoreGitState_FallbackToBranch(t *testing.T) {
	fix := newGitRepoFixture(t)
	// Remove the tag so the primary ref doesn't resolve.
	exec.Command("git", "-C", fix.dir, "tag", "-d", fix.tagOnOld).Run()

	err := restoreGitStateFn(fix.dir, fix.tagOnOld, discardLog)
	if err != nil {
		t.Fatalf("restoreGitStateFn (with fallback): %v", err)
	}

	out, _ := exec.Command("git", "-C", fix.dir, "rev-parse", "HEAD").Output()
	if got := strings.TrimSpace(string(out)); got != fix.oldSHA {
		t.Errorf("HEAD = %s, want %s (oldSHA via fallback)", got, fix.oldSHA)
	}
}

func TestRestoreGitState_DetachedHeadOK(t *testing.T) {
	// Checkout by SHA always lands in detached-HEAD; the function must
	// still post-verify successfully.
	fix := newGitRepoFixture(t)
	if err := restoreGitStateFn(fix.dir, fix.oldSHA, discardLog); err != nil {
		t.Fatalf("restoreGitStateFn detached: %v", err)
	}
	// Confirm it really is detached.
	out, _ := exec.Command("git", "-C", fix.dir, "symbolic-ref", "-q", "HEAD").CombinedOutput()
	if strings.TrimSpace(string(out)) != "" {
		t.Errorf("expected detached HEAD, got symbolic-ref output: %q", out)
	}
}

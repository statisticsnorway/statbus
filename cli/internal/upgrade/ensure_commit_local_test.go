package upgrade

import (
	"os"
	"os/exec"
	"strings"
	"testing"
	"time"
)

// TestEnsureCommitLocal_FetchesMissingCommit_STATBUS169 pins the deploy-by-commit
// fetch-before-use fix. `./sb upgrade register <sha>` reads the commit's metadata
// with `git show`; a standalone box only fetches during an upgrade it is already
// running, so a fresh register for an unfetched commit died at "git show <sha>:
// bad object" (rune). ensureCommitLocal must make a reachable-but-absent commit
// local (fetch), and no-op when it is already present.
func TestEnsureCommitLocal_FetchesMissingCommit_STATBUS169(t *testing.T) {
	if _, err := exec.LookPath("git"); err != nil {
		t.Skip("git not on PATH")
	}

	git := func(t *testing.T, dir string, args ...string) string {
		t.Helper()
		cmd := exec.Command("git", args...)
		cmd.Dir = dir
		cmd.Env = append(os.Environ(),
			"GIT_AUTHOR_NAME=test", "GIT_AUTHOR_EMAIL=test@example.com",
			"GIT_COMMITTER_NAME=test", "GIT_COMMITTER_EMAIL=test@example.com",
		)
		out, err := cmd.CombinedOutput()
		if err != nil {
			t.Fatalf("git %s: %v\n%s", strings.Join(args, " "), err, out)
		}
		return strings.TrimSpace(string(out))
	}

	// "origin": a repo with commit C at the tip of main (advertised → fetchable by SHA).
	origin := t.TempDir()
	git(t, origin, "init", "-q", "-b", "main")
	git(t, origin, "config", "commit.gpgsign", "false")
	git(t, origin, "commit", "-q", "--allow-empty", "-m", "commit C")
	commitC := git(t, origin, "rev-parse", "HEAD")

	// "local": a box that has origin as a remote but has NOT fetched C.
	local := t.TempDir()
	git(t, local, "init", "-q", "-b", "main")
	git(t, local, "config", "commit.gpgsign", "false")
	git(t, local, "remote", "add", "origin", origin)

	catFileOK := func(dir, sha string) bool {
		cmd := exec.Command("git", "cat-file", "-e", sha+"^{commit}")
		cmd.Dir = dir
		return cmd.Run() == nil
	}

	// Precondition: C is genuinely ABSENT locally — else the fetch path is untested.
	if catFileOK(local, commitC) {
		t.Fatalf("test setup: commit %s already present locally; the fetch path would be untested", commitC)
	}

	d := &Service{projDir: local}
	if err := d.ensureCommitLocal(commitC, 30*time.Second); err != nil {
		t.Fatalf("ensureCommitLocal(missing commit): %v — register must fetch a reachable commit to make it local", err)
	}
	if !catFileOK(local, commitC) {
		t.Fatalf("commit %s still absent after ensureCommitLocal — the fetch did not land it", commitC)
	}

	// Idempotent: a second call is a no-op success (commit now present).
	if err := d.ensureCommitLocal(commitC, 30*time.Second); err != nil {
		t.Errorf("ensureCommitLocal(present commit) = %v, want nil (must no-op when already local)", err)
	}
}

// TestEnsureCommitLocal_FetchesTagViaRefspec_STATBUS183 is the BEHAVIORAL proof of
// A1: a tag argument must land the LOCAL TAG REF (so `git rev-parse <tag>` resolves),
// not just FETCH_HEAD. Plain `git fetch origin <tag>` would leave rev-parse failing —
// the exact rc.06 apply-race case; the explicit refs/tags refspec form fixes it.
func TestEnsureCommitLocal_FetchesTagViaRefspec_STATBUS183(t *testing.T) {
	if _, err := exec.LookPath("git"); err != nil {
		t.Skip("git not on PATH")
	}
	git := func(t *testing.T, dir string, args ...string) string {
		t.Helper()
		cmd := exec.Command("git", args...)
		cmd.Dir = dir
		cmd.Env = append(os.Environ(),
			"GIT_AUTHOR_NAME=test", "GIT_AUTHOR_EMAIL=test@example.com",
			"GIT_COMMITTER_NAME=test", "GIT_COMMITTER_EMAIL=test@example.com",
		)
		out, err := cmd.CombinedOutput()
		if err != nil {
			t.Fatalf("git %s: %v\n%s", strings.Join(args, " "), err, out)
		}
		return strings.TrimSpace(string(out))
	}

	// origin has a release tag; local has origin as a remote but has NOT fetched it.
	origin := t.TempDir()
	git(t, origin, "init", "-q", "-b", "main")
	git(t, origin, "config", "commit.gpgsign", "false")
	git(t, origin, "commit", "-q", "--allow-empty", "-m", "release commit")
	const tag = "v2026.07.0-rc.99"
	git(t, origin, "tag", tag)

	local := t.TempDir()
	git(t, local, "init", "-q", "-b", "main")
	git(t, local, "config", "commit.gpgsign", "false")
	git(t, local, "remote", "add", "origin", origin)

	revParseOK := func(dir, ref string) bool {
		cmd := exec.Command("git", "rev-parse", "--verify", "-q", ref+"^{commit}")
		cmd.Dir = dir
		return cmd.Run() == nil
	}
	if revParseOK(local, tag) {
		t.Fatalf("test setup: tag %s already resolvable locally; the fetch path would be untested", tag)
	}

	d := &Service{projDir: local}
	if err := d.ensureCommitLocal(tag, 30*time.Second); err != nil {
		t.Fatalf("ensureCommitLocal(missing tag): %v — the apply-race fix must fetch a tag to make it resolvable", err)
	}
	if !revParseOK(local, tag) {
		t.Fatalf("tag %s still not rev-parse-able after ensureCommitLocal — the refspec fetch did not create the local tag ref (FETCH_HEAD-only regression, the rc.06 case)", tag)
	}
}

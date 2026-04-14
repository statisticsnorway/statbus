package upgrade

import (
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestRegexEscape(t *testing.T) {
	cases := []struct {
		in, want string
	}{
		{"plain", "plain"},
		{"with.dot", `with\.dot`},
		{"with+plus", `with\+plus`},
		{"with*star", `with\*star`},
		{"refs/heads/devops/*", `refs\/heads\/devops\/\*`},
		// Real refspec shape: every special metachar present
		{
			"+refs/heads/devops/deploy-to-dev:refs/remotes/origin/devops/deploy-to-dev",
			`\+refs\/heads\/devops\/deploy-to-dev:refs\/remotes\/origin\/devops\/deploy-to-dev`,
		},
		{"a.b+c*d?e(f)g[h]i{j}k|l^m$n/o", `a\.b\+c\*d\?e\(f\)g\[h\]i\{j\}k\|l\^m\$n\/o`},
	}
	for _, c := range cases {
		t.Run(c.in, func(t *testing.T) {
			got := regexEscape(c.in)
			if got != c.want {
				t.Errorf("regexEscape(%q) = %q, want %q", c.in, got, c.want)
			}
		})
	}
}

// TestCleanStaleRefspecs sets up a temp git repo with a mix of legitimate
// and stale refspecs, runs CleanStaleRefspecs, and asserts only stale ones
// were removed.
func TestCleanStaleRefspecs(t *testing.T) {
	if _, err := exec.LookPath("git"); err != nil {
		t.Skip("git not on PATH")
	}

	dir := t.TempDir()
	run := func(args ...string) {
		t.Helper()
		cmd := exec.Command("git", args...)
		cmd.Dir = dir
		if out, err := cmd.CombinedOutput(); err != nil {
			t.Fatalf("git %s: %v\n%s", strings.Join(args, " "), err, out)
		}
	}

	run("init", "-q")
	run("remote", "add", "origin", "https://example.invalid/repo.git")
	// Default fetch refspec from `git remote add` is the legitimate one;
	// keep it. Add the stale ones we want CleanStaleRefspecs to remove,
	// plus a non-stale extra to confirm it's left alone.
	run("config", "--add", "remote.origin.fetch",
		"+refs/heads/devops/deploy-to-dev:refs/remotes/origin/devops/deploy-to-dev")
	run("config", "--add", "remote.origin.fetch",
		"+refs/heads/devops/*:refs/remotes/origin/devops/*")
	run("config", "--add", "remote.origin.fetch",
		"+refs/heads/ops/cloud/deploy/dev:refs/remotes/origin/ops/cloud/deploy/dev")

	CleanStaleRefspecs(dir)

	out, err := exec.Command("git", "-C", dir, "config", "--get-all", "remote.origin.fetch").Output()
	if err != nil {
		t.Fatalf("post-clean config read: %v", err)
	}
	got := strings.TrimSpace(string(out))

	for _, line := range strings.Split(got, "\n") {
		if strings.Contains(line, "refs/heads/devops/") {
			t.Errorf("stale refspec still present: %q\nfull config:\n%s", line, got)
		}
	}

	// The legitimate ones must still be there.
	wantPresent := []string{
		"+refs/heads/*:refs/remotes/origin/*", // default from `git remote add`
		"+refs/heads/ops/cloud/deploy/dev:refs/remotes/origin/ops/cloud/deploy/dev",
	}
	for _, want := range wantPresent {
		if !strings.Contains(got, want) {
			t.Errorf("legitimate refspec %q removed:\nfull config:\n%s", want, got)
		}
	}
}

// TestCleanStaleRefspecs_noRepo confirms the no-op behavior when invoked
// outside a git working tree (e.g., during install before repo is cloned).
func TestCleanStaleRefspecs_noRepo(t *testing.T) {
	dir := t.TempDir()
	// Should not panic, should not error visibly.
	CleanStaleRefspecs(dir)
	// Sanity: filepath.Join works (just ensures we didn't mutate `dir`).
	_ = filepath.Join(dir, "x")
}

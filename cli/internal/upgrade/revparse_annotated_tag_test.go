package upgrade

import (
	"context"
	"os"
	"os/exec"
	"strings"
	"testing"
)

// TestRevParse_PeelsAnnotatedTag_STATBUS169 pins the annotated-tag peel. Release
// tags are cut ANNOTATED (`git tag -m`), and a bare `git rev-parse <annotated-tag>`
// returns the TAG OBJECT sha, not the commit — which made the AC#1 write-guard
// refuse every real rc.04 register ("tag points at <tag-object>, not <commit>").
// The fixed RevParse peels with ^{commit}, so it returns the COMMIT for an
// annotated tag, a lightweight tag, a full SHA, and a short SHA alike.
//
// The fake-lookup resolver tests can't catch this (their double returns a mapped
// commit directly); only a REAL annotated tag through real git exercises the peel.
func TestRevParse_PeelsAnnotatedTag_STATBUS169(t *testing.T) {
	if _, err := exec.LookPath("git"); err != nil {
		t.Skip("git not on PATH")
	}
	dir := t.TempDir()
	run := func(args ...string) string {
		t.Helper()
		cmd := exec.Command("git", args...)
		cmd.Dir = dir
		// Isolate from the operator's global/system git config (signing keys,
		// hooks) so the test is hermetic across dev machines.
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

	run("init", "-q", "-b", "main")
	run("config", "commit.gpgsign", "false")
	run("config", "tag.gpgSign", "false")
	run("commit", "-q", "--allow-empty", "-m", "commit 1")
	commit := run("rev-parse", "HEAD")

	run("tag", "-a", "-m", "annotated release", "v2026.07.0-rc.99") // annotated (the shipped shape)
	run("tag", "lightweight-tag")                                   // lightweight

	// Guard the guard: prove the setup really produced an annotated tag whose
	// object sha differs from the commit — otherwise this test would pass even if
	// the peel were removed.
	tagObject := run("rev-parse", "v2026.07.0-rc.99")
	if tagObject == commit {
		t.Fatalf("test setup: annotated tag object %s == commit %s — git did not create an annotated tag; the peel would be untested", tagObject, commit)
	}

	d := &Service{projDir: dir}
	for _, ref := range []string{"v2026.07.0-rc.99", "lightweight-tag", commit, commit[:8]} {
		got, err := d.RevParse(context.Background(), ref)
		if err != nil {
			t.Fatalf("RevParse(%q): %v", ref, err)
		}
		if string(got) != commit {
			t.Errorf("RevParse(%q) = %s, want the COMMIT %s — annotated tags must peel via ^{commit}", ref, got, commit)
		}
	}
}

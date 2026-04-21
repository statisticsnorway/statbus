package cmd

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestPrereleaseTagRE(t *testing.T) {
	cases := []struct {
		tag   string
		match bool
	}{
		{"v2026.04.0-rc.1", true},
		{"v2026.04.0-rc.10", true},
		{"v2026.12.5-rc.42", true},
		{"v2026.04.0", false},              // stable, not rc
		{"v26.04.0-rc.1", false},           // 2-digit year
		{"v2026.4.0-rc.1", false},          // 1-digit month
		{"v2026.04.0-rc", false},           // missing rc number
		{"v2026.04.0-rc.", false},          // missing rc number
		{"2026.04.0-rc.1", false},          // missing v prefix
		{"v2026.04.0-rc.1-extra", false},   // trailing garbage
		{"prefix-v2026.04.0-rc.1", false},  // leading garbage
	}
	for _, c := range cases {
		got := prereleaseTagRE.MatchString(c.tag)
		if got != c.match {
			t.Errorf("prereleaseTagRE.MatchString(%q) = %v, want %v", c.tag, got, c.match)
		}
	}
}

func TestStableTagRE(t *testing.T) {
	cases := []struct {
		tag   string
		match bool
	}{
		{"v2026.04.0", true},
		{"v2026.04.12", true},
		{"v2026.04.0-rc.1", false},
		{"v2026.4.0", false},
		{"2026.04.0", false},
	}
	for _, c := range cases {
		got := stableTagRE.MatchString(c.tag)
		if got != c.match {
			t.Errorf("stableTagRE.MatchString(%q) = %v, want %v", c.tag, got, c.match)
		}
	}
}

// makeRepo initialises a throwaway git repo under t.TempDir() suitable for
// the tag-validation tests. Returns the repo root.
func makeRepo(t *testing.T) string {
	t.Helper()
	if _, err := exec.LookPath("git"); err != nil {
		t.Skip("git not on PATH")
	}
	dir := t.TempDir()

	run := func(args ...string) {
		t.Helper()
		cmd := exec.Command("git", args...)
		cmd.Dir = dir
		// Prevent the test from picking up the developer's signing config —
		// we want signature verification to FAIL on unsigned test commits
		// so ValidatePrereleaseTag's signature check is exercised.
		cmd.Env = append(os.Environ(),
			"GIT_AUTHOR_NAME=Test",
			"GIT_AUTHOR_EMAIL=test@example.invalid",
			"GIT_COMMITTER_NAME=Test",
			"GIT_COMMITTER_EMAIL=test@example.invalid",
		)
		if out, err := cmd.CombinedOutput(); err != nil {
			t.Fatalf("git %s: %v\n%s", strings.Join(args, " "), err, out)
		}
	}

	run("init", "-q")
	run("config", "commit.gpgsign", "false")
	run("config", "tag.gpgsign", "false")
	// A single migration to satisfy compareMigrationsForTag.
	if err := os.MkdirAll(filepath.Join(dir, "migrations"), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "migrations", "20260101000000_init.up.sql"), []byte("-- init\n"), 0644); err != nil {
		t.Fatal(err)
	}
	run("add", "migrations")
	run("commit", "-q", "-m", "init")
	return dir
}

// tagAnnotated creates an annotated tag with the given message at HEAD.
func tagAnnotated(t *testing.T, dir, name, msg string) {
	t.Helper()
	cmd := exec.Command("git", "tag", "-a", name, "-m", msg)
	cmd.Dir = dir
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("tag -a %s: %v\n%s", name, err, out)
	}
}

// tagLightweight creates a lightweight tag (no tag object) at HEAD.
func tagLightweight(t *testing.T, dir, name string) {
	t.Helper()
	cmd := exec.Command("git", "tag", name)
	cmd.Dir = dir
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("tag %s: %v\n%s", name, err, out)
	}
}

// Each case exercises one specific invariant in ValidatePrereleaseTag.
// The signature check always fails in these tests (commits are unsigned),
// so the error string that bubbles up distinguishes each case by the
// unique sub-check that fires first.
func TestValidatePrereleaseTag_RejectsBadShapes(t *testing.T) {
	dir := makeRepo(t)

	t.Run("name does not match pattern", func(t *testing.T) {
		err := ValidatePrereleaseTag(dir, "not-a-version")
		if err == nil || !strings.Contains(err.Error(), "does not match") {
			t.Fatalf("want 'does not match' error, got %v", err)
		}
	})

	t.Run("tag does not exist", func(t *testing.T) {
		err := ValidatePrereleaseTag(dir, "v2026.04.0-rc.1")
		if err == nil || !strings.Contains(err.Error(), "does not exist") {
			t.Fatalf("want 'does not exist' error, got %v", err)
		}
	})

	t.Run("lightweight tag rejected", func(t *testing.T) {
		tagLightweight(t, dir, "v2026.04.0-rc.1")
		err := ValidatePrereleaseTag(dir, "v2026.04.0-rc.1")
		if err == nil || !strings.Contains(err.Error(), "lightweight") {
			t.Fatalf("want 'lightweight' error, got %v", err)
		}
		// Clean up for subsequent subtests.
		_ = exec.Command("git", "-C", dir, "tag", "-d", "v2026.04.0-rc.1").Run()
	})

	t.Run("wrong tag subject rejected", func(t *testing.T) {
		tagAnnotated(t, dir, "v2026.04.0-rc.1", "wrong subject")
		err := ValidatePrereleaseTag(dir, "v2026.04.0-rc.1")
		if err == nil || !strings.Contains(err.Error(), "subject") {
			t.Fatalf("want 'subject' error, got %v", err)
		}
		_ = exec.Command("git", "-C", dir, "tag", "-d", "v2026.04.0-rc.1").Run()
	})

	t.Run("unsigned commit rejected", func(t *testing.T) {
		tagAnnotated(t, dir, "v2026.04.0-rc.1", "Pre-release v2026.04.0-rc.1")
		err := ValidatePrereleaseTag(dir, "v2026.04.0-rc.1")
		if err == nil || !strings.Contains(err.Error(), "signature") {
			t.Fatalf("want 'signature' error on unsigned commit, got %v", err)
		}
		_ = exec.Command("git", "-C", dir, "tag", "-d", "v2026.04.0-rc.1").Run()
	})
}

func TestValidateStableTag_NameRegex(t *testing.T) {
	dir := makeRepo(t)
	// Shape-only: stable name regex rejects RC-style tags before anything else.
	if err := ValidateStableTag(dir, "v2026.04.0-rc.1"); err == nil || !strings.Contains(err.Error(), "does not match") {
		t.Fatalf("want 'does not match' for rc tag passed to ValidateStableTag, got %v", err)
	}
}

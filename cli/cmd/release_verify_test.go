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

// TestFindLatestStableTagBeforePrefix covers the helper that closes the
// year-month-rollover gap in ValidatePrereleaseTag (task #124 Part B).
// The helper finds the latest stable tag whose (year, month) is
// strictly less than the given prefix's (year, month) — used as the
// migration-immutability predecessor for rc.1 of patch == 0 in a
// brand-new year-month series.
func TestFindLatestStableTagBeforePrefix(t *testing.T) {
	dir := makeRepo(t)

	t.Run("empty repo returns empty string", func(t *testing.T) {
		got, err := findLatestStableTagBeforePrefix(dir, "v2026.05")
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if got != "" {
			t.Errorf("empty repo: got %q, want \"\"", got)
		}
	})

	// Build a tag layout exercising the comparison shapes.
	for _, tag := range []string{
		"v2025.12.4",      // prior year-month, mid-patch
		"v2026.01.0",      // prior year-month, patch 0
		"v2026.04.0",      // prior year-month (closer), patch 0
		"v2026.04.5",      // prior year-month (closer), higher patch — should win for v2026.05
		"v2026.05.0",      // same year-month — must be excluded by strict-less rule
		"v2026.04.0-rc.1", // RC tag — must be excluded (only stable shapes count)
	} {
		tagAnnotated(t, dir, tag, "Release "+tag) // subject is irrelevant to the helper
	}

	t.Run("picks closest year-month, highest patch", func(t *testing.T) {
		got, err := findLatestStableTagBeforePrefix(dir, "v2026.05")
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if got != "v2026.04.5" {
			t.Errorf("got %q, want v2026.04.5", got)
		}
	})

	t.Run("excludes same year-month (strict less than)", func(t *testing.T) {
		// For prefix v2026.04, v2026.04.5 is NOT strictly less; should
		// return the next-closest prior month.
		got, err := findLatestStableTagBeforePrefix(dir, "v2026.04")
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if got != "v2026.01.0" {
			t.Errorf("got %q, want v2026.01.0", got)
		}
	})

	t.Run("returns empty when no qualifying prior stable", func(t *testing.T) {
		got, err := findLatestStableTagBeforePrefix(dir, "v2025.01")
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if got != "" {
			t.Errorf("v2025.01 prefix: got %q, want \"\"", got)
		}
	})

	t.Run("rejects malformed prefix", func(t *testing.T) {
		_, err := findLatestStableTagBeforePrefix(dir, "v2026.5") // 1-digit month
		if err == nil {
			t.Errorf("want error for malformed prefix, got nil")
		}
	})
}

// TestPickPrereleasePredecessor covers the unified predecessor-finding
// helper used by ValidatePrereleaseTag and releasePrereleaseCmd.RunE.
// Three branches: prior-RC-in-patch, prior-stable-patch, and cross-
// year-month (the case Part B fixes).
func TestPickPrereleasePredecessor(t *testing.T) {
	dir := makeRepo(t)
	for _, tag := range []string{
		"v2026.04.5",      // last April stable (cross-year-month predecessor target)
		"v2026.05.0-rc.1", // first May RC
		"v2026.05.0-rc.2", // second May RC
		"v2026.05.0",      // May stable patch 0 (predecessor for patch 1)
	} {
		tagAnnotated(t, dir, tag, "Release "+tag)
	}

	t.Run("rc.N where N>1 picks previous RC in same patch", func(t *testing.T) {
		got, err := pickPrereleasePredecessor(dir, "v2026.05", 0, []int{1, 2})
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if got != "v2026.05.0-rc.2" {
			t.Errorf("got %q, want v2026.05.0-rc.2", got)
		}
	})

	t.Run("rc.1 where patch>0 picks previous stable patch", func(t *testing.T) {
		got, err := pickPrereleasePredecessor(dir, "v2026.05", 1, nil)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if got != "v2026.05.0" {
			t.Errorf("got %q, want v2026.05.0", got)
		}
	})

	t.Run("rc.1 where patch==0 picks latest stable in prior year-month", func(t *testing.T) {
		got, err := pickPrereleasePredecessor(dir, "v2026.06", 0, nil)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		// v2026.05.0 is the latest stable strictly less than v2026.06.
		if got != "v2026.05.0" {
			t.Errorf("got %q, want v2026.05.0", got)
		}
	})

	t.Run("rc.1 where patch==0 with no prior stable returns empty", func(t *testing.T) {
		// Empty repo: assert the base case (first-release-ever).
		emptyDir := makeRepo(t)
		got, err := pickPrereleasePredecessor(emptyDir, "v2026.01", 0, nil)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if got != "" {
			t.Errorf("got %q, want \"\"", got)
		}
	})
}

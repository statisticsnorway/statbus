package release

import (
	"os"
	"os/exec"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/testgit"
)

// makeTagRepo initialises a throwaway git repo under t.TempDir() suitable for
// the tag-predecessor tests below. Returns the repo root.
//
// Moved from cli/cmd/release_verify_test.go's makeRepo (STATBUS-329) —
// renamed to avoid colliding with this package's own initGitRepo
// (immutability_test.go), which returns a different shape.
func makeTagRepo(t *testing.T) string {
	t.Helper()
	if _, err := exec.LookPath("git"); err != nil {
		t.Skip("git not on PATH")
	}
	dir := t.TempDir()

	run := func(args ...string) {
		t.Helper()
		cmd := exec.Command("git", testgit.Args(args...)...)
		cmd.Dir = dir
		cmd.Env = testgit.Env()
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
	run("config", "user.name", "Test")
	run("config", "user.email", "test@example.invalid")
	run("config", "commit.gpgsign", "false")
	run("config", "tag.gpgsign", "false")
	if err := os.MkdirAll(dir+"/migrations", 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(dir+"/migrations/20260101000000_init.up.sql", []byte("-- init\n"), 0644); err != nil {
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

// TestFindLatestStableTagBeforePrefix covers the helper that closes the
// year-month-rollover gap in ValidatePrereleaseTag (task #124 Part B).
// The helper finds the latest stable tag whose (year, month) is
// strictly less than the given prefix's (year, month) — used as the
// migration-immutability predecessor for rc.1 of patch == 0 in a
// brand-new year-month series.
//
// Moved from cli/cmd/release_verify_test.go (STATBUS-329) alongside
// FindLatestStableTagBeforePrefix itself.
func TestFindLatestStableTagBeforePrefix(t *testing.T) {
	dir := makeTagRepo(t)

	t.Run("empty repo returns empty string", func(t *testing.T) {
		got, err := FindLatestStableTagBeforePrefix(dir, "v2026.05")
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
		got, err := FindLatestStableTagBeforePrefix(dir, "v2026.05")
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
		got, err := FindLatestStableTagBeforePrefix(dir, "v2026.04")
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if got != "v2026.01.0" {
			t.Errorf("got %q, want v2026.01.0", got)
		}
	})

	t.Run("returns empty when no qualifying prior stable", func(t *testing.T) {
		got, err := FindLatestStableTagBeforePrefix(dir, "v2025.01")
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if got != "" {
			t.Errorf("v2025.01 prefix: got %q, want \"\"", got)
		}
	})

	t.Run("rejects malformed prefix", func(t *testing.T) {
		_, err := FindLatestStableTagBeforePrefix(dir, "v2026.5") // 1-digit month
		if err == nil {
			t.Errorf("want error for malformed prefix, got nil")
		}
	})
}

// TestPickPrereleasePredecessor covers the unified predecessor-finding
// helper used by ValidatePrereleaseTag and releasePrereleaseCmd.RunE.
// Three branches: prior-RC-in-patch, prior-stable-patch, and cross-
// year-month (the case Part B fixes).
//
// Moved from cli/cmd/release_verify_test.go (STATBUS-329) alongside
// PickPrereleasePredecessor itself.
func TestPickPrereleasePredecessor(t *testing.T) {
	dir := makeTagRepo(t)
	for _, tag := range []string{
		"v2026.04.5",       // last April stable (cross-year-month predecessor target)
		"v2026.05.0-rc.01", // first May RC — canonical zero-padded form (task #130 Part C)
		"v2026.05.0-rc.02", // second May RC
		"v2026.05.0",       // May stable patch 0 (predecessor for patch 1)
	} {
		tagAnnotated(t, dir, tag, "Release "+tag)
	}

	t.Run("rc.N where N>1 picks previous RC in same patch (zero-padded)", func(t *testing.T) {
		got, err := PickPrereleasePredecessor(dir, "v2026.05", 0, []int{1, 2})
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		// MUST return the zero-padded form to match the canonical tag
		// naming used by releasePrereleaseCmd. Regression guard for
		// the task #130 Part C bug: prior code returned "v2026.05.0-rc.2"
		// (unpadded), TagExistsLocally returned false, and the
		// immutability check was silently skipped.
		if got != "v2026.05.0-rc.02" {
			t.Errorf("got %q, want v2026.05.0-rc.02", got)
		}
	})

	t.Run("rc.1 where patch>0 picks previous stable patch", func(t *testing.T) {
		got, err := PickPrereleasePredecessor(dir, "v2026.05", 1, nil)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if got != "v2026.05.0" {
			t.Errorf("got %q, want v2026.05.0", got)
		}
	})

	t.Run("rc.1 where patch==0 picks latest stable in prior year-month", func(t *testing.T) {
		got, err := PickPrereleasePredecessor(dir, "v2026.06", 0, nil)
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
		emptyDir := makeTagRepo(t)
		got, err := PickPrereleasePredecessor(emptyDir, "v2026.01", 0, nil)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if got != "" {
			t.Errorf("got %q, want \"\"", got)
		}
	})
}

// TestTagExistsLocally is new (STATBUS-329) — the moved helper had no direct
// unit test before (only exercised transitively through the tests above).
func TestTagExistsLocally(t *testing.T) {
	dir := makeTagRepo(t)
	if TagExistsLocally(dir, "v2026.99.0") {
		t.Error("nonexistent tag reported as existing")
	}
	tagAnnotated(t, dir, "v2026.99.0", "Release v2026.99.0")
	if !TagExistsLocally(dir, "v2026.99.0") {
		t.Error("just-created tag reported as not existing")
	}
}

// TestCurrentImmutabilityBaselineTag_NoTags covers the very-first-release
// base case: an empty repo (no release tags at all) must resolve to "" with
// no error — the same "nothing to check" state checkImmutabilityGate treats
// as an automatic pass. The date-dependent branches (which year-month is
// "current") are exercised indirectly via TestPickPrereleasePredecessor and
// TestFindLatestStableTagBeforePrefix above; this test only pins the
// zero-tags edge case, which is stable regardless of what "today" is.
func TestCurrentImmutabilityBaselineTag_NoTags(t *testing.T) {
	dir := makeTagRepo(t)
	got, err := CurrentImmutabilityBaselineTag(dir)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got != "" {
		t.Errorf("empty repo: got %q, want \"\"", got)
	}
}

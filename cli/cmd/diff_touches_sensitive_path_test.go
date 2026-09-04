package cmd

// STATBUS-199 D2 unit for diffTouchesSensitivePath — the gate-side walk's
// per-candidate sensitivity check (release.go's checkUpgradeArcHarnessGate).
// A real git fixture is required: the function shells out to `git diff
// --name-only fromRef..toRef`, so this can't be pinned by string-scanning
// the source the way the toolchain-advice tests do.

import (
	"github.com/statisticsnorway/statbus/cli/internal/release"
	"github.com/statisticsnorway/statbus/cli/internal/testgit"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func runGitInCmd(t *testing.T, dir string, args ...string) string {
	t.Helper()
	cmd := exec.Command("git", testgit.Args(args...)...)
	cmd.Dir = dir
	cmd.Env = testgit.Env()
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("git %s failed: %v\n%s", strings.Join(args, " "), err, out)
	}
	return strings.TrimSpace(string(out))
}

// writeAndCommit writes each path (repo-relative) with placeholder
// content and commits all of them in one commit.
func writeAndCommit(t *testing.T, dir, message string, paths ...string) {
	t.Helper()
	for _, p := range paths {
		full := filepath.Join(dir, p)
		if err := os.MkdirAll(filepath.Dir(full), 0755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(full, []byte("placeholder\n"), 0644); err != nil {
			t.Fatal(err)
		}
	}
	runGitInCmd(t, dir, "add", ".")
	runGitInCmd(t, dir, "commit", "-q", "-m", message)
}

// TestDiffTouchesSensitivePath pins the walk's per-candidate check: it
// must report exactly which CHANGED files matched the sensitivity list
// (not the whole changed-file list, and not the list entries themselves),
// and its matching rule is documented substring containment — deliberately
// over-inclusive per ops/release/upgrade-sensitive-paths.txt's own header
// comment, not a strict path-prefix check.
func TestDiffTouchesSensitivePath(t *testing.T) {
	t.Run("touched: a sensitive file changed alongside an unrelated one", func(t *testing.T) {
		dir := t.TempDir()
		runGitInCmd(t, dir, "init", "-q")
		writeAndCommit(t, dir, "base", "doc/readme.md")
		base := runGitInCmd(t, dir, "rev-parse", "HEAD")
		writeAndCommit(t, dir, "advance", "cli/cmd/release.go", "doc/other.md")

		touched, matched, err := release.DiffTouchesSensitivePath(dir, base, "HEAD", []string{"cli/", "postgres/"})
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if !touched {
			t.Fatal("want touched=true (cli/cmd/release.go changed)")
		}
		want := []string{"cli/cmd/release.go"}
		if !equalMatchedFiles(matched, want) {
			t.Errorf("matchedFiles: got %v, want %v (doc/other.md must NOT appear — it isn't sensitive)", matched, want)
		}
	})

	t.Run("not touched: only non-sensitive files changed", func(t *testing.T) {
		dir := t.TempDir()
		runGitInCmd(t, dir, "init", "-q")
		writeAndCommit(t, dir, "base", "doc/readme.md")
		base := runGitInCmd(t, dir, "rev-parse", "HEAD")
		writeAndCommit(t, dir, "advance", "doc/other.md", "app/src/foo.tsx")

		touched, matched, err := release.DiffTouchesSensitivePath(dir, base, "HEAD", []string{"cli/", "postgres/", "migrations/"})
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if touched {
			t.Errorf("want touched=false, got true with matched=%v", matched)
		}
		if len(matched) != 0 {
			t.Errorf("want no matched files, got %v", matched)
		}
	})

	t.Run("substring containment is deliberately over-inclusive, not a strict path prefix", func(t *testing.T) {
		dir := t.TempDir()
		runGitInCmd(t, dir, "init", "-q")
		writeAndCommit(t, dir, "base", "doc/readme.md")
		base := runGitInCmd(t, dir, "rev-parse", "HEAD")
		// "not-ops/file.txt" is NOT under ops/ as a real top-level directory
		// (it's under "not-ops/"), but it CONTAINS the substring "ops/" —
		// the sensitivity file's own header documents this as intentional
		// (a coincidental hit costs one extra full-suite run; a missed
		// genuine change costs an unproven promotion). Pin that the
		// function actually behaves this way, not a stricter
		// HasPrefix-per-path-segment check someone could "improve" it
		// into later and silently narrow the gate.
		writeAndCommit(t, dir, "advance", "not-ops/file.txt")

		touched, matched, err := release.DiffTouchesSensitivePath(dir, base, "HEAD", []string{"ops/"})
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if !touched {
			t.Fatal("want touched=true — substring containment must catch this, even though it's not a real ops/ path")
		}
		want := []string{"not-ops/file.txt"}
		if !equalMatchedFiles(matched, want) {
			t.Errorf("matchedFiles: got %v, want %v", matched, want)
		}
	})
}

// equalMatchedFiles compares diffTouchesSensitivePath's matchedFiles
// return against an expectation, order-sensitive (matches diff order,
// which is deterministic for these fixtures).
func equalMatchedFiles(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

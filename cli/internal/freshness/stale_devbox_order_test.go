package freshness

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// noGo simulates a machine with no Go toolchain on PATH — exec.LookPath
// itself can't be faked without touching the real PATH, so isStale takes
// lookPath as a seam (see devToolchain's doc comment).
func noGo(string) (string, error) { return "", errors.New("not found") }

// hasGo simulates a machine with a Go toolchain on PATH.
func hasGo(string) (string, error) { return "/usr/bin/go", nil }

// TestIsStale_DevBoxOrdering pins STATBUS-203 AC#1: a Go toolchain on
// PATH (regardless of dev.sh) leads the remedy with ./dev.sh build-sb,
// mentioning ./sb install second.
func TestIsStale_DevBoxOrdering(t *testing.T) {
	dir, oldHead := setupGitRepoWithCli(t)
	advanceCliCommit(t, dir)

	got := isStale(dir, oldHead, hasGo)
	if got == "" {
		t.Fatal("committed drift: got empty, want diagnostic")
	}
	devIdx := strings.Index(got, "./dev.sh build-sb")
	installIdx := strings.Index(got, "./sb install")
	if devIdx < 0 {
		t.Fatalf("dev-box message missing ./dev.sh build-sb: %q", got)
	}
	if installIdx < 0 {
		t.Fatalf("dev-box message missing ./sb install (must still mention it, second): %q", got)
	}
	if devIdx > installIdx {
		t.Errorf("dev-box ordering wrong: ./dev.sh build-sb must lead, ./sb install must follow; got %q", got)
	}
}

// TestIsStale_OperatorBoxOrdering pins STATBUS-203's unchanged default: no
// Go toolchain on PATH and no dev.sh in projDir leads with the
// toolchain-free ./sb install, mentioning the dev rebuild paths second
// (STATBUS-085's original ordering, preserved for this case).
func TestIsStale_OperatorBoxOrdering(t *testing.T) {
	dir, oldHead := setupGitRepoWithCli(t)
	advanceCliCommit(t, dir)
	// setupGitRepoWithCli's temp dir has no dev.sh — confirm that
	// invariant so this test fails loudly if the fixture ever changes,
	// rather than silently passing for the wrong reason.
	if _, err := os.Stat(filepath.Join(dir, "dev.sh")); err == nil {
		t.Fatal("test fixture unexpectedly has dev.sh — operator-box case is no longer isolated")
	}

	got := isStale(dir, oldHead, noGo)
	if got == "" {
		t.Fatal("committed drift: got empty, want diagnostic")
	}
	installIdx := strings.Index(got, "./sb install")
	devIdx := strings.Index(got, "./dev.sh build-sb")
	if installIdx < 0 {
		t.Fatalf("operator-box message missing ./sb install: %q", got)
	}
	if devIdx < 0 {
		t.Fatalf("operator-box message missing the dev fallback mention: %q", got)
	}
	if installIdx > devIdx {
		t.Errorf("operator-box ordering wrong: ./sb install must lead, ./dev.sh build-sb must follow; got %q", got)
	}
}

// TestIsStale_DevBoxOrdering_DevShSignal pins the OTHER detection signal
// (comment #6-style pluggable-seam discipline: both signals independently
// tested): dev.sh present in projDir, even with no Go toolchain on PATH,
// is enough to trigger the dev-box ordering.
func TestIsStale_DevBoxOrdering_DevShSignal(t *testing.T) {
	dir, oldHead := setupGitRepoWithCli(t)
	if err := os.WriteFile(filepath.Join(dir, "dev.sh"), []byte("#!/bin/sh\n"), 0755); err != nil {
		t.Fatal(err)
	}
	advanceCliCommit(t, dir)

	got := isStale(dir, oldHead, noGo)
	if got == "" {
		t.Fatal("committed drift: got empty, want diagnostic")
	}
	devIdx := strings.Index(got, "./dev.sh build-sb")
	installIdx := strings.Index(got, "./sb install")
	if devIdx < 0 || installIdx < 0 || devIdx > installIdx {
		t.Errorf("dev.sh-present-only signal must still lead with ./dev.sh build-sb; got %q", got)
	}
}

// advanceCliCommit adds a second commit that touches cli/, on top of
// setupGitRepoWithCli's initial commit — the same shape TestIsStale_
// CommittedDrift in check_test.go uses to force committed drift.
func advanceCliCommit(t *testing.T, dir string) {
	t.Helper()
	cliFile := filepath.Join(dir, "cli", "main.go")
	if err := os.WriteFile(cliFile, []byte("package main\n// later\n"), 0644); err != nil {
		t.Fatal(err)
	}
	runGitIn(t, dir, "add", "cli/main.go")
	runGitIn(t, dir, "commit", "-q", "-m", "advance cli")
}

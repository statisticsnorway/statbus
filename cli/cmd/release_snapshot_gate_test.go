package cmd

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// TestCheckAndRefreshSnapshot_Regen_Stale verifies the core #47 contract:
// when checkAndRefreshSnapshot runs against a stale .db-snapshot/snapshot.json,
// it invokes snapshotCreator (the regen hook), and the post-regen snapshot.json
// is fresh. This is a hermetic test — no docker, no pg_dump — thanks to the
// snapshotCreator injection point.
//
// The test's "stale" scenario is commit_sha mismatch: snapshot.json pins
// commit_sha=stale-sha but HEAD returns a different SHA. Mock regen writes
// snapshot.json with commit_sha=HEAD. Assertion: mock was called exactly once
// and the post-regen fresh-check passes.
func TestCheckAndRefreshSnapshot_Regen_Stale(t *testing.T) {
	projDir := setupProjDirWithGit(t)
	writeStaleSnapshot(t, projDir, "stale-sha")

	calls := injectMockSnapshotCreator(t, projDir)

	if ok := checkAndRefreshSnapshot(projDir); !ok {
		t.Fatalf("checkAndRefreshSnapshot returned false for a recoverable stale snapshot")
	}
	if *calls != 1 {
		t.Fatalf("snapshotCreator invoked %d times, want 1", *calls)
	}

	// Post-regen snapshot.json should match HEAD
	gotCommit := readSnapshotCommitSHA(t, projDir)
	wantCommit := gitRevParseHEAD(t, projDir)
	if gotCommit != wantCommit {
		t.Fatalf("post-regen snapshot commit_sha = %s, want %s", gotCommit, wantCommit)
	}
}

// TestCheckAndRefreshSnapshot_FreshNoop verifies the no-op path: when
// snapshot.json already matches HEAD, checkAndRefreshSnapshot returns true
// WITHOUT invoking snapshotCreator. The release fast-path stays fast.
func TestCheckAndRefreshSnapshot_FreshNoop(t *testing.T) {
	projDir := setupProjDirWithGit(t)
	writeFreshSnapshot(t, projDir, gitRevParseHEAD(t, projDir))

	calls := injectMockSnapshotCreator(t, projDir)

	if ok := checkAndRefreshSnapshot(projDir); !ok {
		t.Fatalf("checkAndRefreshSnapshot returned false for a fresh snapshot")
	}
	if *calls != 0 {
		t.Fatalf("snapshotCreator invoked %d times on fresh snapshot, want 0", *calls)
	}
}

// TestCheckAndRefreshSnapshot_RegenFailsHardFails verifies the error path:
// when snapshotCreator returns an error, checkAndRefreshSnapshot returns false
// so the release preflight refuses to tag.
func TestCheckAndRefreshSnapshot_RegenFailsHardFails(t *testing.T) {
	projDir := setupProjDirWithGit(t)
	writeStaleSnapshot(t, projDir, "stale-sha")

	orig := snapshotCreator
	snapshotCreator = func(string) error { return fmt.Errorf("simulated pg_dump failure") }
	t.Cleanup(func() { snapshotCreator = orig })

	if ok := checkAndRefreshSnapshot(projDir); ok {
		t.Fatalf("checkAndRefreshSnapshot returned true despite regen failure")
	}
}

// TestCheckAndRefreshSnapshot_RegenStillStaleHardFails verifies the double-
// stale path: regen succeeds but the resulting snapshot.json STILL doesn't
// match HEAD (corrupt/buggy regen). Preflight must refuse to tag rather
// than loop forever.
func TestCheckAndRefreshSnapshot_RegenStillStaleHardFails(t *testing.T) {
	projDir := setupProjDirWithGit(t)
	writeStaleSnapshot(t, projDir, "stale-sha")

	// Mock regen that writes ANOTHER stale snapshot (e.g. tool bug).
	orig := snapshotCreator
	snapshotCreator = func(pd string) error {
		writeStaleSnapshot(t, pd, "still-not-head")
		return nil
	}
	t.Cleanup(func() { snapshotCreator = orig })

	if ok := checkAndRefreshSnapshot(projDir); ok {
		t.Fatalf("checkAndRefreshSnapshot returned true despite still-stale snapshot after regen")
	}
}

// ─── helpers ─────────────────────────────────────────────────────────────

// setupProjDirWithGit creates a temporary project directory with a
// git-initialised tree containing .db-snapshot/ and migrations/ directories.
// Registers the tmpdir's HEAD SHA by making an empty commit so
// `git rev-parse HEAD` returns a concrete value.
func setupProjDirWithGit(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()

	runGit := func(args ...string) {
		cmd := exec.Command("git", args...)
		cmd.Dir = dir
		// Set explicit config so git init doesn't fail on CI machines
		// lacking global user.name / user.email.
		cmd.Env = append(os.Environ(),
			"GIT_AUTHOR_NAME=test", "GIT_AUTHOR_EMAIL=test@example.com",
			"GIT_COMMITTER_NAME=test", "GIT_COMMITTER_EMAIL=test@example.com",
		)
		if out, err := cmd.CombinedOutput(); err != nil {
			t.Fatalf("git %s failed: %v\n%s", strings.Join(args, " "), err, out)
		}
	}
	runGit("init", "-q")
	runGit("commit", "--allow-empty", "-q", "-m", "test-init")

	if err := os.MkdirAll(filepath.Join(dir, ".db-snapshot"), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(dir, "migrations"), 0755); err != nil {
		t.Fatal(err)
	}
	return dir
}

// writeStaleSnapshot writes a snapshot.json that pins to the given fake
// commit_sha. Guaranteed stale as long as commit_sha != real HEAD.
func writeStaleSnapshot(t *testing.T, projDir, fakeCommit string) {
	t.Helper()
	writeSnapshotJSON(t, projDir, fakeCommit)
}

// writeFreshSnapshot writes a snapshot.json with commit_sha == real HEAD.
func writeFreshSnapshot(t *testing.T, projDir, realCommit string) {
	t.Helper()
	writeSnapshotJSON(t, projDir, realCommit)
}

func writeSnapshotJSON(t *testing.T, projDir, commitSHA string) {
	t.Helper()
	meta := snapshotMeta{
		MigrationVersion: "00000000000000",
		CommitSHA:        commitSHA,
		Tags:             "",
		CreatedAt:        "2026-04-24T00:00:00Z",
	}
	b, err := json.MarshalIndent(meta, "", "  ")
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(projDir, ".db-snapshot", "snapshot.json"), b, 0644); err != nil {
		t.Fatal(err)
	}
}

// injectMockSnapshotCreator swaps snapshotCreator for a mock that writes
// a fresh (HEAD-matching) snapshot.json. Returns a pointer to a call counter.
// Cleanup restores the original creator.
func injectMockSnapshotCreator(t *testing.T, projDir string) *int {
	t.Helper()
	var calls int
	orig := snapshotCreator
	snapshotCreator = func(pd string) error {
		calls++
		head := gitRevParseHEAD(t, pd)
		writeFreshSnapshot(t, pd, head)
		return nil
	}
	t.Cleanup(func() { snapshotCreator = orig })
	return &calls
}

func gitRevParseHEAD(t *testing.T, projDir string) string {
	t.Helper()
	cmd := exec.Command("git", "rev-parse", "HEAD")
	cmd.Dir = projDir
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("git rev-parse HEAD: %v\n%s", err, out)
	}
	return strings.TrimSpace(string(out))
}

func readSnapshotCommitSHA(t *testing.T, projDir string) string {
	t.Helper()
	b, err := os.ReadFile(filepath.Join(projDir, ".db-snapshot", "snapshot.json"))
	if err != nil {
		t.Fatalf("read snapshot.json: %v", err)
	}
	var meta snapshotMeta
	if err := json.Unmarshal(b, &meta); err != nil {
		t.Fatalf("unmarshal snapshot.json: %v", err)
	}
	return meta.CommitSHA
}

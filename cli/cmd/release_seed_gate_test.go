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

// TestCheckAndRefreshSeed_Regen_Stale verifies the core #47 contract:
// when checkAndRefreshSeed runs against a stale .db-seed/seed.json,
// it invokes seedCreator (the regen hook), and the post-regen seed.json
// is fresh. This is a hermetic test — no docker, no pg_dump — thanks to the
// seedCreator injection point.
//
// The test's "stale" scenario is commit_sha mismatch: seed.json pins
// commit_sha=stale-sha but HEAD returns a different SHA. Mock regen writes
// seed.json with commit_sha=HEAD. Assertion: mock was called exactly once
// and the post-regen fresh-check passes.
func TestCheckAndRefreshSeed_Regen_Stale(t *testing.T) {
	projDir := setupProjDirWithGit(t)
	writeStaleSeed(t, projDir, "stale-sha")

	calls := injectMockSeedCreator(t, projDir)

	if ok := checkAndRefreshSeed(projDir); !ok {
		t.Fatalf("checkAndRefreshSeed returned false for a recoverable stale seed")
	}
	if *calls != 1 {
		t.Fatalf("seedCreator invoked %d times, want 1", *calls)
	}

	// Post-regen seed.json should match HEAD
	gotCommit := readSeedCommitSHA(t, projDir)
	wantCommit := gitRevParseHEAD(t, projDir)
	if gotCommit != wantCommit {
		t.Fatalf("post-regen seed commit_sha = %s, want %s", gotCommit, wantCommit)
	}
}

// TestCheckAndRefreshSeed_FreshNoop verifies the no-op path: when
// seed.json already matches HEAD, checkAndRefreshSeed returns true
// WITHOUT invoking seedCreator. The release fast-path stays fast.
func TestCheckAndRefreshSeed_FreshNoop(t *testing.T) {
	projDir := setupProjDirWithGit(t)
	writeFreshSeed(t, projDir, gitRevParseHEAD(t, projDir))

	calls := injectMockSeedCreator(t, projDir)

	if ok := checkAndRefreshSeed(projDir); !ok {
		t.Fatalf("checkAndRefreshSeed returned false for a fresh seed")
	}
	if *calls != 0 {
		t.Fatalf("seedCreator invoked %d times on fresh seed, want 0", *calls)
	}
}

// TestCheckAndRefreshSeed_RegenFailsHardFails verifies the error path:
// when seedCreator returns an error, checkAndRefreshSeed returns false
// so the release preflight refuses to tag.
func TestCheckAndRefreshSeed_RegenFailsHardFails(t *testing.T) {
	projDir := setupProjDirWithGit(t)
	writeStaleSeed(t, projDir, "stale-sha")

	orig := seedCreator
	seedCreator = func(string) error { return fmt.Errorf("simulated pg_dump failure") }
	t.Cleanup(func() { seedCreator = orig })

	if ok := checkAndRefreshSeed(projDir); ok {
		t.Fatalf("checkAndRefreshSeed returned true despite regen failure")
	}
}

// TestCheckAndRefreshSeed_RegenStillStaleHardFails verifies the double-
// stale path: regen succeeds but the resulting seed.json STILL doesn't
// match HEAD (corrupt/buggy regen). Preflight must refuse to tag rather
// than loop forever.
func TestCheckAndRefreshSeed_RegenStillStaleHardFails(t *testing.T) {
	projDir := setupProjDirWithGit(t)
	writeStaleSeed(t, projDir, "stale-sha")

	// Mock regen that writes ANOTHER stale seed (e.g. tool bug).
	orig := seedCreator
	seedCreator = func(pd string) error {
		writeStaleSeed(t, pd, "still-not-head")
		return nil
	}
	t.Cleanup(func() { seedCreator = orig })

	if ok := checkAndRefreshSeed(projDir); ok {
		t.Fatalf("checkAndRefreshSeed returned true despite still-stale seed after regen")
	}
}

// ─── helpers ─────────────────────────────────────────────────────────────

// setupProjDirWithGit creates a temporary project directory with a
// git-initialised tree containing .db-seed/ and migrations/ directories.
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

	if err := os.MkdirAll(filepath.Join(dir, ".db-seed"), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(dir, "migrations"), 0755); err != nil {
		t.Fatal(err)
	}
	return dir
}

// writeStaleSeed writes a seed.json that pins to the given fake
// commit_sha. Guaranteed stale as long as commit_sha != real HEAD.
func writeStaleSeed(t *testing.T, projDir, fakeCommit string) {
	t.Helper()
	writeSeedJSON(t, projDir, fakeCommit)
}

// writeFreshSeed writes a seed.json with commit_sha == real HEAD.
func writeFreshSeed(t *testing.T, projDir, realCommit string) {
	t.Helper()
	writeSeedJSON(t, projDir, realCommit)
}

func writeSeedJSON(t *testing.T, projDir, commitSHA string) {
	t.Helper()
	meta := seedMeta{
		MigrationVersion: "00000000000000",
		CommitSHA:        commitSHA,
		Tags:             "",
		CreatedAt:        "2026-04-24T00:00:00Z",
	}
	b, err := json.MarshalIndent(meta, "", "  ")
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(projDir, ".db-seed", "seed.json"), b, 0644); err != nil {
		t.Fatal(err)
	}
}

// injectMockSeedCreator swaps seedCreator for a mock that writes
// a fresh (HEAD-matching) seed.json. Returns a pointer to a call counter.
// Cleanup restores the original creator.
func injectMockSeedCreator(t *testing.T, projDir string) *int {
	t.Helper()
	var calls int
	orig := seedCreator
	seedCreator = func(pd string) error {
		calls++
		head := gitRevParseHEAD(t, pd)
		writeFreshSeed(t, pd, head)
		return nil
	}
	t.Cleanup(func() { seedCreator = orig })
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

func readSeedCommitSHA(t *testing.T, projDir string) string {
	t.Helper()
	b, err := os.ReadFile(filepath.Join(projDir, ".db-seed", "seed.json"))
	if err != nil {
		t.Fatalf("read seed.json: %v", err)
	}
	var meta seedMeta
	if err := json.Unmarshal(b, &meta); err != nil {
		t.Fatalf("unmarshal seed.json: %v", err)
	}
	return meta.CommitSHA
}

package cmd

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// TestCheckSeedGate_Stale_Refuses verifies the gate-only contract:
// when checkSeedGate runs against a stale .db-seed/seed.json, it
// returns false (refusing the release). The gate prints a Fix-line
// pointing the operator at ./dev.sh update-seed; it does not
// auto-run anything. That's the operator's job after seeing the
// guide — same shape as every other preflight gate.
func TestCheckSeedGate_Stale_Refuses(t *testing.T) {
	projDir := setupProjDirWithGit(t)
	writeStaleSeed(t, projDir, "stale-sha")

	if ok := checkSeedGate(projDir); ok {
		t.Fatalf("checkSeedGate returned true for a stale seed; expected refusal")
	}
}

// TestCheckSeedGate_FreshOK verifies the pass path: when seed.json
// commit_sha already matches HEAD, checkSeedGate returns true.
func TestCheckSeedGate_FreshOK(t *testing.T) {
	projDir := setupProjDirWithGit(t)
	writeFreshSeed(t, projDir, gitRevParseHEAD(t, projDir))

	if ok := checkSeedGate(projDir); !ok {
		t.Fatalf("checkSeedGate returned false for a fresh seed; expected pass")
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

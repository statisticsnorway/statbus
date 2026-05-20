package cmd

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// Task #130 Part A rewrote checkSeedGate to compare migration_version
// against the max on-disk migration timestamp instead of commit_sha
// (the prior shape invalidated the seed on every commit, including
// pure-code commits that didn't touch migrations). These tests cover
// the four post-#130 outcomes: fresh, behind, ahead, missing.
//
// commit_sha is intentionally NOT tested as a freshness gate — it's
// kept in seed.json as a tracking field for operator visibility but
// no longer participates in the gate's pass/fail decision.

// TestCheckSeedGate_FreshOK verifies the pass path: seed.json's
// migration_version matches the max on-disk migration timestamp.
func TestCheckSeedGate_FreshOK(t *testing.T) {
	projDir := setupProjDirWithGit(t)
	writeMigration(t, projDir, "20260101000000_init.up.sql")
	writeSeedJSON(t, projDir, seedMeta{
		MigrationVersion: "20260101000000",
		CommitSHA:        "anything-not-consulted",
	})

	if ok := checkSeedGate(projDir); !ok {
		t.Fatalf("checkSeedGate returned false for a fresh seed; expected pass")
	}
}

// TestCheckSeedGate_FreshOK_IgnoresCommitSHA verifies that the gate
// passes even when commit_sha differs from HEAD — Part A explicitly
// drops commit_sha from the gating logic. Regression guard against
// any reintroduction of the prior commit_sha-coupling.
func TestCheckSeedGate_FreshOK_IgnoresCommitSHA(t *testing.T) {
	projDir := setupProjDirWithGit(t)
	writeMigration(t, projDir, "20260101000000_init.up.sql")
	writeSeedJSON(t, projDir, seedMeta{
		MigrationVersion: "20260101000000",
		CommitSHA:        "deadbeef-not-head",
	})

	if ok := checkSeedGate(projDir); !ok {
		t.Fatalf("checkSeedGate refused a seed whose migration_version matches HEAD but commit_sha doesn't — Part A explicitly drops commit_sha from the gating logic")
	}
}

// TestCheckSeedGate_Behind_Refuses verifies that a seed whose
// migration_version is older than the latest on-disk migration is
// refused with the "behind" diagnostic and a Fix-line pointing at
// ./dev.sh update-seed.
func TestCheckSeedGate_Behind_Refuses(t *testing.T) {
	projDir := setupProjDirWithGit(t)
	writeMigration(t, projDir, "20260101000000_init.up.sql")
	writeMigration(t, projDir, "20260102000000_later.up.sql")
	writeSeedJSON(t, projDir, seedMeta{
		MigrationVersion: "20260101000000",
		CommitSHA:        "anything",
	})

	if ok := checkSeedGate(projDir); ok {
		t.Fatalf("checkSeedGate returned true for a behind-by-1 seed; expected refusal")
	}
}

// TestCheckSeedGate_Ahead_Refuses verifies the symmetric "ahead" case
// (Part A: seed migration_version > on-disk max). Operator is on a
// stale branch checkout; gate refuses with the appropriate Fix.
func TestCheckSeedGate_Ahead_Refuses(t *testing.T) {
	projDir := setupProjDirWithGit(t)
	writeMigration(t, projDir, "20260101000000_init.up.sql")
	writeSeedJSON(t, projDir, seedMeta{
		MigrationVersion: "20260201000000", // newer than on-disk max
		CommitSHA:        "anything",
	})

	if ok := checkSeedGate(projDir); ok {
		t.Fatalf("checkSeedGate returned true for a seed ahead of on-disk migrations; expected refusal")
	}
}

// TestCheckSeedGate_MissingJSON_Refuses verifies the missing case:
// no seed.json on disk → gate refuses with a missing-seed Fix.
func TestCheckSeedGate_MissingJSON_Refuses(t *testing.T) {
	projDir := setupProjDirWithGit(t)
	writeMigration(t, projDir, "20260101000000_init.up.sql")
	// No seed.json written.

	if ok := checkSeedGate(projDir); ok {
		t.Fatalf("checkSeedGate returned true when seed.json was absent; expected refusal")
	}
}

// TestCheckSeedGate_NoMigrations_Passes covers the legitimate edge
// case where on-disk migrations are empty (e.g., very first commit of
// a fresh project). Any seed should be considered fresh — there's
// nothing to be behind.
func TestCheckSeedGate_NoMigrations_Passes(t *testing.T) {
	projDir := setupProjDirWithGit(t)
	writeSeedJSON(t, projDir, seedMeta{
		MigrationVersion: "20260101000000",
		CommitSHA:        "anything",
	})
	// No migrations written.

	if ok := checkSeedGate(projDir); !ok {
		t.Fatalf("checkSeedGate returned false when no migrations exist on disk; expected pass (nothing to be behind)")
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

// writeSeedJSON writes a seed.json with the given metadata. Used by
// all the gate tests to set up the seed state under test.
func writeSeedJSON(t *testing.T, projDir string, meta seedMeta) {
	t.Helper()
	if meta.CreatedAt == "" {
		meta.CreatedAt = "2026-04-24T00:00:00Z"
	}
	b, err := json.MarshalIndent(meta, "", "  ")
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(projDir, ".db-seed", "seed.json"), b, 0644); err != nil {
		t.Fatal(err)
	}
}

// writeMigration creates an empty file with the given basename under
// migrations/, used to populate the on-disk migration set the gate
// compares against.
func writeMigration(t *testing.T, projDir, filename string) {
	t.Helper()
	if err := os.WriteFile(filepath.Join(projDir, "migrations", filename), []byte("-- "+filename+"\n"), 0644); err != nil {
		t.Fatal(err)
	}
}

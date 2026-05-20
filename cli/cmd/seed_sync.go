package cmd

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/spf13/cobra"
	"github.com/statisticsnorway/statbus/cli/internal/config"
	"github.com/statisticsnorway/statbus/cli/internal/migrate"
	"github.com/statisticsnorway/statbus/cli/internal/upgrade"
)

// `./sb db seed sync`
//
// Single operator-facing entrypoint for the seed lifecycle. Replaces
// the prior split between `./dev.sh update-seed` (run migrations + dump
// + push) and `./sb db seed create` (dump-only). Owns the full chain:
//
//  1. Acquire the EXCLUSIVE statbus_seed mutation lock so a parallel
//     `./sb assert-db-at-head` blocks during the rebuild window
//     (matches the lock contract `./dev.sh recreate-seed` follows).
//  2. `./sb migrate up --target seed` — bring statbus_seed to HEAD's
//     migration set. Idempotent: no-op when already at HEAD.
//  3. Compute the seed fingerprint:
//     (migration_version, sha256(migrations/post_restore.sql)).
//  4. If the fingerprint matches the existing seed.json's →
//     FAST PATH: skip pg_dump entirely, reuse seed.pg_dump on the
//     db-seed branch's existing tip, rewrite ONLY seed.json (new
//     commit_sha + created_at), commit + push db-seed, publish the
//     per-commit pin.
//     If the fingerprint differs (or seed.json absent) → FULL PATH:
//     CreateSeed (pg_dump + commit + push + pin).
//
// `./dev.sh update-seed` is a thin wrapper around this command; new
// operator habits should go through `./sb db seed sync` directly.

var seedSyncCmd = &cobra.Command{
	Use:   "sync",
	Short: "Bring statbus_seed to HEAD, publish seed.pg_dump + per-commit pin to origin",
	Long: `Single-call seed lifecycle. Ensures the local statbus_seed DB is at HEAD's
migration set, publishes seed.pg_dump + seed.json to the origin/db-seed branch,
and force-with-lease-pushes the per-commit pin branch seed/<commit_short>
that release.yaml reads at tag-push time.

Smart-skip: when neither migration_version nor sha256(post_restore.sql) has
changed since the last sync, the pg_dump is skipped — the existing dump bytes
on db-seed are reused, only seed.json is rewritten with the new commit_sha.
A pure-code commit re-runs sync in ~1-2s; a migration commit re-runs sync
in the full ~30s.

The pin branch seed/<commit_short> ALWAYS gets pushed (whether fast-path or
full-path), because release.yaml's "Fetch seed assets" step refuses to
publish unless seed.json.commit_sha == GITHUB_SHA.

Acquires the EXCLUSIVE statbus_seed mutation advisory lock for the whole
duration so concurrent readers (./sb types generate, ./dev.sh test fast)
block cleanly via their SHARED-lock acquisition instead of hitting
statbus_seed mid-rebuild.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		return runSeedSync(config.ProjectDir())
	},
}

func init() {
	seedCmd.AddCommand(seedSyncCmd)
}

// runSeedSync is the Cobra body, kept as a plain function so future
// callers (preflight hooks, ops scripts) can invoke it in-process.
func runSeedSync(projDir string) error {
	// EXCLUSIVE lock on the statbus_seed mutation key, held for the
	// full duration. Released via defer on the postgres-system-DB
	// connection (PG advisory locks are session-scoped).
	//
	// timeout=0 → block indefinitely. recreate-seed and seed-sync are
	// the only EXCLUSIVE holders; if another one is in flight we'd
	// rather wait for it than fail with a confusing timeout error.
	ctx := context.Background()
	lockConn, err := migrate.AcquireSeedLock(ctx, projDir, true /* exclusive */, 0, "./sb db seed sync")
	if err != nil {
		return fmt.Errorf("seed sync: %w", err)
	}
	defer lockConn.Close(ctx)

	// Bring the seed DB to HEAD. Mirrors `runMigrateUp` (cli/cmd/migrate.go)
	// — env-override pattern so migrate.Up targets POSTGRES_SEED_DB
	// rather than POSTGRES_APP_DB without permanently mutating the
	// process env (defer-restored). all=true, migrateTo=0 → up to HEAD.
	seedDB, err := migrate.ResolveTargetDB(projDir, "seed")
	if err != nil {
		return fmt.Errorf("resolve seed target DB: %w", err)
	}
	prevApp, hadApp := os.LookupEnv("POSTGRES_APP_DB")
	prevPG, hadPG := os.LookupEnv("PGDATABASE")
	os.Setenv("POSTGRES_APP_DB", seedDB)
	os.Setenv("PGDATABASE", seedDB)
	defer func() {
		if hadApp {
			os.Setenv("POSTGRES_APP_DB", prevApp)
		} else {
			os.Unsetenv("POSTGRES_APP_DB")
		}
		if hadPG {
			os.Setenv("PGDATABASE", prevPG)
		} else {
			os.Unsetenv("PGDATABASE")
		}
	}()
	if err := migrate.Up(projDir, 0, true, verbose); err != nil {
		return fmt.Errorf("migrate up --target seed: %w", err)
	}

	// Compute HEAD's seed fingerprint (the (migration_version, post_restore_sha)
	// tuple) and compare against what's recorded in .db-seed/seed.json.
	headFP, err := computeSeedFingerprint(projDir, seedDB)
	if err != nil {
		return fmt.Errorf("compute seed fingerprint: %w", err)
	}
	prevMeta := loadSeedMetaOrNil(projDir)

	if seedFingerprintMatches(prevMeta, headFP) {
		fmt.Printf("Seed unchanged (migration_version=%s post_restore_sha=%s) — fast-path republish\n",
			headFP.MigrationVersion, headFP.PostRestoreSHA[:8])
		return seedSyncFastPath(projDir, prevMeta, headFP)
	}

	// Full rebuild path. CreateSeed handles pg_dump + commit + push
	// db-seed + publish pin. We just delegate.
	if prevMeta == nil {
		fmt.Println("No prior seed metadata — full rebuild.")
	} else {
		fmt.Printf("Seed fingerprint changed:\n")
		fmt.Printf("  migration_version: %s → %s\n", prevMeta.MigrationVersion, headFP.MigrationVersion)
		fmt.Printf("  post_restore_sha:  %s → %s\n", shortOrEmpty(prevMeta.PostRestoreSHA), headFP.PostRestoreSHA[:12])
		fmt.Println("Full rebuild.")
	}
	return CreateSeed(projDir)
}

// seedFingerprint captures the content-deterministic state the seed
// reflects. Two fingerprints with equal fields produce bit-identical
// post-restore database states (modulo non-deterministic toast OIDs in
// the dump itself, which is why we DON'T hash the pg_dump bytes —
// migration_version + post_restore_sha is the principled identity).
type seedFingerprint struct {
	MigrationVersion string
	PostRestoreSHA   string
}

// computeSeedFingerprint queries the live statbus_seed DB for its max
// db.migration version and hashes migrations/post_restore.sql from disk.
// Called AFTER migrate.Up so the DB-side value reflects HEAD.
func computeSeedFingerprint(projDir, seedDB string) (seedFingerprint, error) {
	psqlPath, prefix, env, err := migrate.PsqlCommand(projDir)
	if err != nil {
		return seedFingerprint{}, fmt.Errorf("psql: %w", err)
	}
	args := append([]string(nil), prefix...)
	args = append(args, "-d", seedDB, "-t", "-A", "-c",
		"SELECT version FROM db.migration ORDER BY version DESC LIMIT 1")
	out, err := runWithEnv(psqlPath, args, projDir, env)
	if err != nil {
		return seedFingerprint{}, fmt.Errorf("query db.migration max: %w", err)
	}
	mv := strings.TrimSpace(out)
	if mv == "" {
		return seedFingerprint{}, fmt.Errorf("db.migration in %s is empty (no migrations applied?)", seedDB)
	}

	postSHA, err := postRestoreFileSHA(projDir)
	if err != nil {
		return seedFingerprint{}, err
	}
	return seedFingerprint{MigrationVersion: mv, PostRestoreSHA: postSHA}, nil
}

// loadSeedMetaOrNil reads .db-seed/seed.json. Returns nil (no error)
// when the file is missing or unreadable — callers treat that as
// "no fingerprint to compare against → full rebuild."
func loadSeedMetaOrNil(projDir string) *seedMeta {
	m, err := loadSeedMeta(projDir)
	if err != nil {
		return nil
	}
	return m
}

// seedFingerprintMatches reports whether the prior seed's fingerprint
// equals the current HEAD's. Empty PostRestoreSHA in prev (pre-#133
// seed.json) → no match, forces a full rebuild on first sync (the only
// safe migration — we can't tell whether the prior dump captured the
// current post_restore.sql).
func seedFingerprintMatches(prev *seedMeta, head seedFingerprint) bool {
	if prev == nil {
		return false
	}
	if prev.PostRestoreSHA == "" {
		return false
	}
	return prev.MigrationVersion == head.MigrationVersion &&
		prev.PostRestoreSHA == head.PostRestoreSHA
}

// seedSyncFastPath publishes a new commit on db-seed that REUSES the
// existing seed.pg_dump bytes (already on the branch's tip) but ships
// a fresh seed.json carrying the new commit_sha + created_at.
//
// Why a new commit and not just a re-pointed branch: release.yaml's
// "Fetch seed assets" step verifies seed.json.commit_sha == GITHUB_SHA
// (the release tag's target commit). The pin branch must therefore
// point at a tree whose seed.json names THIS project commit, which
// means a new commit on db-seed with an updated seed.json — even when
// the pg_dump bytes are byte-identical to the prior commit.
//
// Cost: skip pg_dump (~25-30s saved), still pay worktree-add ~200ms +
// git commit + push ~500ms-2s + pin-push ~50-100ms. Total ~1-3s vs the
// full path's ~30s.
func seedSyncFastPath(projDir string, prev *seedMeta, fp seedFingerprint) error {
	if prev == nil {
		// Defensive — caller (seedFingerprintMatches) should have
		// returned false here, routing through CreateSeed instead.
		return fmt.Errorf("fast path requires prior seedMeta")
	}

	// HEAD's project commit + tags pointing at it.
	commitOut, err := upgrade.RunCommandOutput(projDir, "git", "rev-parse", "HEAD")
	if err != nil {
		return fmt.Errorf("git rev-parse HEAD: %w", err)
	}
	commitSHA := strings.TrimSpace(commitOut)
	tagsOut, _ := upgrade.RunCommandOutput(projDir, "git", "tag", "--points-at", "HEAD")
	tags := strings.TrimSpace(tagsOut)

	// Construct the new meta. Preserve migration_version + post_restore_sha
	// from the fingerprint (which equals prev's by the matches() contract);
	// refresh the mutable fields.
	meta := seedMeta{
		MigrationVersion: fp.MigrationVersion,
		PostRestoreSHA:   fp.PostRestoreSHA,
		CommitSHA:        commitSHA,
		Tags:             tags,
		CreatedAt:        time.Now().UTC().Format(time.RFC3339),
	}
	metaJSON, err := json.MarshalIndent(meta, "", "  ")
	if err != nil {
		return fmt.Errorf("marshal seed.json: %w", err)
	}

	// Also update the local .db-seed/seed.json so subsequent local
	// invocations see the new fingerprint. (CreateSeed writes both
	// the worktree copy AND the local one; mirror that.)
	seedDir := filepath.Join(projDir, ".db-seed")
	if err := os.MkdirAll(seedDir, 0755); err != nil {
		return fmt.Errorf("create .db-seed: %w", err)
	}
	localJSON := filepath.Join(seedDir, "seed.json")
	if err := os.WriteFile(localJSON, metaJSON, 0644); err != nil {
		return fmt.Errorf("write local seed.json: %w", err)
	}

	// Sweep stale seed/<sha> branches BEFORE publishing the new one.
	// Matches the cleanup invocation in CreateSeed (release.go's
	// cleanupSeedBranches). preserveSHA = HEAD so the slot we're
	// about to write isn't swept.
	cleanupSeedBranches(projDir, commitSHA)

	// Worktree on db-seed. Its tree already contains seed.pg_dump
	// from the prior commit; we only overwrite seed.json.
	worktreePath, err := ensureSeedWorktree(projDir)
	if err != nil {
		return err
	}
	dst := filepath.Join(worktreePath, "seed.json")
	if err := os.WriteFile(dst, metaJSON, 0644); err != nil {
		return fmt.Errorf("write seed.json to worktree: %w", err)
	}

	if addOut, err := upgrade.RunCommandOutput(worktreePath, "git", "add", "seed.json"); err != nil {
		return fmt.Errorf("git add seed.json in worktree: %w\n  output: %s", err, strings.TrimSpace(addOut))
	}
	commitMsg := fmt.Sprintf("seed: republish at commit %s (unchanged: migration %s, post_restore %s)",
		commitSHA[:8], fp.MigrationVersion, fp.PostRestoreSHA[:8])
	// --allow-empty: pre-#133 seed.json without post_restore_sha is
	// effectively equivalent to a seed.json with the field — the
	// repeat-republish at the same project-commit shouldn't be a
	// hard error.
	if commitOut, err := upgrade.RunCommandOutput(worktreePath, "git", "commit", "--allow-empty", "-m", commitMsg); err != nil {
		return fmt.Errorf("git commit in worktree: %w\n  output: %s", err, strings.TrimSpace(commitOut))
	}
	if pushOut, err := upgrade.RunCommandOutput(worktreePath, "git", "push", "origin", "db-seed", "--force"); err != nil {
		return fmt.Errorf("git push --force db-seed: %w\n  output: %s", err, strings.TrimSpace(pushOut))
	}
	fmt.Printf("Seed republished (migration %s, commit %s) — fast path, no pg_dump\n",
		fp.MigrationVersion, commitSHA[:8])

	// Publish the per-commit pin pointing at the new commit on
	// db-seed (carries the inherited seed.pg_dump + fresh seed.json).
	return publishSeedPinBranch(worktreePath, commitSHA)
}

// runWithEnv is a small wrapper around exec.Cmd that mirrors how
// migrate.AssertDBAtHead invokes psql (custom Env + Dir). Kept inline
// rather than added to the migrate package because seed_sync.go is the
// only caller; if a second site appears it can move.
func runWithEnv(path string, args []string, dir string, env []string) (string, error) {
	cmd := exec.Command(path, args...)
	cmd.Dir = dir
	cmd.Env = env
	out, err := cmd.Output()
	return string(out), err
}

// shortOrEmpty returns a 12-char prefix, or "(none)" when s is empty.
// Used to format the fingerprint-change diagnostic when prev meta
// predates the post_restore_sha field.
func shortOrEmpty(s string) string {
	if s == "" {
		return "(none)"
	}
	if len(s) <= 12 {
		return s
	}
	return s[:12]
}

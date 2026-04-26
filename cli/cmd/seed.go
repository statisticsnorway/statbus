package cmd

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/spf13/cobra"
	"github.com/statisticsnorway/statbus/cli/internal/config"
	"github.com/statisticsnorway/statbus/cli/internal/upgrade"
)

// seedSHALen is the short-SHA length used in seed branch names
// (`seed/<sha8>`). Rc.63: aligned with the canonical commit_short
// length (8). 8 hex chars → ~1 in 2^16 birthday-collision risk at
// O(256) seeds, rising to ~1 in 2 at O(64k) — acceptable for the
// lifetime of the repo. Must match `${GITHUB_SHA:0:8}` in release.yaml.
const seedSHALen = 8

// seedMeta is the JSON structure stored in .db-seed/seed.json.
// It records which migration and commit the seed covers, so callers
// can decide whether the seed is fresh enough to use.
type seedMeta struct {
	MigrationVersion string `json:"migration_version"`
	CommitSHA        string `json:"commit_sha"`
	Tags             string `json:"tags"`
	CreatedAt        string `json:"created_at"`
}

var seedDatabase string

// ── seed command group ──────────────────────────────────────────────────────

var seedCmd = &cobra.Command{
	Use:   "seed",
	Short: "Manage database seeds for fast DB creation",
	Long: `Manage pg_dump seeds cached on the db-seed git branch.

A seed lets dev.sh skip running ~294 migrations and instead
pg_restore a single dump file (~2 seconds). The seed branch
is a CACHE — it's force-pushed on each update.

Subcommands:
  fetch     Download seed from origin/db-seed
  restore   Restore seed into a database
  create    Dump current DB and push to db-seed branch
  status    Compare seed version to latest migration`,
}

// ── seed fetch ──────────────────────────────────────────────────────────────

// seedFetchCmd downloads the cached DB seed from the db-seed git
// branch. The seed is a pg_dump that speeds up DB creation from ~294
// migrations to one pg_restore (~2 seconds). Auto-called by dev.sh on first run.
//
// Legacy-name fallback (R, rc.66 → rc.67 transition): if the modern
// branch `origin/db-seed` doesn't exist, fall back to the legacy
// `origin/db-snapshot` and emit a clear remediation. Once the
// origin-branch rename has been performed (operator runbook step,
// pre-merge of the seed feature), the legacy branch is gone and the
// fallback simply never fires. Slated for removal in the next RC
// after the seed feature merges.
var seedFetchCmd = &cobra.Command{
	Use:   "fetch",
	Short: "Fetch seed from origin/db-seed branch",
	RunE: func(cmd *cobra.Command, args []string) error {
		projDir := config.ProjectDir()
		seedDir := filepath.Join(projDir, ".db-seed")

		// Fetch the db-seed branch (shallow — we only need the tip).
		// Tolerate failure: the branch may not exist yet on the remote.
		usedLegacy := false
		_, err := upgrade.RunCommandOutput(projDir, "git", "fetch", "origin", "db-seed", "--depth=1", "--quiet")
		if err != nil {
			// Try the legacy name.
			_, legacyErr := upgrade.RunCommandOutput(projDir, "git", "fetch", "origin", "db-snapshot", "--depth=1", "--quiet")
			if legacyErr != nil {
				fmt.Println("No seed branch found on remote. Create one with: ./sb db seed create")
				return nil
			}
			usedLegacy = true
			fmt.Fprintln(os.Stderr, "WARN: fetched legacy db-snapshot branch; operator should run "+
				"`git push origin origin/db-snapshot:db-seed && git push origin :db-snapshot` "+
				"to complete the rename.")
		}

		// Ensure the local directory exists for the seed files.
		if err := os.MkdirAll(seedDir, 0755); err != nil {
			return fmt.Errorf("create .db-seed directory: %w", err)
		}

		// Choose the ref the fetch landed on.
		branchRef := "origin/db-seed"
		dumpName := "seed.pg_dump"
		jsonName := "seed.json"
		if usedLegacy {
			branchRef = "origin/db-snapshot"
			dumpName = "snapshot.pg_dump"
			jsonName = "snapshot.json"
		}

		// Extract dump from the fetched branch.
		// We pipe git show output directly to a file instead of going through
		// a string, because pg_dump custom format is binary and string
		// conversion would corrupt it.
		dumpPath := filepath.Join(seedDir, "seed.pg_dump")
		if err := gitShowToFile(projDir, branchRef+":"+dumpName, dumpPath); err != nil {
			return fmt.Errorf("extract %s from branch: %w", dumpName, err)
		}

		// Extract metadata JSON from the fetched branch.
		jsonPath := filepath.Join(seedDir, "seed.json")
		if err := gitShowToFile(projDir, branchRef+":"+jsonName, jsonPath); err != nil {
			return fmt.Errorf("extract %s from branch: %w", jsonName, err)
		}

		// Read migration version from the metadata to confirm success.
		meta, err := loadSeedMeta(projDir)
		if err != nil {
			return fmt.Errorf("parse seed.json: %w", err)
		}

		fmt.Printf("Seed fetched: migration %s\n", meta.MigrationVersion)
		return nil
	},
}

// ── seed restore ────────────────────────────────────────────────────────────

// seedRestoreCmd restores the cached seed into the target database.
// The database should already exist (created from template_statbus or CREATE DATABASE).
// After restore, only migrations newer than the seed need to run.
var seedRestoreCmd = &cobra.Command{
	Use:   "restore",
	Short: "Restore seed into a database via pg_restore",
	RunE: func(cmd *cobra.Command, args []string) error {
		projDir := config.ProjectDir()

		// Check that the seed file exists locally.
		dumpPath := filepath.Join(projDir, ".db-seed", "seed.pg_dump")
		if _, err := os.Stat(dumpPath); os.IsNotExist(err) {
			return fmt.Errorf("seed not found at %s\nRun: ./sb db seed fetch", dumpPath)
		}

		// Determine target database: --database flag overrides .env default.
		// The flag is needed for test template databases that differ from the
		// main application database.
		dbName := seedDatabase
		if dbName == "" {
			var err error
			dbName, err = loadDbName(projDir)
			if err != nil {
				return err
			}
		}

		if err := validateIdentifier(dbName, "database name"); err != nil {
			return err
		}

		// Read metadata to report the migration version.
		meta, err := loadSeedMeta(projDir)
		if err != nil {
			return err
		}

		// Pipe the dump file into pg_restore via docker compose.
		// We use --clean --if-exists to drop existing objects first (safe for
		// freshly created databases — the DROP errors are harmless).
		// --single-transaction ensures atomicity: either the whole restore
		// succeeds or nothing changes.
		fmt.Printf("Restoring seed to %s ...\n", dbName)

		dumpFile, err := os.Open(dumpPath)
		if err != nil {
			return fmt.Errorf("open seed file: %w", err)
		}
		defer dumpFile.Close()

		restoreCmd := exec.Command("docker", "compose", "exec", "-T", "db",
			"pg_restore", "-U", "postgres",
			"--clean", "--if-exists",
			"--no-owner", "--disable-triggers",
			"--single-transaction",
			"-d", dbName)
		restoreCmd.Dir = projDir
		restoreCmd.Stdin = dumpFile
		restoreCmd.Stdout = os.Stdout
		restoreCmd.Stderr = os.Stderr

		err = restoreCmd.Run()
		if err != nil {
			// pg_restore exit code 1 means warnings (e.g., "role does not exist"
			// for --clean drops). This is expected and harmless — the data is
			// restored correctly. Only exit code 2+ indicates real failure.
			if exitErr, ok := err.(*exec.ExitError); ok && exitErr.ExitCode() == 1 {
				// Warnings only — not an error.
			} else {
				return fmt.Errorf("pg_restore failed: %w", err)
			}
		}

		fmt.Printf("Seed restored to %s (migration %s)\n", dbName, meta.MigrationVersion)
		return nil
	},
}

// ── seed create ─────────────────────────────────────────────────────────────

// seedCreateCmd dumps the current database state and pushes it to the
// db-seed branch. This branch is a CACHE — it's force-pushed on each
// update. Old seeds are intentionally discarded because only the latest
// migration state matters.
var seedCreateCmd = &cobra.Command{
	Use:   "create",
	Short: "Dump current DB and push to db-seed branch",
	RunE: func(cmd *cobra.Command, args []string) error {
		return CreateSeed(config.ProjectDir())
	},
}

// CreateSeed is the reusable body of `./sb db seed create`. Exposed
// so the release-prerelease preflight (cli/cmd/release.go) can invoke the
// same regen path in-process when it detects a stale seed — no
// subprocess, no separate operator step. Behaviour-identical to invoking
// the cobra subcommand.
func CreateSeed(projDir string) error {
	// Verify the database is running — we need it for pg_dump and the
	// migration version query.
	if !dbIsRunning(projDir) {
		return fmt.Errorf("database is not running — start it with 'sb start all'")
	}

	dbName, err := loadDbName(projDir)
	if err != nil {
		return err
	}

	// Get the latest migration version from the database.
	// This tells us exactly what schema state the seed captures.
	migrationOut, err := upgrade.RunCommandOutput(projDir,
		"docker", "compose", "exec", "-T", "db",
		"psql", "-U", "postgres", "-d", dbName,
		"-t", "-A", "-c",
		"SELECT version FROM db.migration ORDER BY version DESC LIMIT 1")
	if err != nil {
		return fmt.Errorf("query migration version: %w\n%s", err, migrationOut)
	}
	migrationVersion := strings.TrimSpace(migrationOut)
	if migrationVersion == "" {
		return fmt.Errorf("no migrations found in db.migration table")
	}

	// Get the current git commit SHA for traceability.
	commitSHA, err := upgrade.RunCommandOutput(projDir, "git", "rev-parse", "HEAD")
	if err != nil {
		return fmt.Errorf("git rev-parse HEAD: %w", err)
	}
	commitSHA = strings.TrimSpace(commitSHA)

	// Get tags pointing at HEAD (if any) for display purposes.
	tagsOut, _ := upgrade.RunCommandOutput(projDir, "git", "tag", "--points-at", "HEAD")
	tags := strings.TrimSpace(tagsOut)

	seedDir := filepath.Join(projDir, ".db-seed")
	if err := os.MkdirAll(seedDir, 0755); err != nil {
		return fmt.Errorf("create .db-seed directory: %w", err)
	}

	// Dump the database in custom format (compact, supports parallel restore).
	// Exclude auth.secrets — those contain per-deployment JWT secrets that
	// must not leak into the shared seed branch.
	fmt.Printf("Dumping %s ...\n", dbName)
	dumpPath := filepath.Join(seedDir, "seed.pg_dump")
	dumpFile, err := os.Create(dumpPath)
	if err != nil {
		return fmt.Errorf("create dump file: %w", err)
	}

	dumpCmd := exec.Command("docker", "compose", "exec", "-T", "db",
		"pg_dump", "-U", "postgres", "-Fc", "--no-owner",
		"--exclude-table-data=auth.secrets",
		dbName)
	dumpCmd.Dir = projDir
	dumpCmd.Stdout = dumpFile
	dumpCmd.Stderr = os.Stderr

	if err := dumpCmd.Run(); err != nil {
		dumpFile.Close()
		os.Remove(dumpPath)
		return fmt.Errorf("pg_dump failed: %w", err)
	}
	dumpFile.Close()

	info, err := os.Stat(dumpPath)
	if err != nil {
		return err
	}
	if info.Size() == 0 {
		os.Remove(dumpPath)
		return fmt.Errorf("pg_dump produced an empty file — check database connectivity")
	}

	// Write metadata JSON alongside the dump.
	meta := seedMeta{
		MigrationVersion: migrationVersion,
		CommitSHA:        commitSHA,
		Tags:             tags,
		CreatedAt:        time.Now().UTC().Format(time.RFC3339),
	}
	metaJSON, err := json.MarshalIndent(meta, "", "  ")
	if err != nil {
		return fmt.Errorf("marshal seed.json: %w", err)
	}
	jsonPath := filepath.Join(seedDir, "seed.json")
	if err := os.WriteFile(jsonPath, metaJSON, 0644); err != nil {
		return fmt.Errorf("write seed.json: %w", err)
	}

	fmt.Printf("Seed created: migration %s, commit %s (%s)\n",
		migrationVersion, commitSHA[:8], humanSize(info.Size()))

	// Sweep stale peer `seed/<sha>` branches BEFORE publishing the
	// new one. Unified gate in cleanupSeedBranches (defined in
	// release.go): delete untagged ephemeral peers, delete tagged
	// peers whose release is fully published (canonical store = GH
	// release assets), retain tagged in-flight peers. preserveSHA is
	// the project commit the new seed pins to — so the cleanup
	// never touches the slot we're about to write.
	cleanupSeedBranches(projDir, commitSHA)

	// Push to the db-seed branch using a git worktree.
	// A worktree lets us commit to an orphan branch without touching the
	// current working tree or index. The worktree lives outside the main
	// repo to avoid confusion.
	worktreePath := filepath.Join(filepath.Dir(projDir), "statbus-db-seed")

	// Check if the worktree already exists.
	if _, err := os.Stat(worktreePath); os.IsNotExist(err) {
		// Try to add worktree for existing branch first.
		_, addErr := upgrade.RunCommandOutput(projDir, "git", "worktree", "add", worktreePath, "db-seed")
		if addErr != nil {
			// Branch doesn't exist — create an orphan worktree.
			// --orphan creates a new branch with no history, which is what
			// we want: the seed branch has no relationship to master.
			_, orphanErr := upgrade.RunCommandOutput(projDir, "git", "worktree", "add", "--orphan", worktreePath, "db-seed")
			if orphanErr != nil {
				return fmt.Errorf("git worktree add: %w\n%s", orphanErr, addErr)
			}
		}
	}

	// Copy seed files to the worktree.
	for _, name := range []string{"seed.pg_dump", "seed.json"} {
		src := filepath.Join(seedDir, name)
		dst := filepath.Join(worktreePath, name)
		data, err := os.ReadFile(src)
		if err != nil {
			return fmt.Errorf("read %s: %w", name, err)
		}
		if err := os.WriteFile(dst, data, 0644); err != nil {
			return fmt.Errorf("write %s to worktree: %w", name, err)
		}
	}

	// Stage, commit, and force-push.
	// Force-push is intentional: the seed branch is a cache with a
	// single commit. History is meaningless — only the latest state matters.
	if _, err := upgrade.RunCommandOutput(worktreePath, "git", "add", "seed.pg_dump", "seed.json"); err != nil {
		return fmt.Errorf("git add in worktree: %w", err)
	}

	commitMsg := fmt.Sprintf("seed: migration %s (commit %s)", migrationVersion, commitSHA[:8])
	if _, err := upgrade.RunCommandOutput(worktreePath, "git", "commit", "--allow-empty", "-m", commitMsg); err != nil {
		return fmt.Errorf("git commit in worktree: %w", err)
	}

	if _, err := upgrade.RunCommandOutput(worktreePath, "git", "push", "origin", "db-seed", "--force"); err != nil {
		return fmt.Errorf("git push --force db-seed: %w", err)
	}

	fmt.Printf("Seed created and pushed (migration %s, commit %s)\n", migrationVersion, commitSHA[:8])

	// Publish the seed under a SHA-named branch
	// `seed/<commitSHA12>` so downstream consumers — release
	// workflow, operator fetches, historical lookups — have a
	// deterministic, collision-safe reference keyed by the project
	// commit the seed pins to. Every seed gets a branch;
	// the tag-conditional gate from the prior release-only design
	// is gone. This removes the chicken-and-egg where a seed
	// could be created before its HEAD was tagged.
	//
	// The branch points at the new commit on the db-seed
	// worktree (where seed.pg_dump + seed.json live);
	// the branch NAME reflects the project commit; seed.json's
	// commit_sha field records the full project SHA (preflight and
	// workflow use the full value for verification).
	seedCommit, err := upgrade.RunCommandOutput(worktreePath, "git", "rev-parse", "HEAD")
	if err != nil {
		return fmt.Errorf("git rev-parse HEAD in worktree: %w", err)
	}
	seedCommit = strings.TrimSpace(seedCommit)
	branchName := "seed/" + commitSHA[:seedSHALen]

	// Force-create the local branch — a stale local ref from an
	// aborted prior attempt at this same project SHA should be
	// replaced, not refused.
	if _, err := upgrade.RunCommandOutput(worktreePath, "git", "branch", "-f", branchName, seedCommit); err != nil {
		return fmt.Errorf("git branch %s: %w", branchName, err)
	}
	// --force-with-lease: cleanupSeedBranches typically leaves
	// this slot empty (or honors preserveSHA to keep us); the
	// --force-with-lease is the safety net for the abort-and-retry
	// case where remote and local diverge mid-run.
	if _, err := upgrade.RunCommandOutput(worktreePath, "git", "push", "origin", "--force-with-lease", branchName); err != nil {
		return fmt.Errorf("git push origin %s: %w", branchName, err)
	}
	fmt.Printf("Seed pinned: %s → %s\n", branchName, seedCommit[:8])
	return nil
}

// ── seed status ─────────────────────────────────────────────────────────────

// seedStatusCmd shows whether the seed covers the latest migrations.
// Used by release pre-flight and by developers to check freshness.
var seedStatusCmd = &cobra.Command{
	Use:   "status",
	Short: "Show seed version vs latest migration",
	RunE: func(cmd *cobra.Command, args []string) error {
		projDir := config.ProjectDir()

		// Read seed metadata. If missing, tell the user how to get it.
		meta, err := loadSeedMeta(projDir)
		if err != nil {
			fmt.Println("No seed cached. Run: ./sb db seed fetch")
			return nil
		}

		// Find the latest migration file on disk.
		// Migration filenames start with a timestamp version (YYYYMMDDHHmmSS),
		// so lexicographic sort gives us chronological order.
		latestMigration, err := findLatestMigration(projDir)
		if err != nil {
			return err
		}

		fmt.Printf("Seed:             %s\n", meta.MigrationVersion)
		fmt.Printf("Latest migration: %s\n", latestMigration)

		if meta.MigrationVersion == latestMigration {
			fmt.Println("Status: Up to date")
		} else {
			fmt.Println("Status: Outdated")
		}

		if meta.CommitSHA != "" {
			fmt.Printf("Seed commit:      %s\n", meta.CommitSHA[:min(8, len(meta.CommitSHA))])
		}
		if meta.CreatedAt != "" {
			fmt.Printf("Created at:       %s\n", meta.CreatedAt)
		}

		return nil
	},
}

// ── helpers ─────────────────────────────────────────────────────────────────

// gitShowToFile writes the output of `git show <ref>` directly to a file.
// This avoids string conversion that would corrupt binary content like
// pg_dump custom format files.
func gitShowToFile(projDir, ref, destPath string) error {
	outFile, err := os.Create(destPath)
	if err != nil {
		return fmt.Errorf("create %s: %w", destPath, err)
	}
	defer outFile.Close()

	cmd := exec.Command("git", "show", ref)
	cmd.Dir = projDir
	cmd.Stdout = outFile
	cmd.Stderr = os.Stderr

	if err := cmd.Run(); err != nil {
		os.Remove(destPath)
		return fmt.Errorf("git show %s: %w", ref, err)
	}
	return nil
}

// loadSeedMeta reads and parses .db-seed/seed.json.
// Returns an error if the file doesn't exist or can't be parsed.
func loadSeedMeta(projDir string) (*seedMeta, error) {
	jsonPath := filepath.Join(projDir, ".db-seed", "seed.json")
	data, err := os.ReadFile(jsonPath)
	if err != nil {
		return nil, fmt.Errorf("read seed.json: %w", err)
	}
	var meta seedMeta
	if err := json.Unmarshal(data, &meta); err != nil {
		return nil, fmt.Errorf("parse seed.json: %w", err)
	}
	return &meta, nil
}

// findLatestMigration scans the migrations/ directory and returns the version
// string (timestamp prefix) of the newest .up.sql file. Migration filenames
// follow the pattern YYYYMMDDHHmmSS_description.up.sql, so the version is
// the part before the first underscore.
func findLatestMigration(projDir string) (string, error) {
	migrationsDir := filepath.Join(projDir, "migrations")
	entries, err := filepath.Glob(filepath.Join(migrationsDir, "*.up.sql"))
	if err != nil {
		return "", fmt.Errorf("glob migrations: %w", err)
	}
	if len(entries) == 0 {
		return "", fmt.Errorf("no migration files found in %s", migrationsDir)
	}

	// Sort lexicographically — timestamps sort chronologically.
	sort.Strings(entries)
	latest := filepath.Base(entries[len(entries)-1])

	// Extract the version: everything before the first underscore.
	// Example: "20260328092344_commit_centric_upgrade_table.up.sql" -> "20260328092344"
	parts := strings.SplitN(latest, "_", 2)
	if len(parts) == 0 {
		return "", fmt.Errorf("unexpected migration filename: %s", latest)
	}

	return parts[0], nil
}

// ── init ────────────────────────────────────────────────────────────────────

func init() {
	seedRestoreCmd.Flags().StringVar(&seedDatabase, "database", "",
		"target database name (default: POSTGRES_APP_DB from .env)")

	seedCmd.AddCommand(seedFetchCmd)
	seedCmd.AddCommand(seedRestoreCmd)
	seedCmd.AddCommand(seedCreateCmd)
	seedCmd.AddCommand(seedStatusCmd)

	dbCmd.AddCommand(seedCmd)
}

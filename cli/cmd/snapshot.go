package cmd

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"

	"github.com/spf13/cobra"
	"github.com/statisticsnorway/statbus/cli/internal/config"
	"github.com/statisticsnorway/statbus/cli/internal/upgrade"
)

// releaseTagPattern matches the project's release tag shape:
// `vYYYY.MM.PATCH` (stable) and `vYYYY.MM.PATCH-rc.N` (prerelease).
// Used to distinguish release tags from other refs pointing at HEAD.
var releaseTagPattern = regexp.MustCompile(`^v\d{4}\.\d{2}\.\d+(-rc\.\d+)?$`)

// findReleaseTag returns the first release-shaped tag in a newline-separated
// string of tag names, or "" if none match. git tag --points-at HEAD may
// return multiple tags (release + local markers + signing tags); we only
// act on the release-shaped one.
func findReleaseTag(tags string) string {
	for _, t := range strings.Split(strings.TrimSpace(tags), "\n") {
		t = strings.TrimSpace(t)
		if releaseTagPattern.MatchString(t) {
			return t
		}
	}
	return ""
}

// snapshotMeta is the JSON structure stored in .db-snapshot/snapshot.json.
// It records which migration and commit the snapshot covers, so callers
// can decide whether the snapshot is fresh enough to use.
type snapshotMeta struct {
	MigrationVersion string `json:"migration_version"`
	CommitSHA        string `json:"commit_sha"`
	Tags             string `json:"tags"`
	CreatedAt        string `json:"created_at"`
}

var snapshotDatabase string

// ── snapshot command group ──────────────────────────────────────────────────

var snapshotCmd = &cobra.Command{
	Use:   "snapshot",
	Short: "Manage database snapshots for fast DB creation",
	Long: `Manage pg_dump snapshots cached on the db-snapshot git branch.

A snapshot lets dev.sh skip running ~294 migrations and instead
pg_restore a single dump file (~2 seconds). The snapshot branch
is a CACHE — it's force-pushed on each update.

Subcommands:
  fetch     Download snapshot from origin/db-snapshot
  restore   Restore snapshot into a database
  create    Dump current DB and push to db-snapshot branch
  status    Compare snapshot version to latest migration`,
}

// ── snapshot fetch ──────────────────────────────────────────────────────────

// snapshotFetchCmd downloads the cached DB snapshot from the db-snapshot git
// branch. The snapshot is a pg_dump that speeds up DB creation from ~294
// migrations to one pg_restore (~2 seconds). Auto-called by dev.sh on first run.
var snapshotFetchCmd = &cobra.Command{
	Use:   "fetch",
	Short: "Fetch snapshot from origin/db-snapshot branch",
	RunE: func(cmd *cobra.Command, args []string) error {
		projDir := config.ProjectDir()
		snapshotDir := filepath.Join(projDir, ".db-snapshot")

		// Fetch the db-snapshot branch (shallow — we only need the tip).
		// Tolerate failure: the branch may not exist yet on the remote.
		_, err := upgrade.RunCommandOutput(projDir, "git", "fetch", "origin", "db-snapshot", "--depth=1", "--quiet")
		if err != nil {
			fmt.Println("No snapshot branch found on remote. Create one with: ./sb db snapshot create")
			return nil
		}

		// Ensure the local directory exists for the snapshot files.
		if err := os.MkdirAll(snapshotDir, 0755); err != nil {
			return fmt.Errorf("create .db-snapshot directory: %w", err)
		}

		// Extract snapshot.pg_dump from the fetched branch.
		// We pipe git show output directly to a file instead of going through
		// a string, because pg_dump custom format is binary and string
		// conversion would corrupt it.
		dumpPath := filepath.Join(snapshotDir, "snapshot.pg_dump")
		if err := gitShowToFile(projDir, "origin/db-snapshot:snapshot.pg_dump", dumpPath); err != nil {
			return fmt.Errorf("extract snapshot.pg_dump from branch: %w", err)
		}

		// Extract snapshot.json from the fetched branch.
		jsonPath := filepath.Join(snapshotDir, "snapshot.json")
		if err := gitShowToFile(projDir, "origin/db-snapshot:snapshot.json", jsonPath); err != nil {
			return fmt.Errorf("extract snapshot.json from branch: %w", err)
		}

		// Read migration version from the metadata to confirm success.
		meta, err := loadSnapshotMeta(projDir)
		if err != nil {
			return fmt.Errorf("parse snapshot.json: %w", err)
		}

		fmt.Printf("Snapshot fetched: migration %s\n", meta.MigrationVersion)
		return nil
	},
}

// ── snapshot restore ────────────────────────────────────────────────────────

// snapshotRestoreCmd restores the cached snapshot into the target database.
// The database should already exist (created from template_statbus or CREATE DATABASE).
// After restore, only migrations newer than the snapshot need to run.
var snapshotRestoreCmd = &cobra.Command{
	Use:   "restore",
	Short: "Restore snapshot into a database via pg_restore",
	RunE: func(cmd *cobra.Command, args []string) error {
		projDir := config.ProjectDir()

		// Check that the snapshot file exists locally.
		dumpPath := filepath.Join(projDir, ".db-snapshot", "snapshot.pg_dump")
		if _, err := os.Stat(dumpPath); os.IsNotExist(err) {
			return fmt.Errorf("snapshot not found at %s\nRun: ./sb db snapshot fetch", dumpPath)
		}

		// Determine target database: --database flag overrides .env default.
		// The flag is needed for test template databases that differ from the
		// main application database.
		dbName := snapshotDatabase
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
		meta, err := loadSnapshotMeta(projDir)
		if err != nil {
			return err
		}

		// Pipe the dump file into pg_restore via docker compose.
		// We use --clean --if-exists to drop existing objects first (safe for
		// freshly created databases — the DROP errors are harmless).
		// --single-transaction ensures atomicity: either the whole restore
		// succeeds or nothing changes.
		fmt.Printf("Restoring snapshot to %s ...\n", dbName)

		dumpFile, err := os.Open(dumpPath)
		if err != nil {
			return fmt.Errorf("open snapshot file: %w", err)
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

		fmt.Printf("Snapshot restored to %s (migration %s)\n", dbName, meta.MigrationVersion)
		return nil
	},
}

// ── snapshot create ─────────────────────────────────────────────────────────

// snapshotCreateCmd dumps the current database state and pushes it to the
// db-snapshot branch. This branch is a CACHE — it's force-pushed on each
// update. Old snapshots are intentionally discarded because only the latest
// migration state matters.
var snapshotCreateCmd = &cobra.Command{
	Use:   "create",
	Short: "Dump current DB and push to db-snapshot branch",
	RunE: func(cmd *cobra.Command, args []string) error {
		projDir := config.ProjectDir()

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
		// This tells us exactly what schema state the snapshot captures.
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

		snapshotDir := filepath.Join(projDir, ".db-snapshot")
		if err := os.MkdirAll(snapshotDir, 0755); err != nil {
			return fmt.Errorf("create .db-snapshot directory: %w", err)
		}

		// Dump the database in custom format (compact, supports parallel restore).
		// Exclude auth.secrets — those contain per-deployment JWT secrets that
		// must not leak into the shared snapshot branch.
		fmt.Printf("Dumping %s ...\n", dbName)
		dumpPath := filepath.Join(snapshotDir, "snapshot.pg_dump")
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
		meta := snapshotMeta{
			MigrationVersion: migrationVersion,
			CommitSHA:        commitSHA,
			Tags:             tags,
			CreatedAt:        time.Now().UTC().Format(time.RFC3339),
		}
		metaJSON, err := json.MarshalIndent(meta, "", "  ")
		if err != nil {
			return fmt.Errorf("marshal snapshot.json: %w", err)
		}
		jsonPath := filepath.Join(snapshotDir, "snapshot.json")
		if err := os.WriteFile(jsonPath, metaJSON, 0644); err != nil {
			return fmt.Errorf("write snapshot.json: %w", err)
		}

		fmt.Printf("Snapshot created: migration %s, commit %s (%s)\n",
			migrationVersion, commitSHA[:8], humanSize(info.Size()))

		// Release-staging: if HEAD carries a release tag (v… or v…-rc.N),
		// we will additionally publish a branch `snapshot/<release-tag>`
		// pinned to the new snapshot commit. First, clean up any STALE
		// snapshot branches on origin that belong to earlier releases —
		// they remain in-tree after their release workflow finishes
		// (cleanup is intentionally deferred to the next prerelease cut).
		// Keep any branch whose suffix matches the current release tag so
		// an in-progress abort-and-retry doesn't lose its snapshot pin.
		//
		// On origin only, per the single-source-of-truth principle for
		// release pins. Non-release snapshot runs (operator-local,
		// rc-less commits) skip both cleanup and branch publication.
		releaseTag := findReleaseTag(tags)
		if releaseTag != "" {
			staleOut, lsErr := upgrade.RunCommandOutput(projDir, "git", "ls-remote", "--heads", "origin", "snapshot/v*")
			if lsErr != nil {
				fmt.Printf("warning: list remote snapshot branches: %v\n", lsErr)
			} else {
				for _, line := range strings.Split(strings.TrimSpace(staleOut), "\n") {
					line = strings.TrimSpace(line)
					if line == "" {
						continue
					}
					// ls-remote lines: "<sha>\trefs/heads/snapshot/vX.Y.Z"
					parts := strings.SplitN(line, "\t", 2)
					if len(parts) != 2 {
						continue
					}
					ref := strings.TrimPrefix(parts[1], "refs/heads/")
					if ref == "snapshot/"+releaseTag {
						continue // keep the in-flight snapshot for this release
					}
					fmt.Printf("Cleaning up stale snapshot branch: %s\n", ref)
					if _, delErr := upgrade.RunCommandOutput(projDir, "git", "push", "origin", "--delete", ref); delErr != nil {
						fmt.Printf("warning: git push origin --delete %s: %v\n", ref, delErr)
					}
					// Remove the local tracking branch too if present.
					_, _ = upgrade.RunCommandOutput(projDir, "git", "branch", "-D", ref)
				}
			}
		}

		// Push to the db-snapshot branch using a git worktree.
		// A worktree lets us commit to an orphan branch without touching the
		// current working tree or index. The worktree lives outside the main
		// repo to avoid confusion.
		worktreePath := filepath.Join(filepath.Dir(projDir), "statbus-db-snapshot")

		// Check if the worktree already exists.
		if _, err := os.Stat(worktreePath); os.IsNotExist(err) {
			// Try to add worktree for existing branch first.
			_, addErr := upgrade.RunCommandOutput(projDir, "git", "worktree", "add", worktreePath, "db-snapshot")
			if addErr != nil {
				// Branch doesn't exist — create an orphan worktree.
				// --orphan creates a new branch with no history, which is what
				// we want: the snapshot branch has no relationship to master.
				_, orphanErr := upgrade.RunCommandOutput(projDir, "git", "worktree", "add", "--orphan", worktreePath, "db-snapshot")
				if orphanErr != nil {
					return fmt.Errorf("git worktree add: %w\n%s", orphanErr, addErr)
				}
			}
		}

		// Copy snapshot files to the worktree.
		for _, name := range []string{"snapshot.pg_dump", "snapshot.json"} {
			src := filepath.Join(snapshotDir, name)
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
		// Force-push is intentional: the snapshot branch is a cache with a
		// single commit. History is meaningless — only the latest state matters.
		if _, err := upgrade.RunCommandOutput(worktreePath, "git", "add", "snapshot.pg_dump", "snapshot.json"); err != nil {
			return fmt.Errorf("git add in worktree: %w", err)
		}

		commitMsg := fmt.Sprintf("snapshot: migration %s (commit %s)", migrationVersion, commitSHA[:8])
		if _, err := upgrade.RunCommandOutput(worktreePath, "git", "commit", "--allow-empty", "-m", commitMsg); err != nil {
			return fmt.Errorf("git commit in worktree: %w", err)
		}

		if _, err := upgrade.RunCommandOutput(worktreePath, "git", "push", "origin", "db-snapshot", "--force"); err != nil {
			return fmt.Errorf("git push --force db-snapshot: %w", err)
		}

		fmt.Printf("Snapshot created and pushed (migration %s, commit %s)\n", migrationVersion, commitSHA[:8])

		// Release-staging: publish the snapshot under a branch
		// `snapshot/<release-tag>` so the release workflow can fetch a
		// version-scoped ref whose commit_sha is verifiable against the
		// release commit. The branch is deleted on the next prerelease
		// cut after the release workflow has uploaded the snapshot as a
		// GitHub release asset (canonical, immutable store).
		if releaseTag != "" {
			snapshotSHA, err := upgrade.RunCommandOutput(worktreePath, "git", "rev-parse", "HEAD")
			if err != nil {
				return fmt.Errorf("git rev-parse HEAD in worktree: %w", err)
			}
			snapshotSHA = strings.TrimSpace(snapshotSHA)
			branchName := "snapshot/" + releaseTag

			// Force-create the local branch — if a stale local ref exists
			// from an aborted prior attempt at this same release tag we
			// want it replaced, not refused.
			if _, err := upgrade.RunCommandOutput(worktreePath, "git", "branch", "-f", branchName, snapshotSHA); err != nil {
				return fmt.Errorf("git branch %s: %w", branchName, err)
			}
			// Non-force push: this is a freshly-cleaned slot (earlier
			// cleanup step removed any prior branch at this name) except
			// when the operator is legitimately re-running the same
			// release's snapshot create (abort + retry), in which case
			// the remote branch and our local branch point at different
			// commits and we need --force-with-lease for safety.
			if _, err := upgrade.RunCommandOutput(worktreePath, "git", "push", "origin", "--force-with-lease", branchName); err != nil {
				return fmt.Errorf("git push origin %s: %w", branchName, err)
			}
			fmt.Printf("Release snapshot pinned: %s → %s\n", branchName, snapshotSHA[:8])
		}
		return nil
	},
}

// ── snapshot status ─────────────────────────────────────────────────────────

// snapshotStatusCmd shows whether the snapshot covers the latest migrations.
// Used by release pre-flight and by developers to check freshness.
var snapshotStatusCmd = &cobra.Command{
	Use:   "status",
	Short: "Show snapshot version vs latest migration",
	RunE: func(cmd *cobra.Command, args []string) error {
		projDir := config.ProjectDir()

		// Read snapshot metadata. If missing, tell the user how to get it.
		meta, err := loadSnapshotMeta(projDir)
		if err != nil {
			fmt.Println("No snapshot cached. Run: ./sb db snapshot fetch")
			return nil
		}

		// Find the latest migration file on disk.
		// Migration filenames start with a timestamp version (YYYYMMDDHHmmSS),
		// so lexicographic sort gives us chronological order.
		latestMigration, err := findLatestMigration(projDir)
		if err != nil {
			return err
		}

		fmt.Printf("Snapshot:         %s\n", meta.MigrationVersion)
		fmt.Printf("Latest migration: %s\n", latestMigration)

		if meta.MigrationVersion == latestMigration {
			fmt.Println("Status: Up to date")
		} else {
			fmt.Println("Status: Outdated")
		}

		if meta.CommitSHA != "" {
			fmt.Printf("Snapshot commit:  %s\n", meta.CommitSHA[:min(8, len(meta.CommitSHA))])
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

// loadSnapshotMeta reads and parses .db-snapshot/snapshot.json.
// Returns an error if the file doesn't exist or can't be parsed.
func loadSnapshotMeta(projDir string) (*snapshotMeta, error) {
	jsonPath := filepath.Join(projDir, ".db-snapshot", "snapshot.json")
	data, err := os.ReadFile(jsonPath)
	if err != nil {
		return nil, fmt.Errorf("read snapshot.json: %w", err)
	}
	var meta snapshotMeta
	if err := json.Unmarshal(data, &meta); err != nil {
		return nil, fmt.Errorf("parse snapshot.json: %w", err)
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
	snapshotRestoreCmd.Flags().StringVar(&snapshotDatabase, "database", "",
		"target database name (default: POSTGRES_APP_DB from .env)")

	snapshotCmd.AddCommand(snapshotFetchCmd)
	snapshotCmd.AddCommand(snapshotRestoreCmd)
	snapshotCmd.AddCommand(snapshotCreateCmd)
	snapshotCmd.AddCommand(snapshotStatusCmd)

	dbCmd.AddCommand(snapshotCmd)
}

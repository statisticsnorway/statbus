package cmd

import (
	"crypto/sha256"
	"encoding/hex"
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
	"github.com/statisticsnorway/statbus/cli/internal/migrate"
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
//
// PostRestoreSHA captures the sha256 of migrations/post_restore.sql at
// the time the seed was produced. Combined with MigrationVersion it
// forms the "did the schema-after-restore actually change" fingerprint
// that `./sb db seed sync` uses to decide between a full pg_dump
// rebuild and the fast-path republish (reuse the existing seed.pg_dump
// bytes, rewrite only seed.json with new commit_sha + created_at).
//
// The field is `omitempty` so existing seed.json files without it
// (produced by pre-#133 builds) still parse cleanly. Absence is
// treated as "fingerprint missing → full rebuild" — the only correct
// migration shape because we can't otherwise tell whether the prior
// dump captured the current post_restore.sql.
type seedMeta struct {
	MigrationVersion string `json:"migration_version"`
	PostRestoreSHA   string `json:"post_restore_sha,omitempty"`
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
  sync      Bring statbus_seed to HEAD, publish dump + per-commit pin (the
            operator-facing entrypoint; smart-skips pg_dump when
            (migration_version, sha256(post_restore.sql)) is unchanged)
  fetch     Download seed from origin/db-seed
  restore   Restore seed into a database
  create    Dump current DB and push to db-seed branch (primitive — sync wraps this)
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

		// Atomic-restore failure contract. With --single-transaction set
		// above, pg_restore wraps every emitted command in BEGIN/COMMIT
		// and (per pg_restore(1)) implies --exit-on-error: any error in
		// any restore step aborts the whole transaction and exits non-
		// zero. There is no "warnings, but data restored correctly"
		// outcome with --single-transaction — either the COMMIT lands
		// (exit 0) or the ROLLBACK fires (exit ≥ 1). runPgRestoreAtomic
		// (cli/cmd/db.go) also scans the streamed stderr for the
		// pg_restore: error: prefix as defense-in-depth, so a future
		// regression that drops --single-transaction (and lets
		// pg_restore exit 0 with errors in its TOC) still fails loudly
		// here rather than silently returning "Seed restored".
		//
		// Earlier versions of this wrapper carried an exit-code-1
		// tolerance ("warnings only, not an error"). That was correct
		// for pg_restore WITHOUT --single-transaction; once the flag
		// landed, the tolerance silently turned ROLLBACK ("data NOT
		// restored") into a passing invocation. tcc's near-miss
		// (forensics: tmp/install-state-machine-forensics.md) surfaced
		// the danger: a destructive restore could fail half-way,
		// leaving the DB in a wedged-or-empty state, while ./sb db
		// seed restore reported success.
		if err := runPgRestoreAtomic(restoreCmd, "seed restore"); err != nil {
			return err
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

// seedDumpCmd is the dump-only half of `db seed create`: it writes
// .db-seed/seed.pg_dump + seed.json WITHOUT publishing to the db-seed git
// branch. The hermetic seed-builder image stage calls this — the build tree has
// no .git, so pass --commit so seed.json carries the right commit.
var seedDumpCommit string

var seedDumpCmd = &cobra.Command{
	Use:   "dump",
	Short: "Dump the seed DB to .db-seed/ (no git publish)",
	RunE: func(cmd *cobra.Command, args []string) error {
		_, err := DumpSeed(config.ProjectDir(), seedDumpCommit)
		return err
	},
}

// seedCreateDbCmd creates an empty seed database from template_statbus + the
// per-DB auth grants — the Go lift of dev.sh's create-seed, so the hermetic
// seed-builder image and dev share ONE definition. Routes through PsqlCommand
// (DOCKER_PSQL-aware), so it runs host-locally inside the seed-builder image
// without docker-in-docker.
var seedCreateDbCmd = &cobra.Command{
	Use:   "create-db",
	Short: "Create an empty seed DB from template_statbus (+ auth grants)",
	RunE: func(cmd *cobra.Command, args []string) error {
		return CreateSeedDb(config.ProjectDir())
	},
}

// CreateSeedDb creates ${POSTGRES_SEED_DB} as a fresh copy of template_statbus
// (the extensions + non-role objects) plus the per-database auth schema + grants
// that init-db.sh adds to the main DB but template_statbus lacks. It is the Go
// single source of truth for dev.sh's create-seed (dev.sh delegates here).
// Connection-agnostic (QueryDB / ExecOnDB → PsqlCommand), so it works under
// DOCKER_PSQL=0 in the hermetic seed-builder.
func CreateSeedDb(projDir string) error {
	dbName, err := loadSeedDbName(projDir)
	if err != nil {
		return fmt.Errorf("load seed DB name: %w", err)
	}

	// Don't clobber an existing seed — point at the recovery primitive.
	if exists, _ := migrate.QueryDB(projDir, "postgres",
		fmt.Sprintf("SELECT 1 FROM pg_database WHERE datname = '%s'", dbName),
		"-t", "-A"); exists == "1" {
		return fmt.Errorf("seed database %q already exists.\n"+
			"  Drop it first: ./dev.sh delete-seed\n"+
			"  Or rebuild end-to-end: ./dev.sh recreate-seed", dbName)
	}

	// Pre-flight: template_statbus must exist — provisioned by init-db.sh on
	// first boot of an empty PGDATA, or `./dev.sh create-db` locally. Naming it
	// makes the failure actionable instead of a generic "template not found".
	tmpl, err := migrate.QueryDB(projDir, "postgres",
		"SELECT 1 FROM pg_database WHERE datname = 'template_statbus'", "-t", "-A")
	if err != nil {
		return fmt.Errorf("cannot reach Postgres to check for template_statbus: %w", err)
	}
	if tmpl != "1" {
		return fmt.Errorf("template_statbus does not exist.\n" +
			"  Provisioned by init-db.sh (first boot of an empty PGDATA) or ./dev.sh create-db")
	}

	// Create the seed DB from template_statbus. CREATE DATABASE is autocommit
	// (runPsql does not wrap statements in a transaction).
	fmt.Printf("Creating empty seed database from template_statbus: %s\n", dbName)
	if err := migrate.ExecOnDB(projDir, "postgres",
		fmt.Sprintf("CREATE DATABASE %s WITH TEMPLATE template_statbus OWNER postgres;", dbName)); err != nil {
		return fmt.Errorf("create seed database from template_statbus: %w", err)
	}

	// Per-database auth schema + grants. Cluster roles already exist (init-db.sh);
	// the auth schema + USAGE grants are per-DB and absent from template_statbus.
	// Mirrors create-test-template / dev.sh:create-seed.
	fmt.Println("Setting up schemas and grants for seed...")
	if err := migrate.ExecOnDB(projDir, dbName,
		"CREATE SCHEMA IF NOT EXISTS auth;\n"+
			"GRANT USAGE ON SCHEMA auth TO authenticated;\n"+
			"GRANT USAGE ON SCHEMA auth TO anon;\n"+
			"GRANT USAGE ON SCHEMA public TO notify_reader;\n"); err != nil {
		return fmt.Errorf("set up seed auth schema + grants: %w", err)
	}

	fmt.Printf("Seed database created (empty): %s\n", dbName)
	fmt.Println("  Apply migrations next: ./sb migrate up --target seed")
	return nil
}

// DumpSeed is the dump-only core: it dumps ${POSTGRES_SEED_DB} to
// .db-seed/seed.pg_dump + writes .db-seed/seed.json, and does NOT touch git.
// It backs `./sb db seed dump` and is the reusable body CreateSeed builds on.
// The hermetic seed-builder image stage calls it (DOCKER_PSQL=0 host-psql; the
// build tree is COPYed in without a .git, so it passes --commit).
//
// commitOverride supplies seed.json's CommitSHA when projDir has no .git: a real
// .git (dev/release) wins via `git rev-parse`/`git tag`; otherwise commitOverride
// is used and Tags are empty. Returns the metadata it wrote so CreateSeed's
// publish tail reuses it without re-reading seed.json.
//
// Per plan section R commit 4: dumps from `${POSTGRES_SEED_DB}` (the canonical
// fresh-from-migrations baseline), NOT from `${POSTGRES_APP_DB}` (the runtime
// dev DB which is contaminable by definition).
func DumpSeed(projDir, commitOverride string) (seedMeta, error) {
	// Verify the database is reachable — we need it for pg_dump and the
	// migration version query. Connection-agnostic (QueryDB → PsqlCommand)
	// so this works under DOCKER_PSQL=0 in the hermetic seed-builder, where
	// the docker-compose-based dbIsRunning would false-negative.
	if _, err := migrate.QueryDB(projDir, "postgres", "SELECT 1", "-t", "-A"); err != nil {
		return seedMeta{}, fmt.Errorf("database is not reachable — start it with 'sb start all': %w", err)
	}

	dbName, err := loadSeedDbName(projDir)
	if err != nil {
		return seedMeta{}, fmt.Errorf("load seed DB name: %w", err)
	}

	// Verify the seed DB exists. If not, point the operator at the
	// recovery primitive — don't silently dump from somewhere else.
	seedExistsOut, _ := migrate.QueryDB(projDir, "postgres",
		fmt.Sprintf("SELECT 1 FROM pg_database WHERE datname = '%s'", dbName),
		"-t", "-A")
	if seedExistsOut != "1" {
		return seedMeta{}, fmt.Errorf("seed database %q does not exist.\n"+
			"  Build it first: ./dev.sh recreate-seed\n"+
			"  Or run: ./sb db seed sync (recreate-seed + db seed create)",
			dbName)
	}

	// Get the latest migration version from the database.
	// This tells us exactly what schema state the seed captures.
	migrationVersion, err := migrate.QueryDB(projDir, dbName,
		"SELECT version FROM db.migration ORDER BY version DESC LIMIT 1",
		"-t", "-A")
	if err != nil {
		return seedMeta{}, fmt.Errorf("query migration version: %w\n%s", err, migrationVersion)
	}
	if migrationVersion == "" {
		return seedMeta{}, fmt.Errorf("no migrations found in db.migration table")
	}

	// Commit + tags for seed.json. Prefer git (dev/release contexts where a
	// .git is present); fall back to --commit when there is no .git — the
	// hermetic seed-builder image build COPYs the project tree in WITHOUT a
	// .git directory, so `git rev-parse` would fail there. Never hard-fail on
	// a missing .git: the image build is a supported caller.
	commitSHA := strings.TrimSpace(commitOverride)
	var tags string
	if gitOut, gitErr := upgrade.RunCommandOutput(projDir, "git", "rev-parse", "HEAD"); gitErr == nil {
		commitSHA = strings.TrimSpace(gitOut)
		tagsOut, _ := upgrade.RunCommandOutput(projDir, "git", "tag", "--points-at", "HEAD")
		tags = strings.TrimSpace(tagsOut)
	}
	if commitSHA == "" {
		return seedMeta{}, fmt.Errorf("no commit for seed.json: %s is not a git repo and --commit was not provided", projDir)
	}

	// Compute post_restore.sql fingerprint so seed.json carries the
	// "what fixups will the next restore apply" identity. `./sb db seed
	// sync` uses this together with migration_version to decide whether
	// the new schema state actually differs from what's already on
	// db-seed (fast-path) or needs a full pg_dump rebuild.
	postRestoreSHA, err := postRestoreFileSHA(projDir)
	if err != nil {
		return seedMeta{}, fmt.Errorf("hash post_restore.sql: %w", err)
	}

	seedDir := filepath.Join(projDir, ".db-seed")
	if err := os.MkdirAll(seedDir, 0755); err != nil {
		return seedMeta{}, fmt.Errorf("create .db-seed directory: %w", err)
	}

	// Dump the database in custom format (compact, supports parallel restore).
	// Exclude auth.secrets — those contain per-deployment JWT secrets that
	// must not leak into the shared seed branch.
	fmt.Printf("Dumping %s ...\n", dbName)
	dumpPath := filepath.Join(seedDir, "seed.pg_dump")
	dumpFile, err := os.Create(dumpPath)
	if err != nil {
		return seedMeta{}, fmt.Errorf("create dump file: %w", err)
	}

	pgDumpPath, pgDumpPrefix, pgDumpEnv, err := migrate.PgDumpCommand(projDir)
	if err != nil {
		dumpFile.Close()
		os.Remove(dumpPath)
		return seedMeta{}, fmt.Errorf("resolve pg_dump command: %w", err)
	}
	dumpArgs := append(append([]string{}, pgDumpPrefix...),
		"-U", "postgres", "-Fc", "--no-owner",
		"--exclude-table-data=auth.secrets",
		dbName)
	dumpCmd := exec.Command(pgDumpPath, dumpArgs...)
	dumpCmd.Dir = projDir
	dumpCmd.Env = pgDumpEnv
	dumpCmd.Stdout = dumpFile
	dumpCmd.Stderr = os.Stderr

	if err := dumpCmd.Run(); err != nil {
		dumpFile.Close()
		os.Remove(dumpPath)
		return seedMeta{}, fmt.Errorf("pg_dump failed: %w", err)
	}
	dumpFile.Close()

	info, err := os.Stat(dumpPath)
	if err != nil {
		return seedMeta{}, err
	}
	if info.Size() == 0 {
		os.Remove(dumpPath)
		return seedMeta{}, fmt.Errorf("pg_dump produced an empty file — check database connectivity")
	}

	// Write metadata JSON alongside the dump.
	meta := seedMeta{
		MigrationVersion: migrationVersion,
		PostRestoreSHA:   postRestoreSHA,
		CommitSHA:        commitSHA,
		Tags:             tags,
		CreatedAt:        time.Now().UTC().Format(time.RFC3339),
	}
	metaJSON, err := json.MarshalIndent(meta, "", "  ")
	if err != nil {
		return seedMeta{}, fmt.Errorf("marshal seed.json: %w", err)
	}
	jsonPath := filepath.Join(seedDir, "seed.json")
	if err := os.WriteFile(jsonPath, metaJSON, 0644); err != nil {
		return seedMeta{}, fmt.Errorf("write seed.json: %w", err)
	}

	fmt.Printf("Seed dumped: migration %s, commit %s (%s)\n",
		migrationVersion, shortCommit(commitSHA), humanSize(info.Size()))
	return meta, nil
}

// CreateSeed dumps the seed (DumpSeed) and then PUBLISHES it to the db-seed git
// branch (+ the per-commit pin). Exposed so the release-prerelease preflight
// (cli/cmd/release.go) can invoke the same regen+publish path in-process.
//
// The publish tail is on death row: once install + dev read the seed from the
// commit-tagged image (the seed-consume phase), the git-publish path is deleted
// wholesale and `create` collapses to `dump`. Until then `./sb db seed create`
// keeps the legacy db-seed-branch behavior.
//
// Operator workflow:
//   1. ./dev.sh recreate-seed          # rebuild the seed from migrations
//   2. ./sb db seed create             # dump it; push to origin/db-seed
// or composite:
//   ./dev.sh update-seed
func CreateSeed(projDir string) error {
	// .git is present in the dev/release contexts that publish, so DumpSeed's
	// git rev-parse wins and the "" override is unused here.
	meta, err := DumpSeed(projDir, "")
	if err != nil {
		return err
	}
	migrationVersion := meta.MigrationVersion
	commitSHA := meta.CommitSHA
	seedDir := filepath.Join(projDir, ".db-seed")

	// Sweep stale peer `seed/<sha>` branches BEFORE publishing the
	// new one. Unified gate in cleanupSeedBranches (defined in
	// release.go): delete untagged ephemeral peers, delete tagged
	// peers whose release is fully published (canonical store = GH
	// release assets), retain tagged in-flight peers. preserveSHA is
	// the project commit the new seed pins to — so the cleanup
	// never touches the slot we're about to write.
	cleanupSeedBranches(projDir, commitSHA)

	// Push to the db-seed branch using a git worktree.
	worktreePath, err := ensureSeedWorktree(projDir)
	if err != nil {
		return err
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
	if addOut, err := upgrade.RunCommandOutput(worktreePath, "git", "add", "seed.pg_dump", "seed.json"); err != nil {
		return fmt.Errorf("git add in worktree: %w\n  output: %s", err, strings.TrimSpace(addOut))
	}

	commitMsg := fmt.Sprintf("seed: migration %s (commit %s)", migrationVersion, shortCommit(commitSHA))
	if commitOut, err := upgrade.RunCommandOutput(worktreePath, "git", "commit", "--allow-empty", "-m", commitMsg); err != nil {
		return fmt.Errorf("git commit in worktree: %w\n  output: %s", err, strings.TrimSpace(commitOut))
	}

	if pushOut, err := upgrade.RunCommandOutput(worktreePath, "git", "push", "origin", "db-seed", "--force"); err != nil {
		return fmt.Errorf("git push --force db-seed: %w\n  output: %s", err, strings.TrimSpace(pushOut))
	}

	fmt.Printf("Seed created and pushed (migration %s, commit %s)\n", migrationVersion, shortCommit(commitSHA))

	// Publish the per-commit pin so release.yaml's "Fetch seed assets"
	// step can read seed.pg_dump + seed.json from this exact project
	// SHA's tree (.github/workflows/release.yaml does
	// `git fetch origin seed/${GITHUB_SHA:0:8}` and `git checkout
	// FETCH_HEAD -- seed.pg_dump seed.json`).
	if err := publishSeedPinBranch(worktreePath, commitSHA); err != nil {
		return err
	}
	return nil
}

// shortCommit truncates a commit SHA to the canonical short length (seedSHALen)
// for display + branch naming, tolerating an already-short value such as a
// --commit commit_short passed by the hermetic image build.
func shortCommit(s string) string {
	if len(s) > seedSHALen {
		return s[:seedSHALen]
	}
	return s
}

// ensureSeedWorktree returns the path to the `db-seed` git worktree,
// creating it if absent.
//
// DWIM order:
//  1. If the worktree directory already exists, reuse it.
//  2. Try `git worktree add <path> db-seed` — succeeds when local
//     `db-seed` exists OR git can auto-track `origin/db-seed`.
//  3. Fall back to `git worktree add --orphan -b db-seed <path>` for
//     the first-time bootstrap where neither local nor remote ref
//     exists yet.
//
// The worktree lives outside projDir so the parent repo's working tree
// + index stay untouched. The orphan branch has no parents — db-seed
// is a cache; history is meaningless.
//
// Extracted from CreateSeed in #133 so the seed-sync fast-path can
// reuse the same DWIM tree without duplicating ~30 lines of glue.
func ensureSeedWorktree(projDir string) (string, error) {
	worktreePath := filepath.Join(filepath.Dir(projDir), "statbus-db-seed")

	if _, err := os.Stat(worktreePath); err == nil {
		return worktreePath, nil
	}

	addOut, addErr := upgrade.RunCommandOutput(projDir, "git", "worktree", "add", worktreePath, "db-seed")
	if addErr == nil {
		return worktreePath, nil
	}
	// Branch doesn't exist locally and no remote-tracking ref to DWIM
	// from — create an orphan worktree with a new branch. Git 2.x
	// requires `-b <name>` for orphan; a trailing branch arg would be
	// parsed as a (forbidden) commit-ish.
	orphanOut, orphanErr := upgrade.RunCommandOutput(projDir, "git", "worktree", "add", "--orphan", "-b", "db-seed", worktreePath)
	if orphanErr != nil {
		return "", fmt.Errorf(
			"git worktree add db-seed failed in both attempts:\n"+
				"  attempt 1 (track existing branch / DWIM origin/db-seed): %v\n"+
				"    output: %s\n"+
				"  attempt 2 (orphan -b db-seed): %v\n"+
				"    output: %s",
			addErr, strings.TrimSpace(addOut),
			orphanErr, strings.TrimSpace(orphanOut),
		)
	}
	return worktreePath, nil
}

// publishSeedPinBranch creates a `seed/<commitSHA[:seedSHALen]>` branch
// at the worktree's current HEAD (i.e. the commit on db-seed that
// carries the seed.pg_dump + seed.json bytes we just pushed) and
// force-with-lease-pushes it to origin.
//
// The branch carries CONTENT (not a marker): release.yaml does
// `git fetch origin seed/${SHORT_SHA}` + `git checkout FETCH_HEAD --
// seed.pg_dump seed.json` (.github/workflows/release.yaml:235-236).
// A content-less marker would break the workflow's checkout step.
//
// Idempotent at the project-SHA level: re-running for the same project
// SHA replaces the local branch (`-f`) and force-with-lease-pushes the
// updated ref (cleanupSeedBranches typically leaves the slot empty;
// the lease is the safety net for the abort-and-retry case where
// remote and local diverge mid-run).
//
// Extracted from CreateSeed in #133 so the seed-sync fast-path can
// reuse the same publish step.
func publishSeedPinBranch(worktreePath, commitSHA string) error {
	seedCommit, err := upgrade.RunCommandOutput(worktreePath, "git", "rev-parse", "HEAD")
	if err != nil {
		return fmt.Errorf("git rev-parse HEAD in worktree: %w", err)
	}
	seedCommit = strings.TrimSpace(seedCommit)
	branchName := "seed/" + commitSHA[:seedSHALen]

	if branchOut, err := upgrade.RunCommandOutput(worktreePath, "git", "branch", "-f", branchName, seedCommit); err != nil {
		return fmt.Errorf("git branch %s: %w\n  output: %s", branchName, err, strings.TrimSpace(branchOut))
	}
	if pushOut, err := upgrade.RunCommandOutput(worktreePath, "git", "push", "origin", "--force-with-lease", branchName); err != nil {
		return fmt.Errorf("git push origin %s: %w\n  output: %s", branchName, err, strings.TrimSpace(pushOut))
	}
	fmt.Printf("Seed pinned: %s → %s\n", branchName, seedCommit[:8])
	return nil
}

// postRestoreFileSHA returns the lowercase-hex sha256 of
// migrations/post_restore.sql. The seed lifecycle stores this in
// seed.json so `./sb db seed sync` can detect when post_restore.sql
// has been edited and force a fresh pg_dump — without this fingerprint
// a post_restore edit that doesn't bump migration_version would
// silently ship a stale dump.
func postRestoreFileSHA(projDir string) (string, error) {
	path := filepath.Join(projDir, "migrations", "post_restore.sql")
	data, err := os.ReadFile(path)
	if err != nil {
		return "", fmt.Errorf("read %s: %w", path, err)
	}
	sum := sha256.Sum256(data)
	return hex.EncodeToString(sum[:]), nil
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

	seedDumpCmd.Flags().StringVar(&seedDumpCommit, "commit", "",
		"commit SHA to stamp into seed.json when projDir has no .git (e.g. the hermetic image build)")

	seedCmd.AddCommand(seedFetchCmd)
	seedCmd.AddCommand(seedRestoreCmd)
	seedCmd.AddCommand(seedCreateCmd)
	seedCmd.AddCommand(seedDumpCmd)
	seedCmd.AddCommand(seedCreateDbCmd)
	seedCmd.AddCommand(seedStatusCmd)

	dbCmd.AddCommand(seedCmd)
}

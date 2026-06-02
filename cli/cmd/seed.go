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
	"github.com/statisticsnorway/statbus/cli/internal/dotenv"
	"github.com/statisticsnorway/statbus/cli/internal/migrate"
	"github.com/statisticsnorway/statbus/cli/internal/upgrade"
)

// seedMeta is the JSON structure stored in .db-seed/seed.json.
// It records which migration and commit the seed covers, so callers
// can decide whether the seed is fresh enough to use.
//
// PostRestoreSHA captures the sha256 of migrations/post_restore.sql at
// the time the seed was produced. Combined with MigrationVersion it
// forms the "did the schema-after-restore actually change" fingerprint
// recorded in seed.json so a post_restore.sql edit that doesn't bump
// migration_version is still detectable as a content change.
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
	Long: `Manage the pg_dump seed shipped as the statbus-seed:<commit_short> image.

A seed lets a fresh install / dev box skip running ~294 migrations and
instead pg_restore a single dump file (~2 seconds). CI (images.yaml)
builds and publishes the seed image on every master push — the same way
the service images are tagged and pulled by commit_short.

Subcommands:
  fetch     Download seed from the published statbus-seed:<commit_short> image
  restore   Restore seed into a database via pg_restore
  dump      Dump statbus_seed to .db-seed/ (the dump CI bakes into the image)
  create-db Create statbus_seed from template_statbus (build primitive)
  status    Compare seed version to latest migration`,
}

// ── seed fetch ──────────────────────────────────────────────────────────────

// seedFetchCmd downloads the DB seed from the published seed image
// `ghcr.io/statisticsnorway/statbus-seed:<commit_short>` — the same
// commit-tagged image, built and pushed by CI (images.yaml) on every
// master push, that the five service images are pulled from. The seed
// is a pg_dump that speeds up DB creation from ~294 migrations to one
// pg_restore (~2 seconds). Auto-called by dev.sh and `./sb install` on
// first run.
//
// The image is `FROM scratch` (no shell), so it cannot be `docker run`;
// the only way to read its files is `docker create` + `docker cp` (see
// extractSeedFromImage). On any failure — commit_short unresolved, no
// image published for this commit, or a daemon error — fetch returns an
// error so the caller (install's runSeedRestore, dev.sh) falls back to
// running all migrations.
var seedFetchCmd = &cobra.Command{
	Use:   "fetch",
	Short: "Fetch seed from the published statbus-seed image",
	RunE: func(cmd *cobra.Command, args []string) error {
		projDir := config.ProjectDir()
		seedDir := filepath.Join(projDir, ".db-seed")

		commitShort := resolveSeedCommitShort(projDir)
		if commitShort == "" {
			return fmt.Errorf("cannot resolve commit_short for the seed image " +
				"(COMMIT_SHORT unset or 'local', and git rev-parse unavailable); " +
				"no published seed image to fetch")
		}
		imageRef := "ghcr.io/statisticsnorway/statbus-seed:" + commitShort

		if err := os.MkdirAll(seedDir, 0755); err != nil {
			return fmt.Errorf("create .db-seed directory: %w", err)
		}

		// Pull the seed image. Uses the same docker daemon auth context as
		// `docker compose pull` for the service images — no new auth surface.
		fmt.Printf("Pulling seed image %s...\n", imageRef)
		if out, err := upgrade.RunCommandOutput(projDir, "docker", "pull", imageRef); err != nil {
			return fmt.Errorf("pull seed image %s: %w\n  %s", imageRef, err, strings.TrimSpace(out))
		}

		// Copy /seed.pg_dump + /seed.json out of the scratch image.
		if err := extractSeedFromImage(projDir, imageRef, seedDir); err != nil {
			return err
		}

		// Read migration version from the metadata to confirm success.
		meta, err := loadSeedMeta(projDir)
		if err != nil {
			return fmt.Errorf("parse seed.json: %w", err)
		}

		fmt.Printf("Seed fetched from image: migration %s\n", meta.MigrationVersion)
		return nil
	},
}

// resolveSeedCommitShort returns the 8-char commit_short used to tag the
// seed image. It prefers COMMIT_SHORT from the generated .env (the exact
// value `docker compose pull` uses for the service images), and falls
// back to `git rev-parse --short=8 HEAD` for clean checkouts that have
// not run `./sb config generate` yet. Returns "" when it cannot resolve
// to a real published tag — empty, or the `local` dev sentinel (compose's
// `${COMMIT_SHORT:-local}`), neither of which has a published image.
func resolveSeedCommitShort(projDir string) string {
	if f, err := dotenv.Load(filepath.Join(projDir, ".env")); err == nil {
		if v, ok := f.Get("COMMIT_SHORT"); ok {
			v = strings.TrimSpace(v)
			if v != "" && v != "local" {
				return v
			}
		}
	}
	if out, err := upgrade.RunCommandOutput(projDir, "git", "rev-parse", "--short=8", "HEAD"); err == nil {
		if v := strings.TrimSpace(out); v != "" && v != "local" {
			return v
		}
	}
	return ""
}

// extractSeedFromImage copies /seed.pg_dump and /seed.json out of the
// `FROM scratch` seed image into seedDir. A scratch image has no shell,
// so `docker run cat` is impossible — `docker create` (no start) +
// `docker cp` is the only extraction path. The container is removed via
// defer so a failed cp still cleans it up.
//
// The trailing "noop" arg is required: `docker create` refuses an image
// with no command, and the seed image is FROM scratch with no
// CMD/ENTRYPOINT (postgres/Dockerfile:525-529). The container is never
// started, so the placeholder command is never executed.
func extractSeedFromImage(projDir, imageRef, seedDir string) error {
	out, err := upgrade.RunCommandOutput(projDir, "docker", "create", imageRef, "noop")
	if err != nil {
		return fmt.Errorf("docker create %s: %w\n  %s", imageRef, err, strings.TrimSpace(out))
	}
	cid := strings.TrimSpace(out)
	if cid == "" {
		return fmt.Errorf("docker create %s returned an empty container id", imageRef)
	}
	defer func() {
		if _, rmErr := upgrade.RunCommandOutput(projDir, "docker", "rm", cid); rmErr != nil {
			fmt.Fprintf(os.Stderr, "WARN: docker rm %s (seed extraction container) failed: %v\n", cid, rmErr)
		}
	}()

	for _, f := range []struct{ src, dst string }{
		{"/seed.pg_dump", filepath.Join(seedDir, "seed.pg_dump")},
		{"/seed.json", filepath.Join(seedDir, "seed.json")},
	} {
		if out, err := upgrade.RunCommandOutput(projDir, "docker", "cp", cid+":"+f.src, f.dst); err != nil {
			return fmt.Errorf("docker cp %s:%s -> %s: %w\n  %s", cid, f.src, f.dst, err, strings.TrimSpace(out))
		}
	}
	return nil
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

// ── seed dump ───────────────────────────────────────────────────────────────

// seedDumpCmd writes .db-seed/seed.pg_dump + seed.json from the current
// statbus_seed database — the dump CI bakes into the published seed image.
// The hermetic seed-builder image stage calls this; the build tree has no
// .git, so pass --commit so seed.json carries the right commit.
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
// It backs `./sb db seed dump`. The hermetic seed-builder image stage calls it
// (DOCKER_PSQL=0 host-psql; the build tree is COPYed in without a .git, so it
// passes --commit), and the resulting files become the published seed image.
//
// commitOverride supplies seed.json's CommitSHA when projDir has no .git: a real
// .git (dev/release) wins via `git rev-parse`/`git tag`; otherwise commitOverride
// is used and Tags are empty. Returns the metadata it wrote.
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
			"  Build it first: ./dev.sh recreate-seed",
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

// shortCommit truncates a commit SHA to the canonical 8-char commit_short
// length for human-readable seed.json display, tolerating an already-short
// value such as a --commit commit_short passed by the hermetic image build.
func shortCommit(s string) string {
	if len(s) > 8 {
		return s[:8]
	}
	return s
}

// postRestoreFileSHA returns the lowercase-hex sha256 of
// migrations/post_restore.sql. The seed build stores this in seed.json so a
// post_restore.sql edit that doesn't bump migration_version still forces a
// fresh pg_dump — without this fingerprint such an edit would silently ship
// a stale dump.
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
	seedCmd.AddCommand(seedDumpCmd)
	seedCmd.AddCommand(seedCreateDbCmd)
	seedCmd.AddCommand(seedStatusCmd)

	dbCmd.AddCommand(seedCmd)
}

// Package migrate handles database schema migrations.
//
// Migrations live in migrations/ as pairs of YYYYMMDDHHMMSS_description.(up|down).(sql|psql).
// Applied migrations are tracked in db.migration table.
// Ported from Crystal cli/src/migrate.cr.
package migrate

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/statisticsnorway/statbus/cli/internal/config"
	"github.com/statisticsnorway/statbus/cli/internal/dotenv"
	"github.com/statisticsnorway/statbus/cli/internal/inject"
	"github.com/statisticsnorway/statbus/cli/internal/release"
)

// MigrationFile represents a parsed migration filename.
type MigrationFile struct {
	Version     int64
	Path        string
	Description string
	IsUp        bool
	Extension   string // "sql" or "psql"
}

// filenameRegex parses: YYYYMMDDHHMMSS_description.(up|down).(sql|psql)
var filenameRegex = regexp.MustCompile(`^(\d{14})_([^0-9].+)\.(up|down)\.(sql|psql)$`)

// parseMigrationFile extracts version, description, direction, extension from a migration path.
func parseMigrationFile(path string) (*MigrationFile, error) {
	base := filepath.Base(path)
	m := filenameRegex.FindStringSubmatch(base)
	if m == nil {
		return nil, fmt.Errorf("invalid migration filename: %s (expected YYYYMMDDHHMMSS_description.(up|down).sql)", base)
	}

	version, err := strconv.ParseInt(m[1], 10, 64)
	if err != nil {
		return nil, fmt.Errorf("invalid version in %s: %w", base, err)
	}

	// Validate timestamp format
	if _, err := time.Parse("20060102150405", m[1]); err != nil {
		return nil, fmt.Errorf("invalid timestamp in %s: %w", base, err)
	}

	return &MigrationFile{
		Version:     version,
		Path:        path,
		Description: m[2],
		IsUp:        m[3] == "up",
		Extension:   m[4],
	}, nil
}

// useDockerPsql determines whether to use docker compose exec for psql.
// DOCKER_PSQL=1/true forces docker mode. DOCKER_PSQL=0/false forces host mode.
// Otherwise auto-detects: host psql if available, docker fallback if not.
func useDockerPsql() bool {
	if v := os.Getenv("DOCKER_PSQL"); v != "" {
		return v == "1" || v == "true"
	}
	_, err := exec.LookPath("psql")
	return err != nil // use docker if psql not on host
}

// PsqlCommand returns the command path, arg prefix, and environment for running psql.
// Auto-detects host psql vs docker compose exec, with DOCKER_PSQL env override.
func PsqlCommand(projDir string) (psqlPath string, prefixArgs []string, env []string, err error) {
	if useDockerPsql() {
		f, loadErr := dotenv.Load(filepath.Join(projDir, ".env"))
		if loadErr != nil {
			return "", nil, nil, fmt.Errorf("load .env for docker psql: %w", loadErr)
		}
		// Process env overrides .env file — allows PGDATABASE=... ./sb migrate up
		getOr := func(key, fallback string) string {
			if v := os.Getenv(key); v != "" {
				return v
			}
			if v, ok := f.Get(key); ok {
				return v
			}
			return fallback
		}
		user := getOr("POSTGRES_ADMIN_USER", "postgres")
		// PGDATABASE env (operator-standard) wins over POSTGRES_APP_DB (.env default).
		// Matches psql's own resolution: `-d <flag>` > PGDATABASE > defaults.
		// User-supplied `-d` in args appears AFTER this prefix's `-d` so psql's
		// last-wins behaviour preserves the explicit override.
		db := os.Getenv("PGDATABASE")
		if db == "" {
			db = getOr("POSTGRES_APP_DB", "statbus_local")
		}
		return "docker", []string{"compose", "exec", "-T", "-w", "/statbus", "db", "psql", "-U", user, "-d", db}, nil, nil
	}

	hostPath, err := exec.LookPath("psql")
	if err != nil {
		return "", nil, nil, fmt.Errorf("psql not found on host and docker fallback disabled: %w", err)
	}
	hostEnv, err := psqlEnv(projDir)
	if err != nil {
		return "", nil, nil, err
	}
	return hostPath, nil, hostEnv, nil
}

// PgDumpCommand returns the command path, arg prefix, and environment for
// running pg_dump — the pg_dump analogue of PsqlCommand. It exists so seed
// creation can run inside the hermetic seed-builder image (DOCKER_PSQL=0,
// no docker-compose) against a local pg_dump, while the dev/compose path is
// unchanged. DOCKER_PSQL governs host-vs-docker identically to PsqlCommand:
//   - docker mode: `docker compose exec -T db pg_dump ...` (runs inside the
//     db container; connects over the local socket — env is nil).
//   - host mode: pg_dump on PATH with PG* env from .env (PGHOST/PGPORT/
//     PGUSER/PGPASSWORD/PGSSLMODE via psqlEnv).
//
// Callers append their own flags + target dbname after the prefix and set
// cmd.Stdout (the custom-format dump is binary) + cmd.Dir = projDir + cmd.Env.
func PgDumpCommand(projDir string) (cmdPath string, prefixArgs []string, env []string, err error) {
	if useDockerPsql() {
		return "docker", []string{"compose", "exec", "-T", "db", "pg_dump"}, nil, nil
	}
	hostPath, err := exec.LookPath("pg_dump")
	if err != nil {
		return "", nil, nil, fmt.Errorf("pg_dump not found on host and docker fallback disabled: %w", err)
	}
	hostEnv, err := psqlEnv(projDir)
	if err != nil {
		return "", nil, nil, err
	}
	return hostPath, nil, hostEnv, nil
}

// PgRestoreCommand returns the command path, arg prefix, and environment for
// running pg_restore — the pg_restore analogue of PgDumpCommand (pg_restore lives
// beside pg_dump in the same bin/prefix). It exists so the incremental seed build
// can restore a prior seed dump INSIDE the hermetic seed-builder stage
// (DOCKER_PSQL=0, host pg_restore, no docker-compose) — the compose-based
// restoreVerifyDB path does not work there (STATBUS-116 AC#1, Step 3b). DOCKER_PSQL
// governs host-vs-docker identically to PgDumpCommand:
//   - docker mode: `docker compose exec -T db pg_restore ...` (runs inside the
//     db container; connects over the local socket — env is nil).
//   - host mode: pg_restore on PATH with PG* env from .env (via psqlEnv).
//
// Callers append their own flags + `-d <dbname>` after the prefix, set cmd.Stdin
// to the dump, cmd.Dir = projDir, and cmd.Env. Wrap in runPgRestoreAtomic for the
// --single-transaction atomic contract.
func PgRestoreCommand(projDir string) (cmdPath string, prefixArgs []string, env []string, err error) {
	if useDockerPsql() {
		return "docker", []string{"compose", "exec", "-T", "db", "pg_restore"}, nil, nil
	}
	hostPath, err := exec.LookPath("pg_restore")
	if err != nil {
		return "", nil, nil, fmt.Errorf("pg_restore not found on host and docker fallback disabled: %w", err)
	}
	hostEnv, err := psqlEnv(projDir)
	if err != nil {
		return "", nil, nil, err
	}
	return hostPath, nil, hostEnv, nil
}

// psqlEnv builds the environment for psql from .env file.
//
// Host/port come from CADDY_DB_BIND_ADDRESS + CADDY_DB_PORT (server-internal
// bind, e.g. 127.0.0.1 in private mode). Using SITE_DOMAIN here breaks on
// private-mode servers where Caddy binds :3014 only to loopback.
// Process env still wins (PGHOST=... ./sb migrate up) via the final env pass.
func psqlEnv(projDir string) ([]string, error) {
	envPath := filepath.Join(projDir, ".env")
	f, err := dotenv.Load(envPath)
	if err != nil {
		return nil, fmt.Errorf("load .env: %w", err)
	}

	requireKey := func(key string) (string, error) {
		if v, ok := f.Get(key); ok && v != "" {
			return v, nil
		}
		return "", fmt.Errorf("%s not found in .env — regenerate with: ./sb config generate", key)
	}
	// Process env overrides .env file — allows PGDATABASE=... ./sb migrate up
	getOr := func(key, fallback string) string {
		if v := os.Getenv(key); v != "" {
			return v
		}
		if v, ok := f.Get(key); ok {
			return v
		}
		return fallback
	}

	dbHost, err := requireKey("CADDY_DB_BIND_ADDRESS")
	if err != nil {
		return nil, err
	}
	dbPort, err := requireKey("CADDY_DB_PORT")
	if err != nil {
		return nil, err
	}

	// PGDATABASE env (operator-standard) wins over POSTGRES_APP_DB (.env default).
	// Note: in the appended env below, the LAST `PGDATABASE=...` entry wins
	// when exec.Command processes duplicates. Without this explicit override
	// the appended `PGDATABASE=<POSTGRES_APP_DB>` shadows any pre-existing
	// PGDATABASE in os.Environ(), silently ignoring the operator's intent.
	dbName := os.Getenv("PGDATABASE")
	if dbName == "" {
		dbName = getOr("POSTGRES_APP_DB", "statbus_local")
	}

	env := os.Environ()
	env = append(env,
		"PGHOST="+dbHost,
		"PGPORT="+dbPort,
		"PGDATABASE="+dbName,
		"PGUSER="+getOr("POSTGRES_ADMIN_USER", "postgres"),
		"PGPASSWORD="+getOr("POSTGRES_ADMIN_PASSWORD", ""),
		"PGSSLMODE=disable",
	)
	return env, nil
}

// runPsql executes a SQL string via psql. Returns stdout+stderr and any error.
func runPsql(projDir string, sql string, extraArgs ...string) (string, error) {
	psqlPath, prefix, env, err := PsqlCommand(projDir)
	if err != nil {
		return "", err
	}

	args := append(prefix, "-v", "ON_ERROR_STOP=on")
	args = append(args, extraArgs...)
	// STATBUS-110: exempt migrate's write sessions (ensureMigrationTable, the
	// db.migration bookkeeping INSERT) from the read-only upgrade window.
	args, env = injectReadOnlyExempt(psqlPath, args, env)
	cmd := exec.Command(psqlPath, args...)
	cmd.Dir = projDir
	cmd.Env = env
	cmd.Stdin = strings.NewReader(sql)

	out, err := cmd.CombinedOutput()
	return string(out), err
}

// QueryDB runs a SQL query against the named PostgreSQL database (overriding
// the default PGDATABASE), returning trimmed stdout. Used by release-side
// preflight probes that need to check state on a SPECIFIC database (e.g.,
// statbus_seed during the seed-stale gate) without requiring the caller to
// juggle PGDATABASE or POSTGRES_APP_DB env vars by hand.
//
// Note on side effects: this function MUTATES the process env (PGDATABASE +
// POSTGRES_APP_DB) for the duration of the call, then restores it via
// defer. It is NOT safe to call concurrently with another psql invocation
// in the same process — the runPsql infra reads psqlEnv at call time and
// would observe whichever env happened to be set last. The preflight call
// sites are strictly serial, so this is fine.
//
// extraArgs are appended to the psql invocation after -v ON_ERROR_STOP=on;
// callers can pass -t / -A / etc. The SQL is sent via stdin per the
// runPsql contract (avoids shell-quoting issues for embedded literals).
func QueryDB(projDir, dbName, sql string, extraArgs ...string) (string, error) {
	if dbName == "" {
		return "", fmt.Errorf("QueryDB: dbName must not be empty")
	}

	prevApp, hadApp := os.LookupEnv("POSTGRES_APP_DB")
	prevPG, hadPG := os.LookupEnv("PGDATABASE")
	os.Setenv("POSTGRES_APP_DB", dbName)
	os.Setenv("PGDATABASE", dbName)
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

	out, err := runPsql(projDir, sql, extraArgs...)
	if err != nil {
		return out, err
	}
	return strings.TrimSpace(out), nil
}

// ExecOnDB runs exec/DDL SQL against the named database — the exec analogue of
// QueryDB. Same PGDATABASE override + ON_ERROR_STOP=on + stdin delivery, but it
// discards stdout and returns only an error (folding psql's output into the
// error on failure). Use for CREATE/GRANT/ALTER where no result row is expected
// — e.g. the seed-DB creation lifted from dev.sh. Like QueryDB it MUTATES the
// process env for the duration of the call and is NOT concurrency-safe.
func ExecOnDB(projDir, dbName, sql string, extraArgs ...string) error {
	out, err := QueryDB(projDir, dbName, sql, extraArgs...)
	if err != nil {
		return fmt.Errorf("%w\n%s", err, out)
	}
	return nil
}

// runPsqlFile executes a SQL file via psql.
// migrateSubprocessAppNamePrefix tags the migration psql SUBPROCESS's backend
// application_name (task #14). The upgrade service, on a migrate TIMEOUT,
// pg_terminate_backend's the orphaned in-container backend by matching this
// prefix (LIKE 'statbus-migrate-sql%') — docker compose exec does NOT forward
// SIGKILL, so a host-side process-group kill of `./sb migrate` leaves the
// in-container psql alive with its transaction open and locks held (a
// commit-after-rollback consistency race). The terminate side matches by PREFIX
// (not exact pid): the terminate runs in the SERVICE process, which cannot know
// the migrate child's pid, and the upgrade-mutex serializes so only one such
// backend can exist. The pid suffix (below) is forensic/uniqueness only.
//
// Distinct from the Go advisory-lock conn's application_name
// ('statbus-migrate-<pid>', set in acquireAdvisoryLock) — that is a SEPARATE
// connection from the psql backend actually running the migration SQL.
// SubprocessAppNamePrefix is exported so the upgrade package's
// terminate-on-timeout (task #14) matches the SAME prefix this package tags
// with — single source of truth for `application_name LIKE 'statbus-migrate-sql%'`.
const SubprocessAppNamePrefix = "statbus-migrate-sql"

// migrateSubprocessAppNamePrefix is the internal alias used within this package.
const migrateSubprocessAppNamePrefix = SubprocessAppNamePrefix

// migrateSubprocessAppName returns the application_name for the migration psql
// subprocess: the match prefix + this process's pid (stable across all files in
// one `migrate up`; forensic only — the terminate side matches by prefix).
func migrateSubprocessAppName() string {
	return fmt.Sprintf("%s-%d", migrateSubprocessAppNamePrefix, os.Getpid())
}

// injectPsqlAppName tags the psql subprocess's backend application_name with
// appName, in whichever PsqlCommand mode is in use:
//   - host (psqlPath != "docker"): append PGAPPNAME=<appName> to env — psql
//     reads PGAPPNAME and sets the backend application_name. args untouched.
//   - docker (psqlPath == "docker"): the host process's env does NOT reach the
//     in-container psql, so pass it via `docker compose exec -e PGAPPNAME=<appName>`
//     — an exec OPTION, inserted right after the "exec" token so it precedes the
//     service name + command. env untouched (it's nil in docker mode).
//
// Pure (no I/O) so both modes are unit-testable.
func injectPsqlAppName(psqlPath string, args, env []string, appName string) ([]string, []string) {
	pgappEnv := "PGAPPNAME=" + appName
	if psqlPath != "docker" {
		return args, append(append([]string{}, env...), pgappEnv)
	}
	// docker compose exec: insert `-e PGAPPNAME=<appName>` immediately after the
	// "exec" token (an option position, before SERVICE + COMMAND).
	out := make([]string, 0, len(args)+2)
	inserted := false
	for i, a := range args {
		out = append(out, a)
		if !inserted && a == "exec" && i+1 < len(args) {
			out = append(out, "-e", pgappEnv)
			inserted = true
		}
	}
	if !inserted {
		// No "exec" token (unexpected shape) — prepend defensively so the flag
		// is still present rather than silently dropped.
		out = append([]string{"-e", pgappEnv}, args...)
	}
	return out, env
}

// migrateReadOnlyExemptOptions is the libpq `options` payload that makes a
// migrate psql session read-write even while the app DB is under the STATBUS-110
// read-only upgrade window (`ALTER DATABASE ... default_transaction_read_only=on`,
// set before the pre-backup DB stop). migrate is the upgrade's OWN writer
// (post-swap migrate, boot-migrate, forward-recovery), so its sessions MUST be
// exempt while EXTERNAL sessions stay blocked. Applied as a connection STARTUP
// option so the very first transaction is already read-write; a no-op when the
// window is inactive (off is the normal state). See doc/read-only-upgrade-window.md.
const migrateReadOnlyExemptOptions = "-c default_transaction_read_only=off"

// injectReadOnlyExempt injects the read-only-window self-exemption into a psql
// invocation, in whichever PsqlCommand mode is in use — mirroring
// injectPsqlAppName, because the host env does NOT reach the in-container psql:
//   - host (psqlPath != "docker"): append a PGOPTIONS env entry, MERGING with any
//     operator-set PGOPTIONS (last-wins over os.Environ()) so we don't clobber it.
//   - docker (psqlPath == "docker"): pass `-e PGOPTIONS=<...>` right after the
//     "exec" token (an option position, before SERVICE + COMMAND); env untouched.
//
// Scoped to migrate's WRITE runners (runPsql + runPsqlFile) — NOT PsqlCommand,
// which is shared with interactive `./sb psql` and install probes that must stay
// subject to the window (write-with-intent only). Harmless on read-only queries.
func injectReadOnlyExempt(psqlPath string, args, env []string) ([]string, []string) {
	opts := migrateReadOnlyExemptOptions
	if existing := os.Getenv("PGOPTIONS"); existing != "" {
		opts = existing + " " + opts
	}
	pgOptEnv := "PGOPTIONS=" + opts
	if psqlPath != "docker" {
		return args, append(append([]string{}, env...), pgOptEnv)
	}
	out := make([]string, 0, len(args)+2)
	inserted := false
	for i, a := range args {
		out = append(out, a)
		if !inserted && a == "exec" && i+1 < len(args) {
			out = append(out, "-e", pgOptEnv)
			inserted = true
		}
	}
	if !inserted {
		out = append([]string{"-e", pgOptEnv}, args...)
	}
	return out, env
}

func runPsqlFile(projDir string, filePath string) (string, error) {
	// Harness-only stall site: simulates a migration that runs longer
	// than the upgrade-service's WatchdogSec budget. When activated via
	// STATBUS_INJECT_AT=migration-slower-than-systemd-unit-timeout,
	// holds here until the harness removes
	// STATBUS_INJECT_STALL_UNTIL_REMOVED_FILE. Validates the Race B fix
	// in applyPostSwap's WATCHDOG=1 ticker (commit `e6df084b7`): with
	// the migrate subprocess blocked here, the parent upgrade-service
	// must keep the unit alive via its independent ticker, otherwise
	// systemd's WatchdogSec=120s fires and triggers a restart loop.
	// No-op in production. The hold runs BEFORE psql is invoked so
	// the harness sees a subprocess that has started but not yet
	// produced any output — same observable shape as a migration
	// stuck waiting on a DDL lock.
	inject.StallHere("migration-slower-than-systemd-unit-timeout")

	// Harness-only kill site (C6): simulates the OS / orchestrator
	// killing the process DURING a single migration's execution. Fires
	// AFTER the C12 stall (so a scenario activating one does not
	// shadow the other — STATBUS_INJECT_AT selects a single class,
	// only the matching primitive fires) and BEFORE the psql
	// subprocess is invoked. From the database's perspective the
	// migration's outer transaction is never opened, so there is
	// nothing to roll back; from the install state-machine's
	// perspective the kill produced the same shape as "subprocess
	// killed before completing": flag is whatever the prior step
	// stamped (PostSwap inside applyPostSwap), binary is the NEW
	// binary, db.migration max version UNCHANGED, no committed schema
	// changes from this migration. Recovery via the next install's
	// recoverFromFlag → resumePostSwap path re-enters applyPostSwap
	// and the migration applies cleanly (no leftover state to
	// conflict with). Drives scenario 3-postswap-mid-migration-kill.
	//
	// Placement rationale (mirrors the team-lead's spec for #144):
	// at the start of runPsqlFile is the cleanest single point that
	// covers every migration in the loop without adding a kill site
	// per call. runPsqlFile is also invoked from post_restore.sql and
	// Redo, but those paths run only outside an upgrade scenario; a
	// harness that activates this class is running an upgrade.
	inject.KillHere("killed-by-system-during-individual-migration-execution")

	psqlPath, prefix, env, err := PsqlCommand(projDir)
	if err != nil {
		return "", err
	}

	file, err := os.Open(filePath)
	if err != nil {
		return "", fmt.Errorf("open migration file: %w", err)
	}
	defer file.Close()

	args := append(prefix, "-v", "ON_ERROR_STOP=on")

	// #14: tag the psql backend's application_name so a migrate-timeout can
	// terminate the orphaned in-container backend (see migrateSubprocessAppName).
	// Host mode adds PGAPPNAME to env; docker mode adds `-e PGAPPNAME=` to the
	// exec args (the host env doesn't reach the in-container psql).
	args, env = injectPsqlAppName(psqlPath, args, env, migrateSubprocessAppName())

	// STATBUS-110: exempt this migration-file session from the read-only upgrade
	// window (the app DB is read-only during phase 3; migrate is the upgrade's own
	// writer). Mirrors the app-name injection's host/docker split.
	args, env = injectReadOnlyExempt(psqlPath, args, env)

	// Hardening belt for the DIRECT `./sb migrate up` CLI path (operator /
	// install) — that path runs runPsqlFile with NO outer timeout wrapper, so a
	// single hung statement (a CREATE INDEX wedged on a lock, a runaway query)
	// would run forever. Bound it with a generous 60-min ceiling. NOTE: on the
	// UPGRADE-SERVICE path this is belt-and-suspenders — there the migrate step
	// is already hard-bounded by the OUTER runCommandToLog (CommandContext 5min
	// boot / 30min resume + prepareCmd's process-group SIGKILL, which reaps this
	// psql child since it shares ./sb's process group). The #3 progress-gated
	// watchdog DEFERS during that outer call and relies on the outer bound, NOT
	// on this inner one. This 60-min ceiling is the ultimate backstop for the
	// unwrapped CLI invocation. (plan upgrade-resume-structural-whole.md)
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Minute)
	defer cancel()
	cmd := exec.CommandContext(ctx, psqlPath, args...)
	cmd.Dir = projDir
	cmd.Env = env

	// Mid-transaction inject (cell b — the GREEN control for the commit↔record
	// boundary). When the mid-tx class is active, splice a SQL pause into the
	// OUTER transaction that envelops the migration's statements: prepend an
	// outer BEGIN + the pause so the harness can SIGKILL the psql child AFTER
	// BEGIN, BEFORE COMMIT. The migration file's
	// own leading BEGIN becomes a warned no-op (a WARNING, not an error — so
	// ON_ERROR_STOP does not trip), and its END commits the single outer tx.
	// Env unset → MidTxPauseSQL returns "" → stdin is the unmodified file
	// (production no-op, byte-identical). See inject.MidTxPauseSQL.
	var stdin io.Reader = file
	if pause := inject.MidTxPauseSQL("killed-by-system-during-migration-tx-before-commit"); pause != "" {
		stdin = io.MultiReader(strings.NewReader("BEGIN;\n"+pause+"\n"), file)
	}
	cmd.Stdin = stdin

	out, err := cmd.CombinedOutput()
	if ctx.Err() == context.DeadlineExceeded {
		return string(out), fmt.Errorf("migration %s exceeded the 60-minute hard timeout (statement hung?): %w", filepath.Base(filePath), err)
	}
	return string(out), err
}

// listMigrationFiles returns sorted, de-duplicated migration files from projDir/migrations/.
// No database interaction; pure filesystem scan + parse.
func listMigrationFiles(projDir string) ([]*MigrationFile, error) {
	patterns := []string{
		filepath.Join(projDir, "migrations", "*.up.sql"),
		filepath.Join(projDir, "migrations", "*.up.psql"),
	}

	var files []string
	for _, p := range patterns {
		matches, _ := filepath.Glob(p)
		files = append(files, matches...)
	}

	var migrations []*MigrationFile
	for _, f := range files {
		mf, err := parseMigrationFile(f)
		if err != nil {
			return nil, err
		}
		migrations = append(migrations, mf)
	}
	sort.Slice(migrations, func(i, j int) bool {
		return migrations[i].Version < migrations[j].Version
	})

	seen := make(map[int64]string)
	for _, m := range migrations {
		if prev, ok := seen[m.Version]; ok {
			return nil, fmt.Errorf("duplicate migration version %d: %s and %s", m.Version, prev, filepath.Base(m.Path))
		}
		seen[m.Version] = filepath.Base(m.Path)
	}
	return migrations, nil
}

const ensureMigrationTableSQL = `
DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_tables WHERE schemaname = 'db' AND tablename = 'migration') THEN
    CREATE SCHEMA IF NOT EXISTS db;
    CREATE TABLE db.migration (
      id SERIAL PRIMARY KEY,
      version BIGINT NOT NULL,
      filename TEXT NOT NULL,
      description TEXT NOT NULL,
      applied_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      duration_ms INTEGER NOT NULL
    );
    CREATE INDEX migration_version_idx ON db.migration(version);
    ALTER TABLE db.migration ENABLE ROW LEVEL SECURITY;
    CREATE POLICY migration_authenticated_read ON db.migration FOR SELECT TO authenticated USING (true);
  END IF;
END $$;`

// listAppliedVersions queries db.migration for applied version numbers.
// When the table does not exist yet (fresh database), returns an empty map
// and no error — callers should treat "no recorded migrations" the same as
// "table missing", since both mean nothing has been applied.
func listAppliedVersions(projDir string) (map[int64]bool, error) {
	appliedOut, err := runPsql(projDir, "SELECT version FROM db.migration ORDER BY version", "-t", "-A")
	if err != nil {
		// Distinguish "table/schema doesn't exist yet" from real errors by looking at the message.
		// psql reports these as `ERROR: relation "db.migration" does not exist` or
		// `ERROR: schema "db" does not exist`. Both mean "no migrations yet applied".
		msg := err.Error()
		if strings.Contains(msg, "db.migration") && strings.Contains(msg, "does not exist") {
			return map[int64]bool{}, nil
		}
		if strings.Contains(msg, `schema "db" does not exist`) {
			return map[int64]bool{}, nil
		}
		return nil, fmt.Errorf("query applied migrations: %w", err)
	}
	applied := make(map[int64]bool)
	for _, line := range strings.Split(strings.TrimSpace(appliedOut), "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		v, err := strconv.ParseInt(line, 10, 64)
		if err == nil {
			applied[v] = true
		}
	}
	return applied, nil
}

// HasPending reports whether at least one migration file in projDir/migrations/
// has not been applied according to db.migration.
//
// Read-only: does NOT create the db.migration table if it is missing. When the
// table is absent, any migration files on disk count as pending, so a fresh
// database with migrations on disk returns true.
//
// Use this to decide whether ./sb install should run its Migrations step.
// Callers needing idempotent "apply everything pending" semantics should call
// Up() instead, which ensures the table exists and applies the migrations.
func HasPending(projDir string) (bool, error) {
	migrations, err := listMigrationFiles(projDir)
	if err != nil {
		return false, err
	}
	if len(migrations) == 0 {
		return false, nil
	}
	applied, err := listAppliedVersions(projDir)
	if err != nil {
		return false, err
	}
	for _, m := range migrations {
		if !applied[m.Version] {
			return true, nil
		}
	}
	return false, nil
}

// acquireAdvisoryLock opens a pgx connection and takes a session-scoped
// pg_advisory_lock keyed on `migrate_up`. Holds the lock for the duration
// the returned *pgx.Conn is kept open — callers MUST close it (typically
// via defer) to release the lock.
//
// Serializes every invocation that goes through migrate.Up(), including:
//   - direct CLI: `./sb migrate up`
//   - install's migrations step: install.go → migrate.Up
//   - upgrade service's executeUpgrade step: spawns `./sb migrate up` as
//     a subprocess, which also calls this acquire path
//
// Uses a separate connection from the psql subprocesses that run the
// actual migrations — the advisory lock serializes ACROSS connections by
// key, not by connection. No interference with migration execution.
//
// The lock auto-releases when the connection closes (graceful exit,
// crash, kill). No stale locks possible.
// advisoryLockConnStr builds the pgx connection string for the advisory-lock
// connection. Uses CADDY_DB_BIND_ADDRESS (server-internal bind), not
// SITE_DOMAIN — same rationale as psqlEnv.
func advisoryLockConnStr(f *dotenv.File) (string, error) {
	requireKey := func(key string) (string, error) {
		if v, ok := f.Get(key); ok && v != "" {
			return v, nil
		}
		return "", fmt.Errorf("%s not found in .env — regenerate with: ./sb config generate", key)
	}
	// Process env wins over .env file — matches psqlEnv's pattern.
	// Critical for `./sb migrate up --target seed` (and `migrate redo`)
	// where the env override must reach the lock connection so the
	// advisory lock is acquired against the same database the
	// migrations run against. Without env-awareness, `--target seed`
	// would migrate against statbus_seed but lock against
	// statbus_local — pg_advisory_lock is per-database, so the lock
	// wouldn't actually serialise concurrent invocations. Plan
	// section R commit 3.
	getOr := func(key, fallback string) string {
		if v := os.Getenv(key); v != "" {
			return v
		}
		if v, ok := f.Get(key); ok {
			return v
		}
		return fallback
	}
	dbHost, err := requireKey("CADDY_DB_BIND_ADDRESS")
	if err != nil {
		return "", err
	}
	dbPort, err := requireKey("CADDY_DB_PORT")
	if err != nil {
		return "", err
	}
	return fmt.Sprintf(
		"host=%s port=%s dbname=%s user=%s password=%s sslmode=disable",
		dbHost,
		dbPort,
		getOr("POSTGRES_APP_DB", "statbus_local"),
		getOr("POSTGRES_ADMIN_USER", "postgres"),
		getOr("POSTGRES_ADMIN_PASSWORD", ""),
	), nil
}

// AdminConnStr returns a pgx connection string for the admin user, built from
// the .env file in projDir. Uses CADDY_DB_BIND_ADDRESS (server-internal bind)
// for the host — safe for post-step-table operations where Caddy is guaranteed
// running. Callers: install.go post-completion ops (pgx), advisory lock.
func AdminConnStr(projDir string) (string, error) {
	envPath := filepath.Join(projDir, ".env")
	f, err := dotenv.Load(envPath)
	if err != nil {
		return "", fmt.Errorf("load .env: %w", err)
	}
	return advisoryLockConnStr(f)
}

func acquireAdvisoryLock(ctx context.Context, projDir string) (*pgx.Conn, error) {
	connStr, err := AdminConnStr(projDir)
	if err != nil {
		return nil, fmt.Errorf("build advisory lock conn string: %w", err)
	}
	conn, err := pgx.Connect(ctx, connStr)
	if err != nil {
		return nil, fmt.Errorf("connect for advisory lock: %w", err)
	}
	// Tag this session with our PID before acquiring the advisory lock.
	// install.cleanOrphanSessions uses application_name to distinguish a
	// living migrate.Up's parent connection (which can sit idle for many
	// minutes while psql subprocesses run a slow migration) from a zombie
	// session whose owning Go process died. Format: 'statbus-migrate-<pid>'.
	// The cleanup probes liveness via syscall.Kill(pid, 0); a healthy
	// migration's owner is alive and gets skipped, a killed migration's
	// owner is ESRCH and gets terminated.
	if _, tagErr := conn.Exec(ctx, fmt.Sprintf("SET application_name = 'statbus-migrate-%d'", os.Getpid())); tagErr != nil {
		conn.Close(ctx)
		return nil, fmt.Errorf("tag advisory lock connection: %w", tagErr)
	}
	// advisory lock objid: hashtext('migrate_up') = -1978276407
	// pg_advisory_lock blocks until acquired. Prints a hint after a short
	// wait so the operator knows what's going on if another migrate is
	// running.
	hintTimer := time.AfterFunc(2*time.Second, func() {
		fmt.Fprintln(os.Stderr, "Waiting for migrate lock (another ./sb migrate up or upgrade is running)...")
	})
	recursionHintTimer := time.AfterFunc(30*time.Second, func() {
		fmt.Fprintln(os.Stderr, "Still waiting for migrate lock — check for recursive ./sb migrate up calls (e.g. via dev.sh create-test-template).")
	})
	_, err = conn.Exec(ctx, "SELECT pg_advisory_lock(hashtext('migrate_up'))")
	hintTimer.Stop()
	recursionHintTimer.Stop()
	if err != nil {
		conn.Close(ctx)
		return nil, fmt.Errorf("acquire advisory lock: %w", err)
	}
	return conn, nil
}

// Up applies pending migrations.
// If migrateTo > 0, only apply up to that version.
// If all is false, apply only one pending migration.
func Up(projDir string, migrateTo int64, all bool, verbose bool) error {
	// Take the migrate advisory lock to prevent concurrent invocations from
	// racing on the db.migration bookkeeping table. The lock is released
	// BEFORE spawning the test-template rebuild so that the rebuild's own
	// `./sb migrate up` call can re-acquire it without self-deadlocking.
	ctx := context.Background()
	lockConn, err := acquireAdvisoryLock(ctx, projDir)
	if err != nil {
		return err
	}

	appliedCount, err := runUp(projDir, migrateTo, all, verbose)
	// Explicit close — do NOT defer. The template rebuild spawns
	// `dev.sh create-test-template` which calls `./sb migrate up`, which
	// tries to acquire the same lock. Holding it through the spawn causes
	// a self-deadlock (parent waits for child; child blocks on parent's lock).
	lockConn.Close(context.Background())
	if err != nil {
		return err
	}

	if appliedCount > 0 {
		maybeRebuildTestTemplate(projDir)
	}
	return nil
}

// runUp applies pending migrations and returns the number applied.
// It does NOT rebuild the test template — Up() does that after releasing the lock.
func runUp(projDir string, migrateTo int64, all bool, verbose bool) (int, error) {
	migrations, err := listMigrationFiles(projDir)
	if err != nil {
		return 0, err
	}

	if len(migrations) == 0 {
		fmt.Println("No up migrations found")
		return 0, nil
	}

	// Ensure migration table exists (side-effect belongs to Up, NOT HasPending).
	if _, err := runPsql(projDir, ensureMigrationTableSQL); err != nil {
		return 0, fmt.Errorf("ensure migration table: %w", err)
	}

	// Content-hash mismatch sweep — runs BEFORE the pending filter so it
	// catches in-place edits to migrations that are no longer pending.
	// Hard-fails on immutability violations (released-tag rows whose
	// file bytes have changed); emits a remediation error pointing at
	// `./sb migrate redo <version>` for WIP rows. Silent no-op on
	// legacy DBs that haven't yet applied the content_hash column
	// migration. See plan-rc.66 section R.
	if err := eagerContentHashCheck(projDir); err != nil {
		return 0, err
	}

	// Harness-only stall site: representative phase point inside
	// migrate.runUp where the upgrade is committed to running migrations
	// (eager content-hash check passed, about to query applied versions).
	// When activated via STATBUS_INJECT_AT, holds here until the harness
	// removes STATBUS_INJECT_STALL_UNTIL_REMOVED_FILE — long enough for a
	// concurrent ./sb install attempt to observe the active holder PID
	// and trip probe 2 (live-upgrade refusal). No-op in production.
	inject.StallHere("concurrent-install-attempted-during-migrate-up")

	applied, err := listAppliedVersions(projDir)
	if err != nil {
		return 0, err
	}

	// Filter pending
	var pending []*MigrationFile
	for _, m := range migrations {
		if applied[m.Version] {
			continue
		}
		if migrateTo > 0 && m.Version > migrateTo {
			continue
		}
		pending = append(pending, m)
	}

	if !all && len(pending) > 1 {
		pending = pending[:1]
	}

	// Apply pending migrations (may be empty — post_restore still needs to run).
	appliedCount := 0
	if len(pending) == 0 {
		fmt.Println("All migrations are up to date")
	}
	// Track whether the content_hash column exists. Initially false
	// before the column-add migration applies; flips to true the moment
	// it does. Re-probe ONLY while we still think it's false — once the
	// column exists we don't pay for redundant probes.
	hasContentHash, err := contentHashColumnExists(projDir)
	if err != nil {
		return 0, err
	}
	for _, m := range pending {
		// Unconditional per-migration log line. Emitted on stdout so the
		// upgrade-service journal (via runCommandToLog → MultiWriter) and
		// the local terminal both see "migrate is working" without
		// needing --verbose. Each line also flows through progress.Write
		// (PrefixWriter) which fires WATCHDOG=1, so per-migration output
		// also serves as a heartbeat during multi-minute migrations
		// (complements the active-phase WATCHDOG=1 ticker in
		// applyPostSwap that fires every 30 s independently).
		fmt.Printf("[migrate]   ▶ applying %s\n", filepath.Base(m.Path))

		if verbose {
			// Newline-terminated. Pre-fix this printf was newline-less,
			// intended as a prefix that an [applied]/[FAILED] suffix
			// would complete on the same line. That works in isolation,
			// but the subsequent `[migrate]   ✔ applied` printf (which
			// fires for every migration, verbose or not, and has its
			// own leading whitespace) crashes onto the same line:
			//
			//   Migration X (desc) [migrate]   ✔ applied  ... in 368ms
			//   [applied] (368ms)
			//
			// Adding the \n keeps each piece on its own line; the
			// existing [applied]/[FAILED]/[empty-skipped] suffix
			// structures land as their own lines too.
			fmt.Printf("Migration %d (%s)\n", m.Version, m.Description)
		}

		start := time.Now()
		out, err := runPsqlFile(projDir, m.Path)
		durationMs := time.Since(start).Milliseconds()
		elapsed := time.Since(start).Round(time.Millisecond)

		if err != nil {
			if verbose {
				fmt.Println("[FAILED]")
				fmt.Println(out)
			}
			fmt.Printf("[migrate]   ✗ FAILED   %s after %s\n", filepath.Base(m.Path), elapsed)
			return 0, fmt.Errorf("migration %d (%s) failed: %w\n%s", m.Version, filepath.Base(m.Path), err, out)
		}

		// Canonical Layer 2 injection site. The migration's outer
		// transaction has just committed (runPsqlFile above returned
		// nil) but the db.migration INSERT below has not yet run —
		// the ~ms window where SIGKILL leaves a committed-but-unrecorded
		// migration. Forward-recovery on this state fails deterministically
		// ("relation already exists" on re-run); only rsync-restore
		// can complete recovery coherently.
		//
		// Modeled as two stall classes — the harness picks the target
		// PID (subprocess for Layer 0 in-process recovery, parent for
		// Layer 2 next-install recovery) and sends real SIGKILL.
		// Real signal semantics (WIFEXITED=0, WTERMSIG=SIGKILL,
		// systemd-recorded terminal state) differ observably from
		// in-process os.Exit(137), so the scenarios drive both code
		// paths via genuine signals. Drives the scenario 3-postswap-migrate-killed-after-commit SIGKILL
		// harness validation pending in the install-recovery harness.
		// Exactly one of these stalls is active per run
		// (STATBUS_INJECT_AT picks); the other is a no-op.
		inject.StallHere("migrate-subprocess-killed-after-commit-before-recorded")
		inject.StallHere("upgrade-service-parent-killed-after-commit-before-recorded")

		// Re-probe content_hash column existence AFTER apply only while
		// we still think it's false — the just-applied migration may have
		// added the column. Stops probing once the column exists.
		if !hasContentHash {
			if nowHas, _ := contentHashColumnExists(projDir); nowHas {
				hasContentHash = true
				// STATBUS-116 Part A: the column-add migration just backfilled
				// its 344 frozen April-26 hash literals. Re-stamp any that
				// disagree with the current on-disk file, so a sanctioned
				// in-place edit of a pre-column migration leaves a from-empty
				// build's ledger consistent by construction.
				if err := restampBackfilledHashes(projDir); err != nil {
					return 0, fmt.Errorf("re-stamp backfilled content hashes: %w", err)
				}
			}
		}

		// Record success. Two INSERT shapes:
		//  - Pre-content_hash-column: legacy fields only. Used while
		//    applying migrations 1..N-1 of the column-add migration on
		//    a fresh DB. The column-add migration (20260426220000)
		//    backfills these rows in the same transaction.
		//  - Post-content_hash-column: include the hash. NOT NULL
		//    constraint requires it. Hash is computed from the file
		//    bytes that just ran.
		var insertErr error
		if hasContentHash {
			hash, hashErr := sha256File(m.Path)
			if hashErr != nil {
				return 0, fmt.Errorf("hash migration %d (%s): %w", m.Version, filepath.Base(m.Path), hashErr)
			}
			recordSQL := `INSERT INTO db.migration (version, filename, description, duration_ms, content_hash) VALUES (:version, :'filename', :'description', :duration_ms, :'content_hash')`
			_, insertErr = runPsql(projDir, recordSQL,
				"-v", fmt.Sprintf("version=%d", m.Version),
				"-v", "filename="+filepath.Base(m.Path),
				"-v", "description="+m.Description,
				"-v", fmt.Sprintf("duration_ms=%d", durationMs),
				"-v", "content_hash="+hash,
			)
		} else {
			recordSQL := `INSERT INTO db.migration (version, filename, description, duration_ms) VALUES (:version, :'filename', :'description', :duration_ms)`
			_, insertErr = runPsql(projDir, recordSQL,
				"-v", fmt.Sprintf("version=%d", m.Version),
				"-v", "filename="+filepath.Base(m.Path),
				"-v", "description="+m.Description,
				"-v", fmt.Sprintf("duration_ms=%d", durationMs),
			)
		}
		if insertErr != nil {
			return 0, fmt.Errorf("record migration %d: %w", m.Version, insertErr)
		}

		// Harness-only kill site (C7): simulates the OS / orchestrator
		// killing the process BETWEEN migration N (just recorded — INSERT
		// completed) and the start of migration N+1's iteration (next
		// loop turn). At kill time: migration N is FULLY APPLIED and its
		// db.migration row is committed; migration N+1 has NOT started.
		// The harness ensures ≥ 2 pending migrations so the "between"
		// point exists.
		//
		// Recovery via the next install's recoverFromFlag → resumePostSwap
		// → applyPostSwap re-entry → migrate.Up: forward-recovery resumes
		// from the unrecorded pending set (N+1 onwards) and applies them
		// cleanly. No partial state to reconcile since N's transaction
		// committed and N+1's never opened.
		//
		// Placement rationale (mirrors team-lead's #150 spec): inside
		// runUp's `for _, m := range pending` loop, AFTER the
		// db.migration INSERT for the CURRENT migration succeeds and
		// BEFORE the loop's next iteration begins runPsqlFile for the
		// NEXT migration. Co-located with the canonical C1/C2 stall
		// sites at the same "between" boundary so the topology of
		// per-migration injection sites stays readable in one place.
		// No-op in production. Drives scenario 3-postswap-between-migrations-kill.
		inject.KillHere("killed-by-system-between-migrations")

		fmt.Printf("[migrate]   ✔ applied  %s in %s\n", filepath.Base(m.Path), elapsed)

		if verbose {
			fmt.Printf("[applied] (%dms)\n", durationMs)
		}
		appliedCount++
	}

	// Notify PostgREST
	if appliedCount > 0 {
		runPsql(projDir, "NOTIFY pgrst, 'reload config'; NOTIFY pgrst, 'reload schema';")
		fmt.Printf("Applied %d migration(s)\n", appliedCount)
	}

	// Run post-restore fixups: idempotent repairs for state that
	// pg_dump/pg_restore cannot preserve (cluster-level role grants,
	// extension function search_path overrides). Always runs — even
	// when no pending migrations — because seed restore alone
	// can break these things.
	postRestore := filepath.Join(projDir, "migrations", "post_restore.sql")
	if _, err := os.Stat(postRestore); err == nil {
		if verbose {
			fmt.Println("Running post-restore fixups...")
		}
		if out, err := runPsqlFile(projDir, postRestore); err != nil {
			// STATBUS-116 doc-025 D: HARD-FAIL, not warn. post_restore holds
			// idempotent, admin-run repairs REQUIRED for correctness (cluster-level
			// role GUCs + grants that pg_dump cannot carry). Every statement is
			// idempotent and runs as admin, so a failure means the box is genuinely
			// broken — fail-fast-actionable (the silently-lost safeupdate guard is
			// the standing proof of what warn-only costs).
			return appliedCount, fmt.Errorf("post_restore.sql failed: %w\n%s", err, out)
		}
	}

	return appliedCount, nil
}

// maybeRebuildTestTemplate recreates the statbus_test_template database in
// development mode when the template already exists. Called from Up() AFTER
// the advisory lock has been released so that the spawned `dev.sh
// create-test-template` process (which calls `./sb migrate up` internally)
// can acquire the lock without deadlocking.
func maybeRebuildTestTemplate(projDir string) {
	// Guard: skip if we ARE migrating the template (prevents recursion when
	// create-test-template calls ./sb migrate up on the template database).
	targetDB := os.Getenv("POSTGRES_APP_DB")
	if targetDB == "" {
		targetDB = os.Getenv("PGDATABASE")
	}
	if strings.Contains(targetDB, "test_template") {
		return
	}

	envPath := filepath.Join(projDir, ".env")
	f, err := dotenv.Load(envPath)
	if err != nil {
		return
	}
	mode, ok := f.Get("CADDY_DEPLOYMENT_MODE")
	if !ok || mode != "development" {
		return
	}

	templateName := "statbus_test_template"
	out, _ := runPsql(projDir, fmt.Sprintf(
		"SELECT 1 FROM pg_database WHERE datname = '%s'", templateName), "-t", "-A")
	if strings.TrimSpace(out) != "1" {
		return
	}

	devsh := filepath.Join(projDir, "dev.sh")
	if _, err := os.Stat(devsh); err != nil {
		return
	}

	fmt.Printf("Recreating stale test template %s...\n", templateName)
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Minute)
	defer cancel()
	cmd := exec.CommandContext(ctx, devsh, "create-test-template")
	cmd.Dir = projDir
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "Warning: failed to recreate test template: %v\n", err)
	}
}

// Down rolls back migrations.
// If migrateTo > 0, roll back all migrations >= that version.
// If all is true, roll back all. Otherwise roll back just the last one.
func Down(projDir string, migrateTo int64, all bool, verbose bool) error {
	// Check if migration table exists
	checkOut, err := runPsql(projDir, "SELECT EXISTS (SELECT FROM pg_tables WHERE schemaname = 'db' AND tablename = 'migration')", "-t", "-A")
	if err != nil || strings.TrimSpace(checkOut) != "t" {
		fmt.Println("No migrations to roll back - migration table doesn't exist")
		return nil
	}

	// Get migrations to roll back
	var query string
	if migrateTo > 0 {
		query = fmt.Sprintf("SELECT version FROM db.migration WHERE version >= %d ORDER BY version DESC", migrateTo)
	} else if all {
		query = "SELECT version FROM db.migration ORDER BY version DESC"
	} else {
		query = "SELECT version FROM db.migration ORDER BY version DESC LIMIT 1"
	}

	versionsOut, err := runPsql(projDir, query, "-t", "-A")
	if err != nil {
		return fmt.Errorf("query migrations to roll back: %w", err)
	}

	var versions []int64
	for _, line := range strings.Split(strings.TrimSpace(versionsOut), "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		v, err := strconv.ParseInt(line, 10, 64)
		if err == nil {
			versions = append(versions, v)
		}
	}

	if len(versions) == 0 {
		fmt.Println("No migrations to roll back")
		return nil
	}

	appliedCount := 0
	for _, version := range versions {
		downPath, err := findDownFile(projDir, version)
		if err != nil {
			return fmt.Errorf("missing down migration for version %d", version)
		}

		mf, err := parseMigrationFile(downPath)
		if err != nil {
			return err
		}

		if verbose {
			// Newline-terminated (see Up()'s identical printf for the
			// rationale — pre-fix the missing newline jammed this
			// prefix onto subsequent log lines).
			fmt.Printf("Migration %d (%s)\n", version, mf.Description)
		}

		// Check if file is empty
		info, err := os.Stat(downPath)
		if err != nil {
			return err
		}
		if info.Size() == 0 {
			if verbose {
				fmt.Println("[empty - skipped]")
			}
			deleteSQL := fmt.Sprintf("DELETE FROM db.migration WHERE version = %d", version)
			runPsql(projDir, deleteSQL)
			appliedCount++
			continue
		}

		if verbose {
			fmt.Print("[rolling back] ")
		}

		start := time.Now()
		out, err := runPsqlFile(projDir, downPath)
		durationMs := time.Since(start).Milliseconds()

		if err != nil {
			if verbose {
				fmt.Println("[FAILED]")
				fmt.Println(out)
			}
			return fmt.Errorf("rollback %d (%s) failed: %w\n%s", version, filepath.Base(downPath), err, out)
		}

		// Remove migration record
		deleteSQL := fmt.Sprintf("DELETE FROM db.migration WHERE version = %d", version)
		runPsql(projDir, deleteSQL)

		if verbose {
			fmt.Printf("done (%dms)\n", durationMs)
		}
		appliedCount++
	}

	// Clean up schema if full rollback
	if all && migrateTo == 0 {
		runPsql(projDir, "DROP TABLE IF EXISTS db.migration; DROP SCHEMA IF EXISTS db CASCADE;")
		if verbose {
			fmt.Println("Removed migration tracking table and schema")
		}
	}

	// Notify PostgREST
	if appliedCount > 0 {
		runPsql(projDir, "NOTIFY pgrst, 'reload config'; NOTIFY pgrst, 'reload schema';")
		fmt.Printf("Rolled back %d migration(s)\n", appliedCount)
	}

	return nil
}

// New creates a new migration file pair.
func New(projDir string, description string, extension string) error {
	if description == "" {
		return fmt.Errorf("migration description is required (use --description)")
	}

	timestamp := time.Now().UTC().Format("20060102150405")
	safeDesc := strings.ToLower(description)
	// Strip issue-number references like "(#31)" or "#31" before slugging so
	// they don't appear as trailing _31_ artifacts in the filename.
	safeDesc = regexp.MustCompile(`\s*\(#\d+\)\s*|\s*#\d+`).ReplaceAllString(safeDesc, "")
	safeDesc = regexp.MustCompile(`[^a-z0-9]+`).ReplaceAllString(safeDesc, "_")
	safeDesc = strings.Trim(safeDesc, "_")

	if extension == "" {
		extension = "sql"
	}

	upFile := filepath.Join(projDir, "migrations", fmt.Sprintf("%s_%s.up.%s", timestamp, safeDesc, extension))
	downFile := filepath.Join(projDir, "migrations", fmt.Sprintf("%s_%s.down.%s", timestamp, safeDesc, extension))

	upContent := fmt.Sprintf("-- Migration %s: %s\nBEGIN;\n\n-- Add your migration SQL here\n\nEND;\n", timestamp, description)
	downContent := fmt.Sprintf("-- Down Migration %s: %s\nBEGIN;\n\n-- Add your down migration SQL here\n\nEND;\n", timestamp, description)

	if err := os.WriteFile(upFile, []byte(upContent), 0644); err != nil {
		return err
	}
	if err := os.WriteFile(downFile, []byte(downContent), 0644); err != nil {
		return err
	}

	fmt.Println("Created new migration files:")
	fmt.Printf("  %s\n", upFile)
	fmt.Printf("  %s\n", downFile)
	return nil
}

// PsqlArgs returns the psql command args and environment needed to connect.
// Used by `sb psql` to exec into psql with the right connection settings.
// Returns (fullArgs, env, error) where fullArgs[0] is the argv[0] name.
func PsqlArgs(projDir string) ([]string, []string, error) {
	psqlPath, prefix, env, err := PsqlCommand(projDir)
	if err != nil {
		return nil, nil, err
	}
	// Build full args: [argv0, prefix...]
	// For host psql: ["psql"]
	// For docker: ["docker", "compose", "exec", "-T", "db", "psql", "-U", user, "-d", db]
	args := append([]string{filepath.Base(psqlPath)}, prefix...)
	return args, env, nil
}

// PsqlProjectDir is a convenience to get projDir for psql commands.
func PsqlProjectDir() string {
	return config.ProjectDir()
}

// ResolveTargetDB maps a `--target {dev,seed}` flag to the actual
// PostgreSQL database name read from .env. Used by `./sb migrate up
// --target` and `./sb migrate redo --target` to centralise the
// dev↔POSTGRES_APP_DB / seed↔POSTGRES_SEED_DB resolution.
//
// Returns a clear error when target is unrecognised, when .env can't
// be loaded, or when --target seed is requested but POSTGRES_SEED_DB
// hasn't been configured (operator hasn't regenerated .env after
// pulling commit 3 of the seed feature).
func ResolveTargetDB(projDir, target string) (string, error) {
	if target == "" {
		target = "dev"
	}
	if target != "dev" && target != "seed" {
		return "", fmt.Errorf("--target must be 'dev' or 'seed', got %q", target)
	}
	f, err := dotenv.Load(filepath.Join(projDir, ".env"))
	if err != nil {
		return "", fmt.Errorf("load .env: %w", err)
	}
	switch target {
	case "seed":
		v, ok := f.Get("POSTGRES_SEED_DB")
		if !ok || v == "" {
			return "", fmt.Errorf("POSTGRES_SEED_DB not configured in .env. " +
				"Regenerate config to materialise it: `./sb config generate`")
		}
		return v, nil
	case "dev":
		v, ok := f.Get("POSTGRES_APP_DB")
		if !ok || v == "" {
			return "", fmt.Errorf("POSTGRES_APP_DB not configured in .env. " +
				"Regenerate config: `./sb config generate`")
		}
		return v, nil
	}
	return "", fmt.Errorf("unreachable: target %q", target)
}

// ── content_hash machinery (plan-rc.66 section R, commit 2/4) ───────────────
//
// db.migration.content_hash carries sha256(file bytes at apply time) for
// every tracked migration. The runner uses it to detect in-place edits to
// already-applied migrations — the rc63-fixes immutability violation
// pattern.
//
// Backfill is structural, not lazy: migration 20260426220000 hardcodes
// one UPDATE per prior version inside its body, then sets the column
// NOT NULL. After the migration applies, every db.migration row has a
// non-null hash and the constraint forbids any future NULL. The runner
// stamps the hash on every subsequent INSERT (apply + redo).
//
// Per-call helpers:
//   - eagerContentHashCheck — runs at the top of every `migrate up`,
//     BEFORE pending-only filtering, so it catches edits to migrations
//     that are no longer pending. Compares stored hash to live file
//     bytes; on mismatch, branches on whether the migration is in a
//     released tag.
//
// The eager check is a silent no-op when the content_hash column
// doesn't yet exist (legacy DB pre-rc.67-migration; the column will
// be added during the apply pass that follows). Cheap
// information_schema probe per call.

// sha256File reads the file's bytes and returns lowercase hex sha256.
func sha256File(path string) (string, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	h := sha256.Sum256(data)
	return hex.EncodeToString(h[:]), nil
}

// contentHashColumnExists probes information_schema for the column.
// Returns false (no error) when the column hasn't been added yet.
func contentHashColumnExists(projDir string) (bool, error) {
	out, err := runPsql(projDir,
		"SELECT EXISTS (SELECT FROM information_schema.columns WHERE table_schema='db' AND table_name='migration' AND column_name='content_hash')",
		"-t", "-A")
	if err != nil {
		// If db.migration table itself is missing (very fresh DB pre-ensureMigrationTableSQL),
		// treat as "column doesn't exist".
		msg := err.Error()
		if strings.Contains(msg, "db.migration") && strings.Contains(msg, "does not exist") {
			return false, nil
		}
		if strings.Contains(msg, `schema "db" does not exist`) {
			return false, nil
		}
		return false, fmt.Errorf("probe content_hash column: %w", err)
	}
	return strings.TrimSpace(out) == "t", nil
}

// findUpFile returns the path to the up.sql or up.psql file for a given
// migration version. Both extensions are valid migration shapes (see
// listMigrationFiles); callers that resolve files by version must accept
// either. Returns an error when neither exists.
func findUpFile(projDir string, version int64) (string, error) {
	for _, ext := range []string{"sql", "psql"} {
		pattern := filepath.Join(projDir, "migrations", fmt.Sprintf("%d_*.up.%s", version, ext))
		if matches, _ := filepath.Glob(pattern); len(matches) > 0 {
			return matches[0], nil
		}
	}
	return "", fmt.Errorf("no up.{sql,psql} file for version %d", version)
}

// findDownFile is the down-migration counterpart to findUpFile.
func findDownFile(projDir string, version int64) (string, error) {
	for _, ext := range []string{"sql", "psql"} {
		pattern := filepath.Join(projDir, "migrations", fmt.Sprintf("%d_*.down.%s", version, ext))
		if matches, _ := filepath.Glob(pattern); len(matches) > 0 {
			return matches[0], nil
		}
	}
	return "", fmt.Errorf("no down.{sql,psql} file for version %d", version)
}

// shortHash truncates a hex hash to 8 chars for human-readable logs.
func shortHash(s string) string {
	if len(s) > 8 {
		return s[:8]
	}
	return s
}

// LedgerHashMismatch is a db.migration row whose recorded content_hash disagrees
// with the sha256 of the on-disk up-migration file.
type LedgerHashMismatch struct {
	Version    int64
	StoredHash string
	LiveHash   string
	File       string
}

// ledgerHashMismatchRows is the PURE core (Docker/DB-free, unit-tested): given
// the raw "version|content_hash" rows text of a db.migration ledger, return the
// rows whose recorded hash != sha256(on-disk up-migration file). Rows with no
// on-disk file (findUpFile miss — a migration deleted at HEAD) are SKIPPED as
// harmless orphans (they can never re-run; eagerContentHashCheck skips them the
// same way).
func ledgerHashMismatchRows(projDir, rowsOut string) ([]LedgerHashMismatch, error) {
	var out []LedgerHashMismatch
	for _, line := range strings.Split(strings.TrimSpace(rowsOut), "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		parts := strings.SplitN(line, "|", 2)
		if len(parts) != 2 {
			continue
		}
		version, perr := strconv.ParseInt(parts[0], 10, 64)
		if perr != nil {
			continue
		}
		stored := strings.TrimSpace(parts[1])
		filePath, ferr := findUpFile(projDir, version)
		if ferr != nil {
			continue // file-less orphan → skip (harmless; can never re-run)
		}
		live, herr := sha256File(filePath)
		if herr != nil {
			return nil, fmt.Errorf("hash %s: %w", filePath, herr)
		}
		if live != stored {
			out = append(out, LedgerHashMismatch{Version: version, StoredHash: stored, LiveHash: live, File: filepath.Base(filePath)})
		}
	}
	return out, nil
}

// LedgerContentHashMismatches returns the mismatches in dbName's db.migration
// ledger vs the on-disk files (STATBUS-116 Part B — DumpSeed's publish gate). A
// non-empty result means the seed is inconsistent and must NOT be published.
func LedgerContentHashMismatches(projDir, dbName string) ([]LedgerHashMismatch, error) {
	rowsOut, err := QueryDB(projDir, dbName,
		"SELECT version || '|' || COALESCE(content_hash, '<NULL>') FROM db.migration ORDER BY version",
		"-t", "-A")
	if err != nil {
		return nil, fmt.Errorf("query %s db.migration content_hash: %w", dbName, err)
	}
	return ledgerHashMismatchRows(projDir, rowsOut)
}

// restampBackfilledHashes (STATBUS-116 Part A) corrects db.migration rows on the
// CURRENT connection (the DB being migrated) whose recorded content_hash
// disagrees with the current on-disk file. Called at the content_hash column
// false→true flip in runUp — right after the column-add migration (20260426220000)
// backfills its 344 hash literals frozen at April 26. A later SANCTIONED in-place
// edit of a pre-column migration (e.g. the STATBUS-116 ORDER-BY fix to
// 20260218215337) changes the file but not the frozen literal; re-stamping here
// keeps a from-empty build's ledger consistent BY CONSTRUCTION, so the released
// backfill migration NEVER needs literal maintenance (editing it would recurse
// the in-place-edit class).
func restampBackfilledHashes(projDir string) error {
	rowsOut, err := runPsql(projDir,
		"SELECT version || '|' || COALESCE(content_hash, '<NULL>') FROM db.migration ORDER BY version",
		"-t", "-A")
	if err != nil {
		return fmt.Errorf("query content_hash rows for re-stamp: %w", err)
	}
	mm, err := ledgerHashMismatchRows(projDir, rowsOut)
	if err != nil {
		return err
	}
	for _, m := range mm {
		if _, err := runPsql(projDir,
			"UPDATE db.migration SET content_hash = :'h' WHERE version = :v",
			"-v", "h="+m.LiveHash, "-v", fmt.Sprintf("v=%d", m.Version)); err != nil {
			return fmt.Errorf("re-stamp content_hash for migration %d: %w", m.Version, err)
		}
		fmt.Printf("[migrate]   ⟳ re-stamped backfilled content_hash for migration %d (%s): %s → %s\n",
			m.Version, m.File, shortHash(m.StoredHash), shortHash(m.LiveHash))
	}
	return nil
}

// ErrStaleRestoredMigration (STATBUS-116 Part C) reports that a restored prior
// seed's ledger content_hash for a migration disagrees with the on-disk file —
// detected by eagerContentHashCheck under channelSeedBuild. The seed-build caller
// (`sb db seed build`) catches it (errors.As) and falls back to a FULL rebuild
// rather than proceeding on a stale incremental base. Carries no git dependency.
type ErrStaleRestoredMigration struct {
	Version    int64
	StoredHash string
	LiveHash   string
}

func (e *ErrStaleRestoredMigration) Error() string {
	return fmt.Sprintf("restored prior seed is stale on migration %d: ledger content_hash %s != on-disk file %s "+
		"(seed-build channel) — the incremental base must be discarded and rebuilt full",
		e.Version, shortHash(e.StoredHash), shortHash(e.LiveHash))
}

// eagerContentHashCheck verifies that every tracked migration's stored
// content_hash matches the live file's sha256. On mismatch, branches:
//   - migration version IS in a released tag → immutability violation
//     (hard fail; no override). The error names the tag and tells the
//     operator to create a new migration.
//   - migration version NOT in any released tag → recoverable WIP edit.
//     Error tells the operator to run `./sb migrate redo <version>`.
//
// Skips files that don't exist at HEAD (likely deleted via git revert);
// not the immutability check's concern.
//
// Skips silently when the content_hash column doesn't exist (legacy DB
// upgrading through this RC's column-add migration; the column will be
// added during the apply pass that follows).
//
// NOT NULL constraint on content_hash means every row carries a hash
// post-column-add. The check iterates all rows; no `WHERE IS NOT NULL`
// filter (silent skips violate fail-fast). If a NULL ever surfaces here
// despite the constraint, that's a genuine inconsistency and the check
// fails loudly.
func eagerContentHashCheck(projDir string) error {
	exists, err := contentHashColumnExists(projDir)
	if err != nil {
		return err
	}
	if !exists {
		return nil
	}

	// STATBUS-102: how a content_hash MISMATCH is handled is decided by the
	// deployment CHANNEL (migrationChannelClass), not a per-version sanctioned
	// list — release blesses (re-stamp, trusting the cut gate), edge re-runs,
	// localDev errors for a human. maxVersion gates edge's auto-redo to the
	// latest-applied migration (Redo is latest-only; deeper is a King-flag).
	channel := migrationChannelClass(projDir)
	maxVerOut, err := runPsql(projDir, "SELECT COALESCE(MAX(version), 0) FROM db.migration", "-t", "-A")
	if err != nil {
		return fmt.Errorf("query max applied migration version: %w", err)
	}
	maxVersion, _ := strconv.ParseInt(strings.TrimSpace(maxVerOut), 10, 64)

	rowsOut, err := runPsql(projDir,
		"SELECT version || '|' || COALESCE(content_hash, '<NULL>') FROM db.migration ORDER BY version",
		"-t", "-A")
	if err != nil {
		return fmt.Errorf("query content_hash rows: %w", err)
	}

	for _, line := range strings.Split(strings.TrimSpace(rowsOut), "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		parts := strings.SplitN(line, "|", 2)
		if len(parts) != 2 {
			continue
		}
		version, parseErr := strconv.ParseInt(parts[0], 10, 64)
		if parseErr != nil {
			continue
		}
		storedHash := strings.TrimSpace(parts[1])

		if storedHash == "<NULL>" {
			// Should be impossible — NOT NULL constraint forbids it.
			// If we ever see it, the constraint was bypassed (manual
			// SQL, schema desync). Fail loudly.
			return fmt.Errorf("invariant violated: db.migration.content_hash is NULL for version %d "+
				"despite NOT NULL constraint. Schema desync; investigate manually.", version)
		}

		filePath, fileErr := findUpFile(projDir, version)
		if fileErr != nil {
			// File missing at HEAD (git revert?). Out of scope for this
			// check; let the pending-set logic handle reconciliation.
			continue
		}
		liveHash, hashErr := sha256File(filePath)
		if hashErr != nil {
			return fmt.Errorf("hash %s: %w", filePath, hashErr)
		}
		if liveHash == storedHash {
			continue
		}

		// MISMATCH for version N — how to handle it is decided by the channel.
		switch channel {
		case channelSeedBuild:
			// STATBUS-116 Part C: the hermetic seed-builder has no .git, so it must
			// NEVER reach the released-tag git probe below. A mismatch here means the
			// RESTORED prior seed's ledger disagrees with the on-disk files → it is
			// stale → return a typed error the seed-build caller catches to fall back
			// to a FULL rebuild. No git, no bless, no redo in-stage.
			return &ErrStaleRestoredMigration{Version: version, StoredHash: storedHash, LiveHash: liveHash}
		case channelRelease:
			// BLESS: the cut gate already vetted every modified released migration as an
			// env-var-declared sanctioned broken-fix (STATBUS_INTENTIONALLY_FIX_BROKEN_IMMUTABLE_MIGRATION),
			// so a mismatch here is a sanctioned applied broken-fix → re-stamp content_hash,
			// no re-run. We TRUST the cut gate (King's "trust the gate, no runtime checkers"):
			// NO released-tag provenance re-check — a `git rev-parse <tag>:<path>` probe is
			// unreliable on the shallow `git clone --depth 1` real boxes use (install.go:929;
			// the tag's tree can be absent → it would FALSELY refuse a legit bless), and it
			// is redundant with the cut gate that already gated the change.
			if _, updateErr := runPsql(projDir, fmt.Sprintf(
				"UPDATE db.migration SET content_hash = '%s' WHERE version = %d",
				liveHash, version)); updateErr != nil {
				return fmt.Errorf("content_hash re-stamp UPDATE for migration %d: %w", version, updateErr)
			}
			oldShort, newShort := storedHash, liveHash
			if len(oldShort) > 8 {
				oldShort = oldShort[:8]
			}
			if len(newShort) > 8 {
				newShort = newShort[:8]
			}
			fmt.Printf("[migrate]   ⟳ Intentionally fixing broken (immutable) migration %d: re-stamped content_hash %s → %s\n",
				version, oldShort, newShort)
			continue
		case channelEdge:
			// REDO: a deployed always-latest dev/edge box; data loss acceptable.
			// Re-run the latest-applied migration (down+up) to absorb the change.
			// A deeper-than-latest mismatch is a depth-asymmetry we do not
			// auto-recreate yet (Redo is latest-only) → fall through to the
			// localDev guidance + a King-flag (STATBUS-102 follow-up).
			if version == maxVersion {
				if redoErr := Redo(projDir, version, "dev", true, false); redoErr != nil {
					return fmt.Errorf("edge auto-redo of migration %d: %w", version, redoErr)
				}
				fmt.Printf("[migrate]   ⟳ edge channel: re-ran (down+up) migration %d to absorb its content change\n", version)
				continue
			}
			fmt.Printf("[migrate]   ⚑ edge channel: migration %d content changed but is NOT the latest applied (%d) — deep-edge auto-recreate not yet implemented (STATBUS-102 follow-up; King's call). Falling back to manual guidance.\n",
				version, maxVersion)
			fallthrough
		default:
			// localDev (UPGRADE_CHANNEL=local) or an uncertain channel:
			// a human is present — never auto-mutate. Released → immutability
			// violation; WIP → redo guidance.
			releasedTag, relErr := release.MigrationInReleasedTag(projDir, version)
			if relErr != nil {
				return fmt.Errorf("released-tag detection for migration %d: %w", version, relErr)
			}
			if releasedTag != "" {
				return fmt.Errorf(
					"immutability violation: migration %d (%s) is in release %s and its file bytes have changed since apply.\n"+
						"  Migration files in released tags must not be edited; create a new migration instead:\n"+
						"    ./sb migrate new --description \"fix_<description>\"\n"+
						"  Then revert the modification to the original file:\n"+
						"    git checkout %s -- migrations/%s",
					version, filepath.Base(filePath), releasedTag,
					releasedTag, filepath.Base(filePath))
			}
			target, dbName := currentMigrationTarget(projDir)
			var fixCmd string
			switch target {
			case "dev":
				fixCmd = fmt.Sprintf("./sb migrate redo %d --target dev --confirm", version)
			case "seed":
				fixCmd = fmt.Sprintf("./sb migrate redo %d", version)
			default:
				fixCmd = fmt.Sprintf("./sb migrate redo %d --target {dev --confirm | seed}", version)
			}
			return fmt.Errorf(
				"migration %d (%s) content has changed since apply to %s (WIP edit).\n"+
					"  Fix: %s\n"+
					"  This re-runs the migration's down + up against %s and re-stamps content_hash.",
				version, filepath.Base(filePath), dbName, fixCmd, dbName)
		}
	}
	return nil
}

// currentMigrationTarget infers the {dev,seed} target plus the actual
// PostgreSQL database name from the current process environment. Used by
// the eager content-hash check to emit a guide that names the affected DB
// and the exact redo command for that target — operators never have to
// guess which database is stale or which flags to pass.
//
// PGDATABASE is set by the caller (the cobra migrate up/redo command)
// after ResolveTargetDB; reading it back identifies the live target.
// Returns ("unknown", dbName) when PGDATABASE doesn't match either
// POSTGRES_APP_DB or POSTGRES_SEED_DB — a defensive fallback that
// shouldn't fire in normal use.
func currentMigrationTarget(projDir string) (target, dbName string) {
	dbName = os.Getenv("PGDATABASE")
	if dbName == "" {
		return "unknown", ""
	}
	f, err := dotenv.Load(filepath.Join(projDir, ".env"))
	if err != nil {
		return "unknown", dbName
	}
	if v, ok := f.Get("POSTGRES_SEED_DB"); ok && v == dbName {
		return "seed", dbName
	}
	if v, ok := f.Get("POSTGRES_APP_DB"); ok && v == dbName {
		return "dev", dbName
	}
	return "unknown", dbName
}

// migrationChannel classifies the deployment for content_hash MISMATCH handling
// (STATBUS-102 channel-bless: replaces the per-version sanctioned list).
type migrationChannel int

const (
	channelLocalDev migrationChannel = iota
	channelEdge
	channelRelease
	// channelSeedBuild — the hermetic seed-builder stage (UPGRADE_CHANNEL=seed-build).
	// It has NO .git, so it must NEVER reach the released-tag git probe. A
	// content_hash mismatch on a restored prior there means the restored seed is
	// stale → the caller (sb db seed build) falls back to a FULL rebuild
	// (STATBUS-116 Part C).
	channelSeedBuild
)

// migrationChannelClass reads UPGRADE_CHANNEL from .env (always written by
// config.go; read here via dotenv.Load, same pattern as currentMigrationTarget)
// and classifies the box for content_hash MISMATCH handling. The decision
// depends ONLY on the upgrade axis (UPGRADE_CHANNEL), never on the front-door
// axis (CADDY_DEPLOYMENT_MODE) — deployment mode touches the web front door, not
// the upgrade logic. config.go defaults UPGRADE_CHANNEL by deployment mode at
// config time (development → "local", non-development → "stable"), so a
// developer's box classifies localDev via its channel value, not via a mode read
// here. This makes test == production for the upgrade logic: an arc can exercise
// the release-bless by setting UPGRADE_CHANNEL=stable on a development-mode box.
//
//  1. UPGRADE_CHANNEL == "edge" → edge. A DEPLOYED always-latest box
//     (e.g. dev.statbus.org).
//  2. UPGRADE_CHANNEL ∈ {"stable","prerelease"} → release.
//  3. else (UPGRADE_CHANNEL == "local", unset, unrecognized, or unreadable .env)
//     → localDev. The SAFE default: never auto-bless or auto-redo when the
//     channel is uncertain — stop for a human. On a properly-configured box this
//     fires only for the local-dev channel (config.go always writes a value).
func migrationChannelClass(projDir string) migrationChannel {
	f, err := dotenv.Load(filepath.Join(projDir, ".env"))
	if err != nil {
		return channelLocalDev
	}
	if ch, ok := f.Get("UPGRADE_CHANNEL"); ok {
		switch ch {
		case "edge":
			return channelEdge
		case "stable", "prerelease":
			return channelRelease
		case "seed-build":
			return channelSeedBuild
		}
	}
	return channelLocalDev
}

// Redo re-runs a migration's down + up cycle and re-stamps the tracking
// row. The principled use case is recovering from a WIP edit to an
// already-applied migration: the operator edits up.sql, the next
// migrate up errors with "Run: ./sb migrate redo <version>", and this
// command does the work.
//
// Constraints (enforced; clear errors on violation):
//   - target ∈ {"dev", "seed"}; default "seed".
//   - target=="seed" requires POSTGRES_SEED_DB configured (introduced
//     in commit 3 of the seed feature). Until then this branch errors.
//   - target=="dev" requires confirm=true — destructive on dev DBs
//     with custom data.
//   - Restricted to LATEST applied version only. Intermediate redos
//     leave dependent migrations' effects orphaned over a reverted
//     base. Cascade semantics deferred until needed.
func Redo(projDir string, version int64, target string, confirm bool, verbose bool) error {
	if target == "" {
		target = "seed"
	}
	// Dev requires --confirm; check that BEFORE asking for the DB
	// name so the user gets the safety message even if .env isn't
	// loadable for some reason.
	if target == "dev" && !confirm {
		return fmt.Errorf("./sb migrate redo --target dev requires --confirm.\n" +
			"  Redo runs the migration's down.sql which is destructive on a dev DB with custom data.\n" +
			"  Default --target seed is safe (build-time DB; disposable).")
	}
	dbName, err := ResolveTargetDB(projDir, target)
	if err != nil {
		return err
	}

	prevApp, hadApp := os.LookupEnv("POSTGRES_APP_DB")
	prevPG, hadPG := os.LookupEnv("PGDATABASE")
	os.Setenv("POSTGRES_APP_DB", dbName)
	os.Setenv("PGDATABASE", dbName)
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

	ctx := context.Background()
	lockConn, err := acquireAdvisoryLock(ctx, projDir)
	if err != nil {
		return err
	}
	defer lockConn.Close(context.Background())

	applied, err := listAppliedVersions(projDir)
	if err != nil {
		return err
	}
	if !applied[version] {
		return fmt.Errorf("./sb migrate redo: version %d is not applied to %s", version, dbName)
	}
	var latest int64
	for v := range applied {
		if v > latest {
			latest = v
		}
	}
	if version != latest {
		return fmt.Errorf("./sb migrate redo only supports the latest applied migration (currently %d in %s).\n"+
			"  To revisit older migrations, manually migrate down past it then back up.",
			latest, dbName)
	}

	upPath, err := findUpFile(projDir, version)
	if err != nil {
		return err
	}
	downPath, err := findDownFile(projDir, version)
	if err != nil {
		return err
	}
	mf, err := parseMigrationFile(upPath)
	if err != nil {
		return err
	}

	if verbose {
		fmt.Printf("./sb migrate redo: target=%s db=%s version=%d\n", target, dbName, version)
		fmt.Printf("Running down: %s\n", filepath.Base(downPath))
	}
	if out, err := runPsqlFile(projDir, downPath); err != nil {
		return fmt.Errorf("redo %d: down failed: %w\n%s", version, err, out)
	}

	if _, err := runPsql(projDir, fmt.Sprintf("DELETE FROM db.migration WHERE version = %d", version)); err != nil {
		return fmt.Errorf("redo %d: delete tracking row: %w", version, err)
	}

	if verbose {
		fmt.Printf("Running up:   %s\n", filepath.Base(upPath))
	}
	start := time.Now()
	if out, err := runPsqlFile(projDir, upPath); err != nil {
		return fmt.Errorf("redo %d: up failed: %w\n%s", version, err, out)
	}
	durationMs := time.Since(start).Milliseconds()

	// Re-INSERT tracking row WITH the freshly-computed content_hash.
	// NOT NULL constraint requires it. The Redo command always runs
	// against a target where the column exists (Redo is gated on the
	// content_hash migration having already applied — by the time
	// Redo can be invoked at all, the column must already exist
	// because Redo's `--target seed` requires POSTGRES_SEED_DB which
	// arrives with commit 3, and `--target dev --confirm` against a
	// pre-content_hash-column DB would no-op the content_hash column
	// existence check, but the INSERT shape still works because we
	// branch on column existence below).
	hash, hashErr := sha256File(upPath)
	if hashErr != nil {
		return fmt.Errorf("redo %d: hash up file: %w", version, hashErr)
	}

	hasContentHash, err := contentHashColumnExists(projDir)
	if err != nil {
		return fmt.Errorf("redo %d: probe content_hash column: %w", version, err)
	}
	if hasContentHash {
		recordSQL := `INSERT INTO db.migration (version, filename, description, duration_ms, content_hash) VALUES (:version, :'filename', :'description', :duration_ms, :'content_hash')`
		if _, err := runPsql(projDir, recordSQL,
			"-v", fmt.Sprintf("version=%d", version),
			"-v", "filename="+filepath.Base(upPath),
			"-v", "description="+mf.Description,
			"-v", fmt.Sprintf("duration_ms=%d", durationMs),
			"-v", "content_hash="+hash,
		); err != nil {
			return fmt.Errorf("redo %d: re-record tracking row: %w", version, err)
		}
	} else {
		// Pre-content_hash-column DB. Redo can still run for legacy
		// recovery use-cases; INSERT without the column.
		recordSQL := `INSERT INTO db.migration (version, filename, description, duration_ms) VALUES (:version, :'filename', :'description', :duration_ms)`
		if _, err := runPsql(projDir, recordSQL,
			"-v", fmt.Sprintf("version=%d", version),
			"-v", "filename="+filepath.Base(upPath),
			"-v", "description="+mf.Description,
			"-v", fmt.Sprintf("duration_ms=%d", durationMs),
		); err != nil {
			return fmt.Errorf("redo %d: re-record tracking row: %w", version, err)
		}
	}

	fmt.Printf("Migration %d redone against %s\n", version, dbName)
	return nil
}

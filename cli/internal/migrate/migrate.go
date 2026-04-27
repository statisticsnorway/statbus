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
		db := getOr("POSTGRES_APP_DB", "statbus_local")
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

	env := os.Environ()
	env = append(env,
		"PGHOST="+dbHost,
		"PGPORT="+dbPort,
		"PGDATABASE="+getOr("POSTGRES_APP_DB", "statbus_local"),
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
	cmd := exec.Command(psqlPath, args...)
	cmd.Dir = projDir
	cmd.Env = env
	cmd.Stdin = strings.NewReader(sql)

	out, err := cmd.CombinedOutput()
	return string(out), err
}

// runPsqlFile executes a SQL file via psql.
func runPsqlFile(projDir string, filePath string) (string, error) {
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
	cmd := exec.Command(psqlPath, args...)
	cmd.Dir = projDir
	cmd.Env = env
	cmd.Stdin = file

	out, err := cmd.CombinedOutput()
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
	getOr := func(key, fallback string) string {
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
		if verbose {
			fmt.Printf("Migration %d (%s) ", m.Version, m.Description)
		}

		start := time.Now()
		out, err := runPsqlFile(projDir, m.Path)
		durationMs := time.Since(start).Milliseconds()

		if err != nil {
			if verbose {
				fmt.Println("[FAILED]")
				fmt.Println(out)
			}
			return 0, fmt.Errorf("migration %d (%s) failed: %w\n%s", m.Version, filepath.Base(m.Path), err, out)
		}

		// Re-probe content_hash column existence AFTER apply only while
		// we still think it's false — the just-applied migration may have
		// added the column. Stops probing once the column exists.
		if !hasContentHash {
			hasContentHash, _ = contentHashColumnExists(projDir)
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
			fmt.Fprintf(os.Stderr, "Warning: post_restore.sql failed: %v\n%s\n", err, out)
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
			fmt.Printf("Migration %d (%s) ", version, mf.Description)
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

		// Mismatch — branch on released-tag containment.
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
		return fmt.Errorf(
			"migration %d (%s) content has changed since apply (WIP edit).\n"+
				"  Run: ./sb migrate redo %d\n"+
				"  This re-runs the migration's down + up against the seed DB and re-stamps content_hash.",
			version, filepath.Base(filePath), version)
	}
	return nil
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
	if target != "dev" && target != "seed" {
		return fmt.Errorf("--target must be 'dev' or 'seed', got %q", target)
	}

	// Resolve the actual database name and override env so all subsequent
	// psql/pgx calls in this command target it. Reverted via defer.
	envPath := filepath.Join(projDir, ".env")
	f, err := dotenv.Load(envPath)
	if err != nil {
		return fmt.Errorf("load .env: %w", err)
	}

	var dbName string
	switch target {
	case "seed":
		v, ok := f.Get("POSTGRES_SEED_DB")
		if !ok || v == "" {
			return fmt.Errorf("POSTGRES_SEED_DB not configured; the seed DB is introduced in commit 3 of the seed feature.\n" +
				"  For now, use `--target dev --confirm` at your own risk.")
		}
		dbName = v
	case "dev":
		if !confirm {
			return fmt.Errorf("./sb migrate redo --target dev requires --confirm.\n" +
				"  Redo runs the migration's down.sql which is destructive on a dev DB with custom data.\n" +
				"  Default --target seed is safe (build-time DB; disposable).")
		}
		v, ok := f.Get("POSTGRES_APP_DB")
		if !ok || v == "" {
			v = "statbus_local"
		}
		dbName = v
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

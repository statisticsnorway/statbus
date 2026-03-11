// Package migrate handles database schema migrations.
//
// Migrations live in migrations/ as pairs of YYYYMMDDHHMMSS_description.(up|down).(sql|psql).
// Applied migrations are tracked in db.migration table.
// Ported from Crystal cli/src/migrate.cr.
package migrate

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/statisticsnorway/statbus/cli/internal/config"
	"github.com/statisticsnorway/statbus/cli/internal/dotenv"
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

// psqlEnv builds the environment for psql from .env file.
func psqlEnv(projDir string) ([]string, error) {
	envPath := filepath.Join(projDir, ".env")
	f, err := dotenv.Load(envPath)
	if err != nil {
		return nil, fmt.Errorf("load .env: %w", err)
	}

	getOr := func(key, fallback string) string {
		if v, ok := f.Get(key); ok {
			return v
		}
		return fallback
	}

	siteDomain := getOr("SITE_DOMAIN", "local.statbus.org")
	dbPort := getOr("CADDY_DB_PORT", "5432")

	env := os.Environ()
	env = append(env,
		"PGHOST="+siteDomain,
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
	env, err := psqlEnv(projDir)
	if err != nil {
		return "", err
	}

	args := append([]string{"-v", "ON_ERROR_STOP=on"}, extraArgs...)
	cmd := exec.Command("psql", args...)
	cmd.Dir = projDir
	cmd.Env = env
	cmd.Stdin = strings.NewReader(sql)

	out, err := cmd.CombinedOutput()
	return string(out), err
}

// runPsqlFile executes a SQL file via psql.
func runPsqlFile(projDir string, filePath string) (string, error) {
	env, err := psqlEnv(projDir)
	if err != nil {
		return "", err
	}

	file, err := os.Open(filePath)
	if err != nil {
		return "", fmt.Errorf("open migration file: %w", err)
	}
	defer file.Close()

	cmd := exec.Command("psql", "-v", "ON_ERROR_STOP=on")
	cmd.Dir = projDir
	cmd.Env = env
	cmd.Stdin = file

	out, err := cmd.CombinedOutput()
	return string(out), err
}

// Up applies pending migrations.
// If migrateTo > 0, only apply up to that version.
// If all is false, apply only one pending migration.
func Up(projDir string, migrateTo int64, all bool, verbose bool) error {
	// Find migration files
	patterns := []string{
		filepath.Join(projDir, "migrations", "*.up.sql"),
		filepath.Join(projDir, "migrations", "*.up.psql"),
	}

	var files []string
	for _, p := range patterns {
		matches, _ := filepath.Glob(p)
		files = append(files, matches...)
	}

	// Parse and sort
	var migrations []*MigrationFile
	for _, f := range files {
		mf, err := parseMigrationFile(f)
		if err != nil {
			return err
		}
		migrations = append(migrations, mf)
	}
	sort.Slice(migrations, func(i, j int) bool {
		return migrations[i].Version < migrations[j].Version
	})

	// Check for duplicate versions
	seen := make(map[int64]string)
	for _, m := range migrations {
		if prev, ok := seen[m.Version]; ok {
			return fmt.Errorf("duplicate migration version %d: %s and %s", m.Version, prev, filepath.Base(m.Path))
		}
		seen[m.Version] = filepath.Base(m.Path)
	}

	if len(migrations) == 0 {
		fmt.Println("No up migrations found")
		return nil
	}

	// Ensure migration table exists
	ensureSQL := `
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

	if _, err := runPsql(projDir, ensureSQL); err != nil {
		return fmt.Errorf("ensure migration table: %w", err)
	}

	// Get applied versions
	appliedOut, err := runPsql(projDir, "SELECT version FROM db.migration ORDER BY version", "-t", "-A")
	if err != nil {
		return fmt.Errorf("query applied migrations: %w", err)
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

	if len(pending) == 0 {
		fmt.Println("All migrations are up to date")
		return nil
	}

	// Apply
	appliedCount := 0
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
			return fmt.Errorf("migration %d (%s) failed: %w\n%s", m.Version, filepath.Base(m.Path), err, out)
		}

		// Record success
		recordSQL := fmt.Sprintf(
			"INSERT INTO db.migration (version, filename, description, duration_ms) VALUES (%d, '%s', '%s', %d)",
			m.Version, strings.ReplaceAll(filepath.Base(m.Path), "'", "''"), strings.ReplaceAll(m.Description, "'", "''"), durationMs)
		if _, err := runPsql(projDir, recordSQL); err != nil {
			return fmt.Errorf("record migration %d: %w", m.Version, err)
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

	return nil
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
		// Find down migration file
		downPatterns := []string{
			filepath.Join(projDir, "migrations", fmt.Sprintf("%d_*.down.sql", version)),
			filepath.Join(projDir, "migrations", fmt.Sprintf("%d_*.down.psql", version)),
		}
		var downPath string
		for _, p := range downPatterns {
			matches, _ := filepath.Glob(p)
			if len(matches) > 0 {
				downPath = matches[0]
				break
			}
		}
		if downPath == "" {
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
	safeDesc = regexp.MustCompile(`[^a-z0-9]+`).ReplaceAllString(safeDesc, "_")

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

// PsqlArgs returns the psql command and arguments needed to connect.
// Used by `sb psql` to exec into psql with the right connection settings.
func PsqlArgs(projDir string) ([]string, []string, error) {
	env, err := psqlEnv(projDir)
	if err != nil {
		return nil, nil, err
	}
	return []string{"psql"}, env, nil
}

// PsqlProjectDir is a convenience to get projDir for psql commands.
func PsqlProjectDir() string {
	return config.ProjectDir()
}

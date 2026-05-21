package migrate

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/dotenv"
)

// writeEnv writes a throw-away .env file in a temp dir and returns the project
// directory (parent of the .env). Uses t.TempDir() for auto-cleanup.
func writeEnv(t *testing.T, contents string) string {
	t.Helper()
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, ".env"), []byte(contents), 0o600); err != nil {
		t.Fatalf("write .env: %v", err)
	}
	return dir
}

func TestPsqlEnv_UsesCaddyBind(t *testing.T) {
	dir := writeEnv(t, strings.Join([]string{
		"CADDY_DB_BIND_ADDRESS=127.0.0.1",
		"CADDY_DB_PORT=3014",
		"POSTGRES_APP_DB=statbus_test",
		"POSTGRES_ADMIN_USER=postgres",
		"POSTGRES_ADMIN_PASSWORD=secret",
	}, "\n"))

	// Scrub process env so we're not testing the override path.
	t.Setenv("PGHOST", "")
	t.Setenv("PGPORT", "")
	t.Setenv("PGDATABASE", "")
	t.Setenv("SITE_DOMAIN", "")

	env, err := psqlEnv(dir)
	if err != nil {
		t.Fatalf("psqlEnv: %v", err)
	}

	want := map[string]string{
		"PGHOST":     "127.0.0.1",
		"PGPORT":     "3014",
		"PGDATABASE": "statbus_test",
		"PGUSER":     "postgres",
		"PGPASSWORD": "secret",
	}
	got := map[string]string{}
	for _, kv := range env {
		for k := range want {
			if strings.HasPrefix(kv, k+"=") {
				got[k] = strings.TrimPrefix(kv, k+"=")
			}
		}
	}
	for k, v := range want {
		if got[k] != v {
			t.Errorf("env[%s] = %q, want %q", k, got[k], v)
		}
	}
}

// TestPsqlEnv_PGDATABASE_OverrideWins verifies the operator-standard
// resolution: PGDATABASE env wins over .env's POSTGRES_APP_DB. Pre-fix
// the appended `PGDATABASE=<POSTGRES_APP_DB>` silently overrode any
// pre-existing PGDATABASE because exec.Command resolves duplicate
// env keys last-wins.
func TestPsqlEnv_PGDATABASE_OverrideWins(t *testing.T) {
	dir := writeEnv(t, strings.Join([]string{
		"CADDY_DB_BIND_ADDRESS=127.0.0.1",
		"CADDY_DB_PORT=3014",
		"POSTGRES_APP_DB=statbus_default",
		"POSTGRES_ADMIN_USER=postgres",
		"POSTGRES_ADMIN_PASSWORD=secret",
	}, "\n"))
	t.Setenv("PGHOST", "")
	t.Setenv("PGPORT", "")
	t.Setenv("PGDATABASE", "statbus_seed_via_env")
	t.Setenv("SITE_DOMAIN", "")

	env, err := psqlEnv(dir)
	if err != nil {
		t.Fatalf("psqlEnv: %v", err)
	}

	// Walk env in order, last PGDATABASE= entry is what exec.Command will use.
	var last string
	for _, kv := range env {
		if strings.HasPrefix(kv, "PGDATABASE=") {
			last = strings.TrimPrefix(kv, "PGDATABASE=")
		}
	}
	if last != "statbus_seed_via_env" {
		t.Errorf("PGDATABASE override leaked: last PGDATABASE= entry was %q, want %q (POSTGRES_APP_DB shadowed the operator override)",
			last, "statbus_seed_via_env")
	}
}

// TestPsqlEnv_PGDATABASE_EmptyFallsBack regression guards the fallback:
// when PGDATABASE is unset (or empty), the .env's POSTGRES_APP_DB is
// the source of truth. Without this, scrubbing PGDATABASE in tests
// could regress to surfacing test-runner-leaked PGDATABASE.
func TestPsqlEnv_PGDATABASE_EmptyFallsBack(t *testing.T) {
	dir := writeEnv(t, strings.Join([]string{
		"CADDY_DB_BIND_ADDRESS=127.0.0.1",
		"CADDY_DB_PORT=3014",
		"POSTGRES_APP_DB=statbus_default",
		"POSTGRES_ADMIN_USER=postgres",
		"POSTGRES_ADMIN_PASSWORD=secret",
	}, "\n"))
	t.Setenv("PGHOST", "")
	t.Setenv("PGPORT", "")
	t.Setenv("PGDATABASE", "")
	t.Setenv("SITE_DOMAIN", "")

	env, err := psqlEnv(dir)
	if err != nil {
		t.Fatalf("psqlEnv: %v", err)
	}

	var last string
	for _, kv := range env {
		if strings.HasPrefix(kv, "PGDATABASE=") {
			last = strings.TrimPrefix(kv, "PGDATABASE=")
		}
	}
	if last != "statbus_default" {
		t.Errorf("PGDATABASE fallback wrong: last PGDATABASE= entry was %q, want %q (POSTGRES_APP_DB from .env)",
			last, "statbus_default")
	}
}

func TestPsqlEnv_MissingKeyFailsLoud(t *testing.T) {
	// No CADDY_DB_BIND_ADDRESS in .env.
	dir := writeEnv(t, "CADDY_DB_PORT=3014\n")
	t.Setenv("PGHOST", "")
	t.Setenv("SITE_DOMAIN", "")

	_, err := psqlEnv(dir)
	if err == nil {
		t.Fatal("expected error for missing CADDY_DB_BIND_ADDRESS, got nil")
	}
	if !strings.Contains(err.Error(), "CADDY_DB_BIND_ADDRESS") {
		t.Errorf("error should mention key name: %v", err)
	}
	if !strings.Contains(err.Error(), "./sb config generate") {
		t.Errorf("error should point at config generate: %v", err)
	}
}

func TestAcquireAdvisoryLockConnStr(t *testing.T) {
	dir := writeEnv(t, strings.Join([]string{
		"CADDY_DB_BIND_ADDRESS=127.0.0.1",
		"CADDY_DB_PORT=3014",
		"POSTGRES_APP_DB=statbus_test",
		"POSTGRES_ADMIN_USER=postgres",
		"POSTGRES_ADMIN_PASSWORD=secret",
	}, "\n"))

	f, err := dotenv.Load(filepath.Join(dir, ".env"))
	if err != nil {
		t.Fatalf("load .env: %v", err)
	}
	connStr, err := advisoryLockConnStr(f)
	if err != nil {
		t.Fatalf("advisoryLockConnStr: %v", err)
	}
	for _, want := range []string{
		"host=127.0.0.1",
		"port=3014",
		"dbname=statbus_test",
		"user=postgres",
		"password=secret",
		"sslmode=disable",
	} {
		if !strings.Contains(connStr, want) {
			t.Errorf("connStr missing %q; got %q", want, connStr)
		}
	}
}

func TestParseMigrationFile(t *testing.T) {
	valid := []struct {
		path        string
		version     int64
		description string
		isUp        bool
		extension   string
	}{
		{"migrations/20260311174120_add_upgrade_tracking.up.sql", 20260311174120, "add_upgrade_tracking", true, "sql"},
		{"migrations/20260204234245_btree_optimization.down.sql", 20260204234245, "btree_optimization", false, "sql"},
		{"/abs/path/20260101000000_initial.up.psql", 20260101000000, "initial", true, "psql"},
		{"20261231235959_end_of_year.down.psql", 20261231235959, "end_of_year", false, "psql"},
		{"20260101120000_multi_word_description.up.sql", 20260101120000, "multi_word_description", true, "sql"},
		{"20260601000000_ab.up.sql", 20260601000000, "ab", true, "sql"},
	}
	for _, tc := range valid {
		mf, err := parseMigrationFile(tc.path)
		if err != nil {
			t.Errorf("parseMigrationFile(%q) error: %v", tc.path, err)
			continue
		}
		if mf.Version != tc.version {
			t.Errorf("%q: version = %d, want %d", tc.path, mf.Version, tc.version)
		}
		if mf.Description != tc.description {
			t.Errorf("%q: description = %q, want %q", tc.path, mf.Description, tc.description)
		}
		if mf.IsUp != tc.isUp {
			t.Errorf("%q: isUp = %v, want %v", tc.path, mf.IsUp, tc.isUp)
		}
		if mf.Extension != tc.extension {
			t.Errorf("%q: extension = %q, want %q", tc.path, mf.Extension, tc.extension)
		}
	}

	invalid := []string{
		"not_a_migration.sql",
		"20260311_missing_seconds.up.sql",
		"12345_too_short.up.sql",
		"20260311174120_desc.up.txt",          // wrong extension
		"20260311174120_desc.sql",             // missing direction
		"20261301000000_bad_month.up.sql",     // month 13 invalid
		"20260230000000_bad_day.up.sql",       // Feb 30 invalid
		"99991232000000_bad_timestamp.up.sql", // Dec 32 invalid
	}
	for _, path := range invalid {
		_, err := parseMigrationFile(path)
		if err == nil {
			t.Errorf("parseMigrationFile(%q) expected error, got nil", path)
		}
	}
}

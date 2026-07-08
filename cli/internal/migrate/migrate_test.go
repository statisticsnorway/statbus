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

// TestSetTargetDB_UnconditionalSetsAndRestores pins the shared primitive:
// no divergence check, ever — this is what QueryDB and the seed-verify
// pipeline's migrateNamedDb rely on, since their dbName is explicit fixed
// internal state (e.g. "postgres", "statbus_seed"), not something resolved
// from the operator's env/config. Overriding a DIFFERENT pre-existing value
// must proceed silently here (the refuse behavior lives only in
// OverrideTargetDB, below, for the two operator-facing cobra entrypoints).
func TestSetTargetDB_UnconditionalSetsAndRestores(t *testing.T) {
	t.Setenv("POSTGRES_APP_DB", "some_unrelated_db")
	t.Setenv("PGDATABASE", "some_unrelated_db")

	restore := SetTargetDB("statbus_seed")
	if got := os.Getenv("POSTGRES_APP_DB"); got != "statbus_seed" {
		t.Fatalf("POSTGRES_APP_DB = %q, want statbus_seed (no refusal expected)", got)
	}
	if got := os.Getenv("PGDATABASE"); got != "statbus_seed" {
		t.Fatalf("PGDATABASE = %q, want statbus_seed (no refusal expected)", got)
	}

	restore()
	if got := os.Getenv("POSTGRES_APP_DB"); got != "some_unrelated_db" {
		t.Errorf("POSTGRES_APP_DB = %q after restore, want some_unrelated_db", got)
	}
	if got := os.Getenv("PGDATABASE"); got != "some_unrelated_db" {
		t.Errorf("PGDATABASE = %q after restore, want some_unrelated_db", got)
	}
}

// TestSetTargetDB_UnsetSetsAndRestoresToUnset: nothing exported beforehand →
// restore() puts the process back to fully unset (not merely empty).
func TestSetTargetDB_UnsetSetsAndRestoresToUnset(t *testing.T) {
	os.Unsetenv("POSTGRES_APP_DB")
	os.Unsetenv("PGDATABASE")
	t.Cleanup(func() {
		os.Unsetenv("POSTGRES_APP_DB")
		os.Unsetenv("PGDATABASE")
	})

	restore := SetTargetDB("statbus_seed")
	if got := os.Getenv("POSTGRES_APP_DB"); got != "statbus_seed" {
		t.Fatalf("POSTGRES_APP_DB = %q, want statbus_seed", got)
	}

	restore()
	if _, ok := os.LookupEnv("POSTGRES_APP_DB"); ok {
		t.Error("expected POSTGRES_APP_DB unset after restore")
	}
	if _, ok := os.LookupEnv("PGDATABASE"); ok {
		t.Error("expected PGDATABASE unset after restore")
	}
}

// TestOverrideTargetDB_DivergentPOSTGRES_APP_DBRefusesLoudly is the
// STATBUS-146 pin: at the two operator-facing target-selection entrypoints
// (`./sb migrate up`/`redo`), a target-selection env var the operator set
// must either work or refuse — never get silently discarded while the
// command goes on to report success against a different database (the
// original bug: `POSTGRES_APP_DB=statbus_floor_test ./sb migrate up`
// silently targeted statbus_local and printed "up to date").
func TestOverrideTargetDB_DivergentPOSTGRES_APP_DBRefusesLoudly(t *testing.T) {
	t.Setenv("POSTGRES_APP_DB", "statbus_floor_test")
	t.Setenv("PGDATABASE", "")

	restore, err := OverrideTargetDB("statbus_local")
	if err == nil {
		if restore != nil {
			restore()
		}
		t.Fatal("expected refusal on divergent POSTGRES_APP_DB, got nil error")
	}
	if restore != nil {
		t.Error("expected nil restore func on refusal")
	}
	for _, want := range []string{"POSTGRES_APP_DB", "statbus_floor_test", "statbus_local", "--target"} {
		if !strings.Contains(err.Error(), want) {
			t.Errorf("error %q should mention %q (names both databases + the remedy)", err.Error(), want)
		}
	}
}

// TestOverrideTargetDB_DivergentPGDATABASERefusesLoudly covers the other
// target-selection var — PGDATABASE is the operator-standard override
// (psql's own convention); it must refuse identically to POSTGRES_APP_DB.
func TestOverrideTargetDB_DivergentPGDATABASERefusesLoudly(t *testing.T) {
	t.Setenv("POSTGRES_APP_DB", "")
	t.Setenv("PGDATABASE", "statbus_scratch")

	_, err := OverrideTargetDB("statbus_local")
	if err == nil {
		t.Fatal("expected refusal on divergent PGDATABASE, got nil error")
	}
	for _, want := range []string{"PGDATABASE", "statbus_scratch", "statbus_local"} {
		if !strings.Contains(err.Error(), want) {
			t.Errorf("error %q should mention %q", err.Error(), want)
		}
	}
}

// TestOverrideTargetDB_EqualProceedsSilently keeps the documented
// `eval $(./sb config show --postgres)` workflow friction-free: when the
// operator's exported value already matches the resolved target, there is
// nothing to refuse.
func TestOverrideTargetDB_EqualProceedsSilently(t *testing.T) {
	t.Setenv("POSTGRES_APP_DB", "statbus_local")
	t.Setenv("PGDATABASE", "statbus_local")

	restore, err := OverrideTargetDB("statbus_local")
	if err != nil {
		t.Fatalf("expected no error when already equal, got %v", err)
	}
	defer restore()

	if got := os.Getenv("POSTGRES_APP_DB"); got != "statbus_local" {
		t.Errorf("POSTGRES_APP_DB = %q, want statbus_local", got)
	}
	if got := os.Getenv("PGDATABASE"); got != "statbus_local" {
		t.Errorf("PGDATABASE = %q, want statbus_local", got)
	}
}

// TestOverrideTargetDB_UnsetSetsAndRestores is the base case: nothing
// exported beforehand → no divergence possible → proceeds, and restore()
// puts the process back to fully unset (not merely empty).
func TestOverrideTargetDB_UnsetSetsAndRestores(t *testing.T) {
	os.Unsetenv("POSTGRES_APP_DB")
	os.Unsetenv("PGDATABASE")
	t.Cleanup(func() {
		os.Unsetenv("POSTGRES_APP_DB")
		os.Unsetenv("PGDATABASE")
	})

	restore, err := OverrideTargetDB("statbus_seed")
	if err != nil {
		t.Fatalf("expected no error when unset, got %v", err)
	}
	if got := os.Getenv("POSTGRES_APP_DB"); got != "statbus_seed" {
		t.Fatalf("POSTGRES_APP_DB = %q, want statbus_seed", got)
	}

	restore()
	if _, ok := os.LookupEnv("POSTGRES_APP_DB"); ok {
		t.Error("expected POSTGRES_APP_DB unset after restore")
	}
	if _, ok := os.LookupEnv("PGDATABASE"); ok {
		t.Error("expected PGDATABASE unset after restore")
	}
}

// TestOverrideTargetDB_EmptyStringExportIsNotDivergence matches the
// codebase-wide convention (getOr, PsqlCommand) that an explicitly-empty
// env export is equivalent to absent — a test runner or CI job that leaks
// `PGDATABASE=` (exported empty, not unset) must not trigger a false-positive
// refusal.
func TestOverrideTargetDB_EmptyStringExportIsNotDivergence(t *testing.T) {
	t.Setenv("POSTGRES_APP_DB", "")
	t.Setenv("PGDATABASE", "")

	restore, err := OverrideTargetDB("statbus_local")
	if err != nil {
		t.Fatalf("expected no error for empty-string exports, got %v", err)
	}
	defer restore()
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

package cmd

import (
	"errors"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/migrate"
)

func TestSeedCacheIncompatibleHasDedicatedExitCode(t *testing.T) {
	err := &commandExecutionError{err: &seedCacheIncompatibleError{err: errors.New("stale cache")}}
	if got := ExitCode(err); got != ExitSeedIncompatible {
		t.Fatalf("ExitCode(incompatible seed) = %d, want %d", got, ExitSeedIncompatible)
	}
	if got := ExitCode(&commandExecutionError{err: errors.New("pg_restore failed")}); got == ExitSeedIncompatible {
		t.Fatalf("generic restore failure must not use incompatible-cache exit %d", got)
	}
}

func cachedSeedProject(t *testing.T) (string, seedMeta) {
	t.Helper()
	projDir := t.TempDir()
	migrationsDir := filepath.Join(projDir, "migrations")
	if err := os.MkdirAll(migrationsDir, 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(migrationsDir, "20260916000100_original.up.sql"), []byte("SELECT 1;\n"), 0644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(migrationsDir, "post_restore.sql"), []byte("SELECT 2;\n"), 0644); err != nil {
		t.Fatal(err)
	}
	fingerprint, err := migrate.UpMigrationsFingerprintUpTo(projDir, 20260916000100)
	if err != nil {
		t.Fatal(err)
	}
	postRestoreSHA, err := postRestoreFileSHA(projDir)
	if err != nil {
		t.Fatal(err)
	}
	return projDir, seedMeta{
		MigrationVersion:      "20260916000100",
		MigrationsFingerprint: fingerprint,
		PostRestoreSHA:        postRestoreSHA,
	}
}

// This structural guard pins the safety boundary in the real command, not just
// the pure validator: incompatibility must be decided before the dump is opened
// and before a pg_restore process can be constructed. Thus every rejection path
// returns while the target database is still untouched.
func TestRunSeedRestoreCmd_ValidatesCacheBeforeRestoreMutation(t *testing.T) {
	_, testFile, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("resolve test source path")
	}
	seedSource, err := os.ReadFile(filepath.Join(filepath.Dir(testFile), "seed.go"))
	if err != nil {
		t.Fatal(err)
	}
	source := string(seedSource)
	start := strings.Index(source, "func runSeedRestoreCmd(")
	if start < 0 {
		t.Fatal("locate runSeedRestoreCmd start")
	}
	end := strings.Index(source[start:], "\n}\n\n// ── seed dump")
	if end < 0 {
		t.Fatal("locate runSeedRestoreCmd end")
	}
	body := source[start : start+end]
	validateAt := strings.Index(body, "validateCachedSeedForRestore(")
	openAt := strings.Index(body, "os.Open(dumpPath)")
	execAt := strings.Index(body, `composeCommand(projDir, "exec"`)
	if validateAt < 0 || openAt < 0 || execAt < 0 {
		t.Fatalf("restore safety landmarks missing: validate=%d open=%d exec=%d", validateAt, openAt, execAt)
	}
	if validateAt > openAt || validateAt > execAt {
		t.Fatalf("cache validation must precede every restore mutation: validate=%d open=%d exec=%d", validateAt, openAt, execAt)
	}
	if strings.Contains(body, "DROP DATABASE") || strings.Contains(body, "resetStaleSeededDB") {
		t.Fatal("seed restore self-heal must never drop or reset the target database")
	}
}

func TestValidateCachedSeedForRestore_AcceptsMatchingCache(t *testing.T) {
	projDir, meta := cachedSeedProject(t)
	if err := validateCachedSeedForRestore(projDir, &meta); err != nil {
		t.Fatalf("matching cache rejected: %v", err)
	}
}

func TestValidateCachedSeedForRestore_RejectsRetimestampedBakedMigration(t *testing.T) {
	projDir, meta := cachedSeedProject(t)
	migrationsDir := filepath.Join(projDir, "migrations")
	if err := os.Remove(filepath.Join(migrationsDir, "20260916000100_original.up.sql")); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(migrationsDir, "20260916000050_retimestamped.up.sql"), []byte("SELECT 1;\n"), 0644); err != nil {
		t.Fatal(err)
	}

	err := validateCachedSeedForRestore(projDir, &meta)
	if err == nil {
		t.Fatal("retimestamped baked migration must reject cached seed")
	}
	if !strings.Contains(err.Error(), "differ from the cached seed fingerprint") {
		t.Fatalf("unexpected rejection: %v", err)
	}
}

func TestValidateCachedSeedForRestore_RejectsLegacyAndMalformedMetadata(t *testing.T) {
	projDir, meta := cachedSeedProject(t)

	withoutFingerprint := meta
	withoutFingerprint.MigrationsFingerprint = ""
	if err := validateCachedSeedForRestore(projDir, &withoutFingerprint); err == nil {
		t.Fatal("missing migrations fingerprint must reject cached seed")
	}

	withoutPostRestore := meta
	withoutPostRestore.PostRestoreSHA = ""
	if err := validateCachedSeedForRestore(projDir, &withoutPostRestore); err == nil {
		t.Fatal("missing post_restore fingerprint must reject cached seed")
	}

	malformedVersion := meta
	malformedVersion.MigrationVersion = "not-a-version"
	if err := validateCachedSeedForRestore(projDir, &malformedVersion); err == nil {
		t.Fatal("malformed migration version must reject cached seed")
	}
}

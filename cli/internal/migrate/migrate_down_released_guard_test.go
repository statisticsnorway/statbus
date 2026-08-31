package migrate

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/statisticsnorway/statbus/cli/internal/testgit"
)

// makeReleaseGuardRepo builds a throwaway git repo with:
//   - a migration committed and tagged in a STABLE release from LAST
//     calendar month (so release.CurrentImmutabilityBaselineTag resolves to
//     it via FindLatestStableTagBeforePrefix's cross-year-month induction,
//     regardless of what "today" actually is when this test runs — no
//     current-month tag exists, so PickPrereleasePredecessor's patch==0
//     branch always lands here)
//   - a second, WIP migration committed AFTER the tag, never tagged
//
// Returns (dir, releasedVersion, wipVersion, releaseTag).
func makeReleaseGuardRepo(t *testing.T) (dir string, releasedVersion, wipVersion int64, releaseTag string) {
	t.Helper()
	if _, err := exec.LookPath("git"); err != nil {
		t.Skip("git not on PATH")
	}
	dir = t.TempDir()

	run := func(args ...string) {
		t.Helper()
		cmd := exec.Command("git", testgit.Args(args...)...)
		cmd.Dir = dir
		cmd.Env = testgit.Env()
		cmd.Env = append(os.Environ(),
			"GIT_AUTHOR_NAME=Test", "GIT_AUTHOR_EMAIL=test@example.invalid",
			"GIT_COMMITTER_NAME=Test", "GIT_COMMITTER_EMAIL=test@example.invalid",
		)
		if out, err := cmd.CombinedOutput(); err != nil {
			t.Fatalf("git %s: %v\n%s", strings.Join(args, " "), err, out)
		}
	}

	run("init", "-q")
	run("config", "user.name", "Test")
	run("config", "user.email", "test@example.invalid")
	run("config", "commit.gpgsign", "false")
	run("config", "tag.gpgsign", "false")

	migrationsDir := filepath.Join(dir, "migrations")
	if err := os.MkdirAll(migrationsDir, 0755); err != nil {
		t.Fatal(err)
	}

	releasedVersion = 20260101000000
	releasedUp := filepath.Join(migrationsDir, fmt.Sprintf("%d_released.up.sql", releasedVersion))
	if err := os.WriteFile(releasedUp, []byte("-- released up\n"), 0644); err != nil {
		t.Fatal(err)
	}
	// Empty down file (matches down_ledger_hardfail_test.go's convention):
	// releasedMigrationDownGuard never reads down-file CONTENT (only the up
	// file's presence in a release tag), and an empty down file lets the
	// Down()-integration tests below exercise the ledger-DELETE-only branch
	// without a real psql/database connection.
	releasedDown := filepath.Join(migrationsDir, fmt.Sprintf("%d_released.down.sql", releasedVersion))
	if err := os.WriteFile(releasedDown, nil, 0644); err != nil {
		t.Fatal(err)
	}
	run("add", "migrations")
	run("commit", "-q", "-m", "released migration")

	lastMonth := time.Date(time.Now().Year(), time.Now().Month(), 1, 0, 0, 0, 0, time.UTC).AddDate(0, -1, 0)
	releaseTag = fmt.Sprintf("v%d.%02d.0", lastMonth.Year(), int(lastMonth.Month()))
	tagCmd := exec.Command("git", "tag", "-a", releaseTag, "-m", "Release "+releaseTag)
	tagCmd.Dir = dir
	if out, err := tagCmd.CombinedOutput(); err != nil {
		t.Fatalf("tag -a %s: %v\n%s", releaseTag, err, out)
	}

	wipVersion = 20260201000000
	wipUp := filepath.Join(migrationsDir, fmt.Sprintf("%d_wip.up.sql", wipVersion))
	if err := os.WriteFile(wipUp, []byte("-- wip up\n"), 0644); err != nil {
		t.Fatal(err)
	}
	wipDown := filepath.Join(migrationsDir, fmt.Sprintf("%d_wip.down.sql", wipVersion))
	if err := os.WriteFile(wipDown, nil, 0644); err != nil { // empty — see releasedDown's comment above
		t.Fatal(err)
	}
	run("add", "migrations")
	run("commit", "-q", "-m", "wip migration")

	return dir, releasedVersion, wipVersion, releaseTag
}

// withEnv sets the environment variable for the duration of the test,
// restoring the prior value (or unsetting it) on cleanup.
func withEnv(t *testing.T, key, value string) {
	t.Helper()
	prior, had := os.LookupEnv(key)
	if err := os.Setenv(key, value); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if had {
			_ = os.Setenv(key, prior)
		} else {
			_ = os.Unsetenv(key)
		}
	})
}

// writeDotEnv writes a minimal .env so currentMigrationTarget can classify
// PGDATABASE as "dev" (POSTGRES_APP_DB) or "seed" (POSTGRES_SEED_DB).
func writeDotEnv(t *testing.T, dir string) {
	t.Helper()
	content := "POSTGRES_APP_DB=statbus_dev_test\nPOSTGRES_SEED_DB=statbus_seed_test\n"
	if err := os.WriteFile(filepath.Join(dir, ".env"), []byte(content), 0644); err != nil {
		t.Fatal(err)
	}
}

// captureStdout runs fn and returns everything it printed to os.Stdout.
func captureStdout(t *testing.T, fn func()) string {
	t.Helper()
	r, w, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	orig := os.Stdout
	os.Stdout = w
	fn()
	_ = w.Close()
	os.Stdout = orig
	buf := make([]byte, 64*1024)
	n, _ := r.Read(buf)
	return string(buf[:n])
}

// TestReleasedMigrationDownGuard_RefusesReleasedOnDev and its _Seed sibling
// are STATBUS-329 AC#1/AC#3: a released migration must refuse on BOTH
// targets, and the refusal must name the migration, the tag, and — seed only
// — the published-artifact consequence.
func TestReleasedMigrationDownGuard_RefusesReleasedOnDev(t *testing.T) {
	dir, releasedVersion, _, releaseTag := makeReleaseGuardRepo(t)
	writeDotEnv(t, dir)
	withEnv(t, "PGDATABASE", "statbus_dev_test")

	err := releasedMigrationDownGuard(dir, []int64{releasedVersion})
	if err == nil {
		t.Fatal("expected refusal for a released migration on dev, got nil")
	}
	msg := err.Error()
	if !strings.Contains(msg, fmt.Sprintf("%d", releasedVersion)) {
		t.Errorf("refusal does not name the migration version: %q", msg)
	}
	if !strings.Contains(msg, releaseTag) {
		t.Errorf("refusal does not name the release tag: %q", msg)
	}
	if !strings.Contains(msg, IntentionallyRevertReleasedMigrationEnvVar) {
		t.Errorf("refusal does not name the override: %q", msg)
	}
	if strings.Contains(msg, "SEED") {
		t.Errorf("dev-target refusal should not carry the seed-specific consequence line: %q", msg)
	}
}

func TestReleasedMigrationDownGuard_RefusesReleasedOnSeed_NamesPublishConsequence(t *testing.T) {
	dir, releasedVersion, _, releaseTag := makeReleaseGuardRepo(t)
	writeDotEnv(t, dir)
	withEnv(t, "PGDATABASE", "statbus_seed_test")

	err := releasedMigrationDownGuard(dir, []int64{releasedVersion})
	if err == nil {
		t.Fatal("expected refusal for a released migration on seed, got nil")
	}
	msg := err.Error()
	if !strings.Contains(msg, fmt.Sprintf("%d", releasedVersion)) {
		t.Errorf("refusal does not name the migration version: %q", msg)
	}
	if !strings.Contains(msg, releaseTag) {
		t.Errorf("refusal does not name the release tag: %q", msg)
	}
	if !strings.Contains(msg, "SEED") || !strings.Contains(msg, "publish") {
		t.Errorf("seed-target refusal must name the published-artifact consequence: %q", msg)
	}
}

// TestReleasedMigrationDownGuard_WIPPassesUnchanged is AC#5's WIP case: a
// migration that has never been released must never be refused.
func TestReleasedMigrationDownGuard_WIPPassesUnchanged(t *testing.T) {
	dir, _, wipVersion, _ := makeReleaseGuardRepo(t)
	writeDotEnv(t, dir)
	withEnv(t, "PGDATABASE", "statbus_dev_test")

	if err := releasedMigrationDownGuard(dir, []int64{wipVersion}); err != nil {
		t.Errorf("WIP migration must pass unchanged, got error: %v", err)
	}
}

// TestReleasedMigrationDownGuard_MixedBatchRefusesOnTheReleasedOne covers a
// --to range crossing the released/WIP boundary: the WIP-only version must
// not make the batch pass silently when a released version is ALSO present.
func TestReleasedMigrationDownGuard_MixedBatchRefusesOnTheReleasedOne(t *testing.T) {
	dir, releasedVersion, wipVersion, releaseTag := makeReleaseGuardRepo(t)
	writeDotEnv(t, dir)
	withEnv(t, "PGDATABASE", "statbus_dev_test")

	err := releasedMigrationDownGuard(dir, []int64{wipVersion, releasedVersion})
	if err == nil {
		t.Fatal("expected refusal for a mixed batch containing a released migration, got nil")
	}
	if !strings.Contains(err.Error(), releaseTag) {
		t.Errorf("refusal does not name the release tag: %q", err.Error())
	}
}

// TestReleasedMigrationDownGuard_OverrideProceedsLoudly is AC#4: the named
// env var bypasses the refusal, but must print an unmissable acknowledgment
// naming the migration and the tag it bypassed — the override does not
// proceed silently.
func TestReleasedMigrationDownGuard_OverrideProceedsLoudly(t *testing.T) {
	dir, releasedVersion, _, releaseTag := makeReleaseGuardRepo(t)
	writeDotEnv(t, dir)
	withEnv(t, "PGDATABASE", "statbus_dev_test")
	withEnv(t, IntentionallyRevertReleasedMigrationEnvVar, "1")

	var err error
	out := captureStdout(t, func() {
		err = releasedMigrationDownGuard(dir, []int64{releasedVersion})
	})
	if err != nil {
		t.Fatalf("override must proceed (err=nil), got: %v", err)
	}
	if !strings.Contains(out, IntentionallyRevertReleasedMigrationEnvVar) {
		t.Errorf("override acknowledgment does not name the env var: %q", out)
	}
	if !strings.Contains(out, fmt.Sprintf("%d", releasedVersion)) {
		t.Errorf("override acknowledgment does not name the migration: %q", out)
	}
	if !strings.Contains(out, releaseTag) {
		t.Errorf("override acknowledgment does not name the release tag: %q", out)
	}
}

// TestReleasedMigrationDownGuard_OnlyTheNamedOverrideWorks is AC#4's negative
// half: nothing else (a generic FORCE=1, an unrelated truthy value on the
// right var) may bypass the refusal.
func TestReleasedMigrationDownGuard_OnlyTheNamedOverrideWorks(t *testing.T) {
	dir, releasedVersion, _, _ := makeReleaseGuardRepo(t)
	writeDotEnv(t, dir)
	withEnv(t, "PGDATABASE", "statbus_dev_test")
	withEnv(t, "FORCE", "1")
	withEnv(t, IntentionallyRevertReleasedMigrationEnvVar, "true") // not the exact string "1"

	if err := releasedMigrationDownGuard(dir, []int64{releasedVersion}); err == nil {
		t.Error("FORCE=1 and a non-\"1\" value on the named var must NOT bypass the refusal")
	}
}

// TestDown_RefusesBeforeAnyRollbackSQLRuns is the end-to-end integration
// proof (AC#1): wiring the guard into Down() must refuse ATOMICALLY, before
// any ledger DELETE or rollback SQL is even attempted — a --to range
// crossing the boundary must not partially revert the WIP migrations first.
func TestDown_RefusesBeforeAnyRollbackSQLRuns(t *testing.T) {
	dir, releasedVersion, wipVersion, _ := makeReleaseGuardRepo(t)
	writeDotEnv(t, dir)
	withEnv(t, "PGDATABASE", "statbus_dev_test")

	var sqlCalls []string
	origRunPsqlFn := runPsqlFn
	defer func() { runPsqlFn = origRunPsqlFn }()
	runPsqlFn = func(projDir, sql string, extraArgs ...string) (string, error) {
		sqlCalls = append(sqlCalls, sql)
		switch {
		case strings.Contains(sql, "pg_tables"):
			return "t", nil
		case strings.HasPrefix(sql, "SELECT version FROM db.migration"):
			// Newest-first, matching the DESC query order Down() expects —
			// the WIP version is newer than the released one.
			return fmt.Sprintf("%d\n%d", wipVersion, releasedVersion), nil
		default:
			return "", nil
		}
	}

	err := Down(dir, releasedVersion, false, false) // --to releasedVersion: range crosses the boundary
	if err == nil {
		t.Fatal("Down() = nil, want a refusal (range includes a released migration)")
	}
	if !strings.Contains(err.Error(), fmt.Sprintf("%d", releasedVersion)) {
		t.Errorf("refusal does not name the released version: %q", err.Error())
	}
	for _, c := range sqlCalls {
		if strings.HasPrefix(c, "DELETE FROM db.migration") {
			t.Fatalf("Down() issued a ledger DELETE (%q) before refusing — the guard must run before ANY rollback SQL", c)
		}
	}
}

// TestDown_WIPOnlyRangeProceedsUnchanged confirms the guard's wiring into
// Down() doesn't regress the ordinary WIP-only case: no released migration
// anywhere in the batch, Down() proceeds exactly as it did before STATBUS-329.
func TestDown_WIPOnlyRangeProceedsUnchanged(t *testing.T) {
	dir, _, wipVersion, _ := makeReleaseGuardRepo(t)
	writeDotEnv(t, dir)
	withEnv(t, "PGDATABASE", "statbus_dev_test")

	var deleteCalled bool
	origRunPsqlFn := runPsqlFn
	defer func() { runPsqlFn = origRunPsqlFn }()
	runPsqlFn = func(projDir, sql string, extraArgs ...string) (string, error) {
		switch {
		case strings.Contains(sql, "pg_tables"):
			return "t", nil
		case strings.HasPrefix(sql, "SELECT version FROM db.migration"):
			return fmt.Sprintf("%d", wipVersion), nil
		case strings.HasPrefix(sql, "DELETE FROM db.migration"):
			deleteCalled = true
			return "", nil
		default:
			return "", nil
		}
	}

	if err := Down(dir, 0, false, false); err != nil {
		t.Fatalf("Down() on a WIP-only migration must succeed, got: %v", err)
	}
	if !deleteCalled {
		t.Error("Down() never issued the ledger DELETE — the WIP-only path must proceed exactly as before STATBUS-329")
	}
}

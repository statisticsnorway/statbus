package migrate

import (
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// STATBUS-138 — the shared lister/validity split. One predicate (parseMigrationFile:
// filename regex + timestamp parse) + one lister (listMigrationFiles) are the
// single source for "what is a migration", used by BOTH the applier (migrate.Up)
// and ground truth (MaxDiskVersion). A file the applier would refuse is invisible
// to the comparator BY CONSTRUCTION.

// writeMigrationFile writes a raw-named file into projDir/migrations (so a test
// can place an INVALID name the version-typed helpers can't express).
func writeMigrationFile(t *testing.T, projDir, name, body string) {
	t.Helper()
	dir := filepath.Join(projDir, "migrations")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, name), []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
}

// captureStderr runs fn with os.Stderr redirected to a pipe and returns what was
// written (the lister's warn goes to os.Stderr).
func captureStderr(t *testing.T, fn func()) string {
	t.Helper()
	old := os.Stderr
	r, w, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	os.Stderr = w
	fn()
	_ = w.Close()
	os.Stderr = old
	out, _ := io.ReadAll(r)
	return string(out)
}

// TestListMigrationFilesSkipsInvalidNamed is the r17 pin: a stray whose 14-digit
// prefix is not a real timestamp (99999999999999 — month 99) is SKIPPED with a
// warn naming it, NOT a hard error for the whole run. The valid file survives.
func TestListMigrationFilesSkipsInvalidNamed(t *testing.T) {
	proj := t.TempDir()
	writeMigrationFile(t, proj, "20240101000000_valid.up.sql", "SELECT 1;")
	writeMigrationFile(t, proj, "99999999999999_stray.up.sql", "SELECT 2;") // r17 stray

	var migs []*MigrationFile
	var err error
	warn := captureStderr(t, func() { migs, err = listMigrationFiles(proj) })

	if err != nil {
		t.Fatalf("a stray invalid-named file must NOT hard-error the whole run (r17); got: %v", err)
	}
	if len(migs) != 1 || migs[0].Version != 20240101000000 {
		t.Fatalf("expected exactly the valid migration, got %+v", migs)
	}
	if !strings.Contains(warn, "ignoring invalid migration file 99999999999999_stray.up.sql") {
		t.Errorf("the skip must LOUDLY warn naming the stray file; stderr:\n%s", warn)
	}
}

// TestMaxDiskVersionIgnoresRefusedFile is the direct r17 root-cause pin: the
// ground-truth on-disk max must be the VALID version, never the refused stray's
// 99999999999999 — that inflated max is what read a healthy box as Behind forever.
func TestMaxDiskVersionIgnoresRefusedFile(t *testing.T) {
	proj := t.TempDir()
	writeMigrationFile(t, proj, "20240101000000_valid.up.sql", "SELECT 1;")
	writeMigrationFile(t, proj, "99999999999999_stray.up.sql", "SELECT 2;")

	var max int64
	var err error
	_ = captureStderr(t, func() { max, err = MaxDiskVersion(proj) })
	if err != nil {
		t.Fatalf("MaxDiskVersion must not error on a stray: %v", err)
	}
	if max != 20240101000000 {
		t.Errorf("MaxDiskVersion = %d, want 20240101000000 (the stray 99999999999999 must be invisible — r17 false Behind)", max)
	}
}

// TestListMigrationFilesCountsPsql pins AC#3: .up.psql is counted by the shared
// lister (so both readers see it — closes the inverse false-AtNew hazard where a
// pending .psql was invisible to the old .up.sql-only comparator).
func TestListMigrationFilesCountsPsql(t *testing.T) {
	proj := t.TempDir()
	writeMigrationFile(t, proj, "20240101000000_alpha.up.sql", "SELECT 1;")
	writeMigrationFile(t, proj, "20240102000000_beta.up.psql", "SELECT 2;")

	migs, err := listMigrationFiles(proj)
	if err != nil {
		t.Fatalf("listMigrationFiles: %v", err)
	}
	if len(migs) != 2 {
		t.Fatalf("expected both .up.sql and .up.psql listed, got %d: %+v", len(migs), migs)
	}
	max, err := MaxDiskVersion(proj)
	if err != nil || max != 20240102000000 {
		t.Errorf("MaxDiskVersion = %d (err=%v), want 20240102000000 (the .up.psql) — both readers must count .psql", max, err)
	}
}

// TestListMigrationFilesDuplicateStillErrors pins AC#2's other arm: a valid-name
// file with an OTHER defect (duplicate version) STILL hard-errors — only the
// invalid-NAME class is downgraded to a skip+warn.
func TestListMigrationFilesDuplicateStillErrors(t *testing.T) {
	proj := t.TempDir()
	writeMigrationFile(t, proj, "20240101000000_alpha.up.sql", "SELECT 1;")
	writeMigrationFile(t, proj, "20240101000000_beta.up.sql", "SELECT 2;") // same version

	_, err := listMigrationFiles(proj)
	if err == nil || !strings.Contains(err.Error(), "duplicate migration version") {
		t.Errorf("a duplicate valid version must still hard-error (not skip); got err=%v", err)
	}
}

// TestMaxDiskVersionMissingDir pins the degraded-mode path (was
// TestLatestDiskMigrationVersion_MissingDirReturnsZero in the upgrade pkg before
// the STATBUS-138 clean break): no migrations/ dir → MaxDiskVersion returns 0, no
// error, so ground truth's Check 2 skips instead of falsely failing.
func TestMaxDiskVersionMissingDir(t *testing.T) {
	proj := t.TempDir() // no migrations/ subdir
	max, err := MaxDiskVersion(proj)
	if err != nil || max != 0 {
		t.Errorf("MaxDiskVersion on a missing migrations dir = (%d, %v), want (0, nil)", max, err)
	}
}

// TestListMigrationFilesIgnoresNonVersionAndDown pins the two ignore cases the
// deleted latestDiskMigrationVersion test covered: a no-version-prefix *.up.sql
// (skipped+warned) and a *.down.sql (never globbed).
func TestListMigrationFilesIgnoresNonVersionAndDown(t *testing.T) {
	proj := t.TempDir()
	writeMigrationFile(t, proj, "20240101000000_valid.up.sql", "SELECT 1;")
	writeMigrationFile(t, proj, "misc.up.sql", "SELECT 2;")            // no version prefix → skip+warn
	writeMigrationFile(t, proj, "20240102000000_x.down.sql", "SELECT 3;") // down → never globbed

	var migs []*MigrationFile
	var err error
	warn := captureStderr(t, func() { migs, err = listMigrationFiles(proj) })
	if err != nil {
		t.Fatalf("listMigrationFiles: %v", err)
	}
	if len(migs) != 1 || migs[0].Version != 20240101000000 {
		t.Fatalf("expected only the valid up migration, got %+v", migs)
	}
	if !strings.Contains(warn, "ignoring invalid migration file misc.up.sql") {
		t.Errorf("a no-version-prefix .up.sql must warn; stderr:\n%s", warn)
	}
}

// TestFloorReadersAgreeOnFixture pins AC#4's consistency: on the same r17 fixture,
// the lister's max and MaxDiskVersion agree (they are the SAME source), and the
// floor bump-guard's scan (also on listMigrationFiles) sees the same skip — no
// reader can disagree with another about what a migration is.
func TestFloorReadersAgreeOnFixture(t *testing.T) {
	proj := t.TempDir()
	writeMigrationFile(t, proj, "20240101000000_valid.up.sql", "SELECT 1;")
	writeMigrationFile(t, proj, "99999999999999_stray.up.sql", "SELECT 2;")

	var migs []*MigrationFile
	var listErr error
	var max int64
	var maxErr error
	_ = captureStderr(t, func() {
		migs, listErr = listMigrationFiles(proj)
		max, maxErr = MaxDiskVersion(proj)
	})
	if listErr != nil || maxErr != nil {
		t.Fatalf("readers errored on the stray: list=%v max=%v", listErr, maxErr)
	}
	if len(migs) == 0 || migs[len(migs)-1].Version != max {
		t.Errorf("lister max (%d) and MaxDiskVersion (%d) must agree on the same fixture", migs[len(migs)-1].Version, max)
	}
}

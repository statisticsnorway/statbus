package migrate

import (
	"os"
	"path/filepath"
	"testing"
)

func writeMig(t *testing.T, proj, name, content string) {
	t.Helper()
	if err := os.WriteFile(filepath.Join(proj, "migrations", name), []byte(content), 0644); err != nil {
		t.Fatal(err)
	}
}

func newMigProj(t *testing.T) string {
	t.Helper()
	proj := t.TempDir()
	if err := os.MkdirAll(filepath.Join(proj, "migrations"), 0755); err != nil {
		t.Fatal(err)
	}
	return proj
}

// TestUpMigrationsFingerprintUpTo pins the STATBUS-116 gate anchor: deterministic,
// bounded by maxVersion, and sensitive to any edit/removal of an in-range migration.
func TestUpMigrationsFingerprintUpTo(t *testing.T) {
	proj := newMigProj(t)
	writeMig(t, proj, "20260101000001_first.up.sql", "AAA")
	writeMig(t, proj, "20260101000002_second.up.sql", "BBB")
	writeMig(t, proj, "20260101000003_third.up.sql", "CCC")
	// A down file must be IGNORED (the fingerprint globs up-files only).
	writeMig(t, proj, "20260101000002_second.down.sql", "DROP")

	const v2 = int64(20260101000002)
	const v3 = int64(20260101000003)

	fp2, err := UpMigrationsFingerprintUpTo(proj, v2)
	if err != nil {
		t.Fatal(err)
	}
	fp3, err := UpMigrationsFingerprintUpTo(proj, v3)
	if err != nil {
		t.Fatal(err)
	}

	// Deterministic.
	if again, _ := UpMigrationsFingerprintUpTo(proj, v2); again != fp2 {
		t.Errorf("fingerprint not deterministic: %s vs %s", fp2, again)
	}
	// maxVersion bound: <=v3 includes migration 3, so it differs from <=v2.
	if fp2 == fp3 {
		t.Error("fingerprint must be bounded by maxVersion (<=v2 and <=v3 must differ)")
	}
	// Editing an in-range (<=v2) migration changes the <=v2 digest.
	writeMig(t, proj, "20260101000001_first.up.sql", "AAA-EDITED")
	fpEdited, _ := UpMigrationsFingerprintUpTo(proj, v2)
	if fpEdited == fp2 {
		t.Error("editing a migration <= maxVersion MUST change the fingerprint (the gate's core property)")
	}
	// Removing an in-range migration changes the digest.
	if err := os.Remove(filepath.Join(proj, "migrations", "20260101000001_first.up.sql")); err != nil {
		t.Fatal(err)
	}
	fpRemoved, _ := UpMigrationsFingerprintUpTo(proj, v2)
	if fpRemoved == fpEdited {
		t.Error("removing a migration <= maxVersion MUST change the fingerprint")
	}
}

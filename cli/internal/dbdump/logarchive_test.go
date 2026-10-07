package dbdump

import (
	"os"
	"path/filepath"
	"testing"
)

// ── STATBUS-456: the log companion that travels with a dump ──────────────────

// writeLogFixture creates a log file under dir and returns its path.
func writeLogFixture(t *testing.T, dir, name, content string) string {
	t.Helper()
	if err := os.MkdirAll(dir, 0755); err != nil {
		t.Fatal(err)
	}
	p := filepath.Join(dir, name)
	if err := os.WriteFile(p, []byte(content), 0644); err != nil {
		t.Fatal(err)
	}
	return p
}

// touchDumpAt writes a dump file at an explicit path (unlike touchDump, which
// always uses the dumps dir).
func touchDumpAt(t *testing.T, path string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte("DUMP"), 0644); err != nil {
		t.Fatal(err)
	}
}

// TestWriteLogsCompanion_UpgradeLogsMinusSymlink: the archive carries every
// regular file under tmp/upgrade-logs/ but never the `latest` symlink (a
// dangling link must not ship).
func TestWriteLogsCompanion_UpgradeLogsMinusSymlink(t *testing.T) {
	proj := t.TempDir()
	dump := filepath.Join(DumpsDir(proj), "no_20261007_120000.pg_dump")
	touchDumpAt(t, dump)

	upDir := filepath.Join(proj, "tmp", "upgrade-logs")
	writeLogFixture(t, upDir, "10-v1.0.0-20261001T000000Z.log", "LOG-A")
	writeLogFixture(t, upDir, "10-v1.0.0-20261001T000000Z.bundle.txt", "BUNDLE-A")
	if err := os.Symlink("10-v1.0.0-20261001T000000Z.log", filepath.Join(upDir, "latest")); err != nil {
		t.Fatal(err)
	}

	companion, count, err := WriteLogsCompanion(proj, dump, nil)
	if err != nil {
		t.Fatalf("WriteLogsCompanion: %v", err)
	}
	if count != 2 {
		t.Errorf("count=%d, want 2 (log + bundle, not the latest symlink)", count)
	}
	if companion != LogsCompanionPathFor(dump, zstdAvailable()) {
		t.Errorf("companion path %q does not match the format actually written", companion)
	}

	// Restore into a fresh project and inspect what actually shipped.
	dest := t.TempDir()
	found, restored, err := RestoreLogsCompanion(dest, dump)
	if err != nil || !found {
		t.Fatalf("RestoreLogsCompanion: found=%v err=%v", found, err)
	}
	if restored != 2 {
		t.Errorf("restored=%d, want 2", restored)
	}
	if b, err := os.ReadFile(filepath.Join(dest, "tmp", "upgrade-logs", "10-v1.0.0-20261001T000000Z.log")); err != nil || string(b) != "LOG-A" {
		t.Errorf("upgrade log content=%q err=%v; want LOG-A", b, err)
	}
	if _, err := os.Lstat(filepath.Join(dest, "tmp", "upgrade-logs", "latest")); !os.IsNotExist(err) {
		t.Errorf("the latest symlink must not be restored; lstat err=%v", err)
	}
}

// TestWriteLogsCompanion_ReferencedInstallLogsSelection: tmp/install-logs/ is
// unbounded, so ONLY the referenced files ship — both stored shapes
// ("install-logs/<name>" and a bare basename) resolve, and unreferenced files
// stay behind.
func TestWriteLogsCompanion_ReferencedInstallLogsSelection(t *testing.T) {
	proj := t.TempDir()
	dump := filepath.Join(DumpsDir(proj), "no_20261007_120000.pg_dump")
	touchDumpAt(t, dump)

	instDir := filepath.Join(proj, "tmp", "install-logs")
	writeLogFixture(t, instDir, "v1.0.0-20261001T000000Z.log", "INSTALL-REFERENCED")
	writeLogFixture(t, instDir, "v2.0.0-20261002T000000Z.log", "INSTALL-REFERENCED-2")
	writeLogFixture(t, instDir, "v0.9.0-20260901T000000Z.log", "INSTALL-UNREFERENCED")

	refs := []string{
		"install-logs/v1.0.0-20261001T000000Z.log", // public.upgrade shape
		"v2.0.0-20261002T000000Z.log",              // system_info shape
		"install-logs/gone-20261003T000000Z.log",   // referenced but absent on disk
		"", "../evil", "install-logs/../../etc/x",  // junk never ships
	}
	companion, count, err := WriteLogsCompanion(proj, dump, refs)
	if err != nil {
		t.Fatalf("WriteLogsCompanion: %v", err)
	}
	if count != 2 {
		t.Errorf("count=%d, want 2 (only the referenced, existing install logs)", count)
	}

	dest := t.TempDir()
	found, restored, err := RestoreLogsCompanion(dest, dump)
	if err != nil || !found {
		t.Fatalf("RestoreLogsCompanion: found=%v err=%v", found, err)
	}
	if restored != 2 {
		t.Errorf("restored=%d, want 2", restored)
	}
	if b, err := os.ReadFile(filepath.Join(dest, "tmp", "install-logs", "v1.0.0-20261001T000000Z.log")); err != nil || string(b) != "INSTALL-REFERENCED" {
		t.Errorf("referenced install log content=%q err=%v", b, err)
	}
	if _, err := os.Stat(filepath.Join(dest, "tmp", "install-logs", "v0.9.0-20260901T000000Z.log")); !os.IsNotExist(err) {
		t.Error("unreferenced install log must NOT ship with the dump")
	}
	if _, err := os.Stat(companion); err != nil {
		t.Errorf("companion file missing: %v", err)
	}
}

// TestWriteLogsCompanion_EmptyIsValidArchive: no logs on disk is not an
// error — a valid empty archive is written and restores to zero files.
func TestWriteLogsCompanion_EmptyIsValidArchive(t *testing.T) {
	proj := t.TempDir()
	dump := filepath.Join(DumpsDir(proj), "no_20261007_120000.pg_dump")
	touchDumpAt(t, dump)

	companion, count, err := WriteLogsCompanion(proj, dump, nil)
	if err != nil {
		t.Fatalf("WriteLogsCompanion with no logs: %v", err)
	}
	if count != 0 {
		t.Errorf("count=%d, want 0", count)
	}
	if _, err := os.Stat(companion); err != nil {
		t.Fatalf("a valid empty archive must still be written: %v", err)
	}

	dest := t.TempDir()
	found, restored, err := RestoreLogsCompanion(dest, dump)
	if err != nil || !found || restored != 0 {
		t.Errorf("empty archive must restore cleanly: found=%v restored=%d err=%v", found, restored, err)
	}
}

// TestRestoreLogsCompanion_Merges: extraction merges — unrelated local files
// survive, same-named files are overwritten, nothing is deleted.
func TestRestoreLogsCompanion_Merges(t *testing.T) {
	proj := t.TempDir()
	dump := filepath.Join(DumpsDir(proj), "no_20261007_120000.pg_dump")
	touchDumpAt(t, dump)
	writeLogFixture(t, filepath.Join(proj, "tmp", "upgrade-logs"), "1-v1-20261001T000000Z.log", "NEW")

	if _, _, err := WriteLogsCompanion(proj, dump, nil); err != nil {
		t.Fatal(err)
	}

	dest := t.TempDir()
	// Pre-existing unrelated local files that the archive knows nothing about.
	writeLogFixture(t, filepath.Join(dest, "tmp", "upgrade-logs"), "99-local-only.log", "LOCAL-ONLY")
	writeLogFixture(t, filepath.Join(dest, "tmp", "other"), "unrelated.txt", "UNRELATED")
	writeLogFixture(t, filepath.Join(dest, "tmp", "upgrade-logs"), "1-v1-20261001T000000Z.log", "STALE")

	found, count, err := RestoreLogsCompanion(dest, dump)
	if err != nil || !found {
		t.Fatalf("RestoreLogsCompanion: found=%v err=%v", found, err)
	}
	if count != 1 {
		t.Errorf("count=%d, want 1", count)
	}
	if b, _ := os.ReadFile(filepath.Join(dest, "tmp", "upgrade-logs", "1-v1-20261001T000000Z.log")); string(b) != "NEW" {
		t.Errorf("same-named file must be overwritten with the archive content, got %q", b)
	}
	if b, _ := os.ReadFile(filepath.Join(dest, "tmp", "upgrade-logs", "99-local-only.log")); string(b) != "LOCAL-ONLY" {
		t.Error("unrelated local log must survive the merge")
	}
	if b, _ := os.ReadFile(filepath.Join(dest, "tmp", "other", "unrelated.txt")); string(b) != "UNRELATED" {
		t.Error("unrelated local file must survive the merge")
	}
}

// TestRestoreLogsCompanion_MissingCompanion: absence is not an error —
// found=false, no error, nothing written.
func TestRestoreLogsCompanion_MissingCompanion(t *testing.T) {
	proj := t.TempDir()
	dump := filepath.Join(DumpsDir(proj), "no_20261007_120000.pg_dump")
	touchDumpAt(t, dump)

	found, count, err := RestoreLogsCompanion(t.TempDir(), dump)
	if err != nil {
		t.Errorf("a missing companion must not error: %v", err)
	}
	if found || count != 0 {
		t.Errorf("found=%v count=%d, want false/0", found, count)
	}
}

// TestRestoreLogsCompanion_RejectsTraversal: a hand-crafted archive with
// unsafe member paths is refused, not extracted outside tmp/.
func TestRestoreLogsCompanion_RejectsTraversal(t *testing.T) {
	proj := t.TempDir()
	dump := filepath.Join(DumpsDir(proj), "no_20261007_120000.pg_dump")
	touchDumpAt(t, dump)

	// Write a hostile archive by hand via the internal writer.
	hostile := LogsCompanionPathFor(dump, false) // gzip: writable without zstd
	f, err := os.Create(hostile)
	if err != nil {
		t.Fatal(err)
	}
	if err := writeCompressedTar(hostile+".tmp", f, []companionMember{
		{name: "tmp/../../../../etc/evil", absPath: dump},
	}); err != nil {
		t.Fatal(err)
	}
	if err := f.Close(); err != nil {
		t.Fatal(err)
	}

	dest := t.TempDir()
	if _, _, err := RestoreLogsCompanion(dest, dump); err == nil {
		t.Error("a companion with traversal paths must be refused")
	}
	if _, err := os.Stat(filepath.Join(dest, "etc", "evil")); !os.IsNotExist(err) {
		t.Error("no file may be written outside tmp/")
	}
}

// TestPurgeDumps_CompanionIsOneUnitWithDump: purge deletes a dump and its
// companion together — never one without the other.
func TestPurgeDumps_CompanionIsOneUnitWithDump(t *testing.T) {
	proj := t.TempDir()
	old := touchDump(t, proj, "no_20260101_000000.pg_dump")
	keep := touchDump(t, proj, "no_20260102_000000.pg_dump")
	oldCompanion := LogsCompanionPathFor(old, false)
	touchDumpAt(t, oldCompanion)
	keepCompanion := LogsCompanionPathFor(keep, false)
	touchDumpAt(t, keepCompanion)

	deleted, err := PurgeDumps(proj, 1)
	if err != nil {
		t.Fatalf("PurgeDumps: %v", err)
	}
	if len(deleted) != 2 {
		t.Fatalf("deleted %d, want 2 (dump + companion): %v", len(deleted), deleted)
	}
	for _, p := range []string{old, oldCompanion} {
		if _, err := os.Stat(p); !os.IsNotExist(err) {
			t.Errorf("must be deleted: %s", filepath.Base(p))
		}
	}
	for _, p := range []string{keep, keepCompanion} {
		if _, err := os.Stat(p); err != nil {
			t.Errorf("must be kept: %s: %v", filepath.Base(p), err)
		}
	}
}

// TestFindLogsCompanion probes both extensions and absence.
func TestFindLogsCompanion(t *testing.T) {
	proj := t.TempDir()
	dump := touchDump(t, proj, "no_20260101_000000.pg_dump")
	if got := FindLogsCompanion(dump); got != "" {
		t.Errorf("no companion → want \"\", got %q", got)
	}
	gz := LogsCompanionPathFor(dump, false)
	touchDumpAt(t, gz)
	if got := FindLogsCompanion(dump); got != gz {
		t.Errorf("gzip companion → want %q, got %q", gz, got)
	}
	zst := LogsCompanionPathFor(dump, true)
	touchDumpAt(t, zst)
	if got := FindLogsCompanion(dump); got != zst {
		t.Errorf("zstd companion is preferred → want %q, got %q", zst, got)
	}
}

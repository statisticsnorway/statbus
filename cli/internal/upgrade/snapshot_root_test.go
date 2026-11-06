package upgrade

import (
	"encoding/json"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// The upgrade snapshot folder is ~/statbus-upgrade-snapshots (STATBUS-574).
// Boxes installed before the rename keep their snapshots in ~/statbus-backups;
// MigrateSnapshotRoot carries them over once, and a path recorded before the
// move still finds the moved snapshot.

func writeSnapshotFile(t *testing.T, path, body string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
}

func readSnapshotFile(t *testing.T, path string) string {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read %s: %v", path, err)
	}
	return string(data)
}

func TestSnapshotRootIsNamedForWhatItHolds(t *testing.T) {
	if got, want := SnapshotRoot("/home/statbus"), "/home/statbus/statbus-upgrade-snapshots"; got != want {
		t.Fatalf("SnapshotRoot = %q, want %q", got, want)
	}
	t.Setenv("HOME", "/home/statbus")
	if got, want := (&Service{}).backupRoot(), "/home/statbus/statbus-upgrade-snapshots"; got != want {
		t.Fatalf("the upgrader's snapshot root = %q, want %q", got, want)
	}
}

func TestMigrateSnapshotRootMovesTheLegacyFolder(t *testing.T) {
	home := t.TempDir()
	writeSnapshotFile(t, filepath.Join(home, "statbus-backups", "pre-upgrade-active", "PG_VERSION"), "18\n")

	move, err := MigrateSnapshotRoot(home)
	if err != nil {
		t.Fatalf("MigrateSnapshotRoot: %v", err)
	}
	if got := readSnapshotFile(t, filepath.Join(home, "statbus-upgrade-snapshots", "pre-upgrade-active", "PG_VERSION")); got != "18\n" {
		t.Fatalf("moved snapshot content = %q", got)
	}
	if _, err := os.Lstat(filepath.Join(home, "statbus-backups")); !os.IsNotExist(err) {
		t.Fatalf("the legacy folder is still there after the move: %v", err)
	}
	if want := (SnapshotRootMove{Moved: true}); move.Moved != want.Moved || len(move.LeftBehind) != 0 {
		t.Fatalf("move report = %+v, want a plain move", move)
	}
	if got, want := move.Lines(home), []string{"  Moved the upgrade snapshots from ~/statbus-backups to ~/statbus-upgrade-snapshots."}; strings.Join(got, "\n") != strings.Join(want, "\n") {
		t.Fatalf("report lines = %q, want %q", got, want)
	}
}

// An install that ran the Directories step while an upgrade marker held the
// legacy folder in place created an empty new folder. The move still happens.
func TestMigrateSnapshotRootReplacesAnEmptyNewFolder(t *testing.T) {
	home := t.TempDir()
	writeSnapshotFile(t, filepath.Join(home, "statbus-backups", "pre-upgrade-active", "PG_VERSION"), "18\n")
	if err := os.Mkdir(filepath.Join(home, "statbus-upgrade-snapshots"), 0o755); err != nil {
		t.Fatal(err)
	}

	if _, err := MigrateSnapshotRoot(home); err != nil {
		t.Fatalf("MigrateSnapshotRoot: %v", err)
	}
	if got := readSnapshotFile(t, filepath.Join(home, "statbus-upgrade-snapshots", "pre-upgrade-active", "PG_VERSION")); got != "18\n" {
		t.Fatalf("moved snapshot content = %q", got)
	}
	if _, err := os.Lstat(filepath.Join(home, "statbus-backups")); !os.IsNotExist(err) {
		t.Fatalf("the legacy folder is still there: %v", err)
	}
}

// When both folders hold snapshots (an upgrade ran on the new name before the
// legacy folder could move), every legacy entry without a namesake moves over
// and a namesake is never overwritten: it stays in the legacy folder, which
// the report names.
func TestMigrateSnapshotRootMergesWithoutOverwriting(t *testing.T) {
	home := t.TempDir()
	legacy := filepath.Join(home, "statbus-backups")
	current := filepath.Join(home, "statbus-upgrade-snapshots")
	writeSnapshotFile(t, filepath.Join(legacy, "pre-upgrade-active", "PG_VERSION"), "old\n")
	writeSnapshotFile(t, filepath.Join(legacy, "upgrade-logs-20261001", "log"), "logs\n")
	writeSnapshotFile(t, filepath.Join(current, "pre-upgrade-active", "PG_VERSION"), "new\n")

	move, err := MigrateSnapshotRoot(home)
	if err != nil {
		t.Fatalf("MigrateSnapshotRoot: %v", err)
	}
	if got := readSnapshotFile(t, filepath.Join(current, "pre-upgrade-active", "PG_VERSION")); got != "new\n" {
		t.Fatalf("the newer snapshot was overwritten: %q", got)
	}
	if got := readSnapshotFile(t, filepath.Join(current, "upgrade-logs-20261001", "log")); got != "logs\n" {
		t.Fatalf("the non-colliding entry did not move: %q", got)
	}
	if got := readSnapshotFile(t, filepath.Join(legacy, "pre-upgrade-active", "PG_VERSION")); got != "old\n" {
		t.Fatalf("the colliding legacy entry was not kept: %q", got)
	}
	if strings.Join(move.LeftBehind, ",") != "pre-upgrade-active" || !move.Moved {
		t.Fatalf("move report = %+v, want moved with pre-upgrade-active left behind", move)
	}
	want := []string{
		"  Moved the upgrade snapshots from ~/statbus-backups to ~/statbus-upgrade-snapshots.",
		"  Left pre-upgrade-active in ~/statbus-backups: ~/statbus-upgrade-snapshots already has one. Remove ~/statbus-backups when it is no longer needed.",
	}
	if got := move.Lines(home); strings.Join(got, "\n") != strings.Join(want, "\n") {
		t.Fatalf("report lines =\n%s\nwant\n%s", strings.Join(got, "\n"), strings.Join(want, "\n"))
	}
	// What is left behind beside a namesake is settled: the next install or
	// tick has nothing to move and reports nothing.
	if SnapshotRootMovePending(home) {
		t.Fatal("a settled left-behind entry is still reported as pending")
	}
	writeSnapshotFile(t, filepath.Join(legacy, "upgrade-logs-20261002", "log"), "more\n")
	if !SnapshotRootMovePending(home) {
		t.Fatal("a legacy entry without a namesake is not reported as pending")
	}
}

func TestMigrateSnapshotRootRemovesAnEmptyLegacyFolder(t *testing.T) {
	home := t.TempDir()
	if err := os.Mkdir(filepath.Join(home, "statbus-backups"), 0o755); err != nil {
		t.Fatal(err)
	}
	writeSnapshotFile(t, filepath.Join(home, "statbus-upgrade-snapshots", "pre-upgrade-active", "PG_VERSION"), "new\n")

	if _, err := MigrateSnapshotRoot(home); err != nil {
		t.Fatalf("MigrateSnapshotRoot: %v", err)
	}
	if _, err := os.Lstat(filepath.Join(home, "statbus-backups")); !os.IsNotExist(err) {
		t.Fatalf("the empty legacy folder is still there: %v", err)
	}
	if got := readSnapshotFile(t, filepath.Join(home, "statbus-upgrade-snapshots", "pre-upgrade-active", "PG_VERSION")); got != "new\n" {
		t.Fatalf("snapshot content = %q", got)
	}
}

func TestMigrateSnapshotRootWithoutALegacyFolderChangesNothing(t *testing.T) {
	home := t.TempDir()
	move, err := MigrateSnapshotRoot(home)
	if err != nil {
		t.Fatalf("MigrateSnapshotRoot: %v", err)
	}
	if move.Moved || len(move.LeftBehind) != 0 || len(move.Lines(home)) != 0 {
		t.Fatalf("move report = %+v, want nothing", move)
	}
	entries, err := os.ReadDir(home)
	if err != nil || len(entries) != 0 {
		t.Fatalf("home after a no-op migration = %v (%v), want empty", entries, err)
	}
}

// The folder moves only while no upgrade is recorded in the marker: a marker
// that names an upgrade (or a snapshot) belongs to recovery, which must find
// the snapshot exactly where it was recorded.
func TestSnapshotRootMoveAllowedOnlyWithoutARecordedUpgrade(t *testing.T) {
	for _, tc := range []struct {
		name   string
		marker *UpgradeFlag
		want   bool
	}{
		{"no marker", nil, true},
		{"install's own claim", &UpgradeFlag{Holder: HolderInstall, Trigger: "install"}, true},
		{"service upgrade", &UpgradeFlag{ID: 7, CommitSHA: "abc", Holder: HolderService}, false},
		{"marker with a snapshot", &UpgradeFlag{Holder: HolderInstall, BackupPath: "/home/statbus/statbus-backups/pre-upgrade-active"}, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			projDir := t.TempDir()
			if tc.marker != nil {
				data, err := json.Marshal(tc.marker)
				if err != nil {
					t.Fatal(err)
				}
				writeSnapshotFile(t, flagFilePath(projDir), string(data))
			}
			allowed, why := SnapshotRootMoveAllowed(projDir)
			if allowed != tc.want {
				t.Fatalf("SnapshotRootMoveAllowed = %v (%s), want %v", allowed, why, tc.want)
			}
		})
	}
}

// A snapshot path recorded before the move (in the marker's BackupPath or in
// public.upgrade.backup_path) resolves to the moved folder, so a rollback
// restores the very snapshot the upgrade took.
func TestRestoreDatabaseUsesTheMovedSnapshotForALegacyRecordedPath(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	moved := filepath.Join(home, "statbus-upgrade-snapshots", "pre-upgrade-active")
	writeSnapshotFile(t, filepath.Join(moved, "PG_VERSION"), "18\n")
	recorded := filepath.Join(home, "statbus-backups", "pre-upgrade-active")

	if got := resolveRecordedSnapshot(recorded); got != moved {
		t.Fatalf("resolveRecordedSnapshot(%q) = %q, want %q", recorded, got, moved)
	}
	out := captureSnapshotStdout(t, func() {
		_ = (&Service{projDir: t.TempDir()}).restoreDatabase(&ProgressLog{projDir: t.TempDir()}, recorded)
	})
	if !strings.Contains(out, "Restoring database from ~/statbus-upgrade-snapshots/pre-upgrade-active ...") {
		t.Fatalf("restore did not use the moved snapshot:\n%s", out)
	}
}

// A recorded path that still exists is used as recorded, wherever it is.
func TestResolveRecordedSnapshotKeepsAnExistingRecordedPath(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	legacy := filepath.Join(home, "statbus-backups", "pre-upgrade-active")
	writeSnapshotFile(t, filepath.Join(legacy, "PG_VERSION"), "18\n")
	writeSnapshotFile(t, filepath.Join(home, "statbus-upgrade-snapshots", "pre-upgrade-active", "PG_VERSION"), "other\n")
	if got := resolveRecordedSnapshot(legacy); got != legacy {
		t.Fatalf("resolveRecordedSnapshot(%q) = %q, want the recorded path", legacy, got)
	}
}

func captureSnapshotStdout(t *testing.T, fn func()) string {
	t.Helper()
	old := os.Stdout
	r, w, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	os.Stdout = w
	done := make(chan string)
	go func() {
		data, _ := io.ReadAll(r)
		done <- string(data)
	}()
	fn()
	_ = w.Close()
	os.Stdout = old
	return <-done
}

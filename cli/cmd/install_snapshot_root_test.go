package cmd

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/upgrade"
)

// STATBUS-574: the install's Directories step owns ~/statbus-upgrade-snapshots
// and carries a pre-rename ~/statbus-backups over to it, once, while no
// upgrade is recorded in the marker.

func TestInstallDirectoriesStepMovesTheLegacySnapshotFolder(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	projDir := t.TempDir()
	snapshot := filepath.Join(home, "statbus-backups", "pre-upgrade-active", "PG_VERSION")
	if err := os.MkdirAll(filepath.Dir(snapshot), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(snapshot, []byte("18\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(home, "statbus-maintenance"), 0o755); err != nil {
		t.Fatal(err)
	}

	if checkDirectoriesDone(projDir) {
		t.Fatal("Directories reported done while ~/statbus-backups still holds the snapshots")
	}
	if err := runEnsureDirectories(projDir); err != nil {
		t.Fatalf("runEnsureDirectories: %v", err)
	}
	data, err := os.ReadFile(filepath.Join(home, "statbus-upgrade-snapshots", "pre-upgrade-active", "PG_VERSION"))
	if err != nil || string(data) != "18\n" {
		t.Fatalf("moved snapshot = %q, %v", data, err)
	}
	if _, err := os.Lstat(filepath.Join(home, "statbus-backups")); !os.IsNotExist(err) {
		t.Fatalf("~/statbus-backups survived the Directories step: %v", err)
	}
	if !checkDirectoriesDone(projDir) {
		t.Fatal("Directories not done after the move")
	}
}

// While the marker records an upgrade, its snapshot path belongs to recovery:
// the step creates the new folder but leaves the legacy one where it is, and
// reports done so recovery runs. The upgrader moves it once the marker is gone.
func TestInstallDirectoriesStepLeavesSnapshotsOfARecordedUpgrade(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	projDir := t.TempDir()
	legacySnapshot := filepath.Join(home, "statbus-backups", "pre-upgrade-active")
	if err := os.MkdirAll(legacySnapshot, 0o755); err != nil {
		t.Fatal(err)
	}
	marker, err := json.Marshal(upgrade.UpgradeFlag{ID: 9, CommitSHA: "abc", Holder: upgrade.HolderService, Phase: upgrade.PhaseNewSbSwapped, BackupPath: legacySnapshot})
	if err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(projDir, "tmp"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(projDir, "tmp", "upgrade-in-progress.json"), marker, 0o644); err != nil {
		t.Fatal(err)
	}

	if err := runEnsureDirectories(projDir); err != nil {
		t.Fatalf("runEnsureDirectories: %v", err)
	}
	if info, err := os.Stat(legacySnapshot); err != nil || !info.IsDir() {
		t.Fatalf("the recorded snapshot moved during a recorded upgrade: %v", err)
	}
	if info, err := os.Stat(filepath.Join(home, "statbus-upgrade-snapshots")); err != nil || !info.IsDir() {
		t.Fatalf("~/statbus-upgrade-snapshots not created: %v", err)
	}
	if !checkDirectoriesDone(projDir) {
		t.Fatal("Directories not done during a recorded upgrade; recovery would never be reached")
	}
}

func TestInstallerManagedHomeDirsNameTheSnapshotFolder(t *testing.T) {
	want := []string{"statbus-maintenance", "statbus-upgrade-snapshots"}
	if strings.Join(installerManagedHomeDirs, ",") != strings.Join(want, ",") {
		t.Fatalf("installerManagedHomeDirs = %v, want %v", installerManagedHomeDirs, want)
	}
}

// `./sb db backup` is the daily database backup (the pg_dump in dbdumps);
// `./sb db snapshot` is the upgrade snapshot. No other spelling exists.
func TestDbCommandsNameBackupsAndSnapshots(t *testing.T) {
	want := map[string][]string{
		"backup":   {"create", "list", "purge"},
		"snapshot": {"create", "list", "purge", "restore"},
	}
	for parent, subs := range want {
		found, _, err := rootCmd.Find([]string{"db", parent})
		if err != nil || found.Name() != parent {
			t.Fatalf("sb db %s not found: %v", parent, err)
		}
		var got []string
		for _, c := range found.Commands() {
			got = append(got, c.Name())
		}
		if strings.Join(got, ",") != strings.Join(subs, ",") {
			t.Errorf("sb db %s subcommands = %v, want %v", parent, got, subs)
		}
	}
	var dbSubs []string
	found, _, err := rootCmd.Find([]string{"db"})
	if err != nil {
		t.Fatal(err)
	}
	for _, c := range found.Commands() {
		dbSubs = append(dbSubs, c.Name())
	}
	wantDB := []string{"backup", "download", "restore", "snapshot", "status", "with-seed-lock"}
	var gotDB []string
	for _, name := range dbSubs {
		if name != "seed" {
			gotDB = append(gotDB, name)
		}
	}
	if strings.Join(gotDB, ",") != strings.Join(wantDB, ",") {
		t.Errorf("sb db subcommands = %v, want %v (plus seed)", dbSubs, wantDB)
	}
}

// The operator sees where the upgrade snapshots went: install.sh shows the
// install's output through ops/install-terminal-output.awk, which passes only
// the sentences it knows.
func TestSnapshotRootMoveLinesReachTheTerminal(t *testing.T) {
	moved := upgrade.SnapshotRootMove{Moved: true, LeftBehind: []string{"pre-upgrade-active"}}
	lines := strings.Join(moved.Lines("/home/statbus"), "\n") + "\n" +
		"  Keeping ~/statbus-backups in place for now: upgrade 9 is recorded in the upgrade marker. The upgrader moves it to ~/statbus-upgrade-snapshots when that upgrade is finished.\n"
	if got := runTerminalFilter(t, lines); got != lines {
		t.Fatalf("snapshot folder lines hidden:\n got:\n%s\nwant:\n%s", got, lines)
	}
}

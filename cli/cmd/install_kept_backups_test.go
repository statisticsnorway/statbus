package cmd

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// STATBUS-419 AC10: a fresh install moves the database backups an uninstall
// kept (~/statbus.dbdumps) back into the checkout's dbdumps folder, and the
// operator learns how to restore one. It never restores by itself.
func TestAdoptKeptBackupsMovesThemIntoTheCheckoutAndNamesTheRestore(t *testing.T) {
	home, dir, _ := provisioningFixture(t, false)
	kept := filepath.Join(home, "statbus.dbdumps")
	if err := os.MkdirAll(kept, 0o755); err != nil {
		t.Fatal(err)
	}
	for name, body := range map[string]string{
		"un_20261105_121219.pg_dump":     "older",
		"un_20261106_090000.pg_dump":     "newer",
		"un_20261106_090000.logs.tar.gz": "logs",
	} {
		if err := os.WriteFile(filepath.Join(kept, name), []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
	}

	var err error
	out := captureStdout(t, func() { err = adoptKeptBackups(dir) })
	if err != nil {
		t.Fatalf("adopt kept backups: %v", err)
	}
	if _, statErr := os.Stat(kept); !os.IsNotExist(statErr) {
		t.Fatalf("%s survived the move: %v", kept, statErr)
	}
	for name, want := range map[string]string{
		"un_20261105_121219.pg_dump":     "older",
		"un_20261106_090000.pg_dump":     "newer",
		"un_20261106_090000.logs.tar.gz": "logs",
	} {
		data, readErr := os.ReadFile(filepath.Join(dir, "dbdumps", name))
		if readErr != nil || string(data) != want {
			t.Fatalf("%s: %q %v", name, data, readErr)
		}
	}
	if want := "  Moved the 2 kept backups from " + kept + " to " + filepath.Join(dir, "dbdumps") + "."; !strings.Contains(out, want) {
		t.Errorf("missing %q in:\n%s", want, out)
	}

	hint := captureStdout(t, func() { reportKeptBackups(dir) })
	for _, want := range []string{
		"2 database backups from the earlier installation are in " + filepath.Join(dir, "dbdumps") + ". The newest is un_20261106_090000.pg_dump.",
		"To put its data into this installation, run:",
		"    cd ~/statbus && ./sb db restore un_20261106_090000.pg_dump",
	} {
		if !strings.Contains(hint, want) {
			t.Errorf("restore hint is missing %q:\n%s", want, hint)
		}
	}
}

// With nothing kept, the install moves nothing and says nothing about backups.
func TestAdoptKeptBackupsIsSilentWithoutKeptBackups(t *testing.T) {
	_, dir, _ := provisioningFixture(t, false)
	var err error
	out := captureStdout(t, func() {
		err = adoptKeptBackups(dir)
		reportKeptBackups(dir)
	})
	if err != nil || out != "" {
		t.Fatalf("err=%v out=%q", err, out)
	}
}

// A kept backup never overwrites a different file of the same name in the
// checkout; both stay, and the install stops naming them.
func TestAdoptKeptBackupsRefusesADifferentFileOfTheSameName(t *testing.T) {
	home, dir, _ := provisioningFixture(t, false)
	kept := filepath.Join(home, "statbus.dbdumps")
	if err := os.MkdirAll(kept, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(dir, "dbdumps"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(kept, "x.pg_dump"), []byte("kept"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "dbdumps", "x.pg_dump"), []byte("other"), 0o644); err != nil {
		t.Fatal(err)
	}
	err := adoptKeptBackups(dir)
	if err == nil || !strings.Contains(err.Error(), filepath.Join(kept, "x.pg_dump")) {
		t.Fatalf("err = %v, want a refusal naming the kept file", err)
	}
	for path, want := range map[string]string{filepath.Join(kept, "x.pg_dump"): "kept", filepath.Join(dir, "dbdumps", "x.pg_dump"): "other"} {
		if data, _ := os.ReadFile(path); string(data) != want {
			t.Fatalf("%s = %q, want %q", path, data, want)
		}
	}
}

// The operator sees the move and the restore hint: install.sh shows the
// install's output through ops/install-terminal-output.awk, which passes only
// the sentences it knows.
func TestKeptBackupsLinesReachTheTerminal(t *testing.T) {
	lines := "  Moved the 2 kept backups from /home/statbus/statbus.dbdumps to /home/statbus/statbus/dbdumps.\n" +
		"  Moved the 1 kept backup from /home/statbus/statbus.dbdumps to /home/statbus/statbus/dbdumps.\n" +
		"2 database backups from the earlier installation are in /home/statbus/statbus/dbdumps. The newest is un_20261106_090000.pg_dump.\n" +
		"1 database backup from the earlier installation is in /home/statbus/statbus/dbdumps. The newest is un_20261105_121219.pg_dump.\n" +
		"To put its data into this installation, run:\n" +
		"    cd ~/statbus && ./sb db restore un_20261106_090000.pg_dump\n"
	if got := runTerminalFilter(t, lines); got != lines {
		t.Fatalf("kept-backup lines hidden:\n got:\n%s\nwant:\n%s", got, lines)
	}
}

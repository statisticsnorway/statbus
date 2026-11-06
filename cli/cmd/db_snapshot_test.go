package cmd

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// snapshotFixture is a project of slot "ug" whose dbdumps folder also holds
// another slot's snapshot archives (as after a slot change or a copied
// folder), under a HOME that must stay untouched (STATBUS-590).
func snapshotFixture(t *testing.T) (home, proj, dumps string) {
	t.Helper()
	home = t.TempDir()
	proj = t.TempDir()
	t.Setenv("HOME", home)
	dumps = filepath.Join(proj, "dbdumps")
	if err := os.MkdirAll(dumps, 0o755); err != nil {
		t.Fatal(err)
	}
	files := map[string]string{
		filepath.Join(proj, ".statbus"):                            "",
		filepath.Join(proj, ".env.config"):                         "DEPLOYMENT_SLOT_CODE=ug\n",
		filepath.Join(dumps, "ug_20261101_010000.snapshot.tar.gz"): "ug-1",
		filepath.Join(dumps, "ug_20261102_010000.snapshot.tar.gz"): "ug-2",
		filepath.Join(dumps, "ug_20261103_010000.snapshot.tar.gz"): "ug-3",
		filepath.Join(dumps, "ma_20261104_010000.snapshot.tar.gz"): "ma-1",
		filepath.Join(dumps, "ma_20261105_010000.snapshot.tar.gz"): "ma-2",
		filepath.Join(dumps, "ug_20261103_010000.pg_dump"):         "dump",
	}
	for path, body := range files {
		if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	t.Chdir(proj)
	return home, proj, dumps
}

func assertHomeEmpty(t *testing.T, home string) {
	t.Helper()
	entries, err := os.ReadDir(home)
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 0 {
		names := make([]string, 0, len(entries))
		for _, e := range entries {
			names = append(names, e.Name())
		}
		t.Fatalf("HOME holds %v; snapshot commands keep everything under <project>/dbdumps", names)
	}
}

// AC1/AC3: create names its archive <slot>_<ts>.snapshot.tar.gz in
// <project>/dbdumps and stages in <project>/dbdumps/staging.
func TestSnapshotCreateWritesUnderProjectDbdumps(t *testing.T) {
	home, proj, dumps := snapshotFixture(t)
	archive, staging, err := snapshotCreatePaths(proj, "20261106_190000")
	if err != nil {
		t.Fatal(err)
	}
	if want := filepath.Join(dumps, "ug_20261106_190000.snapshot.tar.gz"); archive != want {
		t.Errorf("archive = %s, want %s", archive, want)
	}
	if want := filepath.Join(dumps, "staging"); staging != want {
		t.Errorf("staging = %s, want %s", staging, want)
	}
	assertHomeEmpty(t, home)
}

// AC2/AC3: list shows exactly this slot's archives, read from <project>/dbdumps.
func TestSnapshotListShowsOnlyThisSlot(t *testing.T) {
	home, _, dumps := snapshotFixture(t)
	out, _ := captureStdoutStderr(t, func() {
		if err := backupListCmd.RunE(backupListCmd, nil); err != nil {
			t.Error(err)
		}
	})
	var listed []string
	for _, line := range strings.Split(out, "\n") {
		if f := strings.Fields(line); len(f) > 0 && strings.HasSuffix(f[0], ".snapshot.tar.gz") {
			listed = append(listed, f[0])
		}
	}
	want := "ug_20261101_010000.snapshot.tar.gz ug_20261102_010000.snapshot.tar.gz ug_20261103_010000.snapshot.tar.gz"
	if got := strings.Join(listed, " "); got != want {
		t.Errorf("listed %q, want %q\n%s", got, want, out)
	}
	if !strings.Contains(out, "Snapshot archives of ug in "+dumps) {
		t.Errorf("list does not name slot ug and %s:\n%s", dumps, out)
	}
	assertHomeEmpty(t, home)
}

// AC2/AC3: restore resolves a name only to this slot's archive; another
// slot's archive is refused with the reason.
func TestSnapshotRestoreResolvesOnlyThisSlot(t *testing.T) {
	home, proj, dumps := snapshotFixture(t)
	for _, name := range []string{"20261102_010000", "ug_20261102_010000", "ug_20261102_010000.snapshot.tar.gz", filepath.Join(dumps, "ug_20261102_010000.snapshot.tar.gz")} {
		got, err := resolveSnapshotArchive(proj, name)
		if err != nil {
			t.Errorf("%s: %v", name, err)
			continue
		}
		if want := filepath.Join(dumps, "ug_20261102_010000.snapshot.tar.gz"); got != want {
			t.Errorf("%s resolved to %s, want %s", name, got, want)
		}
	}
	for _, name := range []string{"ma_20261104_010000", "ma_20261104_010000.snapshot.tar.gz", "20261104_010000"} {
		got, err := resolveSnapshotArchive(proj, name)
		if err == nil {
			t.Errorf("%s resolved to %s; only ug archives belong to this installation", name, got)
		}
	}
	_, err := resolveSnapshotArchive(proj, "ma_20261104_010000.snapshot.tar.gz")
	if err == nil || !strings.Contains(err.Error(), "taken from slot ma") || !strings.Contains(err.Error(), "this installation is slot ug") {
		t.Errorf("another slot's archive: err = %v, want it to name slot ma and slot ug", err)
	}
	assertHomeEmpty(t, home)
}

// AC2/AC3: purge keeps the newest N of this slot and never selects another
// slot's archive or a logical dump.
func TestSnapshotPurgeSelectsOnlyThisSlot(t *testing.T) {
	home, proj, dumps := snapshotFixture(t)
	doomed, err := snapshotPurgeSelection(proj, 1)
	if err != nil {
		t.Fatal(err)
	}
	want := []string{filepath.Join(dumps, "ug_20261101_010000.snapshot.tar.gz"), filepath.Join(dumps, "ug_20261102_010000.snapshot.tar.gz")}
	if strings.Join(doomed, "|") != strings.Join(want, "|") {
		t.Errorf("purge --keep 1 selects %v, want %v", doomed, want)
	}
	assertHomeEmpty(t, home)
}

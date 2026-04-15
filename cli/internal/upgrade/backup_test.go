package upgrade

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"
)

// scopedBackupRoot points the Service at a per-test backup root by
// pinning $HOME to a temp dir. Returns the resolved backup root path
// (~/statbus-backups inside the temp).
func scopedBackupRoot(t *testing.T) string {
	t.Helper()
	home := t.TempDir()
	t.Setenv("HOME", home)
	root := filepath.Join(home, "statbus-backups")
	if err := os.MkdirAll(root, 0755); err != nil {
		t.Fatal(err)
	}
	return root
}

// makeBackupDir creates a directory under the given root with the given
// name. Returns the full path.
func makeBackupDir(t *testing.T, root, name string) string {
	t.Helper()
	full := filepath.Join(root, name)
	if err := os.MkdirAll(full, 0755); err != nil {
		t.Fatal(err)
	}
	return full
}

func TestPickLatestBackup_EmptyDir(t *testing.T) {
	scopedBackupRoot(t)
	d := &Service{}
	if got := d.pickLatestBackup(); got != "" {
		t.Errorf("pickLatestBackup on empty dir = %q, want \"\"", got)
	}
}

func TestPickLatestBackup_OnlyTmps(t *testing.T) {
	root := scopedBackupRoot(t)
	makeBackupDir(t, root, "pre-upgrade-20260101T000000Z.tmp")
	makeBackupDir(t, root, "pre-upgrade-20260102T000000Z.tmp")
	d := &Service{}
	if got := d.pickLatestBackup(); got != "" {
		t.Errorf("pickLatestBackup with only .tmp = %q, want \"\"", got)
	}
}

func TestPickLatestBackup_PicksNewestNonTmp(t *testing.T) {
	root := scopedBackupRoot(t)
	makeBackupDir(t, root, "pre-upgrade-20260101T120000Z")
	wantPath := makeBackupDir(t, root, "pre-upgrade-20261231T235959Z")
	makeBackupDir(t, root, "pre-upgrade-20260615T060000Z")
	// .tmp newer than the latest finalised — must be ignored.
	makeBackupDir(t, root, "pre-upgrade-20271231T235959Z.tmp")
	// Unrelated dir — must be ignored.
	makeBackupDir(t, root, "some-other-thing")

	d := &Service{}
	got := d.pickLatestBackup()
	if got != wantPath {
		t.Errorf("pickLatestBackup = %q, want %q", got, wantPath)
	}
}

func TestPickLatestBackup_LexSortHandlesYearBoundary(t *testing.T) {
	root := scopedBackupRoot(t)
	// Timestamp format YYYYMMDDTHHMMSSZ sorts lexicographically the same
	// as chronologically, including across year boundaries.
	makeBackupDir(t, root, "pre-upgrade-20251231T235959Z")
	want := makeBackupDir(t, root, "pre-upgrade-20260101T000001Z")
	d := &Service{}
	if got := d.pickLatestBackup(); got != want {
		t.Errorf("pickLatestBackup = %q, want %q", got, want)
	}
}

func TestPruneBackups_KeepsTopN(t *testing.T) {
	root := scopedBackupRoot(t)
	// 5 finalised, want top 3 to survive.
	keep := []string{
		"pre-upgrade-20260103T000000Z",
		"pre-upgrade-20260104T000000Z",
		"pre-upgrade-20260105T000000Z",
	}
	gone := []string{
		"pre-upgrade-20260101T000000Z",
		"pre-upgrade-20260102T000000Z",
	}
	for _, n := range append(append([]string{}, keep...), gone...) {
		makeBackupDir(t, root, n)
	}

	d := &Service{}
	d.pruneBackups(context.Background(), 3)

	for _, n := range keep {
		if _, err := os.Stat(filepath.Join(root, n)); err != nil {
			t.Errorf("expected %s to survive: %v", n, err)
		}
	}
	for _, n := range gone {
		if _, err := os.Stat(filepath.Join(root, n)); err == nil {
			t.Errorf("expected %s to be pruned, still present", n)
		}
	}
}

func TestPruneBackups_TmpDirsNeverTouched(t *testing.T) {
	// pruneBackups must not touch .tmp dirs regardless of age —
	// reconcileBackupDir owns their lifecycle (10-min grace for unreferenced).
	root := scopedBackupRoot(t)

	// Old .tmp — pruneBackups must leave it alone (reconcileBackupDir will purge it).
	old := makeBackupDir(t, root, "pre-upgrade-20260101T000000Z.tmp")
	pastCutoff := time.Now().Add(-30 * time.Minute)
	if err := os.Chtimes(old, pastCutoff, pastCutoff); err != nil {
		t.Fatal(err)
	}

	// Fresh .tmp — must also survive.
	fresh := makeBackupDir(t, root, "pre-upgrade-20260601T000000Z.tmp")

	d := &Service{}
	d.pruneBackups(context.Background(), 3)

	if _, err := os.Stat(old); err != nil {
		t.Errorf("pruneBackups removed old .tmp (should be left to reconcileBackupDir): %v", err)
	}
	if _, err := os.Stat(fresh); err != nil {
		t.Errorf("pruneBackups removed fresh .tmp: %v", err)
	}
}

func TestPruneBackups_NoTouchOnNoExcess(t *testing.T) {
	root := scopedBackupRoot(t)
	// 2 finalised + a fresh .tmp; keep=3; nothing should change.
	a := makeBackupDir(t, root, "pre-upgrade-20260101T000000Z")
	b := makeBackupDir(t, root, "pre-upgrade-20260102T000000Z")
	c := makeBackupDir(t, root, "pre-upgrade-20260103T000000Z.tmp")

	d := &Service{}
	d.pruneBackups(context.Background(), 3)

	for _, p := range []string{a, b, c} {
		if _, err := os.Stat(p); err != nil {
			t.Errorf("unexpectedly removed %s: %v", p, err)
		}
	}
}

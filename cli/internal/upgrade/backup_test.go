package upgrade

import (
	"context"
	"os"
	"path/filepath"
	"strings"
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

// restoreDatabase is identity-keyed (STATBUS-039/-031): it consumes ONLY the
// snapshot path the recovered upgrade recorded for itself (flag.BackupPath /
// row.backup_path). Selection by recency (the former pickLatestBackup) is
// gone — these guards pin the three dispositions deterministically (the
// restore-succeeds arm needs real docker rsync and lives in the
// install-recovery harness).

// TestRestoreDatabase_EmptyIdentity_RefusesToTouchVolume: an upgrade that
// never finalised a snapshot (PreSwap kill — flag.BackupPath empty) must be
// a clean no-op (nil), regardless of how tempting the on-disk dirs are. The
// pre-039 recency scan would have restored the newest legacy dir here.
func TestRestoreDatabase_EmptyIdentity_RefusesToTouchVolume(t *testing.T) {
	root := scopedBackupRoot(t)
	// Tempting recency candidates — must never be considered.
	makeBackupDir(t, root, "pre-upgrade-20261231T235959Z")
	makeBackupDir(t, root, backupActiveName)

	d := &Service{}
	p := &ProgressLog{projDir: t.TempDir()}
	if err := d.restoreDatabase(p, ""); err != nil {
		t.Errorf("restoreDatabase with empty identity must no-op (nil); got %v", err)
	}
}

// TestRestoreDatabase_MissingIdentity_FailsLoud_NoFallback: the upgrade DID
// record a snapshot and it is gone (pruned mid-flight, manual deletion).
// Restoring any OTHER backup would be another upgrade's state — the call
// must fail with a non-nil error naming the recorded path, even when a
// newer-looking legacy dir sits right there (the recency choice).
func TestRestoreDatabase_MissingIdentity_FailsLoud_NoFallback(t *testing.T) {
	root := scopedBackupRoot(t)
	// The would-have-been recency choice — must NOT be silently restored.
	makeBackupDir(t, root, "pre-upgrade-20261231T235959Z")

	recorded := filepath.Join(root, backupActiveName) // recorded but absent
	d := &Service{}
	p := &ProgressLog{projDir: t.TempDir()}
	err := d.restoreDatabase(p, recorded)
	if err == nil {
		t.Fatal("restoreDatabase with a missing recorded snapshot must FAIL loud, never fall back to recency")
	}
	if !strings.Contains(err.Error(), recorded) {
		t.Errorf("error must name the recorded path %q; got: %v", recorded, err)
	}
}

// TestRestoreDatabase_IdentityNotADir_FailsLoud: a recorded path that exists
// but is not a directory is corrupt state — fail loud, touch nothing.
func TestRestoreDatabase_IdentityNotADir_FailsLoud(t *testing.T) {
	root := scopedBackupRoot(t)
	file := filepath.Join(root, "pre-upgrade-active")
	if err := os.WriteFile(file, []byte("not a dir"), 0644); err != nil {
		t.Fatal(err)
	}
	d := &Service{}
	p := &ProgressLog{projDir: t.TempDir()}
	if err := d.restoreDatabase(p, file); err == nil {
		t.Fatal("restoreDatabase on a non-directory recorded path must FAIL loud")
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

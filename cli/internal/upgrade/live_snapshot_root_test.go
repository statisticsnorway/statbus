//go:build livedb

package upgrade

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"
)

// TestMigrateSnapshotRootRewritesRecordedPaths runs the upgrader's STATBUS-574
// move against the REAL local database: a row recorded under ~/statbus-backups
// points into ~/statbus-upgrade-snapshots afterwards, and a row whose own
// snapshot stayed behind (a namesake already in the new folder) keeps its path. Everything runs
// inside one transaction that is rolled back.
//
// go test -tags livedb -count=1 ./internal/upgrade
func TestMigrateSnapshotRootRewritesRecordedPaths(t *testing.T) {
	projDir := findProjDir(t)
	d := NewService(projDir, false, "test", "")
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()
	if err := d.loadConfig(); err != nil {
		t.Fatalf("loadConfig: %v", err)
	}
	if err := d.connect(ctx); err != nil {
		t.Fatalf("connect: %v", err)
	}
	defer d.Close()
	if _, err := d.queryConn.Exec(ctx, "BEGIN"); err != nil {
		t.Fatal(err)
	}
	defer func() {
		if _, err := d.queryConn.Exec(context.Background(), "ROLLBACK"); err != nil {
			t.Errorf("cleanup ROLLBACK: %v", err)
		}
	}()

	home := t.TempDir()
	legacy := filepath.Join(home, LegacySnapshotRootName)
	for _, dir := range []string{
		filepath.Join(legacy, "pre-upgrade-active"),
		filepath.Join(legacy, "pre-upgrade-20261001T000000Z"),
		filepath.Join(SnapshotRoot(home), "pre-upgrade-20261001T000000Z"),
	} {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	t.Setenv("HOME", home)

	insert := func(sha, path string) int {
		t.Helper()
		var id int
		if err := d.queryConn.QueryRow(ctx, `
			INSERT INTO public.upgrade (commit_sha, committed_at, commit_tags, release_status, summary, state, scheduled_at, started_at, completed_at, backup_path, log_relative_file_path)
			VALUES ($1, now() - interval '3 days', '{}', 'commit', 'snapshot root probe', 'completed', now() - interval '2 days', now() - interval '2 days', now() - interval '2 days', $2, 'snapshot-root-probe.log')
			RETURNING id`, sha, path).Scan(&id); err != nil {
			t.Fatalf("insert probe row: %v", err)
		}
		return id
	}
	movedID := insert("5740000000000000000000000000000000000001", filepath.Join(legacy, "pre-upgrade-active"))
	keptID := insert("5740000000000000000000000000000000000002", filepath.Join(legacy, "pre-upgrade-20261001T000000Z"))
	// A snapshot that was already gone keeps being reported missing, under the
	// one remaining name.
	goneID := insert("5740000000000000000000000000000000000003", filepath.Join(legacy, "pre-upgrade-20260901T000000Z"))

	migrateSnapshotRoot(ctx, t.TempDir(), home, d.queryConn)

	for id, want := range map[int]string{
		movedID: filepath.Join(SnapshotRoot(home), "pre-upgrade-active"),
		keptID:  filepath.Join(legacy, "pre-upgrade-20261001T000000Z"),
		goneID:  filepath.Join(SnapshotRoot(home), "pre-upgrade-20260901T000000Z"),
	} {
		var got string
		if err := d.queryConn.QueryRow(ctx, "SELECT backup_path FROM public.upgrade WHERE id = $1", id).Scan(&got); err != nil {
			t.Fatalf("read back %d: %v", id, err)
		}
		if got != want {
			t.Errorf("upgrade %d backup_path = %q, want %q", id, got, want)
		}
	}
}

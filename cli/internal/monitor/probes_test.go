package monitor

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/statisticsnorway/statbus/cli/internal/dbdump"
)

// TestBackupsProbeReadsScheduledDumpNotVolumeBackups pins what the backups
// check measures: the upgrader's scheduled logical dump in <projectDir>/dbdumps
// (the artifact BACKUP_ENABLED/BACKUP_INTERVAL govern), not ~/statbus-backups.
// StatBus-541 follow-up: dev.statbus.org answered 503 with "newest backup 3218h
// ago" while a fresh dump existed in dbdumps, because the old ~/statbus-backups
// directory was the only thing read.
func TestBackupsProbeReadsScheduledDumpNotVolumeBackups(t *testing.T) {
	projectDir := t.TempDir()
	dumpsDir := dbdump.DumpsDir(projectDir)
	if err := os.MkdirAll(dumpsDir, 0o755); err != nil {
		t.Fatal(err)
	}
	dumpPath := filepath.Join(dumpsDir, "dev_20261030_000248.pg_dump")
	if err := os.WriteFile(dumpPath, []byte("dump"), 0o644); err != nil {
		t.Fatal(err)
	}
	dumpTime := time.Now().Add(-time.Hour)
	if err := os.Chtimes(dumpPath, dumpTime, dumpTime); err != nil {
		t.Fatal(err)
	}

	// A stale volume-backup directory must not influence the reading.
	home := t.TempDir()
	t.Setenv("HOME", home)
	oldDir := filepath.Join(home, "statbus-backups", "upgrade-20260918")
	if err := os.MkdirAll(oldDir, 0o755); err != nil {
		t.Fatal(err)
	}
	oldTime := time.Date(2026, 9, 18, 0, 0, 0, 0, time.UTC)
	if err := os.Chtimes(oldDir, oldTime, oldTime); err != nil {
		t.Fatal(err)
	}

	result, err := BackupsProbe(projectDir)(context.Background())
	if err != nil {
		t.Fatalf("probe: %v", err)
	}
	if result.Newest.IsZero() {
		t.Fatal("probe reported no backup; want the scheduled dump in dbdumps")
	}
	if got := time.Since(result.Newest); got < 59*time.Minute || got > 61*time.Minute {
		t.Fatalf("newest = %s ago, want the 1h-old scheduled dump", got)
	}

	check := backupsCheck(context.Background(), BackupsProbe(projectDir), time.Now())
	if check.Status != StatusOK {
		t.Fatalf("backups check = %s (%s), want ok", check.Status, check.Detail)
	}
	if check.Detail != "newest backup 1h ago" {
		t.Fatalf("detail = %q, want %q", check.Detail, "newest backup 1h ago")
	}
}

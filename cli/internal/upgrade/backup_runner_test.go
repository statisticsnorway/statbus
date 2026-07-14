package upgrade

import (
	"os"
	"path/filepath"
	"syscall"
	"testing"
	"time"

	"github.com/statisticsnorway/statbus/cli/internal/dbdump"
)

// writeDump drops a fake *.pg_dump in projDir/dbdumps so the schedule due-check
// has on-disk state to read.
func writeDump(t *testing.T, proj, name string) string {
	t.Helper()
	dir := dbdump.DumpsDir(proj)
	if err := os.MkdirAll(dir, 0755); err != nil {
		t.Fatal(err)
	}
	p := filepath.Join(dir, name)
	if err := os.WriteFile(p, []byte("x"), 0644); err != nil {
		t.Fatal(err)
	}
	return p
}

// holdUpgradeFlock creates the upgrade-in-progress flag file and holds an
// exclusive flock on it (separate open description), so IsFlockHeld(projDir)
// reports a live upgrade — simulating an install-CLI-driven upgrade.
func holdUpgradeFlock(t *testing.T, proj string) func() {
	t.Helper()
	path := flagFilePath(proj)
	if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
		t.Fatal(err)
	}
	f, err := os.OpenFile(path, os.O_CREATE|os.O_RDWR, 0644)
	if err != nil {
		t.Fatal(err)
	}
	if err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		_ = f.Close()
		t.Fatalf("hold flock: %v", err)
	}
	return func() {
		_ = syscall.Flock(int(f.Fd()), syscall.LOCK_UN)
		_ = f.Close()
	}
}

// ── config parse ──────────────────────────────────────────────────────────────

func TestLoadConfig_BackupSettings(t *testing.T) {
	proj := t.TempDir()
	env := "POSTGRES_APP_DB=statbus_test\n" +
		"BACKUP_ENABLED=false\nBACKUP_INTERVAL=12h\nBACKUP_RETENTION_COUNT=3\n"
	if err := os.WriteFile(filepath.Join(proj, ".env"), []byte(env), 0644); err != nil {
		t.Fatal(err)
	}
	d := &Service{projDir: proj}
	if err := d.loadConfig(); err != nil {
		t.Fatalf("loadConfig: %v", err)
	}
	if d.backupEnabled {
		t.Error("BACKUP_ENABLED=false must parse to disabled")
	}
	if d.backupInterval != 12*time.Hour {
		t.Errorf("backupInterval = %v, want 12h", d.backupInterval)
	}
	if d.backupRetention != 3 {
		t.Errorf("backupRetention = %d, want 3", d.backupRetention)
	}
}

func TestLoadConfig_BackupDefaults(t *testing.T) {
	proj := t.TempDir()
	// .env present but no BACKUP_* keys → built-in defaults.
	if err := os.WriteFile(filepath.Join(proj, ".env"), []byte("POSTGRES_APP_DB=x\n"), 0644); err != nil {
		t.Fatal(err)
	}
	d := &Service{projDir: proj}
	if err := d.loadConfig(); err != nil {
		t.Fatalf("loadConfig: %v", err)
	}
	if !d.backupEnabled || d.backupInterval != 24*time.Hour || d.backupRetention != 7 {
		t.Errorf("defaults wrong: enabled=%v interval=%v retention=%d; want true/24h/7",
			d.backupEnabled, d.backupInterval, d.backupRetention)
	}
}

// ── due-check + coordination gate ─────────────────────────────────────────────

func TestBackupDue(t *testing.T) {
	proj := t.TempDir()
	interval := 24 * time.Hour

	if !backupDue(proj, interval) {
		t.Error("no dumps yet → must be due")
	}

	dump := writeDump(t, proj, "no_20260601_000000.pg_dump")
	now := time.Now()
	if err := os.Chtimes(dump, now, now); err != nil {
		t.Fatal(err)
	}
	if backupDue(proj, interval) {
		t.Error("a just-written dump → must NOT be due")
	}

	// Older than 0.9×interval (21.6h) → due, covering the periodic-tick boundary.
	old := time.Now().Add(-23 * time.Hour)
	if err := os.Chtimes(dump, old, old); err != nil {
		t.Fatal(err)
	}
	if !backupDue(proj, interval) {
		t.Error("a dump older than 0.9×interval → must be due")
	}
}

func TestBackupGate_DisabledIsSilentSkip(t *testing.T) {
	d := &Service{projDir: t.TempDir(), backupEnabled: false, backupInterval: 24 * time.Hour}
	if run, reason := d.backupGate(); run || reason != "" {
		t.Errorf("disabled → silent skip; got run=%v reason=%q", run, reason)
	}
}

func TestBackupGate_UpgradingIsLoudSkip(t *testing.T) {
	d := &Service{projDir: t.TempDir(), backupEnabled: true, backupInterval: 24 * time.Hour, upgrading: true}
	if run, reason := d.backupGate(); run || reason != "upgrade in progress" {
		t.Errorf("d.upgrading → loud skip 'upgrade in progress'; got run=%v reason=%q", run, reason)
	}
}

func TestBackupGate_FlockHeldIsLoudSkip(t *testing.T) {
	proj := t.TempDir()
	release := holdUpgradeFlock(t, proj)
	defer release()
	d := &Service{projDir: proj, backupEnabled: true, backupInterval: 24 * time.Hour}
	if run, reason := d.backupGate(); run || reason != "upgrade in progress" {
		t.Errorf("install-CLI flock held → loud skip; got run=%v reason=%q", run, reason)
	}
}

func TestBackupGate_RunsWhenDueAndNoUpgrade(t *testing.T) {
	proj := t.TempDir()
	d := &Service{projDir: proj, backupEnabled: true, backupInterval: 24 * time.Hour}
	if run, reason := d.backupGate(); !run || reason != "" {
		t.Errorf("enabled, no upgrade, no dump → run; got run=%v reason=%q", run, reason)
	}
}

func TestBackupGate_NotDueIsSilentSkip(t *testing.T) {
	proj := t.TempDir()
	dump := writeDump(t, proj, "no_20260601_000000.pg_dump")
	now := time.Now()
	if err := os.Chtimes(dump, now, now); err != nil {
		t.Fatal(err)
	}
	d := &Service{projDir: proj, backupEnabled: true, backupInterval: 24 * time.Hour}
	if run, reason := d.backupGate(); run || reason != "" {
		t.Errorf("a recent dump → silent not-due skip; got run=%v reason=%q", run, reason)
	}
}

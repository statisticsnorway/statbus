package upgrade

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// TestSetMaintenanceRepairsViaEnsureWritable pins the STATBUS-431 daemon
// behaviour: before writing the flag, setMaintenance routes the directory
// through the shared ensure/repair (not a bare MkdirAll), so an existing
// root-owned ~/statbus-maintenance gets fixed instead of failing the upgrade
// at "write maintenance flag ...: permission denied" (rc.01 smoke run
// 36851924215).
func TestSetMaintenanceRepairsViaEnsureWritable(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	dir := filepath.Join(home, maintenanceFlagDir)

	var gotProjDir, gotDir string
	calls := 0
	orig := ensureHostDirWritable
	ensureHostDirWritable = func(projDir, d string) error {
		calls++
		gotProjDir, gotDir = projDir, d
		return os.MkdirAll(d, 0o755) // stand-in for the real ensure+repair
	}
	t.Cleanup(func() { ensureHostDirWritable = orig })

	projDir := t.TempDir()
	d := NewService(projDir, false, "test", "")
	if err := d.setMaintenance(true, "upgrade to v2099.01.0-rc.01"); err != nil {
		t.Fatalf("setMaintenance: %v", err)
	}
	if calls != 1 {
		t.Fatalf("ensureHostDirWritable called %d times, want 1", calls)
	}
	if gotProjDir != projDir || gotDir != dir {
		t.Errorf("ensureHostDirWritable(%q, %q), want (%q, %q)", gotProjDir, gotDir, projDir, dir)
	}
	content, err := os.ReadFile(maintenanceFlagHostPath())
	if err != nil {
		t.Fatalf("flag not written: %v", err)
	}
	if string(content) != "upgrade to v2099.01.0-rc.01" {
		t.Errorf("flag content = %q", content)
	}
}

// TestSetMaintenanceRepairFailureIsLoud: when the shared repair cannot make
// the directory writable, setMaintenance fails with the repair's error —
// never a bare write error detached from the repair attempt.
func TestSetMaintenanceRepairFailureIsLoud(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)

	repairErr := errors.New("repair container exited 0 but still not writable")
	orig := ensureHostDirWritable
	ensureHostDirWritable = func(projDir, d string) error { return repairErr }
	t.Cleanup(func() { ensureHostDirWritable = orig })

	d := NewService(t.TempDir(), false, "test", "")
	err := d.setMaintenance(true, "content")
	if err == nil {
		t.Fatal("setMaintenance succeeded despite the repair failure")
	}
	if !errors.Is(err, repairErr) {
		t.Errorf("error %v does not wrap the repair failure", err)
	}
	if !strings.Contains(err.Error(), "ensure maintenance directory") {
		t.Errorf("error does not name the maintenance directory: %v", err)
	}
}

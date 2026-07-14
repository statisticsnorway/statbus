package cmd

import (
	"os"
	"path/filepath"
	"syscall"
	"testing"
	"time"
)

// TestConfirmUpgradeDeathViaFlock locks down item D (STATBUS-052): the takeover
// quiesce confirms a SIGKILL'd upgrade holder is actually gone via the
// AUTHORITATIVE kernel flock (upgrade.IsFlockHeld) — NOT by inferring from the
// SIGKILL exit status or a silent MainPID-poll timeout. A held flock ⇒ "still
// held" (false: the observer warns and proceeds); a released flock ⇒ "confirmed
// dead" (true). PID-reuse-immune by construction: a recycled PID cannot inherit
// a dead holder's flock, so there is no pidAlive/proc check (the codebase
// removed pidAlive as a ghost-flag-unreliable guard — service.go:784-789).
func TestConfirmUpgradeDeathViaFlock(t *testing.T) {
	projDir := t.TempDir()
	if err := os.MkdirAll(filepath.Join(projDir, "tmp"), 0o755); err != nil {
		t.Fatalf("mkdir tmp: %v", err)
	}
	flagPath := filepath.Join(projDir, "tmp", "upgrade-in-progress.json")

	// No flag file at all → no live upgrade → confirmed dead immediately.
	if !confirmUpgradeDeathViaFlock(projDir, time.Second) {
		t.Error("no flag file present, but confirmUpgradeDeathViaFlock reported NOT-dead; absent flag ⇒ confirmed dead (true)")
	}

	// A live holder: a real flag file with a held exclusive flock, mirroring an
	// in-flight upgrade. IsFlockHeld opens its OWN fd, so the lock conflicts
	// across open file descriptions even within this process (flock(2)).
	f, err := os.OpenFile(flagPath, os.O_CREATE|os.O_RDWR, 0o644)
	if err != nil {
		t.Fatalf("create flag file: %v", err)
	}
	defer func() { _ = f.Close() }()
	if _, err := f.WriteString(`{"holder":"service","pid":4242}`); err != nil {
		t.Fatalf("write flag: %v", err)
	}
	if err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		t.Fatalf("hold LOCK_EX on flag file: %v", err)
	}

	// Held → holder alive → NOT confirmed dead. Short timeout: the poll exhausts
	// it while the lock is held.
	if confirmUpgradeDeathViaFlock(projDir, 600*time.Millisecond) {
		t.Error("flock held by a live holder, but confirmUpgradeDeathViaFlock reported confirmed-dead (true); must be false so the observer warns and proceeds")
	}

	// Release the lock (the killed holder's fd teardown) → confirmed dead.
	if err := syscall.Flock(int(f.Fd()), syscall.LOCK_UN); err != nil {
		t.Fatalf("release flock: %v", err)
	}
	if !confirmUpgradeDeathViaFlock(projDir, 2*time.Second) {
		t.Error("flock released (holder gone), but confirmUpgradeDeathViaFlock did not report confirmed-dead (true)")
	}
}

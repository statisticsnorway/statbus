package cmd

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strconv"
	"syscall"
	"testing"

	installstate "github.com/statisticsnorway/statbus/cli/internal/install"
	"github.com/statisticsnorway/statbus/cli/internal/upgrade"
)

func TestAcquireOrBypassReusesAdoptedInstallMutex(t *testing.T) {
	dir := t.TempDir()
	if err := os.MkdirAll(filepath.Join(dir, "tmp"), 0755); err != nil {
		t.Fatal(err)
	}
	const token = "cmd-handoff-447"
	path := filepath.Join(dir, "tmp", "upgrade-in-progress.json")
	data, err := json.Marshal(upgrade.UpgradeFlag{
		Holder:       upgrade.HolderInstall,
		Trigger:      "install",
		HandoffToken: token,
	})
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, data, 0644); err != nil {
		t.Fatal(err)
	}
	file, err := os.OpenFile(path, os.O_RDWR, 0)
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = file.Close() }()
	if err := syscall.Flock(int(file.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		t.Fatal(err)
	}
	fd, err := syscall.Dup(int(file.Fd()))
	if err != nil {
		t.Fatal(err)
	}
	fdOwned := true
	defer func() {
		if fdOwned {
			_ = syscall.Close(fd)
		}
	}()
	t.Setenv(upgrade.InstallMutexFDEnv, strconv.Itoa(fd))
	t.Setenv(upgrade.InstallMutexTokenEnv, token)

	lock, attempted, err := upgrade.AdoptInheritedInstallFlag(dir)
	if err != nil || !attempted || lock == nil {
		t.Fatalf("lock=%v attempted=%v err=%v", lock, attempted, err)
	}
	fdOwned = false
	release, err := acquireOrBypass(dir, false, lock)
	if err != nil {
		t.Fatalf("acquireOrBypass tried to re-acquire the adopted mutex: %v", err)
	}
	release()
}

func TestStaleUpgradeHandoffCannotDestroyValidInstallHandoff(t *testing.T) {
	dir := t.TempDir()
	if err := os.MkdirAll(filepath.Join(dir, "tmp"), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, ".env.config"), []byte("configured\n"), 0644); err != nil {
		t.Fatal(err)
	}
	const token = "same-fd-install-447"
	path := filepath.Join(dir, "tmp", "upgrade-in-progress.json")
	data, err := json.Marshal(upgrade.UpgradeFlag{
		Holder:       upgrade.HolderInstall,
		Trigger:      "install",
		HandoffToken: token,
	})
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, data, 0644); err != nil {
		t.Fatal(err)
	}
	file, err := os.OpenFile(path, os.O_RDWR, 0)
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = file.Close() }()
	if err := syscall.Flock(int(file.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		t.Fatal(err)
	}
	fd, err := syscall.Dup(int(file.Fd()))
	if err != nil {
		t.Fatal(err)
	}
	fdOwned := true
	defer func() {
		if fdOwned {
			_ = syscall.Close(fd)
		}
	}()
	t.Setenv("STATBUS_UPGRADE_MUTEX_FD", strconv.Itoa(fd))
	t.Setenv("STATBUS_UPGRADE_MUTEX_TOKEN", token)
	t.Setenv(upgrade.InstallMutexFDEnv, strconv.Itoa(fd))
	t.Setenv(upgrade.InstallMutexTokenEnv, token)

	installLock, upgradeLock := adoptInheritedMutexes(dir)
	if upgradeLock != nil {
		upgradeLock.Close()
		t.Fatal("install-held marker was incorrectly adopted as an upgrade handoff")
	}
	if installLock == nil {
		t.Fatal("stale upgrade handoff destroyed the valid install handoff")
	}
	fdOwned = false
	defer installLock.Close()
	state, _, err := installstate.DetectHoldingInstallFlag(dir, "test")
	if err != nil {
		t.Fatal(err)
	}
	if state == installstate.StateLiveUpgrade {
		t.Fatal("held-aware detection classified the adopted install handoff as live upgrade")
	}
}

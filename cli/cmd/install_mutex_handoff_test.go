package cmd

import (
	"context"
	"encoding/json"
	"os"
	"os/exec"
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

func TestExistingRecoveryChannelInheritsFD9(t *testing.T) {
	if dir := os.Getenv("STATBUS_TEST_EXISTING_FD9_DIR"); dir != "" {
		path := filepath.Join(dir, "tmp", "upgrade-in-progress.json")
		before, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		installLock, recoveryLock := adoptInheritedMutexes(dir)
		if installLock != nil || recoveryLock == nil {
			t.Fatal("pre-existing marker was suppressed as a fresh install")
		}
		defer recoveryLock.Close()
		for _, name := range []string{upgrade.InstallMutexFDEnv, upgrade.InstallMutexTokenEnv, "STATBUS_UPGRADE_MUTEX_FD", "STATBUS_UPGRADE_MUTEX_TOKEN"} {
			if _, present := os.LookupEnv(name); present {
				t.Fatalf("metadata not consumed: %s", name)
			}
		}
		checkHold := func() {
			t.Helper()
			probe, err := os.OpenFile(path, os.O_RDWR, 0)
			if err != nil {
				t.Fatal(err)
			}
			defer func() { _ = probe.Close() }()
			if err := syscall.Flock(int(probe.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err == nil {
				t.Fatal("contender entered inherited recovery")
			}
			after, err := os.ReadFile(path)
			if err != nil || string(before) != string(after) {
				t.Fatal("handoff changed marker bytes")
			}
		}
		checkHold()
		state, _, err := installstate.DetectHoldingUpgradeFlag(dir, "test")
		if err != nil || state != installstate.StateCrashedUpgrade {
			t.Fatalf("recovery classification: %v %v", state, err)
		}
		flag, err := upgrade.ReadFlagFile(dir)
		if err != nil {
			t.Fatal(err)
		}
		if flag.Trigger == "restart" {
			if err := restartServicesWithLock(dir, "app", restartOperations{stack: func(string) error { checkHold(); return nil }}, recoveryLock); err != nil {
				t.Fatal(err)
			}
		} else if flag.Holder == upgrade.HolderInstall {
			svc := upgrade.NewService(dir, false, "test", "test")
			svc.AdoptFlagLock(recoveryLock)
			if err := svc.RecoverFromFlag(context.Background()); err != nil {
				t.Fatal(err)
			}
		}
		return
	}
	for _, tc := range []struct{ holder, trigger string }{
		{upgrade.HolderService, "install-cli"}, {upgrade.HolderInstall, "install"}, {upgrade.HolderInstall, "restart"}, {"", "install-cli"},
	} {
		t.Run(tc.holder+":"+tc.trigger, func(t *testing.T) {
			dir := t.TempDir()
			if err := os.MkdirAll(filepath.Join(dir, "tmp"), 0755); err != nil {
				t.Fatal(err)
			}
			if err := os.WriteFile(filepath.Join(dir, ".env.config"), []byte("configured\n"), 0644); err != nil {
				t.Fatal(err)
			}
			flag := upgrade.UpgradeFlag{Holder: tc.holder, Trigger: tc.trigger}
			if tc.trigger == "restart" {
				flag.Restart = &upgrade.RestartIntent{Profile: "app", Prepared: true}
			}
			data, err := json.Marshal(flag)
			if err != nil {
				t.Fatal(err)
			}
			path := filepath.Join(dir, "tmp", "upgrade-in-progress.json")
			if err := os.WriteFile(path, data, 0644); err != nil {
				t.Fatal(err)
			}
			held, err := os.OpenFile(path, os.O_RDWR, 0)
			if err != nil {
				t.Fatal(err)
			}
			defer func() { _ = held.Close() }()
			if err := syscall.Flock(int(held.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
				t.Fatal(err)
			}
			null, err := os.Open(os.DevNull)
			if err != nil {
				t.Fatal(err)
			}
			defer func() { _ = null.Close() }()
			cmd := exec.Command(os.Args[0], "-test.run=^TestExistingRecoveryChannelInheritsFD9$")
			cmd.ExtraFiles = []*os.File{null, null, null, null, null, null, held}
			cmd.Env = append(os.Environ(), "STATBUS_TEST_EXISTING_FD9_DIR="+dir, "STATBUS_UPGRADE_MUTEX_FD=9")
			if out, err := cmd.CombinedOutput(); err != nil {
				t.Fatalf("actual fd9 child: %v\n%s", err, out)
			}
		})
	}
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

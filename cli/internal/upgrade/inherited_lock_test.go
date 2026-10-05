package upgrade

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strconv"
	"syscall"
	"testing"
)

func inheritedInstallFixture(t *testing.T, holder, token string, held bool) (string, int) {
	t.Helper()
	dir := t.TempDir()
	if err := os.MkdirAll(filepath.Join(dir, "tmp"), 0755); err != nil {
		t.Fatal(err)
	}
	path := flagFilePath(dir)
	data, err := json.Marshal(UpgradeFlag{Holder: holder, Trigger: "install", HandoffToken: token})
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
	t.Cleanup(func() { _ = file.Close() })
	if held {
		if err := syscall.Flock(int(file.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
			t.Fatal(err)
		}
	}
	fd, err := syscall.Dup(int(file.Fd()))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = syscall.Close(fd) })
	return dir, fd
}

func setInstallHandoffEnv(t *testing.T, fd int, token string) {
	t.Helper()
	t.Setenv(InstallMutexFDEnv, strconv.Itoa(fd))
	t.Setenv(InstallMutexTokenEnv, token)
}

func TestAdoptInheritedInstallFlag(t *testing.T) {
	const token = "token-447"
	t.Run("adopts proven inherited hold", func(t *testing.T) {
		dir, fd := inheritedInstallFixture(t, HolderInstall, token, true)
		setInstallHandoffEnv(t, fd, token)
		lock, attempted, err := AdoptInheritedInstallFlag(dir)
		if err != nil || !attempted || lock == nil {
			t.Fatalf("lock=%v attempted=%v err=%v", lock, attempted, err)
		}
		flags, _, errno := syscall.Syscall(syscall.SYS_FCNTL, uintptr(fd), uintptr(syscall.F_GETFD), 0)
		if errno != 0 || flags&syscall.FD_CLOEXEC == 0 {
			t.Fatalf("adopted fd must be close-on-exec for ordinary children: flags=%#x errno=%v", flags, errno)
		}
		lock.Close()
	})

	for _, tc := range []struct {
		name   string
		holder string
		token  string
		held   bool
		wrong  bool
	}{
		{name: "token mismatch", holder: HolderInstall, token: "other", held: true},
		{name: "flock not held", holder: HolderInstall, token: token, held: false},
		{name: "holder is not install", holder: HolderService, token: token, held: true},
		{name: "wrong inode", holder: HolderInstall, token: token, held: true, wrong: true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			dir, fd := inheritedInstallFixture(t, tc.holder, tc.token, tc.held)
			if tc.wrong {
				other, err := os.Create(filepath.Join(dir, "other-lock"))
				if err != nil {
					t.Fatal(err)
				}
				defer other.Close()
				fd, err = syscall.Dup(int(other.Fd()))
				if err != nil {
					t.Fatal(err)
				}
				defer syscall.Close(fd)
			}
			setInstallHandoffEnv(t, fd, token)
			lock, attempted, err := AdoptInheritedInstallFlag(dir)
			if !attempted || err == nil || lock != nil {
				t.Fatalf("mismatched handoff adopted: lock=%v attempted=%v err=%v", lock, attempted, err)
			}
		})
	}
}

func TestPrepareInheritedUpgradeLockForExec(t *testing.T) {
	const token = "install-token-447"
	dir, fd := inheritedInstallFixture(t, HolderInstall, token, true)
	setInstallHandoffEnv(t, fd, token)
	t.Setenv(upgradeMutexFDEnv, "")
	t.Setenv(upgradeMutexTokenEnv, "")
	lock, _, err := AdoptInheritedInstallFlag(dir)
	if err != nil {
		t.Fatal(err)
	}
	svc := NewService(dir, false, "test", "test")
	svc.AdoptFlagLock(lock)
	if err := svc.writeUpgradeFlag(447, "abcdef", nil, "test", "install-cli", false); err != nil {
		t.Fatal(err)
	}
	if err := svc.prepareInheritedUpgradeLockForExec(); err != nil {
		t.Fatal(err)
	}
	execFD, err := strconv.Atoi(os.Getenv(upgradeMutexFDEnv))
	if err != nil {
		t.Fatal(err)
	}
	flags, _, errno := syscall.Syscall(syscall.SYS_FCNTL, uintptr(execFD), uintptr(syscall.F_GETFD), 0)
	if errno != 0 || flags&syscall.FD_CLOEXEC != 0 {
		t.Fatalf("deliberate syscall.Exec handoff fd must survive exec: flags=%#x errno=%v", flags, errno)
	}
	flag, err := ReadFlagFile(dir)
	if err != nil {
		t.Fatal(err)
	}
	if flag == nil || flag.Holder != HolderService || flag.HandoffToken == "" || flag.HandoffToken != os.Getenv(upgradeMutexTokenEnv) {
		t.Fatalf("exec handoff flag/env mismatch: flag=%+v envToken=%q", flag, os.Getenv(upgradeMutexTokenEnv))
	}
	svc.cancelInheritedUpgradeLockAfterExecFailure()
	flags, _, errno = syscall.Syscall(syscall.SYS_FCNTL, uintptr(execFD), uintptr(syscall.F_GETFD), 0)
	if errno != 0 || flags&syscall.FD_CLOEXEC == 0 {
		t.Fatalf("failed exec must restore close-on-exec: flags=%#x errno=%v", flags, errno)
	}
	if os.Getenv(upgradeMutexFDEnv) != "" || os.Getenv(upgradeMutexTokenEnv) != "" {
		t.Fatalf("failed exec must clear private handoff environment")
	}
	lock.Close()
}

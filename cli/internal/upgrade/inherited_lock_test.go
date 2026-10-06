package upgrade

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"syscall"
	"testing"

	"golang.org/x/sys/unix"
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
	return dir, fd
}

func setInstallHandoffEnv(t *testing.T, fd int, token string) {
	t.Helper()
	t.Setenv(InstallMutexFDEnv, strconv.Itoa(fd))
	t.Setenv(InstallMutexTokenEnv, token)
}

func runInheritedLockTestChild(t *testing.T, testName string, extraEnv ...string) {
	t.Helper()
	cmd := exec.Command(os.Args[0], "-test.run", "^"+testName+"$")
	cmd.Env = append(os.Environ(), extraEnv...)
	if output, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("child failed: %v\n%s", err, output)
	}
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
		if _, _, errno := syscall.Syscall(syscall.SYS_FCNTL, uintptr(fd), uintptr(syscall.F_GETFD), 0); errno != syscall.EBADF {
			t.Fatalf("successful adoption must close original fd %d: errno=%v", fd, errno)
		}
		flags, _, errno := syscall.Syscall(syscall.SYS_FCNTL, lock.file.Fd(), uintptr(syscall.F_GETFD), 0)
		if errno != 0 || flags&syscall.FD_CLOEXEC == 0 {
			t.Fatalf("adopted duplicate must be close-on-exec for ordinary children: flags=%#x errno=%v", flags, errno)
		}
		lock.Close()
	})

	for _, held := range []bool{true, false} {
		t.Run(fmt.Sprintf("exclusive acquisition held=%t", held), func(t *testing.T) {
			dir, fd := inheritedInstallFixture(t, HolderInstall, "", held)
			setInstallHandoffEnv(t, fd, "")
			lock, attempted, err := AdoptInheritedInstallFlag(dir)
			if err != nil || !attempted || lock == nil {
				t.Fatalf("adoption: %v", err)
			}
			defer lock.Close()
			probe, err := os.OpenFile(flagFilePath(dir), os.O_RDWR, 0)
			if err != nil {
				t.Fatal(err)
			}
			defer func() { _ = probe.Close() }()
			if err := syscall.Flock(int(probe.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err == nil {
				t.Fatal("independent description entered adopted mutex")
			}
		})
	}

	t.Run("independent canonical description cannot take another hold", func(t *testing.T) {
		dir, heldFD := inheritedInstallFixture(t, HolderInstall, "", true)
		defer func() { _ = syscall.Close(heldFD) }()
		other, err := os.OpenFile(flagFilePath(dir), os.O_RDWR, 0)
		if err != nil {
			t.Fatal(err)
		}
		defer func() { _ = other.Close() }()
		setInstallHandoffEnv(t, int(other.Fd()), "")
		lock, attempted, err := AdoptInheritedInstallFlag(dir)
		if !attempted || err == nil || lock != nil {
			t.Fatal("independent descriptor took another owner's hold")
		}
		if _, err := other.Stat(); err != nil {
			t.Fatalf("rejection closed nominated original: %v", err)
		}
	})

	for _, tc := range []struct {
		name   string
		holder string
		token  string
		held   bool
		wrong  bool
	}{
		{name: "holder is not install", holder: HolderService, token: token, held: true},
		{name: "wrong inode", holder: HolderInstall, token: token, held: true, wrong: true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			dir, fd := inheritedInstallFixture(t, tc.holder, tc.token, tc.held)
			defer func(fd int) { _ = syscall.Close(fd) }(fd)
			if tc.wrong {
				other, err := os.Create(filepath.Join(dir, "other-lock"))
				if err != nil {
					t.Fatal(err)
				}
				defer func() { _ = other.Close() }()
				fd, err = syscall.Dup(int(other.Fd()))
				if err != nil {
					t.Fatal(err)
				}
				defer func(fd int) { _ = syscall.Close(fd) }(fd)
			}
			setInstallHandoffEnv(t, fd, token)
			lock, attempted, err := AdoptInheritedInstallFlag(dir)
			if !attempted || err == nil || lock != nil {
				t.Fatalf("mismatched handoff adopted: lock=%v attempted=%v err=%v", lock, attempted, err)
			}
		})
	}
}

func TestRejectedForgedHandoffPreservesUnrelatedFD(t *testing.T) {
	if os.Getenv("STATBUS_TEST_REJECTED_FD_CHILD") == "1" {
		dir := t.TempDir()
		if err := os.MkdirAll(filepath.Join(dir, "tmp"), 0755); err != nil {
			t.Fatal(err)
		}
		unrelated, err := os.Create(filepath.Join(t.TempDir(), "unrelated"))
		if err != nil {
			t.Fatal(err)
		}
		defer func() { _ = unrelated.Close() }()
		setInstallHandoffEnv(t, int(unrelated.Fd()), "forged-token")
		lock, attempted, err := AdoptInheritedInstallFlag(dir)
		if !attempted || err == nil || lock != nil {
			t.Fatalf("forged handoff result: lock=%v attempted=%v err=%v", lock, attempted, err)
		}
		if _, err := unrelated.Stat(); err != nil {
			t.Fatalf("rejected forged handoff closed unrelated fd %d: %v", unrelated.Fd(), err)
		}
		return
	}

	runInheritedLockTestChild(t, "TestRejectedForgedHandoffPreservesUnrelatedFD", "STATBUS_TEST_REJECTED_FD_CHILD=1")
}

func TestSuccessfulAdoptionConsumesPrivateEnvironmentBeforeChild(t *testing.T) {
	if os.Getenv("STATBUS_TEST_ENV_CHILD") == "1" {
		fd, err := strconv.Atoi(os.Getenv("STATBUS_TEST_OWNED_FD"))
		if err != nil {
			t.Fatal(err)
		}
		var inherited, canonical unix.Stat_t
		if err := unix.Stat(os.Getenv("STATBUS_TEST_OWNED_PATH"), &canonical); err != nil {
			t.Fatal(err)
		}
		if err := unix.Fstat(fd, &inherited); err == nil && inherited.Dev == canonical.Dev && inherited.Ino == canonical.Ino {
			t.Fatal("ordinary exec child retained owned mutex descriptor")
		}
		for _, name := range []string{InstallMutexFDEnv, InstallMutexTokenEnv, upgradeMutexFDEnv, upgradeMutexTokenEnv} {
			if value, ok := os.LookupEnv(name); ok {
				t.Fatalf("child inherited consumed private environment %s=%q", name, value)
			}
		}
		return
	}

	const token = "consume-env-447"
	dir, fd := inheritedInstallFixture(t, HolderInstall, token, true)
	setInstallHandoffEnv(t, fd, token)
	t.Setenv(upgradeMutexFDEnv, "999")
	t.Setenv(upgradeMutexTokenEnv, "stale-upgrade-token")
	lock, attempted, err := AdoptInheritedInstallFlag(dir)
	if err != nil || !attempted || lock == nil {
		t.Fatalf("lock=%v attempted=%v err=%v", lock, attempted, err)
	}
	defer lock.Close()
	for _, name := range []string{InstallMutexFDEnv, InstallMutexTokenEnv, upgradeMutexFDEnv, upgradeMutexTokenEnv} {
		if value, ok := os.LookupEnv(name); ok {
			t.Fatalf("successful adoption left %s=%q exported", name, value)
		}
	}
	runInheritedLockTestChild(t, "TestSuccessfulAdoptionConsumesPrivateEnvironmentBeforeChild", "STATBUS_TEST_ENV_CHILD=1",
		"STATBUS_TEST_OWNED_FD="+strconv.Itoa(int(lock.file.Fd())), "STATBUS_TEST_OWNED_PATH="+flagFilePath(dir))
}

func TestChildReusingAdoptedOriginalFDIsUnaffected(t *testing.T) {
	if os.Getenv("STATBUS_TEST_REUSE_FD_CHILD") == "1" {
		targetFD, err := strconv.Atoi(os.Getenv("STATBUS_TEST_REUSE_FD"))
		if err != nil {
			t.Fatal(err)
		}
		unrelated, err := os.Create(filepath.Join(t.TempDir(), "child-unrelated"))
		if err != nil {
			t.Fatal(err)
		}
		defer func() { _ = unrelated.Close() }()
		if int(unrelated.Fd()) != targetFD {
			if err := unix.Dup2(int(unrelated.Fd()), targetFD); err != nil {
				t.Fatal(err)
			}
			defer func() { _ = unix.Close(targetFD) }()
		}
		lock, _, _ := AdoptInheritedInstallFlag(os.Getenv("STATBUS_TEST_REUSE_PROJ_DIR"))
		if lock != nil {
			lock.Close()
			t.Fatal("stale child environment unexpectedly adopted an unrelated fd")
		}
		if _, err := unix.FcntlInt(uintptr(targetFD), unix.F_GETFD, 0); err != nil {
			t.Fatalf("stale handoff closed child fd %d reused for an unrelated file: %v", targetFD, err)
		}
		return
	}

	const token = "reuse-fd-447"
	dir, fd := inheritedInstallFixture(t, HolderInstall, token, true)
	setInstallHandoffEnv(t, fd, token)
	lock, attempted, err := AdoptInheritedInstallFlag(dir)
	if err != nil || !attempted || lock == nil {
		t.Fatalf("lock=%v attempted=%v err=%v", lock, attempted, err)
	}
	defer lock.Close()
	runInheritedLockTestChild(t, "TestChildReusingAdoptedOriginalFDIsUnaffected",
		"STATBUS_TEST_REUSE_FD_CHILD=1",
		"STATBUS_TEST_REUSE_FD="+strconv.Itoa(fd),
		"STATBUS_TEST_REUSE_PROJ_DIR="+dir,
	)
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

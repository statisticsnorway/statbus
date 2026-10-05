package upgrade

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"os"
	"strconv"
	"syscall"
)

const (
	InstallMutexFDEnv    = "STATBUS_INSTALL_MUTEX_FD"
	InstallMutexTokenEnv = "STATBUS_INSTALL_MUTEX_TOKEN"
	upgradeMutexFDEnv    = "STATBUS_UPGRADE_MUTEX_FD"
	upgradeMutexTokenEnv = "STATBUS_UPGRADE_MUTEX_TOKEN"
)

// AdoptInheritedInstallFlag proves and adopts install.sh's inherited mutex.
// attempted is true whenever either handoff environment variable was present.
func AdoptInheritedInstallFlag(projDir string) (lock *FlagLock, attempted bool, err error) {
	return adoptInheritedFlag(projDir, InstallMutexFDEnv, InstallMutexTokenEnv, HolderInstall)
}

// AdoptInheritedUpgradeFlag resumes the private mutex handoff across the
// inline upgrade pipeline's syscall.Exec boundary.
func AdoptInheritedUpgradeFlag(projDir string) (lock *FlagLock, attempted bool, err error) {
	return adoptInheritedFlag(projDir, upgradeMutexFDEnv, upgradeMutexTokenEnv, HolderService)
}

func adoptInheritedFlag(projDir, fdEnv, tokenEnv, expectedHolder string) (*FlagLock, bool, error) {
	fdText, token := os.Getenv(fdEnv), os.Getenv(tokenEnv)
	attempted := fdText != "" || token != ""
	if !attempted {
		return nil, false, nil
	}
	if fdText == "" || token == "" {
		return nil, true, fmt.Errorf("both %s and %s are required", fdEnv, tokenEnv)
	}
	fd, err := strconv.Atoi(fdText)
	if err != nil || fd < 3 {
		return nil, true, fmt.Errorf("%s is not a valid inherited descriptor", fdEnv)
	}
	path := flagFilePath(projDir)
	file := os.NewFile(uintptr(fd), path)
	if file == nil {
		return nil, true, fmt.Errorf("descriptor %d is not open", fd)
	}
	reject := func(format string, args ...any) (*FlagLock, bool, error) {
		_ = file.Close()
		return nil, true, fmt.Errorf(format, args...)
	}
	heldInfo, err := file.Stat()
	if err != nil {
		return reject("stat inherited descriptor %d: %v", fd, err)
	}
	pathInfo, err := os.Stat(path)
	if err != nil {
		return reject("stat canonical upgrade mutex: %v", err)
	}
	if !os.SameFile(heldInfo, pathInfo) {
		return reject("descriptor %d does not name the canonical upgrade mutex", fd)
	}

	// First prove another open file description is blocked. If this succeeds,
	// the inherited description was not holding LOCK_EX before adoption.
	probe, err := os.OpenFile(path, os.O_RDWR, 0)
	if err != nil {
		return reject("open canonical upgrade mutex for hold proof: %v", err)
	}
	probeErr := syscall.Flock(int(probe.Fd()), syscall.LOCK_EX|syscall.LOCK_NB)
	if probeErr == nil {
		_ = syscall.Flock(int(probe.Fd()), syscall.LOCK_UN)
		_ = probe.Close()
		return reject("descriptor %d was not holding the upgrade mutex", fd)
	}
	_ = probe.Close()
	if !errors.Is(probeErr, syscall.EWOULDBLOCK) && !errors.Is(probeErr, syscall.EAGAIN) {
		return reject("verify canonical upgrade mutex contention: %v", probeErr)
	}
	// Re-locking the inherited open file description succeeds only when it is
	// the description that owns the flock proved above.
	if err := syscall.Flock(fd, syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		return reject("descriptor %d does not own the held upgrade mutex: %v", fd, err)
	}
	flag, err := ReadFlagFile(projDir)
	if err != nil {
		return reject("read inherited upgrade mutex record: %v", err)
	}
	if flag == nil || flag.Holder != expectedHolder {
		return reject("upgrade mutex holder is %q, want %q", holderOf(flag), expectedHolder)
	}
	if flag.HandoffToken != token {
		return reject("upgrade mutex handoff token does not match")
	}
	// Ordinary subprocesses must never retain the mutex. The one deliberate
	// syscall.Exec handoff clears this bit immediately before exec.
	syscall.CloseOnExec(fd)
	return &FlagLock{file: file, markerPath: path}, true, nil
}

func holderOf(flag *UpgradeFlag) string {
	if flag == nil {
		return ""
	}
	return flag.Holder
}

func randomHandoffToken() (string, error) {
	buf := make([]byte, 16)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	return hex.EncodeToString(buf), nil
}

func clearCloseOnExec(fd int) error {
	flags, _, errno := syscall.Syscall(syscall.SYS_FCNTL, uintptr(fd), uintptr(syscall.F_GETFD), 0)
	if errno != 0 {
		return errno
	}
	_, _, errno = syscall.Syscall(syscall.SYS_FCNTL, uintptr(fd), uintptr(syscall.F_SETFD), flags&^uintptr(syscall.FD_CLOEXEC))
	if errno != 0 {
		return errno
	}
	return nil
}

func (d *Service) prepareInheritedUpgradeLockForExec() error {
	if d.flagLock == nil || d.flagLock.file == nil {
		return errors.New("upgrade mutex is not held")
	}
	token, err := randomHandoffToken()
	if err != nil {
		return fmt.Errorf("generate handoff token: %w", err)
	}
	if err := d.mutateHeldFlag(func(flag *UpgradeFlag) {
		flag.HandoffToken = token
	}); err != nil {
		return err
	}
	fd := int(d.flagLock.file.Fd())
	if err := os.Setenv(upgradeMutexFDEnv, strconv.Itoa(fd)); err != nil {
		return err
	}
	if err := os.Setenv(upgradeMutexTokenEnv, token); err != nil {
		_ = os.Unsetenv(upgradeMutexFDEnv)
		return err
	}
	_ = os.Unsetenv(InstallMutexFDEnv)
	_ = os.Unsetenv(InstallMutexTokenEnv)
	if err := clearCloseOnExec(fd); err != nil {
		_ = os.Unsetenv(upgradeMutexFDEnv)
		_ = os.Unsetenv(upgradeMutexTokenEnv)
		return fmt.Errorf("clear close-on-exec on fd %d: %w", fd, err)
	}
	return nil
}

func (d *Service) cancelInheritedUpgradeLockAfterExecFailure() {
	if d.flagLock != nil && d.flagLock.file != nil {
		syscall.CloseOnExec(int(d.flagLock.file.Fd()))
	}
	_ = os.Unsetenv(upgradeMutexFDEnv)
	_ = os.Unsetenv(upgradeMutexTokenEnv)
}

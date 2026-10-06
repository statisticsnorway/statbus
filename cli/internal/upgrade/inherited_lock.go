package upgrade

import (
	"errors"
	"fmt"
	"os"
	"strconv"
	"syscall"

	"golang.org/x/sys/unix"
)

const (
	legacyHandoffToken   = "statbus-fd-handoff"
	InstallMutexFDEnv    = "STATBUS_INSTALL_MUTEX_FD"
	InstallMutexTokenEnv = "STATBUS_INSTALL_MUTEX_TOKEN"
	upgradeMutexFDEnv    = "STATBUS_UPGRADE_MUTEX_FD"
	upgradeMutexTokenEnv = "STATBUS_UPGRADE_MUTEX_TOKEN"
)

// AdoptInheritedInstallFlag adopts install.sh's inherited mutex.
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
	consumeInheritedMutexEnvironment()
	return AdoptInheritedFlagDescriptor(projDir, fdText, fdText != "" || token != "", expectedHolder)
}

// AdoptInheritedFlagDescriptor validates a captured routing candidate. Metadata
// must already have been consumed by the caller before attempting adoption.
func AdoptInheritedFlagDescriptor(projDir, fdText string, attempted bool, expectedHolder string) (*FlagLock, bool, error) {
	if !attempted {
		return nil, false, nil
	}
	fd, err := strconv.Atoi(fdText)
	if err != nil || fd < 3 {
		return nil, true, fmt.Errorf("%q is not a valid inherited descriptor", fdText)
	}
	path := flagFilePath(projDir)
	// The environment-nominated fd is untrusted until every proof below has
	// succeeded. Validate a close-on-exec duplicate so rejection can close only
	// the duplicate, never a descriptor the process reused for unrelated work.
	dupFD, err := unix.FcntlInt(uintptr(fd), unix.F_DUPFD_CLOEXEC, 3)
	if err != nil {
		return nil, true, fmt.Errorf("duplicate inherited descriptor %d: %v", fd, err)
	}
	file := os.NewFile(uintptr(dupFD), path)
	if file == nil {
		_ = unix.Close(dupFD)
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

	flag, err := ReadFlagFile(projDir)
	if err != nil {
		return reject("read inherited upgrade mutex record: %v", err)
	}
	if flag == nil || flag.Holder != expectedHolder {
		return reject("upgrade mutex holder is %q, want %q", holderOf(flag), expectedHolder)
	}
	// Holder is routing data, not authentication. Acquire or retain exclusive
	// ownership on the actual inherited open-file description, without waiting.
	if err := syscall.Flock(dupFD, syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		return reject("descriptor %d cannot own the upgrade mutex: %v", fd, err)
	}
	pathInfo, err = os.Stat(path)
	if err != nil || !os.SameFile(heldInfo, pathInfo) {
		return reject("canonical upgrade mutex changed during adoption")
	}
	// file is already close-on-exec from F_DUPFD_CLOEXEC. The duplicate shares
	// the inherited fd's open-file description, so its flock survives closing
	// the original. Close the original only now, after complete validation, to
	// leave FlagLock as the process's sole owner of this description.
	if err := unix.Close(fd); err != nil {
		return reject("close adopted original descriptor %d: %v", fd, err)
	}
	return &FlagLock{file: file, markerPath: path}, true, nil
}

func consumeInheritedMutexEnvironment() {
	_ = os.Unsetenv(InstallMutexFDEnv)
	_ = os.Unsetenv(InstallMutexTokenEnv)
	_ = os.Unsetenv(upgradeMutexFDEnv)
	_ = os.Unsetenv(upgradeMutexTokenEnv)
}

func holderOf(flag *UpgradeFlag) string {
	if flag == nil {
		return ""
	}
	return flag.Holder
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
	if err := d.mutateHeldFlag(func(flag *UpgradeFlag) {
		flag.HandoffToken = legacyHandoffToken
	}); err != nil {
		return err
	}
	fd := int(d.flagLock.file.Fd())
	if err := os.Setenv(upgradeMutexFDEnv, strconv.Itoa(fd)); err != nil {
		return err
	}
	if err := os.Setenv(upgradeMutexTokenEnv, legacyHandoffToken); err != nil {
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

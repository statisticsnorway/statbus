//go:build darwin

package cmd

import (
	"bytes"
	"os"
	"unsafe"

	"golang.org/x/sys/unix"
)

// ptsName names the terminal side of a /dev/ptmx master on macOS, after
// granting and unlocking it (the work posix_openpt callers do in C).
func ptsName(master *os.File) (string, error) {
	fd := int(master.Fd())
	if err := unix.IoctlSetInt(fd, unix.TIOCPTYGRANT, 0); err != nil {
		return "", err
	}
	if err := unix.IoctlSetInt(fd, unix.TIOCPTYUNLK, 0); err != nil {
		return "", err
	}
	buf := make([]byte, 128)
	if _, _, errno := unix.Syscall(unix.SYS_IOCTL, uintptr(fd), uintptr(unix.TIOCPTYGNAME), uintptr(unsafe.Pointer(&buf[0]))); errno != 0 {
		return "", errno
	}
	return string(buf[:bytes.IndexByte(buf, 0)]), nil
}

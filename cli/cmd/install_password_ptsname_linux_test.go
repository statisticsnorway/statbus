//go:build linux

package cmd

import (
	"fmt"
	"os"

	"golang.org/x/sys/unix"
)

// ptsName names the terminal side of a /dev/ptmx master on Linux, after
// unlocking it (the work posix_openpt callers do in C).
func ptsName(master *os.File) (string, error) {
	fd := int(master.Fd())
	if err := unix.IoctlSetPointerInt(fd, unix.TIOCSPTLCK, 0); err != nil {
		return "", err
	}
	n, err := unix.IoctlGetInt(fd, unix.TIOCGPTN)
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("/dev/pts/%d", n), nil
}

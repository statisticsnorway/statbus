//go:build linux || darwin

package cmd

import (
	"golang.org/x/sys/unix"
	"golang.org/x/term"
)

// disableAdministratorPasswordEcho changes ONLY ECHO. In particular, leave
// ICANON and ISIG intact so Ctrl-C continues to interrupt at the prompt.
// ReadPassword will install its own private mode after the prompt is shown.
func disableAdministratorPasswordEcho(fd int) (*term.State, error) {
	state, err := term.GetState(fd)
	if err != nil {
		return nil, err
	}
	settings, err := unix.IoctlGetTermios(fd, passwordIoctlReadTermios)
	if err != nil {
		return nil, err
	}
	settings.Lflag &^= unix.ECHO
	if err := unix.IoctlSetTermios(fd, passwordIoctlWriteTermios, settings); err != nil {
		return nil, err
	}
	return state, nil
}

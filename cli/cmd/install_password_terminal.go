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

// makePasswordRaw is term.MakeRaw for a masked password read, except that
// output processing (OPOST) stays on. The read needs input byte by byte and
// no echo; the screen still needs "\n" to return the carriage, because
// install.sh's terminal filter prints the prompt and other lines from a
// separate process while the read is in progress. term.MakeRaw clears OPOST,
// so the PFX prompt landed at the right edge and the stars ran into the next
// line (manual box, 2026-11-03, STATBUS-422).
func makePasswordRaw(fd int) (*term.State, error) {
	state, err := term.GetState(fd)
	if err != nil {
		return nil, err
	}
	settings, err := unix.IoctlGetTermios(fd, passwordIoctlReadTermios)
	if err != nil {
		return nil, err
	}
	settings.Iflag &^= unix.IGNBRK | unix.BRKINT | unix.PARMRK | unix.ISTRIP | unix.INLCR | unix.IGNCR | unix.ICRNL | unix.IXON
	settings.Lflag &^= unix.ECHO | unix.ECHONL | unix.ICANON | unix.ISIG | unix.IEXTEN
	settings.Cflag &^= unix.CSIZE | unix.PARENB
	settings.Cflag |= unix.CS8
	settings.Cc[unix.VMIN] = 1
	settings.Cc[unix.VTIME] = 0
	if err := unix.IoctlSetTermios(fd, passwordIoctlWriteTermios, settings); err != nil {
		return nil, err
	}
	return state, nil
}

//go:build linux || darwin

package cmd

import (
	"os"
	"testing"

	"github.com/creack/pty"
	"golang.org/x/sys/unix"
	"golang.org/x/term"
)

// openTestTerminal opens a real pseudo-terminal pair and returns the
// terminal-side file (what the installer reads the password from).
func openTestTerminal(t *testing.T) *os.File {
	t.Helper()
	master, terminal, err := pty.Open()
	if err != nil {
		t.Fatalf("open pseudo-terminal pair: %v", err)
	}
	t.Cleanup(func() { _ = master.Close() })
	t.Cleanup(func() { _ = terminal.Close() })
	if !term.IsTerminal(int(terminal.Fd())) {
		t.Fatal("pseudo-terminal terminal side is not a terminal")
	}
	return terminal
}

func outputProcessing(t *testing.T, fd int) bool {
	t.Helper()
	settings, err := unix.IoctlGetTermios(fd, passwordIoctlReadTermios)
	if err != nil {
		t.Fatal(err)
	}
	return settings.Oflag&unix.OPOST != 0
}

// During the masked read the terminal still turns "\n" into a new line at the
// left margin: install.sh's terminal filter prints the prompt from another
// process while the read runs. term.MakeRaw turns output processing off, which
// put the PFX prompt at the right edge and ran the stars into the next line on
// the manual box (2026-11-03, STATBUS-422). Echo and line buffering are off,
// so the password is read byte by byte and never shown.
func TestPasswordRawModeKeepsLineEndings(t *testing.T) {
	terminal := openTestTerminal(t)
	fd := int(terminal.Fd())
	if !outputProcessing(t, fd) {
		t.Skip("this pseudo-terminal starts without output processing")
	}

	state, err := makePasswordRaw(fd)
	if err != nil {
		t.Fatal(err)
	}
	if !outputProcessing(t, fd) {
		t.Error("output processing is off during the password read; a newline would not return the carriage")
	}
	settings, err := unix.IoctlGetTermios(fd, passwordIoctlReadTermios)
	if err != nil {
		t.Fatal(err)
	}
	if settings.Lflag&(unix.ECHO|unix.ICANON) != 0 {
		t.Error("echo or line buffering is still on during the password read")
	}
	if err := term.Restore(fd, state); err != nil {
		t.Fatal(err)
	}
	if !outputProcessing(t, fd) {
		t.Error("output processing not restored")
	}

	// The mode the installer used before: term.MakeRaw drops it.
	before, err := term.MakeRaw(fd)
	if err != nil {
		t.Fatal(err)
	}
	if outputProcessing(t, fd) {
		t.Error("term.MakeRaw was expected to clear output processing")
	}
	_ = term.Restore(fd, before)
}

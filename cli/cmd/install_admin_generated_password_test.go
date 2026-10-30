package cmd

import (
	"bytes"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// bufferWriteCloser is the terminal seam in tests: the installer and the
// show-password command write secrets here instead of the real /dev/tty.
type bufferWriteCloser struct {
	bytes.Buffer
}

func (b *bufferWriteCloser) Close() error { return nil }

func captureStdoutStderr(t *testing.T, fn func()) (stdout, stderr string) {
	t.Helper()
	outR, outW, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	errR, errW, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	oldOut, oldErr := os.Stdout, os.Stderr
	os.Stdout, os.Stderr = outW, errW
	outCh, errCh := make(chan string, 1), make(chan string, 1)
	go func() {
		var b strings.Builder
		buf := make([]byte, 4096)
		for {
			n, err := outR.Read(buf)
			b.Write(buf[:n])
			if err != nil {
				break
			}
		}
		outCh <- b.String()
	}()
	go func() {
		var b strings.Builder
		buf := make([]byte, 4096)
		for {
			n, err := errR.Read(buf)
			b.Write(buf[:n])
			if err != nil {
				break
			}
		}
		errCh <- b.String()
	}()
	fn()
	_ = outW.Close()
	_ = errW.Close()
	os.Stdout, os.Stderr = oldOut, oldErr
	return <-outCh, <-errCh
}

func TestGeneratedAdministratorPasswordGoesOnlyToTerminal(t *testing.T) {
	_, dir, accounts := provisioningFixture(t, true)
	var tty bufferWriteCloser
	oldOpen := openPasswordTerminal
	openPasswordTerminal = func() (io.WriteCloser, error) { return &tty, nil }
	t.Cleanup(func() { openPasswordTerminal = oldOpen })
	oldPrompt := administratorPrompt
	administratorPrompt = func(label, _ string) string {
		switch label {
		case "  Email":
			return "first-admin@example.org"
		case "  Name":
			return "First Admin"
		}
		return ""
	}
	t.Cleanup(func() { administratorPrompt = oldPrompt })
	oldGenerate := newAdministratorPasswordFn
	newAdministratorPasswordFn = func() string { return "generated-secret-123" }
	t.Cleanup(func() { newAdministratorPasswordFn = oldGenerate })
	oldUse := askUseOfferedAdministratorPasswordFn
	askUseOfferedAdministratorPasswordFn = func(string) bool { return true }
	t.Cleanup(func() { askUseOfferedAdministratorPasswordFn = oldUse })
	oldAsk := askAdministratorPasswordFn
	askAdministratorPasswordFn = func() (string, error) {
		t.Error("accepting the generated password must not ask for a typed one")
		return "", nil
	}
	t.Cleanup(func() { askAdministratorPasswordFn = oldAsk })

	var err error
	stdout, stderr := captureStdoutStderr(t, func() { err = runCreateUsers(dir) })
	if err != nil {
		t.Fatal(err)
	}
	if len(accounts.created) != 1 {
		t.Fatalf("created %d accounts", len(accounts.created))
	}
	if got := accounts.created[0].password; got != "generated-secret-123" {
		t.Fatalf("created password = %q", got)
	}
	for name, out := range map[string]string{"stdout": stdout, "stderr": stderr} {
		if strings.Contains(out, "generated-secret-123") {
			t.Fatalf("generated password leaked to %s: %q", name, out)
		}
	}
	if !strings.Contains(tty.String(), "  Password: generated-secret-123\n") {
		t.Fatalf("generated password not shown on the terminal: %q", tty.String())
	}
	if !strings.Contains(tty.String(), "./sb users show-password first-admin@example.org") {
		t.Fatalf("terminal guidance missing the show command: %q", tty.String())
	}
	data, err := os.ReadFile(filepath.Join(dir, ".users.yml"))
	if err != nil || !strings.Contains(string(data), "generated-secret-123") {
		t.Fatalf("generated password not saved: %q %v", data, err)
	}
}

func TestGeneratedAdministratorPasswordDeclinedUsesTypedPassword(t *testing.T) {
	_, dir, accounts := provisioningFixture(t, true)
	var tty bufferWriteCloser
	oldOpen := openPasswordTerminal
	openPasswordTerminal = func() (io.WriteCloser, error) { return &tty, nil }
	t.Cleanup(func() { openPasswordTerminal = oldOpen })
	oldPrompt := administratorPrompt
	administratorPrompt = func(label, _ string) string {
		switch label {
		case "  Email":
			return "first-admin@example.org"
		case "  Name":
			return "First Admin"
		}
		return ""
	}
	t.Cleanup(func() { administratorPrompt = oldPrompt })
	oldGenerate := newAdministratorPasswordFn
	newAdministratorPasswordFn = func() string { return "generated-secret-123" }
	t.Cleanup(func() { newAdministratorPasswordFn = oldGenerate })
	oldUse := askUseOfferedAdministratorPasswordFn
	askUseOfferedAdministratorPasswordFn = func(string) bool { return false }
	t.Cleanup(func() { askUseOfferedAdministratorPasswordFn = oldUse })
	oldAsk := askAdministratorPasswordFn
	askAdministratorPasswordFn = func() (string, error) { return "typed-secret", nil }
	t.Cleanup(func() { askAdministratorPasswordFn = oldAsk })

	if err := runCreateUsers(dir); err != nil {
		t.Fatal(err)
	}
	if len(accounts.created) != 1 || accounts.created[0].password != "typed-secret" {
		t.Fatalf("created %+v", accounts.created)
	}
	if tty.Len() != 0 {
		t.Fatalf("declined generated password still written: %q", tty.String())
	}
}

func TestMaskedPasswordReaderEchoesStarsAndErases(t *testing.T) {
	var echo strings.Builder
	value, err := readMaskedLine(strings.NewReader("ab\x7fc\r"), &echo)
	if err != nil {
		t.Fatal(err)
	}
	if value != "ac" {
		t.Fatalf("value = %q", value)
	}
	if got := echo.String(); got != "**\b \b*" {
		t.Fatalf("echo = %q", got)
	}
}

func TestMaskedPasswordReaderCtrlCAborts(t *testing.T) {
	var echo strings.Builder
	if _, err := readMaskedLine(strings.NewReader("abc\x03"), &echo); err != errPasswordInterrupted {
		t.Fatalf("err = %v", err)
	}
}

func TestShowUserPasswordPrintsSavedPasswordToTerminal(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	dir := t.TempDir()
	t.Chdir(dir)
	writeUsersFile(t, filepath.Join(home, operatorUsersFileName), "- display_name: \"Ada\"\n  email: \"ada@example.org\"\n  password: \"ada-secret\"\n  role: admin_user\n")
	var tty bufferWriteCloser
	oldOpen := openPasswordTerminal
	openPasswordTerminal = func() (io.WriteCloser, error) { return &tty, nil }
	t.Cleanup(func() { openPasswordTerminal = oldOpen })

	stdout, stderr := captureStdoutStderr(t, func() {
		if err := showSavedUserPassword("ADA@example.org"); err != nil {
			t.Fatal(err)
		}
	})
	if tty.String() != "ada-secret\n" {
		t.Fatalf("terminal output = %q", tty.String())
	}
	if stdout != "" || stderr != "" {
		t.Fatalf("password command wrote to stdout/stderr: %q %q", stdout, stderr)
	}
}

func TestShowUserPasswordRefusesUnknownEmailAndMissingFile(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	dir := t.TempDir()
	t.Chdir(dir)
	var tty bufferWriteCloser
	oldOpen := openPasswordTerminal
	openPasswordTerminal = func() (io.WriteCloser, error) { return &tty, nil }
	t.Cleanup(func() { openPasswordTerminal = oldOpen })

	err := showSavedUserPassword("ada@example.org")
	if err == nil || !strings.Contains(err.Error(), "no saved users file") {
		t.Fatalf("missing file: %v", err)
	}
	writeUsersFile(t, filepath.Join(home, operatorUsersFileName), "- display_name: \"Ada\"\n  email: \"ada@example.org\"\n  password: \"ada-secret\"\n  role: admin_user\n")
	err = showSavedUserPassword("nobody@example.org")
	if err == nil || !strings.Contains(err.Error(), "was not found") {
		t.Fatalf("unknown email: %v", err)
	}
	if tty.Len() != 0 {
		t.Fatalf("refusals wrote to the terminal: %q", tty.String())
	}
}

package cmd

import (
	"bytes"
	"errors"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"golang.org/x/term"
)

func captureCertificateStdout(t *testing.T, fn func()) string {
	t.Helper()
	reader, writer, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	original := os.Stdout
	os.Stdout = writer
	fn()
	_ = writer.Close()
	os.Stdout = original
	data, err := io.ReadAll(reader)
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
}

func TestPFXPasswordRetryWrongThenRight(t *testing.T) {
	data := readFixture(t, pfxFixtureEncrypted)
	original := readPFXPassword
	defer func() { readPFXPassword = original }()

	answers := []string{"not-the-password", pfxFixturePassword}
	calls := 0
	readPFXPassword = func(string) (string, error) {
		answer := answers[calls]
		calls++
		return answer, nil
	}
	var chainErr error
	output := captureCertificateStdout(t, func() {
		_, _, chainErr = decodePFXOrFallback(data, nil, "/certs/secure.pfx")
	})
	if chainErr != nil {
		t.Fatalf("correct second attempt did not decode: %v", chainErr)
	}
	if calls != 2 {
		t.Errorf("password attempts = %d, want 2", calls)
	}
	if !strings.Contains(output, "That password did not open /certs/secure.pfx.") {
		t.Errorf("wrong-password retry line missing: %q", output)
	}
	if strings.Contains(output, "not-the-password") || strings.Contains(output, pfxFixturePassword) {
		t.Errorf("a password leaked into output: %q", output)
	}
}

func TestPFXPasswordRetryStopsAtThreeAndClassifies(t *testing.T) {
	data := readFixture(t, pfxFixtureEncrypted)
	original := readPFXPassword
	defer func() { readPFXPassword = original }()

	calls := 0
	readPFXPassword = func(string) (string, error) {
		calls++
		return "wrong-password", nil
	}
	var decodeErr error
	output := captureCertificateStdout(t, func() {
		_, _, decodeErr = decodePFXOrFallback(data, nil, "/certs/secure.pfx")
	})
	if calls != 3 {
		t.Errorf("password attempts = %d, want 3", calls)
	}
	if !errors.Is(decodeErr, errCertificatePasswordNotAccepted) {
		t.Fatalf("error = %v, want certificate-password-not-accepted", decodeErr)
	}
	cause, fix := classifyInstallFailure("Certificate", decodeErr)
	if cause != "The certificate password was not accepted." {
		t.Errorf("cause = %q", cause)
	}
	if fix != "Run the same install command again and type the PFX password when asked." {
		t.Errorf("fix = %q", fix)
	}
	if strings.Contains(output, "wrong-password") {
		t.Errorf("a password leaked into output: %q", output)
	}
}

func TestPFXSuppliedPasswordDoesNotRetry(t *testing.T) {
	data := readFixture(t, pfxFixtureEncrypted)
	original := readPFXPassword
	defer func() { readPFXPassword = original }()
	readPFXPassword = func(string) (string, error) {
		t.Error("supplied-password path must not prompt")
		return "", nil
	}
	wrong := "supplied-wrong"
	_, _, err := decodePFXOrFallback(data, &wrong, "/certs/secure.pfx")
	if !errors.Is(err, errCertificatePasswordNotAccepted) {
		t.Fatalf("error = %v, want certificate-password-not-accepted", err)
	}
}

func TestPFXPasswordPromptReachesTerminalStream(t *testing.T) {
	t.Setenv("STATBUS_INSTALL_PROMPTS_TO_TTY", "1")
	stdinReader, stdinWriter, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	originalStdin := os.Stdin
	os.Stdin = stdinReader
	_, _ = stdinWriter.WriteString("secret-password\n")
	_ = stdinWriter.Close()
	var password string
	output := captureCertificateStdout(t, func() {
		password, err = readPassword("Enter PFX password (type it and press Enter; it will not be shown; leave empty if none): ")
	})
	os.Stdin = originalStdin
	if err != nil {
		t.Fatal(err)
	}
	if password != "secret-password" {
		t.Errorf("password read = %q", password)
	}
	prompt := "Enter PFX password (type it and press Enter; it will not be shown; leave empty if none):"
	if !strings.Contains(output, prompt) {
		t.Errorf("prompt did not reach the terminal stream: %q", output)
	}
	if strings.Contains(output, "secret-password") {
		t.Errorf("password leaked into the terminal stream: %q", output)
	}
}

// sharedBufferWriter appends to one buffer across open/close cycles, unlike
// bufferWriteCloser which owns its own copy.
type sharedBufferWriter struct{ buf *bytes.Buffer }

func (w sharedBufferWriter) Write(p []byte) (int, error) { return w.buf.Write(p) }
func (w sharedBufferWriter) Close() error                { return nil }

// fakeMaskedTerminal installs the terminal seams for a test with no PTY. The
// raw-mode switch leaves "RAW:" on stdout, so the captured prompt stream shows
// whether the prompt was published before or after echo was disabled.
func fakeMaskedTerminal(t *testing.T) (*bytes.Buffer, *[]string) {
	t.Helper()
	tty := &bytes.Buffer{}
	savedOpen, savedTerminal := openPasswordTerminal, terminalIsTerminal
	savedRaw, savedRestore := makeRawTerminal, restoreTerminal
	var events []string
	openPasswordTerminal = func() (io.WriteCloser, error) { return sharedBufferWriter{buf: tty}, nil }
	terminalIsTerminal = func(int) bool { return true }
	makeRawTerminal = func(int) (*term.State, error) {
		events = append(events, "raw")
		_, _ = io.WriteString(os.Stdout, "RAW:")
		return &term.State{}, nil
	}
	restoreTerminal = func(int, *term.State) error {
		events = append(events, "restore")
		return nil
	}
	t.Cleanup(func() {
		openPasswordTerminal, terminalIsTerminal = savedOpen, savedTerminal
		makeRawTerminal, restoreTerminal = savedRaw, savedRestore
	})
	return tty, &events
}

// TestPFXPasswordPromptFollowsRawModeAndEndsLineOnTerminal: install.sh's
// terminal filter prints a marked prompt asynchronously, so the prompt must be
// published only after echo is off (its newline would otherwise not return the
// carriage), and the masked line must be ended on the terminal itself or the
// choices printed next start beside the stars (STATBUS-422).
func TestPFXPasswordPromptFollowsRawModeAndEndsLineOnTerminal(t *testing.T) {
	t.Setenv("STATBUS_INSTALL_PROMPTS_TO_TTY", "1")
	tty, events := fakeMaskedTerminal(t)
	stdinR, stdinW, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	oldStdin := os.Stdin
	os.Stdin = stdinR
	if _, err := stdinW.WriteString("secret-password\n"); err != nil {
		t.Fatal(err)
	}
	_ = stdinW.Close()
	const prompt = "  PFX password (type it and press Enter; it will not be shown; leave empty if none): "
	var password string
	output := captureCertificateStdout(t, func() {
		password, err = readPassword(prompt)
	})
	os.Stdin = oldStdin
	if err != nil {
		t.Fatal(err)
	}
	if password != "secret-password" {
		t.Errorf("password read = %q", password)
	}
	rawAt := strings.Index(output, "RAW:")
	promptAt := strings.Index(output, "INSTALL_PROMPT_ANSWER: "+prompt)
	if rawAt < 0 || promptAt < 0 || rawAt > promptAt {
		t.Fatalf("prompt must be published after raw mode; stream:\n%q", output)
	}
	if strings.Contains(output, "secret-password") {
		t.Fatalf("password leaked into the terminal stream: %q", output)
	}
	got := tty.String()
	if want := strings.Repeat("*", len("secret-password")) + "\n"; got != want {
		t.Fatalf("terminal output = %q, want the masked stars and one line ending %q", got, want)
	}
	if len(*events) != 2 || (*events)[0] != "raw" || (*events)[1] != "restore" {
		t.Fatalf("terminal events = %v, want raw then restore", *events)
	}
	if filtered := runTerminalFilter(t, output); filtered != prompt {
		t.Fatalf("screen text:\n%q\nwant:\n%q", filtered, prompt)
	}
}

// TestCertificateFolderPFXPasswordEndsLineBeforeChoices: the operator saw the
// masked stars run straight into the certificate list ("***************1)
// /home/..."): the PFX prompt asked with an empty prompt string, so it never
// reached the marked stream, and nothing ended the line on the terminal.
func TestCertificateFolderPFXPasswordEndsLineBeforeChoices(t *testing.T) {
	t.Setenv("STATBUS_INSTALL_PROMPTS_TO_TTY", "1")
	const password = "pfx-secret"
	folder := t.TempDir()
	cert, key := testCertificate(t, "statbus.example.org", []string{"statbus.example.org"}, time.Now().Add(-time.Hour), time.Now().Add(365*24*time.Hour))
	pfx := filepath.Join(folder, "statbus.pfx")
	writePFX(t, pfx, cert, key, password)

	tty, _ := fakeMaskedTerminal(t)
	stdinR, stdinW, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	oldStdin := os.Stdin
	os.Stdin = stdinR
	if _, err := stdinW.WriteString(password + "\n"); err != nil {
		t.Fatal(err)
	}
	_ = stdinW.Close()
	stubCertificateDefaultYes(t, true)

	var args []string
	output := captureCertificateStdout(t, func() {
		args, _ = chooseCertificateFromFolder(folder, t.TempDir())
	})
	os.Stdin = oldStdin

	if len(args) != 1 || args[0] != pfx {
		t.Fatalf("PFX folder produced %q, want [%q]", args, pfx)
	}
	if strings.Contains(output, password) {
		t.Fatalf("password leaked into the terminal stream: %q", output)
	}
	const prompt = "  PFX password (type it and press Enter; it will not be shown; leave empty if none): "
	if screen := runTerminalFilter(t, output); !strings.Contains(screen, prompt) {
		t.Fatalf("PFX password prompt did not reach the screen:\n%s", screen)
	}
	if want := strings.Repeat("*", len(password)) + "\n"; tty.String() != want {
		t.Fatalf("terminal output = %q, want the masked stars and one line ending %q", tty.String(), want)
	}
}

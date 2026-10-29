package cmd

import (
	"errors"
	"io"
	"os"
	"strings"
	"testing"
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

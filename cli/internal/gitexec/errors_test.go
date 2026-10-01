package gitexec

import (
	"bytes"
	"os/exec"
	"strings"
	"testing"
)

func runFailure(t *testing.T, message string) (terminal, logOutput, returned string) {
	t.Helper()
	var terminalBuffer bytes.Buffer
	var logBuffer bytes.Buffer
	sink := ioMultiWriter(&terminalBuffer, &logBuffer)
	err := Run(exec.Command("sh", "-c", "printf '%s\\n' \"$1\" >&2; exit 1", "sh", message), sink, sink)
	if err == nil {
		t.Fatal("expected command failure")
	}
	return terminalBuffer.String(), logBuffer.String(), err.Error()
}

func ioMultiWriter(writers ...*bytes.Buffer) *multiBufferWriter {
	return &multiBufferWriter{writers: writers}
}

type multiBufferWriter struct {
	writers []*bytes.Buffer
}

func (w *multiBufferWriter) Write(p []byte) (int, error) {
	for _, writer := range w.writers {
		_, _ = writer.Write(p)
	}
	return len(p), nil
}

func assertSurfaces(t *testing.T, surfaces []string, want string, forbidden ...string) {
	t.Helper()
	for _, surface := range surfaces {
		if !strings.Contains(surface, want) {
			t.Fatalf("missing %q in %q", want, surface)
		}
		for _, secret := range forbidden {
			if strings.Contains(surface, secret) {
				t.Fatalf("secret %q survived in %q", secret, surface)
			}
		}
	}
}

func TestAuthenticationFailurePreservesMessageAndRedactsSecret(t *testing.T) {
	const secret = "fixture-auth-secret"
	message := "fatal: Authentication failed for 'https://operator:" + secret + "@github.example/statbus.git/'"
	terminal, logOutput, returned := runFailure(t, message)
	assertSurfaces(t, []string{terminal, logOutput, returned}, "fatal: Authentication failed", secret)
	assertSurfaces(t, []string{terminal, logOutput, returned}, "[REDACTED]")
}

func TestMissingRefPreservesMessage(t *testing.T) {
	terminal, logOutput, returned := runFailure(t, "fatal: couldn't find remote ref fixture-missing-ref")
	assertSurfaces(t, []string{terminal, logOutput, returned}, "fatal: couldn't find remote ref fixture-missing-ref")
}

func TestNetworkFailurePreservesMessageAndRedactsURLCredentials(t *testing.T) {
	const secret = "fixture-network-secret"
	message := "fatal: unable to access 'https://operator:" + secret + "@does-not-resolve.invalid/statbus.git/': Could not resolve host: does-not-resolve.invalid"
	terminal, logOutput, returned := runFailure(t, message)
	assertSurfaces(t, []string{terminal, logOutput, returned}, "Could not resolve host", secret)
	assertSurfaces(t, []string{terminal, logOutput, returned}, "[REDACTED]")
}

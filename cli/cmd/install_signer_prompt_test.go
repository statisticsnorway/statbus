package cmd

import (
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestDeclinedSignerPromptIsAskedOnlyOnceAcrossPreflightAndStepPTY(t *testing.T) {
	if os.Getenv("STATBUS_SIGNER_PTY_CHILD") == "1" {
		runSignerPTYChild(t)
		return
	}
	python, err := exec.LookPath("python3")
	if err != nil {
		t.Skip("python3 is required for the PTY regression")
	}
	script := `
import os, pty, sys
pid, fd = pty.fork()
if pid == 0:
    os.environ["STATBUS_SIGNER_PTY_CHILD"] = "1"
    os.execv(sys.argv[1], [sys.argv[1], "-test.run=^TestDeclinedSignerPromptIsAskedOnlyOnceAcrossPreflightAndStepPTY$"])
os.write(fd, b"n\n")
while True:
    try:
        data = os.read(fd, 4096)
    except OSError:
        break
    if not data:
        break
    os.write(1, data)
_, status = os.waitpid(pid, 0)
sys.exit(os.waitstatus_to_exitcode(status))
`
	cmd := exec.Command(python, "-c", script, os.Args[0])
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("PTY signer run failed: %v\n%s", err, out)
	}
}

func runSignerPTYChild(t *testing.T) {
	fi, err := os.Stdin.Stat()
	if err != nil {
		t.Fatalf("stat child stdin: %v", err)
	}
	if fi.Mode()&os.ModeCharDevice == 0 {
		t.Fatalf("child stdin is not a PTY: mode=%v", fi.Mode())
	}
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, ".env.config"), []byte("SITE_DOMAIN=example.invalid\n"), 0600); err != nil {
		t.Fatal(err)
	}
	oldClient := http.DefaultClient
	requests := 0
	http.DefaultClient = &http.Client{Transport: signerRoundTripper(func(req *http.Request) (*http.Response, error) {
		requests++
		return &http.Response{
			StatusCode: 200,
			Header:     make(http.Header),
			Body:       io.NopCloser(strings.NewReader(`[{"key":"ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEZpeHR1cmVTaWduaW5nS2V5MDEyMzQ1Njc4OTAxMjM="}]`)),
		}, nil
	})}
	defer func() { http.DefaultClient = oldClient }()

	signerPromptAnswered, signerPromptAccepted = false, false
	defer func() { signerPromptAnswered, signerPromptAccepted = false, false }()
	// This is the production sequence: existing-install preflight asks first,
	// then the Trusted signers step reaches the same run function.
	if err := runTrustSigners(dir); err != nil {
		t.Fatalf("preflight decline: %v", err)
	}
	if err := runTrustSigners(dir); err == nil {
		t.Fatal("Trusted signers step must stop after the remembered decline")
	}
	if requests != 1 {
		t.Fatalf("GitHub signer lookup count = %d, want 1", requests)
	}
}

type signerRoundTripper func(*http.Request) (*http.Response, error)

func (f signerRoundTripper) RoundTrip(req *http.Request) (*http.Response, error) { return f(req) }

func TestDeclinedSignerPromptIsAskedOnlyOncePerRun(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, ".env.config"), []byte("SITE_DOMAIN=example.invalid\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	stdin, err := os.CreateTemp(t.TempDir(), "stdin")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := stdin.WriteString("n\n"); err != nil {
		t.Fatal(err)
	}
	if _, err := stdin.Seek(0, 0); err != nil {
		t.Fatal(err)
	}
	oldStdin := os.Stdin
	os.Stdin = stdin
	defer func() { os.Stdin = oldStdin }()

	oldClient := http.DefaultClient
	requests := 0
	http.DefaultClient = &http.Client{Transport: signerRoundTripper(func(req *http.Request) (*http.Response, error) {
		requests++
		return &http.Response{
			StatusCode: 200,
			Header:     make(http.Header),
			Body:       io.NopCloser(strings.NewReader(`[{"key":"ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEZpeHR1cmVTaWduaW5nS2V5MDEyMzQ1Njc4OTAxMjM="}]`)),
		}, nil
	})}
	defer func() { http.DefaultClient = oldClient }()

	signerPromptAnswered, signerPromptAccepted = false, false
	defer func() { signerPromptAnswered, signerPromptAccepted = false, false }()
	if err := runTrustSigners(dir); err != nil {
		t.Fatalf("decline should be remembered until the signer step: %v", err)
	}
	if err := runTrustSigners(dir); err == nil {
		t.Fatal("second signer step call must stop without asking again")
	}
	if requests != 1 {
		t.Fatalf("GitHub signer lookup count = %d, want 1", requests)
	}
}

package cmd

import (
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

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

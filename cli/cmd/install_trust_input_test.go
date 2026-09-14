package cmd

import (
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/dotenv"
	"github.com/statisticsnorway/statbus/cli/internal/installinput"
)

type installTrustTransport func(*http.Request) (*http.Response, error)

func (f installTrustTransport) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }

func TestFreshUnattendedConfigThenTrust(t *testing.T) {
	for _, fail := range []bool{false, true} {
		name := "success"
		if fail {
			name = "fetch-refusal"
		}
		t.Run(name, func(t *testing.T) {
			dir, content := unattendedFixture(t)
			input := filepath.Join(t.TempDir(), "input.env")
			if err := os.WriteFile(input, []byte(content), 0600); err != nil {
				t.Fatal(err)
			}
			t.Setenv(installinput.EnvConfig, input)
			oldTrust := trustGitHubUser
			trustGitHubUser = "fixture-signer"
			t.Cleanup(func() { trustGitHubUser = oldTrust })
			oldClient := http.DefaultClient
			t.Cleanup(func() { http.DefaultClient = oldClient })
			requests := 0
			key := "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
			http.DefaultClient = &http.Client{Transport: installTrustTransport(func(r *http.Request) (*http.Response, error) {
				requests++
				cfg, err := os.ReadFile(filepath.Join(dir, ".env.config"))
				if err != nil || !strings.Contains(string(cfg), "SITE_DOMAIN=") {
					t.Fatalf("trust ran before config creation: %v", err)
				}
				status := http.StatusOK
				body := `[{"key":"` + key + `"}]`
				if fail {
					status = http.StatusServiceUnavailable
					body = "unavailable"
				}
				return &http.Response{StatusCode: status, Body: io.NopCloser(strings.NewReader(body)), Header: make(http.Header)}, nil
			})}
			if err := runCreateConfig(dir); err != nil {
				t.Fatal(err)
			}
			err := runTrustSigners(dir)
			if requests == 0 {
				t.Fatalf("explicit fresh trust answer was never consumed: %v", err)
			}
			cfg, loadErr := dotenv.Load(filepath.Join(dir, ".env.config"))
			if loadErr != nil {
				t.Fatal(loadErr)
			}
			got, found := cfg.Get(trustedSignerPrefix + trustGitHubUser)
			if fail {
				if err == nil || found {
					t.Fatalf("fetch refusal not propagated: err=%v saved=%v", err, found)
				}
				return
			}
			if err != nil {
				t.Fatal(err)
			}
			if !found || got != key {
				t.Fatalf("trust not persisted: %q", got)
			}
			if requests != 1 {
				t.Fatalf("wanted one signing-key fetch, got %d", requests)
			}
		})
	}
}

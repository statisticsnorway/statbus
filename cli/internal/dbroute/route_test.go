package dbroute

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/dotenv"
)

func TestResolveIgnoresSiteDomainAndRequiresInternalEndpoint(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, ".env")
	t.Setenv("SITE_DOMAIN", "wrong-process.example.invalid")
	for _, tc := range []struct{ name, env, wantError string }{
		{"internal", "SITE_DOMAIN=wrong-file.example.invalid\nCADDY_DB_BIND_ADDRESS=127.0.0.1\nCADDY_DB_PORT=3914\n", ""},
		{"missing host", "SITE_DOMAIN=wrong-file.example.invalid\nCADDY_DB_PORT=3914\n", "CADDY_DB_BIND_ADDRESS"},
		{"missing port", "SITE_DOMAIN=wrong-file.example.invalid\nCADDY_DB_BIND_ADDRESS=127.0.0.1\n", "CADDY_DB_PORT"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if err := os.WriteFile(path, []byte(tc.env), 0600); err != nil {
				t.Fatal(err)
			}
			file, err := dotenv.Load(path)
			if err != nil {
				t.Fatal(err)
			}
			for name, resolve := range map[string]func() (string, string, error){"FromFile": func() (string, string, error) { return FromFile(file) }, "Resolve": func() (string, string, error) { return Resolve(dir) }} {
				host, port, err := resolve()
				if tc.wantError != "" {
					if err == nil || !strings.Contains(err.Error(), tc.wantError) {
						t.Errorf("%s: expected %s, got %v", name, tc.wantError, err)
					}
					continue
				}
				if err != nil || host != "127.0.0.1" || port != "3914" {
					t.Errorf("%s: %s:%s, %v", name, host, port, err)
				}
			}
		})
	}
}

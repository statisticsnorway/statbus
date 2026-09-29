package config

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestValidateTLSPaths(t *testing.T) {
	dir := t.TempDir()
	certDir := filepath.Join(dir, "caddy", "data", "custom-certs")
	if err := os.MkdirAll(certDir, 0700); err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{"site.crt", "site.key"} {
		if err := os.WriteFile(filepath.Join(certDir, name), []byte("fixture"), 0600); err != nil {
			t.Fatal(err)
		}
	}
	for _, tc := range []struct{ name, cert, key, want string }{
		{"unset", "", "", ""},
		{"valid", "/data/custom-certs/site.crt", "/data/custom-certs/site.key", ""},
		{"host path", "/home/statbus/statbus.crt", "/data/custom-certs/site.key", "not a valid Caddy container path"},
		{"missing", "/data/custom-certs/missing.crt", "/data/custom-certs/site.key", "corresponding host file"},
		{"pair", "/data/custom-certs/site.crt", "", "both TLS_CERT_FILE and TLS_KEY_FILE"},
		{"traversal", "/data/../etc/passwd", "/data/custom-certs/site.key", "not a valid Caddy container path"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			err := validateTLSPaths(dir, tc.cert, tc.key)
			if tc.want == "" {
				if err != nil {
					t.Fatal(err)
				}
				return
			}
			if err == nil || !strings.Contains(err.Error(), tc.want) || !strings.Contains(err.Error(), "doc/DEPLOYMENT.md") {
				t.Fatalf("got %v, want %q and documentation", err, tc.want)
			}
		})
	}
}

//go:build !livedb

package cmd

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// TestShowPostgresVars_UsesBoundDBAddress pins STATBUS-529 AC1 for the
// `sb config show --postgres` interface: PGHOST comes from
// CADDY_DB_BIND_ADDRESS (where the database route actually binds), never
// from SITE_DOMAIN — a public site name is for users and certificates and
// may not even resolve on this host.
func TestShowPostgresVars_UsesBoundDBAddress(t *testing.T) {
	dir := t.TempDir()
	env := strings.Join([]string{
		"SITE_DOMAIN=unresolvable.statbus.invalid",
		"CADDY_DB_BIND_ADDRESS=127.0.0.1",
		"CADDY_DB_PORT=3034",
		"CADDY_DB_TLS_PORT=3035",
		"POSTGRES_APP_DB=statbus",
		"POSTGRES_ADMIN_USER=postgres",
		"POSTGRES_ADMIN_PASSWORD=secret",
	}, "\n") + "\n"
	if err := os.WriteFile(filepath.Join(dir, ".env"), []byte(env), 0o600); err != nil {
		t.Fatal(err)
	}

	cases := []struct {
		name    string
		tls     string
		wantOut string
	}{
		{name: "plain", tls: "", wantOut: "export PGHOST=127.0.0.1 PGPORT=3034 "},
		{name: "tls", tls: "1", wantOut: "export PGHOST=127.0.0.1 PGPORT=3035 "},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Setenv("TLS", tc.tls)
			withWorkingDir(t, dir, func() {
				out := captureStdout(t, func() {
					if err := showPostgresVars(); err != nil {
						t.Fatalf("showPostgresVars: %v", err)
					}
				})
				if !strings.Contains(out, tc.wantOut) {
					t.Errorf("output %q does not contain %q", out, tc.wantOut)
				}
				if strings.Contains(out, "unresolvable.statbus.invalid") {
					t.Errorf("PGHOST came from SITE_DOMAIN: %q", out)
				}
			})
		})
	}
}

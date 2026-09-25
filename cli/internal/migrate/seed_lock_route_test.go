package migrate

import (
	"strings"
	"testing"
)

func TestPostgresSystemConnStrUsesInternalRoute(t *testing.T) {
	t.Setenv("SITE_DOMAIN", "process.example.invalid")
	t.Setenv("PGHOST", "process.example.invalid")
	for _, tc := range []struct{ name, env, missing string }{
		{"internal", "SITE_DOMAIN=file.example.invalid\nCADDY_DB_BIND_ADDRESS=127.0.0.1\nCADDY_DB_PORT=3914\n", ""},
		{"missing host", "SITE_DOMAIN=file.example.invalid\nCADDY_DB_PORT=3914\n", "CADDY_DB_BIND_ADDRESS"},
		{"missing port", "SITE_DOMAIN=file.example.invalid\nCADDY_DB_BIND_ADDRESS=127.0.0.1\n", "CADDY_DB_PORT"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			dir := writeEnv(t, tc.env)
			dsn, err := PostgresSystemConnStr(dir)
			if tc.missing != "" {
				if err == nil || !strings.Contains(err.Error(), tc.missing) {
					t.Fatalf("want missing %s, got %q, %v", tc.missing, dsn, err)
				}
				return
			}
			if err != nil || !strings.Contains(dsn, "host=127.0.0.1 port=3914 dbname=postgres") || strings.Contains(dsn, "example.invalid") {
				t.Fatalf("system DB route: %q, %v", dsn, err)
			}
		})
	}
}

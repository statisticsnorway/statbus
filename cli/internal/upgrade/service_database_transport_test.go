package upgrade

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// The recovery DSN builder reloads the internal endpoint after configuration
// regeneration. This test does not run service reconciliation.
func TestRecoveryDSNUsesInternalRoute(t *testing.T) {
	dir := t.TempDir()
	env := "SITE_DOMAIN=dead.example.invalid\nCADDY_DB_BIND_ADDRESS=127.0.0.1\nCADDY_DB_PORT=3914\nPOSTGRES_APP_DB=statbus_test\nPOSTGRES_ADMIN_USER=postgres\nPOSTGRES_ADMIN_PASSWORD=irrelevant\n"
	if err := os.WriteFile(filepath.Join(dir, ".env"), []byte(env), 0600); err != nil {
		t.Fatal(err)
	}
	svc := &Service{projDir: dir}
	dsn, err := svc.recoveryDSN()
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(dsn, "host=127.0.0.1 port=3914") || strings.Contains(dsn, "dead.example.invalid") {
		t.Fatalf("startup route: %s", dsn)
	}
	// Verify the route is re-read, not cached across installation repair.
	env = strings.Replace(env, "CADDY_DB_PORT=3914", "CADDY_DB_PORT=3915", 1)
	if err := os.WriteFile(filepath.Join(dir, ".env"), []byte(env), 0600); err != nil {
		t.Fatal(err)
	}
	dsn, err = svc.recoveryDSN()
	if err != nil || !strings.Contains(dsn, "port=3915") {
		t.Fatalf("route after regeneration: %s, %v", dsn, err)
	}
}

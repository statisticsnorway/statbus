package cmd

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/migrate"
)

// Installer SQL probes and migrations use PsqlCommand, and its final pgx
// connection and advisory lock use AdminConnStr. The actual seed restore uses
// compose exec directly (seed.go), not migrate.PgRestoreCommand: it needs the
// database container's trusted admin socket. Do not mistake the helper's host
// pg_restore mode for proof of the install seed path.
func TestInstallerDatabaseOperationsUseInternalRoute(t *testing.T) {
	dir := t.TempDir()
	env := "SITE_DOMAIN=unreachable.example.invalid\nCADDY_DB_BIND_ADDRESS=127.0.0.1\nCADDY_DB_PORT=3914\nPOSTGRES_APP_DB=statbus_test\nPOSTGRES_ADMIN_USER=postgres\nPOSTGRES_ADMIN_PASSWORD=irrelevant\n"
	if err := os.WriteFile(filepath.Join(dir, ".env"), []byte(env), 0600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("DOCKER_PSQL", "0")
	t.Setenv("PGHOST", "unreachable.example.invalid")
	t.Setenv("PGPORT", "1")
	{
		_, _, cmdEnv, err := migrate.PsqlCommand(dir)
		if err != nil {
			t.Fatal(err)
		}
		got := map[string]string{}
		for _, pair := range cmdEnv {
			if k, v, ok := strings.Cut(pair, "="); ok {
				got[k] = v
			}
		}
		if got["PGHOST"] != "127.0.0.1" || got["PGPORT"] != "3914" {
			t.Errorf("state/migration route: %s:%s", got["PGHOST"], got["PGPORT"])
		}
	}
	for _, name := range []string{"advisory lock", "final readiness"} {
		dsn, err := migrate.AdminConnStr(dir)
		if err != nil {
			t.Fatal(err)
		}
		if !strings.Contains(dsn, "host=127.0.0.1 port=3914") {
			t.Errorf("%s route: %s", name, dsn)
		}
	}
}

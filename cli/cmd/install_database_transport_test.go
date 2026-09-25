package cmd

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/migrate"
)

// These source-scoped checks pin the distinct installer callers without dialing a DB.
// The command builders below verify their selected transports without running Docker.
func TestInstallerDatabaseOperationsUseInternalRoute(t *testing.T) {
	dir := t.TempDir()
	env := "SITE_DOMAIN=unreachable.example.invalid\nCADDY_DB_BIND_ADDRESS=127.0.0.1\nCADDY_DB_PORT=3914\nPOSTGRES_APP_DB=statbus_test\nPOSTGRES_ADMIN_USER=postgres\nPOSTGRES_ADMIN_PASSWORD=irrelevant\n"
	if err := os.WriteFile(filepath.Join(dir, ".env"), []byte(env), 0600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("DOCKER_PSQL", "0")
	t.Setenv("PGHOST", "unreachable.example.invalid")
	t.Setenv("PGPORT", "1")
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
		t.Errorf("psql route: %s:%s", got["PGHOST"], got["PGPORT"])
	}
	dsn, err := migrate.AdminConnStr(dir)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(dsn, "host=127.0.0.1 port=3914") || strings.Contains(dsn, "unreachable.example.invalid") {
		t.Errorf("admin route: %s", dsn)
	}

	assertCaller := func(file, start, end, expected string) {
		t.Helper()
		source, err := os.ReadFile(file)
		if err != nil {
			t.Fatal(err)
		}
		body := strings.SplitN(string(source), start, 2)
		if len(body) != 2 {
			t.Fatalf("missing caller %s", start)
		}
		body = strings.SplitN(body[1], end, 2)
		if len(body) != 2 || !strings.Contains(body[0], expected) {
			t.Errorf("%s does not call %s", start, expected)
		}
	}
	assertCaller("install.go", "func checkJWTDone(", "func checkUsersDone(", "migrate.PsqlCommand(dir)")
	assertCaller("install.go", "func runInstallSQL(", "func connectInstallDB(", "migrate.PsqlCommand(dir)")
	assertCaller("install.go", "func connectInstallDB(", "func logInstallState(", "migrate.AdminConnStr(dir)")
	assertCaller(filepath.Join("..", "internal", "migrate", "migrate.go"), "func acquireAdvisoryLock(", "func ", "AdminConnStr(projDir)")
	assertCaller("seed.go", "restoreCmd, buildErr :=", "restoreCmd.Stdin", "composeCommand(projDir, \"exec\", \"-T\", \"db\",")
	assertCaller("install_services.go", "var probeUpgradeDatabaseRoute =", "func checkUpgradeDatabaseRoute(", "EnsureDBReachable(context.Background())")
	assertCaller("install.go", "func runInstallService(", "func gitHeadInfo(", "checkUpgradeDatabaseRoute(dir)")
	restore, err := composeCommand(dir, "exec", "-T", "db", "pg_restore", "-U", "postgres", "-d", "statbus_test")
	if err != nil {
		t.Fatal(err)
	}
	if filepath.Base(restore.Path) != "docker" || !strings.Contains(strings.Join(restore.Args, " "), "compose exec -T db pg_restore") {
		t.Errorf("seed socket command: %v", restore.Args)
	}
}

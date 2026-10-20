package cmd

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

// STATBUS-514: the Seed step decides from one direct read of the database
// (which of its tables exist, then whether they hold rows), not from how long
// it waited. These tests drive the production Seed step (checkSeedRestored +
// runSeedRestore through executeInstallStep) against a fake psql on PATH, so
// only the database's answers are scripted.

// seedStep is the Seed row of the install step table.
var seedStep = step{"Seed", checkSeedRestored, runSeedRestore}

// seedFreshnessProject builds a project dir whose .env points host-mode psql at
// a fake database, installs a fake psql that answers from script (the SQL is in
// $sql), and a fake ./sb that records whether the seed fetch was attempted.
func seedFreshnessProject(t *testing.T, script string) (dir string, sbInvoked func() bool) {
	t.Helper()
	dir = t.TempDir()
	env := "CADDY_DB_BIND_ADDRESS=127.0.0.1\nCADDY_DB_PORT=5432\nPOSTGRES_APP_DB=statbus_test\nPOSTGRES_ADMIN_USER=postgres\nPOSTGRES_ADMIN_PASSWORD=x\n"
	if err := os.WriteFile(filepath.Join(dir, ".env"), []byte(env), 0600); err != nil {
		t.Fatal(err)
	}
	// A real install tree ships migrations, so disk is ahead of an empty database.
	if err := os.MkdirAll(filepath.Join(dir, "migrations"), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "migrations", "20260101000000_first.up.sql"), []byte("select 1;\n"), 0600); err != nil {
		t.Fatal(err)
	}
	marker := filepath.Join(dir, "sb-invoked")
	if err := os.WriteFile(filepath.Join(dir, "sb"), []byte("#!/bin/sh\necho \"$*\" >> '"+marker+"'\nexit 0\n"), 0700); err != nil {
		t.Fatal(err)
	}
	bin := t.TempDir()
	body := "#!/bin/sh\nsql=\"$* $(cat)\"\n" + script
	if err := os.WriteFile(filepath.Join(bin, "psql"), []byte(body), 0700); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("DOCKER_PSQL", "0")
	t.Setenv("STATBUS_DB_SEED_NO_FETCH", "")
	old := checkDBHealthyFn
	checkDBHealthyFn = func(string) bool { return true }
	t.Cleanup(func() { checkDBHealthyFn = old })
	return dir, func() bool {
		_, err := os.Stat(marker)
		return err == nil
	}
}

func TestSeedStepRestoresAtOnceOnAnEmptyDatabase(t *testing.T) {
	cases := map[string]string{
		"no tables yet": `case "$sql" in
  *to_regclass*) echo "" ;;
  *) echo "unexpected query: $sql" >&2; exit 3 ;;
esac
`,
		"tables present, no rows": `case "$sql" in
  *to_regclass*) echo "db.migration,public.statistical_unit,public.legal_unit,public.establishment,public.import_job" ;;
  *"FROM db.migration"*) echo f ;;
  *) echo "unexpected query: $sql" >&2; exit 3 ;;
esac
`,
	}
	for name, script := range cases {
		t.Run(name, func(t *testing.T) {
			dir, sbInvoked := seedFreshnessProject(t, script)
			start := time.Now()
			alreadyDone, err := executeInstallStep(seedStep, dir, func() {})
			elapsed := time.Since(start)
			if alreadyDone || err != nil {
				t.Fatalf("an empty database must get the seed restore: alreadyDone=%v err=%v", alreadyDone, err)
			}
			if !sbInvoked() {
				t.Fatal("the seed fetch and restore must run on an empty database")
			}
			if elapsed > 2*time.Second {
				t.Fatalf("the database answered on the first read, yet the Seed step took %s", elapsed)
			}
		})
	}
}

func TestSeedStepSkipsADatabaseWithUserRows(t *testing.T) {
	dir, sbInvoked := seedFreshnessProject(t, `case "$sql" in
  *to_regclass*) echo "public.statistical_unit,public.legal_unit,public.establishment,public.import_job" ;;
  *"FROM public.statistical_unit"*) echo t ;;
  *) echo "unexpected query: $sql" >&2; exit 3 ;;
esac
`)
	alreadyDone, err := executeInstallStep(seedStep, dir, func() {})
	if !alreadyDone || err != nil || sbInvoked() {
		t.Fatalf("a database holding user rows keeps its data: alreadyDone=%v err=%v restoreAttempted=%v", alreadyDone, err, sbInvoked())
	}
}

func TestSeedStepSkipsADatabaseWithAppliedMigrations(t *testing.T) {
	dir, sbInvoked := seedFreshnessProject(t, `case "$sql" in
  *to_regclass*) echo "db.migration" ;;
  *"FROM db.migration"*) echo t ;;
  *) echo "unexpected query: $sql" >&2; exit 3 ;;
esac
`)
	alreadyDone, err := executeInstallStep(seedStep, dir, func() {})
	if !alreadyDone || err != nil || sbInvoked() {
		t.Fatalf("a schema a migration has touched keeps its schema: alreadyDone=%v err=%v restoreAttempted=%v", alreadyDone, err, sbInvoked())
	}
}

func TestSeedStepStopsWhenTheDatabaseCannotBeRead(t *testing.T) {
	dir, sbInvoked := seedFreshnessProject(t, `echo 'psql: error: connection to server at "127.0.0.1", port 5432 failed: Connection refused' >&2; exit 2
`)
	alreadyDone, err := executeInstallStep(seedStep, dir, func() {})
	if alreadyDone {
		t.Fatal("an unread database is not a decision that the seed is done")
	}
	if _, fatal := stepRunOutcome(err); !fatal {
		t.Fatalf("a failed database read must stop the install at the Seed step, got err=%v", err)
	}
	if sbInvoked() {
		t.Fatal("the seed restore must not run over a database that could not be read")
	}
}

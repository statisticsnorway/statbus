package release

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/testgit"
)

func seedLineageRepo(t *testing.T) (dir string, run func(...string), writeMigration func(string)) {
	t.Helper()
	dir = t.TempDir()
	run = func(args ...string) {
		t.Helper()
		cmd := exec.Command("git", testgit.Args(args...)...)
		cmd.Dir = dir
		cmd.Env = testgit.Env()
		if out, err := cmd.CombinedOutput(); err != nil {
			t.Fatalf("git %v: %v\n%s", args, err, out)
		}
	}
	writeMigration = func(name string) {
		t.Helper()
		path := filepath.Join(dir, "migrations", name)
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte("SELECT 1;\n"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	run("init", "-q")
	run("config", "user.email", "test@example.com")
	run("config", "user.name", "test")
	return dir, run, writeMigration
}

func TestMissingSeedLineageMigrationsRejectsPrereleaseRenumber(t *testing.T) {
	dir, run, writeMigration := seedLineageRepo(t)
	writeMigration("20260101000000_baseline.up.sql")
	run("add", "migrations")
	run("commit", "-q", "-m", "baseline")
	run("tag", "baseline")

	writeMigration("20260903205636_pending.up.sql")
	run("add", "migrations")
	run("commit", "-q", "-m", "seed may publish old version")
	oldCommit, err := gitOutput(dir, "rev-parse", "HEAD")
	if err != nil {
		t.Fatal(err)
	}

	run("mv", "migrations/20260903205636_pending.up.sql", "migrations/20260907120000_pending.up.sql")
	run("commit", "-q", "-m", "renumber before rc")

	missing, err := MissingSeedLineageMigrations(dir, "baseline", "HEAD")
	if err != nil {
		t.Fatal(err)
	}
	if len(missing) != 1 {
		t.Fatalf("missing = %#v, want one retained lineage version", missing)
	}
	if missing[0].Version != 20260903205636 {
		t.Fatalf("version = %d, want 20260903205636", missing[0].Version)
	}
	if missing[0].Path != "migrations/20260903205636_pending.up.sql" {
		t.Fatalf("path = %q", missing[0].Path)
	}
	if missing[0].Commit != strings.TrimSpace(oldCommit) {
		t.Fatalf("commit = %q, want %q", missing[0].Commit, strings.TrimSpace(oldCommit))
	}
}

func TestMissingSeedLineageMigrationsAllowsAdditionsAndSameVersionRename(t *testing.T) {
	dir, run, writeMigration := seedLineageRepo(t)
	writeMigration("20260101000000_baseline.up.sql")
	run("add", "migrations")
	run("commit", "-q", "-m", "baseline")
	run("tag", "baseline")

	writeMigration("20260903205636_old_description.up.sql")
	run("add", "migrations")
	run("commit", "-q", "-m", "add")
	run("mv", "migrations/20260903205636_old_description.up.sql", "migrations/20260903205636_new_description.up.sql")
	writeMigration("20260907120000_new.up.psql")
	run("add", "migrations")
	run("commit", "-q", "-m", "keep version and add")

	missing, err := MissingSeedLineageMigrations(dir, "baseline", "HEAD")
	if err != nil {
		t.Fatal(err)
	}
	if len(missing) != 0 {
		t.Fatalf("missing = %#v, want none", missing)
	}
}

func TestMigrationUpPathsAtRefRejectsDuplicateVersion(t *testing.T) {
	dir, run, writeMigration := seedLineageRepo(t)
	writeMigration("20260101000000_one.up.sql")
	writeMigration("20260101000000_two.up.psql")
	run("add", "migrations")
	run("commit", "-q", "-m", "duplicates")

	if _, err := migrationUpPathsAtRef(dir, "HEAD"); err == nil {
		t.Fatal("expected duplicate migration version error")
	}
}

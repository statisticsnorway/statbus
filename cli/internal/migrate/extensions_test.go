package migrate

import (
	"os"
	"strings"
	"testing"
)

// STATBUS-533: the extension lifecycle step (run before pending migrations
// are computed) reconciles each tracked extension against the image default:
// absent -> CREATE at image default, older -> ONE direct ALTER EXTENSION
// UPDATE TO the image default + integrity check + audit receipt, newer ->
// refuse without ever issuing a downgrade. These tests drive the real psql
// subprocess boundary with a fake psql that answers the two catalog queries
// and logs every statement batch it receives.

const fakeImageDefaults = "sql_saga=1.4\njsonb_stats=3.0.0\nltree=1.3\ncitext=1.8\nbtree_gist=1.8\n"

// extensionFakePsql installs a fake psql that reports fakeImageDefaults as
// the image defaults and installedVersions (same "name=version" line shape,
// empty for "nothing installed") as pg_extension. It returns the log file the
// fake appends every received stdin batch to.
func extensionFakePsql(t *testing.T, installedVersions string) (logPath string) {
	t.Helper()
	logPath = t.TempDir() + "/psql-stdin.log"
	t.Setenv("FAKE_PSQL_LOG", logPath)
	t.Setenv("FAKE_INSTALLED", installedVersions)
	fakePsql(t, `sql="$(cat)"
{
  echo "$sql"
  echo "---"
} >> "$FAKE_PSQL_LOG"
case "$sql" in
  *pg_available_extensions*) printf '%s' "$FAKE_DEFAULTS" ;;
  *"FROM pg_extension"*) printf '%s' "$FAKE_INSTALLED" ;;
esac`)
	t.Setenv("FAKE_DEFAULTS", fakeImageDefaults)
	return logPath
}

func readFakePsqlLog(t *testing.T, logPath string) string {
	t.Helper()
	data, err := os.ReadFile(logPath)
	if err != nil {
		t.Fatalf("read fake psql log: %v", err)
	}
	return string(data)
}

func TestEnsureTrackedExtensionsCreatesAbsentAtImageDefault(t *testing.T) {
	logPath := extensionFakePsql(t, "")
	if err := EnsureTrackedExtensions(repoRootForPsql(t)); err != nil {
		t.Fatalf("absent extensions must be created, got error: %v", err)
	}
	log := readFakePsqlLog(t, logPath)
	for _, want := range []string{
		`CREATE EXTENSION "sql_saga";`,
		`CREATE EXTENSION "jsonb_stats";`,
		`CREATE EXTENSION "ltree";`,
		`CREATE EXTENSION "citext";`,
		`CREATE EXTENSION "btree_gist";`,
		// Audit receipt: creation records from_version NULL, to_version the
		// image default.
		`VALUES ('sql_saga', NULL, '1.4')`,
		`VALUES ('jsonb_stats', NULL, '3.0.0')`,
	} {
		if !strings.Contains(log, want) {
			t.Errorf("fake psql never received %q; log:\n%s", want, log)
		}
	}
	if strings.Contains(log, "ALTER EXTENSION") {
		t.Errorf("no ALTER EXTENSION may run when nothing is installed; log:\n%s", log)
	}
}

func TestEnsureTrackedExtensionsUpdatesOlderDirectlyToImageDefault(t *testing.T) {
	logPath := extensionFakePsql(t, "sql_saga=1.0\njsonb_stats=2.0.0\nltree=1.3\ncitext=1.8\nbtree_gist=1.8\n")
	if err := EnsureTrackedExtensions(repoRootForPsql(t)); err != nil {
		t.Fatalf("an older extension must update directly, got error: %v", err)
	}
	log := readFakePsqlLog(t, logPath)
	// Direct update to the image default with the integrity check and the
	// audit receipt in the same batch...
	for _, want := range []string{
		`ALTER EXTENSION "sql_saga" UPDATE TO '1.4';`,
		"SELECT sql_saga.check_integrity();",
		`VALUES ('sql_saga', '1.0', '1.4')`,
		`ALTER EXTENSION "jsonb_stats" UPDATE TO '3.0.0';`,
		`VALUES ('jsonb_stats', '2.0.0', '3.0.0')`,
	} {
		if !strings.Contains(log, want) {
			t.Errorf("fake psql never received %q; log:\n%s", want, log)
		}
	}
	// ...and NEVER intermediate hops: exactly ONE sql_saga ALTER, straight to
	// 1.4. A hop through 1.1/1.2/1.3 would run an old update script against
	// the 1.4 native library, which is the refusal this design exists for.
	if got := strings.Count(log, `ALTER EXTENSION "sql_saga"`); got != 1 {
		t.Errorf("want exactly one direct sql_saga ALTER, got %d; log:\n%s", got, log)
	}
	for _, hop := range []string{"UPDATE TO '1.1'", "UPDATE TO '1.2'", "UPDATE TO '1.3'", "UPDATE TO '2.0.0'"} {
		if strings.Contains(log, hop) {
			t.Errorf("intermediate hop %q must never be issued; log:\n%s", hop, log)
		}
	}
	// Extensions already at the image default are left alone.
	for _, quiet := range []string{`ALTER EXTENSION "ltree"`, `ALTER EXTENSION "citext"`, `ALTER EXTENSION "btree_gist"`} {
		if strings.Contains(log, quiet) {
			t.Errorf("%s is at the image default and must not be touched; log:\n%s", quiet, log)
		}
	}
}

func TestEnsureTrackedExtensionsRefusesNewerWithoutDowngrading(t *testing.T) {
	logPath := extensionFakePsql(t, "sql_saga=1.5\n")
	err := EnsureTrackedExtensions(repoRootForPsql(t))
	if err == nil {
		t.Fatal("a newer extension than the image default must be refused")
	}
	if !strings.Contains(err.Error(), "NEWER") || !strings.Contains(err.Error(), "sql_saga") {
		t.Fatalf("the refusal must name the extension and the direction, got: %v", err)
	}
	log := readFakePsqlLog(t, logPath)
	if strings.Contains(log, "ALTER EXTENSION") || strings.Contains(log, "CREATE EXTENSION") || strings.Contains(log, "DROP EXTENSION") {
		t.Fatalf("refusal must NEVER downgrade or otherwise mutate; log:\n%s", log)
	}
}

func TestEnsureTrackedExtensionsLeavesImageDefaultAlone(t *testing.T) {
	logPath := extensionFakePsql(t, "sql_saga=1.4\njsonb_stats=3.0.0\nltree=1.3\ncitext=1.8\nbtree_gist=1.8\n")
	if err := EnsureTrackedExtensions(repoRootForPsql(t)); err != nil {
		t.Fatal(err)
	}
	log := readFakePsqlLog(t, logPath)
	if strings.Contains(log, "ALTER EXTENSION") || strings.Contains(log, "CREATE EXTENSION \"") {
		t.Errorf("everything at the image default: no extension mutation may run; log:\n%s", log)
	}
}

func TestHasExtensionDrift(t *testing.T) {
	for _, tc := range []struct {
		name      string
		installed string
		want      bool
	}{
		{"all at image default", "sql_saga=1.4\njsonb_stats=3.0.0\nltree=1.3\ncitext=1.8\nbtree_gist=1.8\n", false},
		{"absent is drift", "sql_saga=1.4\njsonb_stats=3.0.0\nltree=1.3\ncitext=1.8\n", true},
		{"older is drift", "sql_saga=1.3\njsonb_stats=3.0.0\nltree=1.3\ncitext=1.8\nbtree_gist=1.8\n", true},
		{"newer is drift (runUp refuses it loudly)", "sql_saga=1.5\njsonb_stats=3.0.0\nltree=1.3\ncitext=1.8\nbtree_gist=1.8\n", true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			_ = extensionFakePsql(t, tc.installed)
			got, err := HasExtensionDrift(repoRootForPsql(t))
			if err != nil {
				t.Fatal(err)
			}
			if got != tc.want {
				t.Fatalf("drift=%v, want %v", got, tc.want)
			}
		})
	}
}

func TestCompareExtensionVersions(t *testing.T) {
	for _, tc := range []struct {
		a, b string
		want int
	}{
		{"1.0", "1.4", -1},
		{"1.4", "1.0", 1},
		{"1.4", "1.4", 0},
		{"1.4", "1.4.0", 0},
		{"1.10", "1.9", 1},
		{"2.0.0", "3.0.0", -1},
		{"1.4.1", "1.4", 1},
	} {
		got, err := compareExtensionVersions(tc.a, tc.b)
		if err != nil {
			t.Fatalf("compare(%q, %q): %v", tc.a, tc.b, err)
		}
		if got != tc.want {
			t.Errorf("compare(%q, %q) = %d, want %d", tc.a, tc.b, got, tc.want)
		}
	}
	// A non-numeric segment must error (refuse), never guess an ordering.
	if _, err := compareExtensionVersions("1.x", "1.4"); err == nil {
		t.Error("non-numeric segment must be an error, not a guessed ordering")
	}
}

package migrate

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"runtime"
	"strings"
	"testing"
)

// repoRoot resolves the repository root from this test file's location
// (<root>/cli/internal/migrate/daemon_floor_test.go) so the guard scans the REAL
// migrations/ tree, not a temp fixture.
func repoRoot(t *testing.T) string {
	t.Helper()
	_, thisFile, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("runtime.Caller failed")
	}
	return filepath.Clean(filepath.Join(filepath.Dir(thisFile), "..", "..", ".."))
}

// stripSQLLineComments removes `-- …` line comments so a comment that mentions a
// daemon relation cannot false-trip the guard. Text before a `--` on a line is
// kept; text from `--` to end-of-line is dropped.
func stripSQLLineComments(sql string) string {
	var b strings.Builder
	for _, line := range strings.Split(sql, "\n") {
		if i := strings.Index(line, "--"); i >= 0 {
			line = line[:i]
		}
		b.WriteString(line)
		b.WriteByte('\n')
	}
	return b.String()
}

// daemonRelationHits returns the daemon relations referenced by a migration's
// SQL (line comments stripped) — the core of the bump guard, factored out so its
// word-boundary matching is directly testable (see TestDaemonRelationMatching).
func daemonRelationHits(sql string) []string {
	stripped := stripSQLLineComments(sql)
	var hits []string
	for _, name := range DaemonRelationNames {
		if regexp.MustCompile(`\b` + regexp.QuoteMeta(name) + `\b`).MatchString(stripped) {
			hits = append(hits, name)
		}
	}
	return hits
}

// TestDaemonRelationMatching proves the guard's matcher actually FIRES (a guard
// that can never fail is worthless) and is precise: a real reference is caught, a
// longer relation sharing a prefix is NOT a false hit on the shorter name, and a
// reference living only in a comment is ignored.
func TestDaemonRelationMatching(t *testing.T) {
	cases := []struct {
		name string
		sql  string
		want []string
	}{
		{"alter upgrade table", "ALTER TABLE public.upgrade ADD COLUMN x int;", []string{"public.upgrade"}},
		{"migration ledger", "INSERT INTO db.migration (version) VALUES (1);", []string{"db.migration"}},
		{"prefix is not a hit on the short name", "ALTER TABLE public.upgrade_retention_caps ADD COLUMN y int;", nil},
		{"supersede proc is its own entry, not public.upgrade", "CALL public.upgrade_supersede_older($1, 0);", []string{"public.upgrade_supersede_older"}},
		{"comment-only reference is ignored", "-- this changes public.upgrade later\nSELECT 1;", nil},
		{"enum type cast", "UPDATE public.upgrade SET release_status = $1::public.release_status_type WHERE id = 1;", []string{"public.upgrade", "public.release_status_type"}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := daemonRelationHits(tc.sql)
			if strings.Join(got, ",") != strings.Join(tc.want, ",") {
				t.Errorf("daemonRelationHits(%q) = %v, want %v", tc.sql, got, tc.want)
			}
		})
	}
}

// TestDaemonSchemaFloorBumpGuard is the STATBUS-145 slice-1 mechanical guarantee:
// any migration NEWER than DaemonSchemaFloor that references a daemon relation
// (DaemonRelationNames) fails this test until the floor is bumped in the same
// commit. That makes it impossible to add a daemon-schema migration above the
// floor without re-deciding the floor — the daemon boots to floor (slice 2), so a
// silently-stale floor would let the daemon operate against a schema missing a
// column its own queries need.
//
// Scanning our own migration SQL for relation NAMES is a data-scan of checked-in
// files, not the doc-022-banned error-prose classification. Match precision:
// schema-qualified names with word boundaries (so `public.upgrade` never matches
// `public.upgrade_supersede_older`). A migration that references a daemon table
// ONLY unqualified (bare `upgrade` under a search_path) would slip this scan —
// the empirical floor test is the backstop oracle for that class.
func TestDaemonSchemaFloorBumpGuard(t *testing.T) {
	root := repoRoot(t)
	files, err := listMigrationFiles(root)
	if err != nil {
		t.Fatalf("listMigrationFiles(%s): %v", root, err)
	}
	if len(files) == 0 {
		t.Fatalf("no migrations found under %s/migrations — repo-root resolution is wrong", root)
	}

	var violations []string
	for _, mf := range files {
		if mf.Version <= DaemonSchemaFloor {
			continue
		}
		body, err := os.ReadFile(mf.Path)
		if err != nil {
			t.Fatalf("read %s: %v", mf.Path, err)
		}
		for _, rel := range daemonRelationHits(string(body)) {
			violations = append(violations, fmt.Sprintf(
				"migration %d (%s) touches daemon relation %s — bump DaemonSchemaFloor to >= %d in the same commit (STATBUS-145)",
				mf.Version, filepath.Base(mf.Path), rel, mf.Version))
		}
	}
	if len(violations) > 0 {
		t.Fatalf("daemon-schema-floor bump guard tripped (%d):\n  %s", len(violations), strings.Join(violations, "\n  "))
	}
}

// TestDaemonSchemaFloorIsARealMigration pins the floor to an actual migration
// version — a floor that is not a real migration would silently migrate-to a
// version that resolves to "everything up to but excluding a nonexistent point".
func TestDaemonSchemaFloorIsARealMigration(t *testing.T) {
	files, err := listMigrationFiles(repoRoot(t))
	if err != nil {
		t.Fatalf("listMigrationFiles: %v", err)
	}
	for _, mf := range files {
		if mf.Version == DaemonSchemaFloor {
			return // found it
		}
	}
	t.Fatalf("DaemonSchemaFloor %d does not correspond to any migration file — it must be a real migration version", DaemonSchemaFloor)
}

// TestDaemonSchemaFloorMigrationTouchesUpgrade is a sanity pin that the floor is
// a genuine daemon-relation migration (it references public.upgrade), not an
// arbitrary number — the floor's own definition is "the max version touching the
// daemon set", so the floor migration must itself touch the set.
func TestDaemonSchemaFloorMigrationTouchesUpgrade(t *testing.T) {
	files, err := listMigrationFiles(repoRoot(t))
	if err != nil {
		t.Fatalf("listMigrationFiles: %v", err)
	}
	re := regexp.MustCompile(`\bpublic\.upgrade\b`)
	for _, mf := range files {
		if mf.Version != DaemonSchemaFloor {
			continue
		}
		body, err := os.ReadFile(mf.Path)
		if err != nil {
			t.Fatalf("read %s: %v", mf.Path, err)
		}
		if !re.MatchString(stripSQLLineComments(string(body))) {
			t.Errorf("floor migration %s does not reference public.upgrade — is %d really the daemon floor?", filepath.Base(mf.Path), DaemonSchemaFloor)
		}
		return
	}
	t.Fatalf("floor migration %d not found", DaemonSchemaFloor)
}

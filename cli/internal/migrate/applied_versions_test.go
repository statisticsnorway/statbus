package migrate

import (
	"testing"
)

// STATBUS-520: listAppliedVersions asks the database whether db.migration
// exists before reading it, so a fresh database answers "none applied"
// and every other failure stays an error. The fake psql answers like the
// real one: SQL arrives on stdin, a missing relation is exit 3 with
// SQLSTATE 42P01, a refused connection is exit 2.

const missingMigrationTablePsql = `sql="$(cat)"
case "$sql" in
  *to_regclass*) echo f ;;
  *"FROM db.migration"*) echo 'ERROR:  42P01: relation "db.migration" does not exist' >&2; exit 3 ;;
  *) echo "unexpected query: $sql" >&2; exit 3 ;;
esac`

func TestListAppliedVersionsOnAFreshDatabaseIsEmpty(t *testing.T) {
	fakePsql(t, missingMigrationTablePsql)
	root := repoRootForPsql(t)
	applied, err := listAppliedVersions(root)
	if err != nil {
		t.Fatalf("a database without db.migration has no applied migrations, got error: %v", err)
	}
	if len(applied) != 0 {
		t.Fatalf("want no applied versions, got %v", applied)
	}
	pending, err := HasPending(root)
	if err != nil || !pending {
		t.Fatalf("every migration on disk is pending on a fresh database: pending=%v err=%v", pending, err)
	}
}

func TestListAppliedVersionsReportsAnUnreachableDatabase(t *testing.T) {
	fakePsql(t, `cat >/dev/null; echo 'psql: error: connection to server at "127.0.0.1", port 5432 failed: Connection refused' >&2; exit 2`)
	if applied, err := listAppliedVersions(repoRootForPsql(t)); err == nil {
		t.Fatalf("an unreachable database must be an error, got applied=%v", applied)
	}
}

func TestListAppliedVersionsReturnsTheRecordedVersions(t *testing.T) {
	fakePsql(t, `sql="$(cat)"
case "$sql" in
  *to_regclass*) echo t ;;
  *"FROM db.migration"*) printf '20240101000000\n20240102000000\n' ;;
  *) echo "unexpected query: $sql" >&2; exit 3 ;;
esac`)
	applied, err := listAppliedVersions(repoRootForPsql(t))
	if err != nil {
		t.Fatal(err)
	}
	want := map[int64]bool{20240101000000: true, 20240102000000: true}
	if len(applied) != len(want) {
		t.Fatalf("want %v, got %v", want, applied)
	}
	for v := range want {
		if !applied[v] {
			t.Fatalf("want %v, got %v", want, applied)
		}
	}
}

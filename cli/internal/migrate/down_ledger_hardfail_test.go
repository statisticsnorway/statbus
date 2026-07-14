package migrate

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// TestDown_LedgerDeleteFailure_AbortsLoop is STATBUS-187 #8/#9's oracle: a
// failing runPsql ledger DELETE must return an error immediately and must
// NOT continue rolling back subsequent versions — continuing would
// compound the ledger/schema divergence rather than contain it.
func TestDown_LedgerDeleteFailure_AbortsLoop(t *testing.T) {
	projDir := t.TempDir()
	migrationsDir := filepath.Join(projDir, "migrations")
	if err := os.MkdirAll(migrationsDir, 0755); err != nil {
		t.Fatal(err)
	}

	// Two versions to roll back, newest first (matches the DESC query
	// order Down() expects). Empty down files so the test exercises the
	// "[empty - skipped]" DELETE-only branch — no runPsqlFile invocation
	// needed to reach the ledger-write site under test.
	newer := int64(20260102000000)
	older := int64(20260101000000)
	for _, v := range []int64{newer, older} {
		downFile := filepath.Join(migrationsDir, fmt.Sprintf("%d_test.down.sql", v))
		if err := os.WriteFile(downFile, nil, 0644); err != nil {
			t.Fatal(err)
		}
	}

	var calls []string
	origRunPsqlFn := runPsqlFn
	defer func() { runPsqlFn = origRunPsqlFn }()
	runPsqlFn = func(dir, sql string, extraArgs ...string) (string, error) {
		calls = append(calls, sql)
		switch {
		case strings.Contains(sql, "pg_tables"):
			return "t", nil
		case strings.HasPrefix(sql, "SELECT version FROM db.migration"):
			return fmt.Sprintf("%d\n%d", newer, older), nil
		case strings.Contains(sql, fmt.Sprintf("WHERE version = %d", newer)):
			// The FIRST version processed (newest-first order) fails its
			// ledger DELETE.
			return "", fmt.Errorf("simulated ledger write failure")
		default:
			return "", nil
		}
	}

	err := Down(projDir, 0, false, false)
	if err == nil {
		t.Fatal("Down() = nil, want an error (ledger DELETE failed)")
	}
	if !strings.Contains(err.Error(), "ledger") {
		t.Errorf("error %q does not mention the ledger divergence", err.Error())
	}

	olderDelete := fmt.Sprintf("DELETE FROM db.migration WHERE version = %d", older)
	for _, c := range calls {
		if c == olderDelete {
			t.Fatalf("Down() continued past the failed DELETE for %d — issued a DELETE for %d too; the loop should have aborted immediately", newer, older)
		}
	}
}

// TestDown_FullRollbackDropFailure_ReturnsError is STATBUS-187 #8/#9's
// second oracle case: a failing full-rollback DROP TABLE/SCHEMA must
// surface as an error, not be silently swallowed.
func TestDown_FullRollbackDropFailure_ReturnsError(t *testing.T) {
	projDir := t.TempDir()
	migrationsDir := filepath.Join(projDir, "migrations")
	if err := os.MkdirAll(migrationsDir, 0755); err != nil {
		t.Fatal(err)
	}
	version := int64(20260101000000)
	downFile := filepath.Join(migrationsDir, fmt.Sprintf("%d_test.down.sql", version))
	if err := os.WriteFile(downFile, nil, 0644); err != nil {
		t.Fatal(err)
	}

	origRunPsqlFn := runPsqlFn
	defer func() { runPsqlFn = origRunPsqlFn }()
	runPsqlFn = func(dir, sql string, extraArgs ...string) (string, error) {
		switch {
		case strings.Contains(sql, "pg_tables"):
			return "t", nil
		case strings.HasPrefix(sql, "SELECT version FROM db.migration"):
			return fmt.Sprintf("%d", version), nil
		case strings.HasPrefix(sql, "DROP TABLE"):
			return "", fmt.Errorf("simulated drop failure")
		default:
			return "", nil
		}
	}

	err := Down(projDir, 0, true, false) // all=true, migrateTo=0 → triggers the full-rollback DROP
	if err == nil {
		t.Fatal("Down() = nil, want an error (DROP TABLE/SCHEMA failed)")
	}
	if !strings.Contains(err.Error(), "ledger") {
		t.Errorf("error %q does not describe the ledger table/schema left behind", err.Error())
	}
}

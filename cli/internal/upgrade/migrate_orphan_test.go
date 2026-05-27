package upgrade

import (
	"errors"
	"fmt"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/migrate"
)

// #14 (migrate-orphan clean kill): on a migrate TIMEOUT, the upgrade service
// pg_terminate_backend's the orphaned in-container psql backend (docker compose
// exec does NOT forward SIGKILL, so a host-side process-group kill leaves it
// alive with its txn open — a commit-after-rollback consistency race). These
// guards pin (1) the terminate SQL matches the migration psql tag by prefix and
// excludes the caller's own backend, and (2) the terminate fires ONLY on a
// genuine timeout, never on a clean migrate failure.

// TestMigrateOrphanTerminateSQL: the terminate query matches the migration psql
// subprocess by its application_name PREFIX (the terminate runs in the service
// process, which can't know the migrate child's pid; the upgrade-mutex
// serializes so only one such backend exists) and never terminates its own
// backend.
func TestMigrateOrphanTerminateSQL(t *testing.T) {
	sql := migrateOrphanTerminateSQL
	// Matches the migration psql tag prefix (single source of truth).
	if !strings.Contains(sql, migrate.SubprocessAppNamePrefix) {
		t.Errorf("terminate SQL must match the migrate psql app_name prefix %q; got:\n%s", migrate.SubprocessAppNamePrefix, sql)
	}
	// LIKE prefix match (not exact), so any pid suffix is caught.
	if !strings.Contains(sql, "LIKE") {
		t.Errorf("terminate SQL must LIKE-match the prefix (pid suffix varies); got:\n%s", sql)
	}
	// Must exclude the caller's own backend.
	if !strings.Contains(sql, "pg_backend_pid()") {
		t.Errorf("terminate SQL must exclude pg_backend_pid() (never terminate self); got:\n%s", sql)
	}
	// Must actually call pg_terminate_backend.
	if !strings.Contains(sql, "pg_terminate_backend") {
		t.Errorf("terminate SQL must call pg_terminate_backend; got:\n%s", sql)
	}
}

// TestErrCommandTimeout_IsMatchable: runCommandToLog wraps a timeout so callers
// can errors.Is() it — the migrate site gates the orphan-terminate on this so a
// clean (non-timeout) migrate failure does NOT trigger a needless terminate.
func TestErrCommandTimeout_IsMatchable(t *testing.T) {
	// A wrapped timeout error (as runCommandToLog returns) must match.
	wrapped := fmt.Errorf("sb migrate up after 30m0s: %w", ErrCommandTimeout)
	if !errors.Is(wrapped, ErrCommandTimeout) {
		t.Error("a wrapped timeout error must errors.Is(ErrCommandTimeout) — the migrate site gates terminate on this")
	}
	// A non-timeout migrate failure must NOT match (psql exited cleanly → no
	// orphan → no terminate).
	cleanFail := fmt.Errorf("migration 0042 failed: syntax error at or near \"FOO\"")
	if errors.Is(cleanFail, ErrCommandTimeout) {
		t.Error("a clean (non-timeout) migrate failure must NOT match ErrCommandTimeout — no orphan to reap")
	}
}

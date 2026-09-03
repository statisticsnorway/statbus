package upgrade

import (
	"context"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
)

// TestLiveRollbackFinishing_ExternalWritesReopen observes the window contract
// from the OUTSIDE: a fresh, non-exempt PostgreSQL session (the shape every app,
// PostgREST, worker and psql session has) is rejected with 25006 while the
// read-only default is ON, and accepted again after the real cleanup-only
// finisher (finalizePendingRollbacks: lift window -> lift maintenance ->
// marker + rolled_back) has run. This is the property the whole design exists
// for: writes accepted after the lift are never overwritten by a second
// restore, and the lift itself is observable by the sessions it affects.
//
// The window flip is a database-level ALTER (persistent), so this test runs
// only when it can restore the prior state; it asserts the default is OFF
// before starting and leaves it OFF.
//
//	STATBUS_LIVE_DB=1 go test -count=1 -run TestLiveRollbackFinishing_ExternalWritesReopen -v ./internal/upgrade
func TestLiveRollbackFinishing_ExternalWritesReopen(t *testing.T) {
	if os.Getenv("STATBUS_LIVE_DB") == "" {
		t.Skip("set STATBUS_LIVE_DB=1 to exercise the real database")
	}
	projDir := findProjDir(t)
	if _, err := os.Stat(flagFilePath(projDir)); err == nil {
		t.Fatalf("a real upgrade marker exists at %s; refusing to run beside a live upgrade", flagFilePath(projDir))
	}
	d := NewService(projDir, false, "test", "")
	ctx, cancel := context.WithTimeout(context.Background(), 120*time.Second)
	defer cancel()
	if err := d.LoadConfigAndConnect(ctx); err != nil {
		t.Fatalf("LoadConfigAndConnect: %v", err)
	}
	t.Cleanup(d.Close)

	dsn, err := d.recoveryDSN()
	if err != nil {
		t.Fatal(err)
	}
	// A plain external session: no self-exemption, so it feels the DB default.
	external := func() *pgx.Conn {
		c, err := pgx.Connect(ctx, strings.Replace(dsn, "application_name=statbus-upgrade-daemon", "application_name=live-external-probe", 1))
		if err != nil {
			t.Fatalf("external connect: %v", err)
		}
		return c
	}
	readOnlyDefault := func() bool {
		var on bool
		if err := d.queryConn.QueryRow(ctx, `SELECT coalesce((SELECT 'default_transaction_read_only=on' = ANY(s.setconfig)
			FROM pg_db_role_setting s JOIN pg_database x ON x.oid = s.setdatabase
			WHERE x.datname = current_database() AND s.setrole = 0), false)`).Scan(&on); err != nil {
			t.Fatal(err)
		}
		return on
	}
	if readOnlyDefault() {
		t.Fatal("the read-only default is already ON on this box; refusing to run (an upgrade may own it)")
	}
	t.Cleanup(func() {
		// Whatever happened above, leave the box writable.
		cctx, ccancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer ccancel()
		if _, err := d.terminalUpdate("SELECT current_database()"); err == nil {
			_, _ = d.liftReadOnlyWindow("live test cleanup")
		}
		_ = cctx
	})

	const sha = "3470000000000000000000000000000000000031"
	var id int
	if err := d.queryConn.QueryRow(ctx, `
		INSERT INTO public.upgrade (commit_sha, committed_at, commit_tags, release_status, summary, state,
		                            scheduled_at, started_at, error, backup_path, log_relative_file_path)
		VALUES ($1, now() - interval '2 days', '{}', 'commit', 'live window probe', 'failed',
		        now() - interval '1 hour', now() - interval '59 minutes', $2, '/nonexistent/live-window-probe-backup', 'live-window-probe.log')
		RETURNING id`, sha, rollbackFinishPendingError(ErrGitFetchRetryable+": live window probe")).Scan(&id); err != nil {
		t.Fatalf("insert pending row: %v", err)
	}
	t.Cleanup(func() {
		cctx, ccancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer ccancel()
		if _, err := d.queryConn.Exec(cctx, "DELETE FROM public.upgrade_state_log WHERE upgrade_id = $1", id); err != nil {
			t.Errorf("cleanup state log: %v", err)
		}
		if _, err := d.queryConn.Exec(cctx, "DELETE FROM public.upgrade WHERE id = $1", id); err != nil {
			t.Errorf("cleanup row: %v", err)
		}
		_ = os.Remove(flagFilePath(projDir))
	})
	if err := d.writeUpgradeFlag(id, sha, nil, "live-probe", "test", false); err != nil {
		t.Fatal(err)
	}
	d.releaseUpgradeFlagLockKeepingFile()

	// Engage the real window (the pre-snapshot state a crashed rollback leaves).
	if _, err := d.setDatabaseReadOnly(ctx, true); err != nil {
		t.Fatalf("engage read-only window: %v", err)
	}
	if !readOnlyDefault() {
		t.Fatal("window did not engage")
	}

	// OUTSIDE VIEW while the window is on: a fresh session's write is rejected.
	ext := external()
	_, writeErr := ext.Exec(ctx, "CREATE TEMP TABLE live_window_probe (x int)")
	_ = ext.Close(ctx)
	if writeErr == nil {
		t.Fatal("an external session could write while the read-only window was ON")
	}
	if !strings.Contains(writeErr.Error(), "25006") && !strings.Contains(writeErr.Error(), "read-only") {
		t.Fatalf("external write failed for an unexpected reason: %v", writeErr)
	}
	t.Logf("window ON: external write rejected as expected: %v", writeErr)

	// The real cleanup-only finisher, exactly as the daemon boot and heartbeat run it.
	out := captureStdoutUpgrade(t, func() { d.finalizePendingRollbacks(ctx) })
	if !strings.Contains(out, "upgrade row ["+LabelRolledBackFinishRecovery+"]") {
		t.Errorf("finisher did not log the rolled_back row:\n%s", out)
	}

	// OUTSIDE VIEW after: the same kind of session writes again; marker gone; row healthy.
	if readOnlyDefault() {
		t.Fatal("read-only default still ON after the finisher")
	}
	ext = external()
	if _, err := ext.Exec(ctx, "CREATE TEMP TABLE live_window_probe (x int)"); err != nil {
		t.Fatalf("external write still rejected after the finisher: %v", err)
	}
	_ = ext.Close(ctx)
	if _, err := os.Stat(flagFilePath(projDir)); !os.IsNotExist(err) {
		t.Errorf("marker still present after the finisher: %v", err)
	}
	var state string
	if err := d.queryConn.QueryRow(ctx, "SELECT state::text FROM public.upgrade WHERE id = $1", id).Scan(&state); err != nil {
		t.Fatal(err)
	}
	if state != "rolled_back" {
		t.Errorf("state = %s, want rolled_back", state)
	}
	t.Logf("window OFF: external write accepted, marker removed, row %s", state)
}

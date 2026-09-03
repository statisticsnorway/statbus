package upgrade

import (
	"context"
	"os"
	"strings"
	"testing"
	"time"
)

// TestLiveRollbackFinishing exercises the REAL cleanup-only rollback finisher
// (db33f1316) against the REAL local database and a REAL marker file, on the
// same connect path the daemon uses. It answers the three questions the design
// makes: does a ROLLBACK_FINISH_PENDING row block every new claim; does
// finalizePendingRollback remove the marker and commit rolled_back in one step;
// and does the same finisher refuse to touch a marker that belongs to a
// different upgrade.
//
// Rows are inserted and cleaned up by the test (the finisher commits its own
// transaction, so a wrapping ROLLBACK cannot cover it). The upgrade rows are
// real inserts into public.upgrade with a probe-only commit_sha; they are
// deleted at the end together with their upgrade_state_log entries.
//
//	STATBUS_LIVE_DB=1 go test -count=1 -run TestLiveRollbackFinishing -v ./internal/upgrade
func TestLiveRollbackFinishing(t *testing.T) {
	if os.Getenv("STATBUS_LIVE_DB") == "" {
		t.Skip("set STATBUS_LIVE_DB=1 to exercise the real database")
	}
	projDir := findProjDir(t)
	if _, err := os.Stat(flagFilePath(projDir)); err == nil {
		t.Fatalf("a real upgrade marker exists at %s; refusing to run the live probe beside a live upgrade", flagFilePath(projDir))
	}
	d := NewService(projDir, false, "test", "")
	ctx, cancel := context.WithTimeout(context.Background(), 90*time.Second)
	defer cancel()
	if err := d.loadConfig(); err != nil {
		t.Fatalf("loadConfig: %v", err)
	}
	if err := d.connect(ctx); err != nil {
		t.Fatalf("connect: %v", err)
	}
	t.Cleanup(d.Close) // registered FIRST so it runs LAST (t.Cleanup is LIFO): the row cleanup below needs the conn

	const pendingSHA = "3470000000000000000000000000000000000001"
	const scheduledSHA = "3470000000000000000000000000000000000002"
	var pendingID, scheduledID int
	pendingErr := rollbackFinishPendingError(ErrGitFetchRetryable + ": live probe: remote closed connection")
	if err := d.queryConn.QueryRow(ctx, `
		INSERT INTO public.upgrade (commit_sha, committed_at, commit_tags, release_status, summary, state,
		                            scheduled_at, started_at, error, backup_path, log_relative_file_path)
		VALUES ($1, now() - interval '2 days', '{}', 'commit', 'live rollback-finishing probe', 'failed',
		        now() - interval '1 hour', now() - interval '59 minutes', $2, '/nonexistent/live-probe-backup', 'live-probe.log')
		RETURNING id`, pendingSHA, pendingErr).Scan(&pendingID); err != nil {
		t.Fatalf("insert pending row: %v", err)
	}
	if err := d.queryConn.QueryRow(ctx, `
		INSERT INTO public.upgrade (commit_sha, committed_at, commit_tags, release_status, summary, state, scheduled_at)
		VALUES ($1, now() - interval '1 day', '{}', 'commit', 'live claim probe', 'scheduled', now())
		RETURNING id`, scheduledSHA).Scan(&scheduledID); err != nil {
		t.Fatalf("insert scheduled row: %v", err)
	}
	t.Cleanup(func() {
		cctx, ccancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer ccancel()
		conn := d.queryConn
		if _, err := conn.Exec(cctx, "DELETE FROM public.upgrade_state_log WHERE upgrade_id IN ($1, $2)", pendingID, scheduledID); err != nil {
			t.Errorf("cleanup upgrade_state_log: %v", err)
		}
		if _, err := conn.Exec(cctx, "DELETE FROM public.upgrade WHERE id IN ($1, $2)", pendingID, scheduledID); err != nil {
			t.Errorf("cleanup upgrade rows: %v", err)
		}
		_ = os.Remove(flagFilePath(projDir))
	})

	// The pending row's own marker survives on disk with a FREE flock, exactly
	// the post-crash / failed-unlink shape.
	if err := d.writeUpgradeFlag(pendingID, pendingSHA, nil, "live-probe", "test", false); err != nil {
		t.Fatalf("write marker: %v", err)
	}
	d.releaseUpgradeFlagLockKeepingFile()

	// 1. Every new claim is refused while the pending row exists.
	_, claimErr := d.claimScheduledUpgrade(ctx, scheduledID)
	if claimErr == nil || !strings.Contains(claimErr.Error(), "rollback finishing cleanup") {
		t.Fatalf("claim of a scheduled row was not refused while ROLLBACK_FINISH_PENDING stands: err=%v", claimErr)
	}
	var st string
	if err := d.queryConn.QueryRow(ctx, "SELECT state::text FROM public.upgrade WHERE id = $1", scheduledID).Scan(&st); err != nil {
		t.Fatal(err)
	}
	if st != "scheduled" {
		t.Fatalf("refused claim still changed the row: state=%s", st)
	}

	// 2. A finisher for a DIFFERENT id must not remove this marker.
	if err := d.clearRollbackFinishFlag(pendingID + 100000); err != nil {
		t.Fatalf("clearRollbackFinishFlag for a foreign id errored: %v", err)
	}
	if _, err := os.Stat(flagFilePath(projDir)); err != nil {
		t.Fatalf("a finisher for another upgrade removed this upgrade's marker: %v", err)
	}

	// 3. The real finisher: marker removal + rolled_back in one transaction.
	out := captureStdoutUpgrade(t, func() {
		finalized, err := d.finalizePendingRollback(ctx, pendingID, LabelRolledBackFinishRecovery)
		if err != nil {
			t.Errorf("finalizePendingRollback: %v", err)
		}
		if !finalized {
			t.Error("finalizePendingRollback reported nothing to finalize")
		}
	})
	if !strings.Contains(out, "upgrade row ["+LabelRolledBackFinishRecovery+"]") {
		t.Errorf("finisher did not log the rolled_back row under %s:\n%s", LabelRolledBackFinishRecovery, out)
	}
	if _, err := os.Stat(flagFilePath(projDir)); !os.IsNotExist(err) {
		t.Errorf("marker still present after finalization: %v", err)
	}
	var state, errText string
	var rolledBackAt *time.Time
	if err := d.queryConn.QueryRow(ctx,
		"SELECT state::text, error, rolled_back_at FROM public.upgrade WHERE id = $1", pendingID).Scan(&state, &errText, &rolledBackAt); err != nil {
		t.Fatal(err)
	}
	if state != "rolled_back" || rolledBackAt == nil {
		t.Errorf("row after finalization: state=%s rolled_back_at=%v, want rolled_back with a timestamp", state, rolledBackAt)
	}
	if strings.HasPrefix(errText, RollbackFinishPendingPrefix) {
		t.Errorf("final row still carries the pending prefix: %q", errText)
	}
	if !strings.Contains(errText, "safe to schedule this same version again") {
		t.Errorf("a retryable cause must yield the retry guidance, got: %q", errText)
	}

	// 4. With the pending row gone, the same claim now succeeds atomically.
	claim, claimErr := d.claimScheduledUpgrade(ctx, scheduledID)
	if claimErr != nil {
		t.Fatalf("claim after finalization: %v", claimErr)
	}
	if claim.Snapshot.ID != scheduledID || claim.Snapshot.CommitSHA != scheduledSHA {
		t.Errorf("claim snapshot = %+v, want id=%d sha=%s", claim.Snapshot, scheduledID, scheduledSHA)
	}
	if err := d.queryConn.QueryRow(ctx, "SELECT state::text FROM public.upgrade WHERE id = $1", scheduledID).Scan(&st); err != nil {
		t.Fatal(err)
	}
	if st != "in_progress" {
		t.Errorf("claimed row state=%s, want in_progress", st)
	}
}

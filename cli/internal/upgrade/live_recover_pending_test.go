package upgrade

import (
	"context"
	"encoding/json"
	"os"
	"strings"
	"testing"
	"time"
)

// TestLiveRecoverFromFlag_PendingRollbackNeverRestores exercises the exported
// recovery entrypoint the daemon boot AND `./sb install`'s crash-recovery ladder
// both call (RecoverFromFlag), against the REAL local database and a REAL
// service-held marker on disk, in the most dangerous shape: a PreSwap-phase
// marker (which recovery would otherwise roll back UNCONDITIONALLY) whose row
// has rollback_finish_pending_at set. Expected: cleanup-only — marker removed, row
// rolled_back, no restore attempted, RecoverFromFlag returns nil.
//
// The restore path is made observable by pointing backup_path at a directory
// that does not exist: any attempt to restore would fail loudly and leave the
// row `failed` with the restore-broke wording instead of `rolled_back`.
//
//	STATBUS_LIVE_DB=1 go test -count=1 -run TestLiveRecoverFromFlag -v ./internal/upgrade
func TestLiveRecoverFromFlag_PendingRollbackNeverRestores(t *testing.T) {
	if os.Getenv("STATBUS_LIVE_DB") == "" {
		t.Skip("set STATBUS_LIVE_DB=1 to exercise the real database")
	}
	projDir := findProjDir(t)
	if _, err := os.Stat(flagFilePath(projDir)); err == nil {
		t.Fatalf("a real upgrade marker exists at %s; refusing to run beside a live upgrade", flagFilePath(projDir))
	}
	d := NewService(projDir, false, "test", "")
	ctx, cancel := context.WithTimeout(context.Background(), 90*time.Second)
	defer cancel()
	if err := d.LoadConfigAndConnect(ctx); err != nil {
		t.Fatalf("LoadConfigAndConnect: %v", err)
	}
	t.Cleanup(d.Close)

	const sha = "3470000000000000000000000000000000000011"
	var id int
	if err := d.queryConn.QueryRow(ctx, `
		INSERT INTO public.upgrade (commit_sha, committed_at, commit_tags, release_status, summary, state,
		                            scheduled_at, started_at, error, backup_path, log_relative_file_path, rollback_finish_pending_at)
		VALUES ($1, now() - interval '2 days', '{}', 'commit', 'live recover probe', 'failed',
		        now() - interval '1 hour', now() - interval '59 minutes', $2, '/nonexistent/live-recover-probe-backup', 'live-recover-probe.log', now())
		RETURNING id`, sha, ErrGitFetchRetryable+": live recover probe").Scan(&id); err != nil {
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

	// A PreSwap (empty phase) service-held marker with a FREE flock: the exact
	// on-disk shape after the finisher crashed between restore and unlink.
	marker, _ := json.Marshal(UpgradeFlag{ID: id, CommitSHA: sha, StartedAt: time.Now(), InvokedBy: "probe", Trigger: "test", Holder: HolderService})
	if err := os.WriteFile(flagFilePath(projDir), marker, 0644); err != nil {
		t.Fatal(err)
	}

	out := captureStdoutUpgrade(t, func() {
		if err := d.RecoverFromFlag(ctx); err != nil {
			t.Errorf("RecoverFromFlag: %v", err)
		}
	})
	t.Logf("recovery output:\n%s", out)

	for _, want := range []string{
		"already restored the previous version",
		"The snapshot will not be restored again",
		"Rollback finishing cleanup for upgrade",
	} {
		if !strings.Contains(out, want) {
			t.Errorf("recovery narrative missing %q", want)
		}
	}
	for _, forbidden := range []string{"Rolling back to the previous version:", "Restoring database", "rollback-docker-up", "ROLLBACK INCOMPLETE"} {
		if strings.Contains(out, forbidden) {
			t.Errorf("recovery attempted a restore (%q) on a cleanup-only row", forbidden)
		}
	}
	if _, err := os.Stat(flagFilePath(projDir)); !os.IsNotExist(err) {
		t.Errorf("marker still on disk after cleanup-only recovery: %v", err)
	}
	var state, errText string
	var pendingAt *time.Time
	if err := d.queryConn.QueryRow(ctx, "SELECT state::text, error, rollback_finish_pending_at FROM public.upgrade WHERE id = $1", id).Scan(&state, &errText, &pendingAt); err != nil {
		t.Fatal(err)
	}
	if state != "rolled_back" || pendingAt != nil {
		t.Errorf("row state=%s pending=%v, want rolled_back with pending cleared; error=%q", state, pendingAt, errText)
	}
	if strings.Contains(errText, "ROLLBACK INCOMPLETE") {
		t.Errorf("row error is not the healthy final guidance: %q", errText)
	}
}

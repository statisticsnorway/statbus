package upgrade

import (
	"context"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"
)

// TestLiveRestoreAndFinalize_UnlinkFailureThenRecovery is the crash-shaped
// twin: the real restoreAndFinalize succeeds at every boundary EXCEPT the
// final marker unlink (injected through the removeFile seam), so it must NOT
// claim completion. Expected: the row stays failed with rollback_finish_pending_at set, SQL and
// HTTP are already reopened (the window was lifted before finishing, and it
// is safe: no path may restore again), the flock is released while the
// marker survives on disk (the crashed-recovery shape), and a later
// RecoverFromFlag — the real entrypoint, unlink working again — finishes
// cleanup-only. Docker is a PATH shim; everything else is real.
//
//	STATBUS_LIVE_DB=1 go test -count=1 -run TestLiveRestoreAndFinalize_UnlinkFailure -v ./internal/upgrade
func TestLiveRestoreAndFinalize_UnlinkFailureThenRecovery(t *testing.T) {
	if os.Getenv("STATBUS_LIVE_DB") == "" {
		t.Skip("set STATBUS_LIVE_DB=1 to exercise the real database")
	}
	projDir := findProjDir(t)
	for _, p := range []string{flagFilePath(projDir), filepath.Join(projDir, "sb.old"), maintenanceFlagHostPath()} {
		if _, err := os.Stat(p); err == nil {
			t.Fatalf("%s exists; refusing to run beside a live upgrade", p)
		}
	}
	shimDir := t.TempDir()
	if err := os.WriteFile(filepath.Join(shimDir, "docker"), []byte("#!/bin/sh\ncase \"$*\" in *pg_isready*) echo 'accepting connections';; *) echo \"shim: $*\";; esac\nexit 0\n"), 0755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", shimDir+string(os.PathListSeparator)+os.Getenv("PATH"))

	d := NewService(projDir, false, "test", "")
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()
	if err := d.LoadConfigAndConnect(ctx); err != nil {
		t.Fatalf("LoadConfigAndConnect: %v", err)
	}
	t.Cleanup(d.Close)

	const sha = "3470000000000000000000000000000000000061"
	var id int
	if err := d.queryConn.QueryRow(ctx, `
		INSERT INTO public.upgrade (commit_sha, committed_at, commit_tags, release_status, summary, state,
		                            scheduled_at, started_at, log_relative_file_path)
		VALUES ($1, now() - interval '2 days', '{}', 'commit', 'live unlink-failure probe', 'in_progress',
		        now() - interval '1 hour', now() - interval '59 minutes', 'live-unlink-probe.log')
		RETURNING id`, sha).Scan(&id); err != nil {
		t.Fatalf("insert: %v", err)
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
		_ = os.Remove(maintenanceFlagHostPath())
		_, _ = d.liftReadOnlyWindow("live test cleanup")
		matches, _ := filepath.Glob(filepath.Join(projDir, "tmp", "upgrade-logs", strconv.Itoa(id)+"-live-probe-*"))
		for _, m := range matches {
			_ = os.RemoveAll(m)
		}
	})

	if err := d.writeUpgradeFlag(id, sha, nil, "live-probe", "test", false); err != nil {
		t.Fatal(err)
	}
	if _, err := d.setDatabaseReadOnly(ctx, true); err != nil {
		t.Fatal(err)
	}
	if err := d.setMaintenance(true, "upgrade probe\n{}\necho probe\n"); err != nil {
		t.Fatal(err)
	}

	// Inject: the marker refuses to unlink (an EROFS/EPERM-class box fault).
	d.removeFile = func(path string) error {
		if path == d.flagPath() {
			return os.ErrPermission
		}
		return os.Remove(path)
	}

	progress := NewUpgradeLog(projDir, int64(id), "live-probe", time.Now().UTC())
	var degraded bool
	captureStdoutUpgrade(t, func() {
		degraded = d.restoreAndFinalize(ctx, id, "live-probe", ErrGitFetchRetryable+": live unlink-failure probe", "", 0, progress)
	})
	progress.Close()
	logBytes, _ := os.ReadFile(progress.AbsPath())
	logText := string(logBytes)
	t.Logf("progress log (attempt 1):\n%s", logText)

	if !degraded {
		t.Fatal("restoreAndFinalize claimed a clean finish although the marker could not be removed")
	}
	if strings.Contains(logText, "Rollback to the previous version complete.") {
		t.Error("the canonical completion line was written despite the unlink failure")
	}
	if !strings.Contains(logText, "finishing did not complete; cleanup will retry without restoring the database again") {
		t.Error("the unlink failure was not narrated as cleanup-only finishing")
	}
	// Half-open by design: SQL and HTTP are reopened (safe: the pending row forbids any restore).
	var state, errText string
	var pendingAt *time.Time
	if err := d.queryConn.QueryRow(ctx, "SELECT state::text, error, rollback_finish_pending_at FROM public.upgrade WHERE id = $1", id).Scan(&state, &errText, &pendingAt); err != nil {
		t.Fatal(err)
	}
	if state != "failed" || pendingAt == nil {
		t.Fatalf("row after unlink failure: state=%s pending=%v error=%q; want failed with rollback_finish_pending_at set", state, pendingAt, errText)
	}
	if strings.Contains(errText, "ROLLBACK_FINISH_PENDING") {
		t.Fatalf("error text still carries the retired prefix: %q", errText)
	}
	if _, err := os.Stat(flagFilePath(projDir)); err != nil {
		t.Fatalf("marker must survive the failed unlink: %v", err)
	}
	if d.flagLock != nil {
		t.Error("flock still held: ./sb install would classify this as a LIVE upgrade instead of crashed recovery")
	}
	if IsFlockHeld(projDir) {
		t.Error("marker flock still held by someone")
	}
	if _, err := os.Stat(maintenanceFlagHostPath()); !os.IsNotExist(err) {
		t.Errorf("maintenance still on: %v", err)
	}

	// Recovery: unlink works again; the real entrypoint finishes cleanup-only.
	d.removeFile = nil
	out := captureStdoutUpgrade(t, func() {
		if err := d.RecoverFromFlag(ctx); err != nil {
			t.Errorf("RecoverFromFlag: %v", err)
		}
	})
	t.Logf("recovery:\n%s", out)
	if !strings.Contains(out, "The snapshot will not be restored again") {
		t.Error("recovery did not take the cleanup-only branch")
	}
	if _, err := os.Stat(flagFilePath(projDir)); !os.IsNotExist(err) {
		t.Errorf("marker still present after recovery: %v", err)
	}
	if err := d.queryConn.QueryRow(ctx, "SELECT state::text, error FROM public.upgrade WHERE id = $1", id).Scan(&state, &errText); err != nil {
		t.Fatal(err)
	}
	if state != "rolled_back" || !strings.Contains(errText, "safe to schedule this same version again") {
		t.Errorf("row after recovery: state=%s error=%q", state, errText)
	}
}

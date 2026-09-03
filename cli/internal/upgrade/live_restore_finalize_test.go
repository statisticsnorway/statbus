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

// TestLiveRestoreAndFinalize_HealthyTail drives the REAL restoreAndFinalize,
// the function that writes ROLLBACK_FINISH_PENDING and then finishes, on the
// real database with a real held marker. Every docker invocation is answered
// by a shim `docker` placed first on PATH (compose stop/up succeed, `compose
// exec db pg_isready` reports healthy), so the box's real containers are never
// touched, while every database and filesystem boundary is the real one:
// the pending row is written by the real terminal writer, SQL read-only is
// lifted by the real teardown-immune flip, the marker is removed by the real
// row-locked finisher, and rolled_back is committed with the retryable
// guidance. backupPath is "" (the PreSwap "nothing moved" shape), so no
// volume rsync is attempted; ./sb.old is absent, so no binary restore.
//
//	STATBUS_LIVE_DB=1 go test -count=1 -run TestLiveRestoreAndFinalize -v ./internal/upgrade
func TestLiveRestoreAndFinalize_HealthyTail(t *testing.T) {
	if os.Getenv("STATBUS_LIVE_DB") == "" {
		t.Skip("set STATBUS_LIVE_DB=1 to exercise the real database")
	}
	projDir := findProjDir(t)
	if _, err := os.Stat(flagFilePath(projDir)); err == nil {
		t.Fatalf("a real upgrade marker exists at %s; refusing to run beside a live upgrade", flagFilePath(projDir))
	}
	if _, err := os.Stat(filepath.Join(projDir, "sb.old")); err == nil {
		t.Fatal("./sb.old exists; restoreBinary would replace ./sb — refusing")
	}
	if _, err := os.Stat(maintenanceFlagHostPath()); err == nil {
		t.Fatalf("a real maintenance flag exists at %s; refusing", maintenanceFlagHostPath())
	}

	// docker shim: first on PATH for this process and its children.
	shimDir := t.TempDir()
	shim := filepath.Join(shimDir, "docker")
	if err := os.WriteFile(shim, []byte(`#!/bin/sh
# live-test docker shim: never touch real containers.
case "$*" in
  *"compose exec db pg_isready"*|*"compose exec"*"pg_isready"*) echo "accepting connections"; exit 0 ;;
  *"compose --profile all up -d --remove-orphans"*) echo "shim: services up"; exit 0 ;;
  *"compose stop"*) echo "shim: stopped"; exit 0 ;;
  *"compose ps"*) echo "[]"; exit 0 ;;
  *) echo "shim: unexpected docker call: $*" >&2; exit 0 ;;
esac
`), 0755); err != nil {
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

	const sha = "3470000000000000000000000000000000000051"
	var id int
	if err := d.queryConn.QueryRow(ctx, `
		INSERT INTO public.upgrade (commit_sha, committed_at, commit_tags, release_status, summary, state,
		                            scheduled_at, started_at, log_relative_file_path)
		VALUES ($1, now() - interval '2 days', '{}', 'commit', 'live restoreAndFinalize probe', 'in_progress',
		        now() - interval '1 hour', now() - interval '59 minutes', 'live-restore-finalize-probe.log')
		RETURNING id`, sha).Scan(&id); err != nil {
		t.Fatalf("insert in_progress row: %v", err)
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
		// The real log + bundle land under tmp/upgrade-logs/<id>-live-probe-*; remove them.
		matches, _ := filepath.Glob(filepath.Join(projDir, "tmp", "upgrade-logs", strconv.Itoa(id)+"-live-probe-*"))
		for _, m := range matches {
			_ = os.RemoveAll(m)
		}
	})

	// The held marker and the engaged window: the state an in-flight upgrade
	// owns when its rollback begins.
	if err := d.writeUpgradeFlag(id, sha, nil, "live-probe", "test", false); err != nil {
		t.Fatal(err)
	}
	if _, err := d.setDatabaseReadOnly(ctx, true); err != nil {
		t.Fatalf("engage window: %v", err)
	}
	if err := d.setMaintenance(true, "upgrade probe\n{}\necho probe\n"); err != nil {
		t.Fatalf("engage maintenance: %v", err)
	}

	progress := NewUpgradeLog(projDir, int64(id), "live-probe", time.Now().UTC())
	reason := ErrGitFetchRetryable + ": live restoreAndFinalize probe"
	var degraded bool
	out := captureStdoutUpgrade(t, func() {
		degraded = d.restoreAndFinalize(ctx, id, "live-probe", reason, "", 0, progress)
	})
	progress.Close()
	logBytes, _ := os.ReadFile(progress.AbsPath())
	logText := string(logBytes)
	t.Logf("progress log:\n%s", logText)
	if degraded {
		t.Fatalf("restoreAndFinalize reported degraded on the healthy tail; stdout:\n%s", out)
	}

	// The narrative, in execution order.
	last := -1
	for _, want := range []string{
		"Checking for this upgrade's database snapshot ... ok (none recorded",
		"Starting services for the previous version ... ok",
		"Waiting for the restored database to become healthy ... healthy",
		"Reconnecting to the restored database ... ok",
		"Unblocking SQL writes ... ok",
		`ran: ALTER DATABASE "`,
		"Lifting maintenance mode ... ok",
		"removed: ~/statbus-maintenance/active",
		"Rollback to the previous version complete.",
	} {
		idx := strings.Index(logText, want)
		if idx < 0 {
			t.Errorf("progress log lacks %q", want)
			continue
		}
		if idx < last {
			t.Errorf("progress log has %q out of order", want)
		}
		last = idx
	}
	if strings.Contains(logText, "ROLLBACK INCOMPLETE") || strings.Contains(logText, "finishing did not complete") {
		t.Errorf("healthy tail narrated a failure:\n%s", logText)
	}

	// The boundaries, observed.
	var state, errText string
	var rolledBackAt *time.Time
	if err := d.queryConn.QueryRow(ctx, "SELECT state::text, error, rolled_back_at FROM public.upgrade WHERE id = $1", id).Scan(&state, &errText, &rolledBackAt); err != nil {
		t.Fatal(err)
	}
	if state != "rolled_back" || rolledBackAt == nil {
		t.Errorf("row: state=%s rolled_back_at=%v; want rolled_back with a timestamp (error=%q)", state, rolledBackAt, errText)
	}
	if strings.HasPrefix(errText, RollbackFinishPendingPrefix) || !strings.Contains(errText, "safe to schedule this same version again") {
		t.Errorf("final guidance wrong: %q", errText)
	}
	if _, err := os.Stat(flagFilePath(projDir)); !os.IsNotExist(err) {
		t.Errorf("marker still on disk: %v", err)
	}
	if d.flagLock != nil {
		t.Error("service still holds the flock after a complete rollback")
	}
	if _, err := os.Stat(maintenanceFlagHostPath()); !os.IsNotExist(err) {
		t.Errorf("maintenance flag still on disk: %v", err)
	}
	var readOnlyOn bool
	if err := d.queryConn.QueryRow(ctx, `SELECT coalesce((SELECT 'default_transaction_read_only=on' = ANY(s.setconfig)
		FROM pg_db_role_setting s JOIN pg_database x ON x.oid = s.setdatabase
		WHERE x.datname = current_database() AND s.setrole = 0), false)`).Scan(&readOnlyOn); err != nil {
		t.Fatal(err)
	}
	if readOnlyOn {
		t.Error("read-only default still ON after the healthy tail")
	}
	// The audit log saw the interim failed row and the final rolled_back row,
	// in that order (STATBUS-154's public.upgrade_state_log).
	var transitions []string
	rows, err := d.queryConn.Query(ctx, "SELECT coalesce(old_state::text,'') || '>' || coalesce(new_state::text,'') FROM public.upgrade_state_log WHERE upgrade_id = $1 ORDER BY id", id)
	if err != nil {
		t.Fatal(err)
	}
	for rows.Next() {
		var s string
		_ = rows.Scan(&s)
		transitions = append(transitions, s)
	}
	rows.Close()
	joined := strings.Join(transitions, " ")
	if !strings.Contains(joined, "in_progress>failed") || !strings.Contains(joined, "failed>rolled_back") ||
		strings.Index(joined, "in_progress>failed") > strings.Index(joined, "failed>rolled_back") {
		t.Errorf("audit log transitions = %v; want in_progress>failed before failed>rolled_back", transitions)
	}
	t.Logf("audit transitions: %v", transitions)
}

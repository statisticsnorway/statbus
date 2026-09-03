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

// TestLiveReattemptRestore_DelayedSecondInstallCannotRestoreAgain reproduces
// SOL review 347 finding 1 with two Service instances. Actor A completes the
// real restore reattempt and a post-A write lands. Actor B then arrives with the
// stale row classification the install detector returned before A ran. Git and Docker
// are PATH-shimmed, while the row, transaction/advisory locks, marker/flock,
// pending transition, and terminal finalizer use the real local database/files.
//
//	STATBUS_LIVE_DB=1 go test -count=1 -run TestLiveReattemptRestore_DelayedSecondInstall -v ./internal/upgrade
func TestLiveReattemptRestore_DelayedSecondInstallCannotRestoreAgain(t *testing.T) {
	if os.Getenv("STATBUS_LIVE_DB") == "" {
		t.Skip("set STATBUS_LIVE_DB=1 to exercise the real database")
	}
	projDir := findProjDir(t)
	for _, path := range []string{flagFilePath(projDir), filepath.Join(projDir, "sb.old"), maintenanceFlagHostPath()} {
		if _, err := os.Stat(path); err == nil {
			t.Fatalf("%s exists; refusing to run beside a live upgrade", path)
		}
	}

	shimDir := t.TempDir()
	dockerLog := filepath.Join(shimDir, "docker.log")
	if err := os.WriteFile(filepath.Join(shimDir, "docker"), []byte(`#!/bin/sh
printf '%s\n' "$*" >> "$STATBUS_TEST_DOCKER_LOG"
case "$*" in
  *"compose exec db pg_isready"*|*"compose exec"*"pg_isready"*) echo "accepting connections"; exit 0 ;;
  *"compose ps"*) echo "[]"; exit 0 ;;
  *) echo "shim: $*"; exit 0 ;;
esac
`), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(shimDir, "git"), []byte(`#!/bin/sh
case "$*" in
  *"rev-parse"*) echo "$STATBUS_TEST_GIT_SHA"; exit 0 ;;
  *) echo "shim git: $*"; exit 0 ;;
esac
`), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", shimDir+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("STATBUS_TEST_DOCKER_LOG", dockerLog)
	t.Setenv("STATBUS_TEST_GIT_SHA", "1111111111111111111111111111111111111111")

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()
	control := NewService(projDir, false, "test", "")
	if err := control.LoadConfigAndConnect(ctx); err != nil {
		t.Fatalf("control LoadConfigAndConnect: %v", err)
	}
	t.Cleanup(control.Close)

	backupPath := t.TempDir()
	const sha = "3470000000000000000000000000000000000081"
	var id int64
	if err := control.queryConn.QueryRow(ctx, `
		INSERT INTO public.upgrade (commit_sha, committed_at, commit_tags, release_status, summary, state,
		                            scheduled_at, started_at, error, backup_path, log_relative_file_path)
		VALUES ($1, now() - interval '2 days', '{}', 'commit', 'live restore reattempt race probe', 'failed',
		        now() - interval '1 hour', now() - interval '59 minutes', $2, $3, 'live-reattempt-race-probe.log')
		RETURNING id`, sha, ErrRollbackDBRestore+": live reattempt race probe", backupPath).Scan(&id); err != nil {
		t.Fatalf("insert failed row: %v", err)
	}
	t.Cleanup(func() {
		cleanupCtx, cleanupCancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cleanupCancel()
		_ = os.Remove(flagFilePath(projDir))
		_ = os.Remove(maintenanceFlagHostPath())
		_, _ = control.liftReadOnlyWindow("live reattempt race cleanup")
		if _, err := control.queryConn.Exec(cleanupCtx, "DELETE FROM public.upgrade_state_log WHERE upgrade_id = $1", id); err != nil {
			t.Errorf("cleanup state log: %v", err)
		}
		if _, err := control.queryConn.Exec(cleanupCtx, "DELETE FROM public.upgrade WHERE id = $1", id); err != nil {
			t.Errorf("cleanup row: %v", err)
		}
		matches, _ := filepath.Glob(filepath.Join(projDir, "tmp", "upgrade-logs", strconv.FormatInt(id, 10)+"-*"))
		for _, match := range matches {
			_ = os.RemoveAll(match)
		}
	})

	actorA := NewService(projDir, false, "test", "")
	if err := actorA.LoadConfigAndConnect(ctx); err != nil {
		t.Fatalf("actor A LoadConfigAndConnect: %v", err)
	}
	if err := actorA.ReattemptRestore(ctx, id); err != nil {
		actorA.Close()
		t.Fatalf("actor A reattempt: %v", err)
	}
	// restoreAndFinalize reconnects and acquires the daemon advisory lock on
	// actor A's session. Closing it models the completed first install process.
	actorA.Close()

	var state string
	if err := control.queryConn.QueryRow(ctx, "SELECT state::text FROM public.upgrade WHERE id = $1", id).Scan(&state); err != nil {
		t.Fatalf("read actor A terminal state: %v", err)
	}
	if state != "rolled_back" {
		t.Fatalf("actor A state = %q, want rolled_back", state)
	}
	if _, err := control.queryConn.Exec(ctx, "UPDATE public.upgrade SET summary = summary || ' / post-A write' WHERE id = $1", id); err != nil {
		t.Fatalf("post-A write was not accepted: %v", err)
	}
	if err := os.WriteFile(dockerLog, nil, 0o644); err != nil {
		t.Fatal(err)
	}

	actorB := NewService(projDir, false, "test", "")
	if err := actorB.LoadConfigAndConnect(ctx); err != nil {
		t.Fatalf("actor B LoadConfigAndConnect: %v", err)
	}
	reattemptErr := actorB.ReattemptRestore(ctx, id)
	actorB.Close()
	if reattemptErr == nil || !strings.Contains(reattemptErr.Error(), "no longer re-attemptable") {
		t.Fatalf("delayed actor B did not refuse stale row authorization: %v", reattemptErr)
	}
	if calls, err := os.ReadFile(dockerLog); err != nil {
		t.Fatal(err)
	} else if strings.TrimSpace(string(calls)) != "" {
		t.Fatalf("delayed actor B touched Docker after actor A reopened writes:\n%s", calls)
	}
	if _, err := os.Stat(flagFilePath(projDir)); !os.IsNotExist(err) {
		t.Fatalf("delayed actor B left or replaced the replay marker: %v", err)
	}
	var summary string
	if err := control.queryConn.QueryRow(ctx, "SELECT summary FROM public.upgrade WHERE id = $1", id).Scan(&summary); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(summary, "post-A write") {
		t.Fatalf("post-A write was lost: %q", summary)
	}
}

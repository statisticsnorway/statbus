package upgrade

import (
	"context"
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"
)

// TestLiveRecoveryRollback_StaleActorCannotRecreateMarker reproduces the
// stale-intent race from SOL review 347 finding 2. Actor B classifies the same
// marker as actor A, then is delayed until A has completed the real healthy
// restore tail, removed the marker, and reopened writes. B runs in a helper
// process because the vulnerable recoveryRollback reaches rollback's exit-75
// process boundary. Docker is PATH-shimmed for both actors. Everything else is
// real: the public.upgrade row, marker/flock, pending transition, cleanup-only
// finalizer, and the delayed actor's recovery entry.
//
//	STATBUS_LIVE_DB=1 go test -count=1 -run TestLiveRecoveryRollback_StaleActor -v ./internal/upgrade
func TestLiveRecoveryRollback_StaleActorCannotRecreateMarker(t *testing.T) {
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
	t.Setenv("PATH", shimDir+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("STATBUS_TEST_DOCKER_LOG", dockerLog)

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()
	d := NewService(projDir, false, "test", "")
	if err := d.LoadConfigAndConnect(ctx); err != nil {
		t.Fatalf("LoadConfigAndConnect: %v", err)
	}
	t.Cleanup(d.Close)

	const sha = "3470000000000000000000000000000000000071"
	var id int
	if err := d.queryConn.QueryRow(ctx, `
		INSERT INTO public.upgrade (commit_sha, committed_at, commit_tags, release_status, summary, state,
		                            scheduled_at, started_at, log_relative_file_path)
		VALUES ($1, now() - interval '2 days', '{}', 'commit', 'live stale recovery actor probe', 'in_progress',
		        now() - interval '1 hour', now() - interval '59 minutes', 'live-stale-recovery-probe.log')
		RETURNING id`, sha).Scan(&id); err != nil {
		t.Fatalf("insert in_progress row: %v", err)
	}
	t.Cleanup(func() {
		cleanupCtx, cleanupCancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cleanupCancel()
		_ = os.Remove(flagFilePath(projDir))
		_ = os.Remove(maintenanceFlagHostPath())
		_, _ = d.liftReadOnlyWindow("live stale recovery cleanup")
		if _, err := d.queryConn.Exec(cleanupCtx, "DELETE FROM public.upgrade_state_log WHERE upgrade_id = $1", id); err != nil {
			t.Errorf("cleanup state log: %v", err)
		}
		if _, err := d.queryConn.Exec(cleanupCtx, "DELETE FROM public.upgrade WHERE id = $1", id); err != nil {
			t.Errorf("cleanup row: %v", err)
		}
		matches, _ := filepath.Glob(filepath.Join(projDir, "tmp", "upgrade-logs", strconv.Itoa(id)+"-live-probe-*"))
		for _, match := range matches {
			_ = os.RemoveAll(match)
		}
	})

	if err := d.writeUpgradeFlag(id, sha, nil, "live-probe", "test", false); err != nil {
		t.Fatalf("actor A write flag: %v", err)
	}
	staleFlag, err := ReadFlagFile(projDir)
	if err != nil || staleFlag == nil {
		t.Fatalf("actor B classify flag: flag=%v err=%v", staleFlag, err)
	}
	if _, err := d.setDatabaseReadOnly(ctx, true); err != nil {
		t.Fatalf("engage read-only window: %v", err)
	}
	if err := d.setMaintenance(true, "upgrade probe\n{}\necho probe\n"); err != nil {
		t.Fatalf("engage maintenance: %v", err)
	}

	progress := NewUpgradeLog(projDir, int64(id), "live-probe", time.Now().UTC())
	degraded := d.restoreAndFinalize(ctx, id, "live-probe", ErrGitFetchRetryable+": actor A", "", 0, progress)
	progress.Close()
	if degraded {
		t.Fatal("actor A did not finish the healthy restore tail")
	}
	if _, err := os.Stat(flagFilePath(projDir)); !os.IsNotExist(err) {
		t.Fatalf("actor A did not remove the marker: %v", err)
	}

	// Writes are open after A. B must derive authorization again from durable
	// state after taking the mutex, not recreate the marker from stale memory.
	var state string
	if err := d.queryConn.QueryRow(ctx, "SELECT state::text FROM public.upgrade WHERE id = $1", id).Scan(&state); err != nil {
		t.Fatalf("read actor A terminal state: %v", err)
	}
	if state != "rolled_back" {
		t.Fatalf("actor A state = %q, want rolled_back", state)
	}
	if _, err := d.queryConn.Exec(ctx, "UPDATE public.upgrade SET summary = summary || ' / post-A write' WHERE id = $1", id); err != nil {
		t.Fatalf("post-A write was not accepted: %v", err)
	}

	staleJSON, err := json.Marshal(staleFlag)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(dockerLog, nil, 0o644); err != nil {
		t.Fatal(err)
	}
	cmd := exec.CommandContext(ctx, os.Args[0], "-test.run=^TestLiveRecoveryRollback_StaleActorHelper$")
	cmd.Env = append(os.Environ(),
		"STATBUS_STALE_RECOVERY_HELPER=1",
		"STATBUS_LIVE_TWIN_LOCK_HELD=1",
		"STATBUS_STALE_RECOVERY_FLAG="+string(staleJSON),
		"STATBUS_STALE_RECOVERY_LOG=live-stale-recovery-probe.log",
	)
	output, runErr := cmd.CombinedOutput()
	t.Logf("delayed actor B output:\n%s", output)
	if runErr != nil {
		t.Fatalf("delayed actor B entered rollback instead of refusing stale intent: %v\n%s", runErr, output)
	}
	if !strings.Contains(string(output), "someone already finished this recovery") {
		t.Fatalf("delayed actor B did not report the durable-state refusal:\n%s", output)
	}
	if calls, err := os.ReadFile(dockerLog); err != nil {
		t.Fatal(err)
	} else if strings.TrimSpace(string(calls)) != "" {
		t.Fatalf("delayed actor B touched Docker after actor A reopened writes:\n%s", calls)
	}
	if _, err := os.Stat(flagFilePath(projDir)); !os.IsNotExist(err) {
		t.Fatalf("delayed actor B recreated the removed marker: %v", err)
	}
}

// TestLiveRecoveryRollback_StaleActorHelper is the delayed actor subprocess for
// TestLiveRecoveryRollback_StaleActorCannotRecreateMarker. It is intentionally
// a separate process because vulnerable code terminates at rollback's exit-75
// boundary. A fixed recoveryRollback returns after its loud stale-state refusal.
func TestLiveRecoveryRollback_StaleActorHelper(t *testing.T) {
	if os.Getenv("STATBUS_STALE_RECOVERY_HELPER") != "1" {
		t.Skip("helper process only")
	}
	var staleFlag UpgradeFlag
	if err := json.Unmarshal([]byte(os.Getenv("STATBUS_STALE_RECOVERY_FLAG")), &staleFlag); err != nil {
		t.Fatalf("decode stale flag: %v", err)
	}
	projDir := findProjDir(t)
	ctx, cancel := context.WithTimeout(context.Background(), 4*time.Minute)
	defer cancel()
	d := NewService(projDir, false, "test", "")
	defer d.Close()
	if err := d.LoadConfigAndConnect(ctx); err != nil {
		t.Fatalf("LoadConfigAndConnect: %v", err)
	}
	d.recoveryRollback(ctx, staleFlag, staleFlag.Label(), os.Getenv("STATBUS_STALE_RECOVERY_LOG"), "delayed stale recovery actor")
}

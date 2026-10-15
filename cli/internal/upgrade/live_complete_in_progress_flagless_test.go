//go:build livedb

package upgrade

import (
	"context"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// TestUpgradeFlaglessBehindRowRollsBack covers the
// markerless reconciliation path used after a corrupt upgrade flag is removed.
// The in_progress row still authorizes recovery, but the observed binary is
// positively behind its target. The reconciler must create a fresh O_EXCL
// marker claim, re-read the same row while holding its flock, and run the normal
// rollback tail. rollback exits 75, so the destructive half runs in a helper
// process. Docker is PATH-shimmed; the public.upgrade row and connections are
// real.
//
// go test -tags livedb -count=1 ./internal/upgrade ./internal/install
func TestUpgradeFlaglessBehindRowRollsBack(t *testing.T) {
	runFlaglessBehindRollback(t, false)
}

// TestUpgradeFlaglessBehindRowServingFailureKeepsDatabaseUp is STATBUS-507: the
// rc.02 fleet shape. A rollback with NO snapshot (nothing was restored) whose
// serving-tier start fails must still leave the database running, so the
// outcome is recorded and the box is not left dark. On the unfixed code the
// rollback stops the database up front and only the serving-tier start brings
// it back, so this failure left it down (rc.02: "DB not ready: service db is
// not running", then ROLLBACK_TERMINAL_WRITE_FAILED).
func TestUpgradeFlaglessBehindRowServingFailureKeepsDatabaseUp(t *testing.T) {
	runFlaglessBehindRollback(t, true)
}

func runFlaglessBehindRollback(t *testing.T, servingFails bool) {
	realProjDir := findProjDir(t)
	for _, path := range []string{flagFilePath(realProjDir), filepath.Join(realProjDir, "sb.old"), maintenanceFlagHostPath()} {
		if _, err := os.Stat(path); err == nil {
			t.Fatalf("%s exists; refusing to run beside a live upgrade", path)
		}
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()
	control := NewService(realProjDir, false, "test", "")
	if err := control.LoadConfigAndConnect(ctx); err != nil {
		t.Fatalf("LoadConfigAndConnect: %v", err)
	}
	t.Cleanup(control.Close)

	var existing int
	if err := control.queryConn.QueryRow(ctx, "SELECT count(*) FROM public.upgrade WHERE state = 'in_progress'").Scan(&existing); err != nil {
		t.Fatalf("count existing in_progress rows: %v", err)
	}
	if existing != 0 {
		t.Fatalf("found %d existing in_progress upgrade row(s); refusing to disturb an active recovery", existing)
	}

	git := newGitRepoFixture(t)
	// reconnect and terminalConnDo deliberately reload the generated connection
	// settings after the simulated service stop. Keep those settings real while
	// the repository, marker, and progress-log paths remain isolated.
	if err := os.Symlink(filepath.Join(realProjDir, ".env"), filepath.Join(git.dir, ".env")); err != nil {
		t.Fatalf("link generated database settings into isolated repo: %v", err)
	}
	shimDir := t.TempDir()
	dockerLog := filepath.Join(shimDir, "docker.log")
	if err := os.WriteFile(filepath.Join(shimDir, "docker"), []byte(`#!/bin/sh
printf '%s\n' "$*" >> "$STATBUS_TEST_DOCKER_LOG"
case "$*" in
  *"compose exec db pg_isready"*|*"compose exec"*"pg_isready"*) echo "accepting connections"; exit 0 ;;
  # The db's route (the Caddy proxy) exists on every real box; the rollback's
  # database start looks it up before starting the existing containers.
  *"compose ps -a -q proxy"*) echo "statbus-test-proxy-id"; exit 0 ;;
  *"compose ps -a --format json"*) echo '[{"ID":"statbus-test-proxy-id","Service":"proxy","State":"running","Image":"statbus-proxy"}]'; exit 0 ;;
  *"compose ps"*) echo "[]"; exit 0 ;;
  *) echo "shim: $*"; exit 0 ;;
esac
`), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", shimDir+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("STATBUS_TEST_DOCKER_LOG", dockerLog)

	var id int
	if err := control.queryConn.QueryRow(ctx, `
		INSERT INTO public.upgrade (commit_sha, committed_at, commit_tags, release_status, summary, state,
		                            scheduled_at, started_at, log_relative_file_path)
		VALUES ($1, now() - interval '2 days', '{}', 'commit', 'live flagless Behind recovery probe', 'in_progress',
		        now() - interval '1 hour', now() - interval '59 minutes', 'live-flagless-behind-probe.log')
		RETURNING id`, git.newSHA).Scan(&id); err != nil {
		t.Fatalf("insert in_progress row: %v", err)
	}
	t.Cleanup(func() {
		cleanupCtx, cleanupCancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cleanupCancel()
		if _, err := control.queryConn.Exec(cleanupCtx, "DELETE FROM public.upgrade_state_log WHERE upgrade_id = $1", id); err != nil {
			t.Errorf("cleanup state log: %v", err)
		}
		if _, err := control.queryConn.Exec(cleanupCtx, "DELETE FROM public.upgrade WHERE id = $1", id); err != nil {
			t.Errorf("cleanup row: %v", err)
		}
	})

	cmd := exec.CommandContext(ctx, os.Args[0], "-test.run=^TestUpgradeFlaglessBehindRow_Helper$")
	cmd.Env = append(os.Environ(),
		"STATBUS_FLAGLESS_BEHIND_HELPER=1",
		"STATBUS_LIVE_TWIN_LOCK_HELD=1",
		"STATBUS_FLAGLESS_BEHIND_PROJ_DIR="+git.dir,
		"STATBUS_FLAGLESS_BEHIND_BINARY_COMMIT="+git.oldSHA,
	)
	if servingFails {
		cmd.Env = append(cmd.Env, "STATBUS_FLAGLESS_BEHIND_SERVING_FAILS=1")
	}
	output, runErr := cmd.CombinedOutput()
	t.Logf("flagless Behind helper output:\n%s", output)

	var state string
	if err := control.queryConn.QueryRow(ctx, "SELECT state::text FROM public.upgrade WHERE id = $1", id).Scan(&state); err != nil {
		t.Fatalf("read recovery outcome: %v", err)
	}
	dockerCalls, _ := os.ReadFile(dockerLog)
	t.Logf("docker calls:\n%s", dockerCalls)
	if servingFails {
		// The database is the box's own record. With no snapshot nothing was
		// restored, so it must never be left stopped: either rollback did not
		// stop it, or it started it again independently of the serving tier.
		stoppedDB, startedDB := false, false
		for _, call := range strings.Split(string(dockerCalls), "\n") {
			fields := strings.Fields(call)
			if len(fields) < 2 || fields[0] != "compose" {
				continue
			}
			hasDB := false
			for _, f := range fields[2:] {
				if f == "db" {
					hasDB = true
				}
			}
			switch {
			case fields[1] == "stop" && hasDB:
				stoppedDB, startedDB = true, false
			case (fields[1] == "start" || fields[1] == "up") && hasDB:
				startedDB = true
			}
		}
		if stoppedDB && !startedDB {
			t.Fatalf("STATBUS-507: the rollback stopped the database and never started it again after the serving tier failed; docker calls:\n%s", dockerCalls)
		}
		if state != "failed" {
			t.Fatalf("STATBUS-507: a failed serving-tier start must record the degraded outcome (state=failed), got state=%s; output:\n%s", state, output)
		}
		return
	}
	var exitErr *exec.ExitError
	exit75 := errors.As(runErr, &exitErr) && exitErr.ExitCode() == 75
	if !exit75 || state != "rolled_back" {
		exitDescription := "0"
		if runErr != nil {
			exitDescription = runErr.Error()
		}
		t.Fatalf("flagless Behind recovery exit=%s state=%s, want exit 75 and rolled_back; output:\n%s",
			exitDescription, state, output)
	}
	if !strings.Contains(string(output), "Rollback to the previous version complete.") {
		t.Fatalf("flagless Behind recovery omitted the completed rollback narrative:\n%s", output)
	}
	if _, err := os.Stat(flagFilePath(git.dir)); !os.IsNotExist(err) {
		t.Fatalf("fresh recovery marker survived terminal rollback: %v", err)
	}
}

// TestUpgradeFlaglessBehindRow_Helper executes the rollback
// process boundary for TestUpgradeFlaglessBehindRowRollsBack.
func TestUpgradeFlaglessBehindRow_Helper(t *testing.T) {
	if os.Getenv("STATBUS_FLAGLESS_BEHIND_HELPER") != "1" {
		t.Skip("helper process only")
	}
	realProjDir := findProjDir(t)
	ctx, cancel := context.WithTimeout(context.Background(), 4*time.Minute)
	defer cancel()
	d := NewService(realProjDir, false, "test", os.Getenv("STATBUS_FLAGLESS_BEHIND_BINARY_COMMIT"))
	defer d.Close()
	if err := d.LoadConfigAndConnect(ctx); err != nil {
		t.Fatalf("LoadConfigAndConnect: %v", err)
	}
	// Keep the real database configuration and connection, but isolate every
	// filesystem, git, progress-log, and flock effect in the synthetic repo.
	d.projDir = os.Getenv("STATBUS_FLAGLESS_BEHIND_PROJ_DIR")
	d.startSourceApplicationStackForTest = func(context.Context, *ProgressLog) error { return nil }
	if os.Getenv("STATBUS_FLAGLESS_BEHIND_SERVING_FAILS") == "1" {
		d.startSourceApplicationStackForTest = func(context.Context, *ProgressLog) error {
			return errors.New("serving tier refused to start (STATBUS-507 fixture)")
		}
	}
	if err := d.completeInProgressUpgrade(ctx); err != nil {
		t.Fatalf("completeInProgressUpgrade: %v", err)
	}
}

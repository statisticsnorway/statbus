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

// TestLiveAbortFailedPreBackupStop drives the REAL abortFailedPreBackupStop
// (the unwind executeUpgrade takes when `docker compose stop` fails BEFORE any
// snapshot) on the real database, twice, with docker answered by a PATH shim:
//
//  1. Every cleanup boundary succeeds (restart ok, maintenance off, reconnect,
//     read-only off): the row must be `failed` (no backup_path), the marker
//     must be GONE, and the box must be writable.
//  2. The service restart FAILS (shim exit 1 on `compose up`): the row is still
//     `failed`, but the marker must SURVIVE with its flock released, so the
//     next `./sb install` classifies crashed recovery and reconciles instead of
//     scheduling over an unconfirmed box.
//
// Both leave the read-only default OFF and remove their rows and files.
//
//	STATBUS_LIVE_DB=1 go test -count=1 -run TestLiveAbortFailedPreBackupStop -v ./internal/upgrade
func TestLiveAbortFailedPreBackupStop(t *testing.T) {
	if os.Getenv("STATBUS_LIVE_DB") == "" {
		t.Skip("set STATBUS_LIVE_DB=1 to exercise the real database")
	}
	projDir := findProjDir(t)
	for _, p := range []string{flagFilePath(projDir), maintenanceFlagHostPath()} {
		if _, err := os.Stat(p); err == nil {
			t.Fatalf("%s exists; refusing to run beside a live upgrade", p)
		}
	}

	run := func(t *testing.T, restartExit int, sha string) (state string, backupPath *string, markerPresent, flockHeld, readOnlyOn bool, logText string) {
		shimDir := t.TempDir()
		shim := "#!/bin/sh\ncase \"$*\" in *pg_isready*) echo 'accepting connections'; exit 0;; *\"compose up -d\"*) echo \"shim: compose up\"; exit " + strconv.Itoa(restartExit) + ";; *) echo \"shim: $*\"; exit 0;; esac\n"
		if err := os.WriteFile(filepath.Join(shimDir, "docker"), []byte(shim), 0755); err != nil {
			t.Fatal(err)
		}
		t.Setenv("PATH", shimDir+string(os.PathListSeparator)+os.Getenv("PATH"))

		d := NewService(projDir, false, "test", "")
		ctx, cancel := context.WithTimeout(context.Background(), 3*time.Minute)
		defer cancel()
		if err := d.LoadConfigAndConnect(ctx); err != nil {
			t.Fatalf("LoadConfigAndConnect: %v", err)
		}
		t.Cleanup(d.Close)

		var id int
		if err := d.queryConn.QueryRow(ctx, `
			INSERT INTO public.upgrade (commit_sha, committed_at, commit_tags, release_status, summary, state,
			                            scheduled_at, started_at, log_relative_file_path)
			VALUES ($1, now() - interval '2 days', '{}', 'commit', 'live pre-backup abort probe', 'in_progress',
			        now() - interval '1 hour', now() - interval '59 minutes', 'live-prebackup-probe.log')
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

		// The state executeUpgrade owns at Step 3: marker held, window on, maintenance on.
		if err := d.writeUpgradeFlag(id, sha, nil, "live-probe", "test", false); err != nil {
			t.Fatal(err)
		}
		if _, err := d.setDatabaseReadOnly(ctx, true); err != nil {
			t.Fatal(err)
		}
		if err := d.setMaintenance(true, "upgrade probe\n{}\necho probe\n"); err != nil {
			t.Fatal(err)
		}
		// executeUpgrade has NOT yet closed its connections at this step; the unwind reconnects regardless.

		progress := NewUpgradeLog(projDir, int64(id), "live-probe", time.Now().UTC())
		captureStdoutUpgrade(t, func() {
			d.abortFailedPreBackupStop(ctx, id, "application-stop", "could not stop application services before backup: shim", []string{"app", "worker", "rest"}, progress)
		})
		progress.Close()
		b, _ := os.ReadFile(progress.AbsPath())
		logText = string(b)

		if err := d.queryConn.QueryRow(ctx, "SELECT state::text, backup_path FROM public.upgrade WHERE id = $1", id).Scan(&state, &backupPath); err != nil {
			t.Fatal(err)
		}
		_, statErr := os.Stat(flagFilePath(projDir))
		markerPresent = statErr == nil
		flockHeld = IsFlockHeld(projDir)
		if err := d.queryConn.QueryRow(ctx, `SELECT coalesce((SELECT 'default_transaction_read_only=on' = ANY(s.setconfig)
			FROM pg_db_role_setting s JOIN pg_database x ON x.oid = s.setdatabase
			WHERE x.datname = current_database() AND s.setrole = 0), false)`).Scan(&readOnlyOn); err != nil {
			t.Fatal(err)
		}
		if _, err := os.Stat(maintenanceFlagHostPath()); err == nil {
			t.Error("maintenance flag still present after the unwind")
		}
		return
	}

	t.Run("every boundary confirmed → marker removed", func(t *testing.T) {
		state, backupPath, marker, held, ro, log := run(t, 0, "3470000000000000000000000000000000000071")
		t.Logf("log:\n%s", log)
		if state != "failed" || backupPath != nil {
			t.Errorf("row: state=%s backup_path=%v; want failed with NULL backup_path (nothing moved)", state, backupPath)
		}
		if marker {
			t.Error("marker still on disk although every cleanup boundary was confirmed")
		}
		if ro {
			t.Error("read-only default still ON")
		}
		for _, want := range []string{
			"Restarting services after the application-stop failure ... ok",
			"Lifting maintenance mode after the application-stop failure ... ok",
			"Reconnecting after the application-stop failure ... ok",
			"Unblocking SQL writes after the application-stop failure ... ok",
			`ran: ALTER DATABASE "`,
			"FAILED: could not stop application services before backup",
		} {
			if !strings.Contains(log, want) {
				t.Errorf("log lacks %q", want)
			}
		}
		_ = held
	})

	t.Run("restart unconfirmed → marker kept, flock released", func(t *testing.T) {
		state, backupPath, marker, held, ro, log := run(t, 1, "3470000000000000000000000000000000000072")
		t.Logf("log:\n%s", log)
		if state != "failed" || backupPath != nil {
			t.Errorf("row: state=%s backup_path=%v; want failed with NULL backup_path", state, backupPath)
		}
		if !marker {
			t.Error("marker was removed although the service restart was not confirmed")
		}
		if held {
			t.Error("flock still held: ./sb install would see a LIVE upgrade instead of crashed recovery")
		}
		if ro {
			t.Error("read-only default still ON (the unwind must lift it even when restart failed)")
		}
		for _, want := range []string{
			"Restarting services after the application-stop failure ... failed",
			"Unblocking SQL writes after the application-stop failure ... ok",
			"Preserving the recovery marker after releasing its live lock",
			"services also did not restart cleanly",
		} {
			if !strings.Contains(log, want) {
				t.Errorf("log lacks %q", want)
			}
		}
	})
}

//go:build livedb

package upgrade

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
)

// Exercise all production completion writers against the disposable livedb
// clone. Docker, the migration subprocess and serving HTTP are fixtures. Closing
// the cached connection at the successful health probe models step 11 replacing
// the proxy through which that connection was established on a real upgrade.
func TestCompletionFinishesLedgerAfterCachedConnectionCloses(t *testing.T) {
	for _, writer := range []string{"flagless", "normal", "self-heal"} {
		t.Run(writer, func(t *testing.T) { completionWriterFinishesLedger(t, writer, false) })
	}
}

func TestCompletionWritersSurfaceFinishingFailure(t *testing.T) {
	for _, writer := range []string{"flagless", "normal", "self-heal"} {
		t.Run(writer, func(t *testing.T) { completionWriterFinishesLedger(t, writer, true) })
	}
}

func completionWriterFinishesLedger(t *testing.T, writer string, failFinishing bool) {
	t.Helper()
	root := findProjDir(t)
	ctx, cancel := context.WithTimeout(context.Background(), 90*time.Second)
	defer cancel()
	control := NewService(root, false, "test", "")
	if err := control.connect(ctx); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(control.Close)
	var db string
	if err := control.queryConn.QueryRow(ctx, "SELECT current_database()").Scan(&db); err != nil {
		t.Fatal(err)
	}
	if !is452KissAttemptDatabase(db) {
		t.Fatalf("refuse non-owned database %q", db)
	}

	git := newGitRepoFixture(t)
	if err := os.Symlink(filepath.Join(root, ".env"), filepath.Join(git.dir, ".env")); err != nil {
		t.Fatal(err)
	}
	d := NewService(git.dir, false, "test", git.newSHA)
	if err := d.loadConfig(); err != nil {
		t.Fatal(err)
	}
	if err := d.connect(ctx); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(d.Close)
	if err := d.acquireAdvisoryLock(ctx); err != nil {
		t.Fatal(err)
	}
	shim := t.TempDir()
	statuses := "[]"
	if writer == "self-heal" {
		statuses = `[{"ID":"db","Service":"db","State":"running"},{"ID":"app","Service":"app","State":"running"},{"ID":"worker","Service":"worker","State":"running"},{"ID":"proxy","Service":"proxy","State":"running"},{"ID":"rest","Service":"rest","State":"running"}]`
	}
	docker := fmt.Sprintf("#!/bin/sh\ncase \"$*\" in *'compose ps'*) echo '%s';; *'inspect --format {{.Config.Image}}'*) echo fixture:%s;; *) echo accepting;; esac\n", statuses, git.newSHA[:8])
	if err := os.WriteFile(filepath.Join(shim, "docker"), []byte(docker), 0700); err != nil {
		t.Fatal(err)
	}
	// These commands cannot change the database or infrastructure. The test
	// exercises the real completed UPDATE and every finishing SQL statement.
	if err := os.WriteFile(filepath.Join(git.dir, "sb"), []byte("#!/bin/sh\ncase \"$*\" in 'migrate up --verbose') echo STATBUS_MIGRATE_PENDING_COUNT=0;; esac\nexit 0\n"), 0700); err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{".env.config", ".env.credentials"} {
		if err := os.WriteFile(filepath.Join(git.dir, name), nil, 0600); err != nil {
			t.Fatal(err)
		}
	}
	t.Setenv("PATH", shim+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("HOME", t.TempDir())

	var ids []int
	t.Cleanup(func() {
		for _, id := range ids {
			if _, err := control.queryConn.Exec(context.Background(), "DELETE FROM public.upgrade_state_log WHERE upgrade_id=$1", id); err != nil {
				t.Error(err)
			}
			if _, err := control.queryConn.Exec(context.Background(), "DELETE FROM public.upgrade WHERE id=$1", id); err != nil {
				t.Error(err)
			}
		}
	})
	insert := func(sha, version, status, state, age string) int {
		t.Helper()
		var id int
		err := control.queryConn.QueryRow(ctx, `INSERT INTO public.upgrade
   (commit_sha,commit_version,commit_tags,release_status,summary,state,committed_at,scheduled_at,started_at,completed_at,backup_path,log_relative_file_path,skipped_at)
   VALUES($1,$2,ARRAY[$2]::text[],$3::public.release_status_type,'579 completion fixture',$4::public.upgrade_state,
   now()-$5::interval,CASE WHEN $4 IN ('in_progress','completed') THEN now()-interval '1 hour' END,CASE WHEN $4 IN ('in_progress','completed') THEN now()-interval '59 minutes' END,
   CASE WHEN $4='completed' THEN now()-interval '58 minutes' END,
   CASE WHEN $4='in_progress' THEN '/nonexistent/579-owned-snapshot' END,'579-'||$1||'.log',CASE WHEN $4='skipped' THEN now() END) RETURNING id`, sha, version, status, state, age).Scan(&id)
		if err != nil {
			t.Fatal(err)
		}
		ids = append(ids, id)
		return id
	}
	old := insert("5790000000000000000000000000000000000001", "v2099.11.2-rc.02", "prerelease", "completed", "2 days")
	available := insert("5790000000000000000000000000000000000002", "v2099.11.1", "release", "available", "3 days")
	retained := insert("5790000000000000000000000000000000000003", "v2099.12.1", "release", "available", "1 hour")
	current := insert(git.newSHA, "v2099.11.2-rc.03", "prerelease", "in_progress", "1 day")
	// Keep superseded prereleases as evidence in this fixture so both the
	// supersession and retention rules have distinct, observable outcomes.
	var priorPurge bool
	if err := control.queryConn.QueryRow(ctx, `SELECT install_purge FROM public.upgrade_retention_caps WHERE release_status='prerelease' AND state='superseded'`).Scan(&priorPurge); err != nil {
		t.Fatal(err)
	}
	if _, err := control.queryConn.Exec(ctx, `UPDATE public.upgrade_retention_caps SET install_purge=false WHERE release_status='prerelease' AND state='superseded'`); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		_, err := control.queryConn.Exec(context.Background(), `UPDATE public.upgrade_retention_caps SET install_purge=$1 WHERE release_status='prerelease' AND state='superseded'`, priorPurge)
		if err != nil {
			t.Error(err)
		}
	})
	// A same-family uninstalled rc is purged by the installed-row retention pass.
	purged := insert("5790000000000000000000000000000000000004", "v2099.11.2-rc.01", "prerelease", "skipped", "4 days")
	if _, err := control.queryConn.Exec(ctx, `INSERT INTO public.system_info(key,value) VALUES
 ('install_last_error','579 stale failure'),('install_last_error_at','579 old timestamp'),('install_last_bundle_path','579 old bundle')
 ON CONFLICT(key) DO UPDATE SET value=EXCLUDED.value`); err != nil {
		t.Fatal(err)
	}
	if failFinishing {
		if _, err := control.queryConn.Exec(ctx, `CREATE FUNCTION public.statbus_579_writer_failure() RETURNS trigger LANGUAGE plpgsql AS $fixture$
		BEGIN IF NEW.key='install_last_error' AND NEW.value='' THEN RAISE EXCEPTION '579 writer finishing refused' USING ERRCODE='23514'; END IF; RETURN NEW; END; $fixture$;
		CREATE TRIGGER statbus_579_writer_failure BEFORE UPDATE ON public.system_info FOR EACH ROW EXECUTE FUNCTION public.statbus_579_writer_failure()`); err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() {
			if _, err := control.queryConn.Exec(context.Background(), `DROP TRIGGER statbus_579_writer_failure ON public.system_info; DROP FUNCTION public.statbus_579_writer_failure()`); err != nil {
				t.Error(err)
			}
		})
	}

	var once sync.Once
	t.Cleanup(func() {
		if _, err := control.liftReadOnlyWindow("579 isolated fixture cleanup"); err != nil {
			t.Error(err)
		}
	})
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		once.Do(func() {
			if _, err := d.setDatabaseReadOnly(ctx, true); err != nil {
				t.Error(err)
			}
			if err := d.queryConn.Close(context.Background()); err != nil {
				t.Error(err)
			}
		})
		w.WriteHeader(http.StatusOK)
	}))
	defer server.Close()
	d.cachedURL = server.URL + "/rpc/auth_status"
	d.cachedReadyURL = server.URL + "/ready"
	var observer *pgx.Conn
	// Subscribe after the completed UPDATE's trigger fired. Only the explicit
	// completion belt can satisfy this observer, not the terminal row trigger.
	d.liftReadOnlyWindowForTest = func(string) (string, error) {
		statement, err := control.liftReadOnlyWindow("579 completion fixture")
		if err != nil {
			return "", err
		}
		// Isolate the explicit belt from subsequent supersession/retention
		// triggers too. Only this package's disposable clone is changed.
		if _, err := control.queryConn.Exec(ctx, `ALTER TABLE public.upgrade DISABLE TRIGGER upgrade_notify_frontend_trigger`); err != nil {
			return "", err
		}
		t.Cleanup(func() {
			if _, err := control.queryConn.Exec(context.Background(), `ALTER TABLE public.upgrade ENABLE TRIGGER upgrade_notify_frontend_trigger`); err != nil {
				t.Error(err)
			}
		})
		dsn, err := d.recoveryDSN()
		if err != nil {
			return "", err
		}
		observer, err = pgx.Connect(ctx, dsn)
		if err != nil {
			return "", err
		}
		_, err = observer.Exec(ctx, "LISTEN worker_status")
		return statement, err
	}
	defer func() {
		if observer != nil {
			_ = observer.Close(context.Background())
		}
	}()
	var completionErr error
	if writer == "flagless" {
		completionErr = d.completeInProgressUpgrade(ctx)
	} else {
		if err := d.writeUpgradeFlag(current, git.newSHA, []string{"v2099.11.2-rc.03"}, "579 fixture", "test", false); err != nil {
			t.Fatal(err)
		}
		if err := d.mutateHeldFlag(func(flag *UpgradeFlag) { flag.Phase = PhaseNewSbSwapped }); err != nil {
			t.Fatal(err)
		}
		flag, err := ReadFlagFile(git.dir)
		if err != nil || flag == nil {
			t.Fatalf("read held upgrade flag: %v", err)
		}
		if writer == "self-heal" {
			completionErr = d.resumeNewSb(ctx, *flag)
		} else {
			progress := NewUpgradeLog(git.dir, int64(current), flag.Label(), time.Now().UTC())
			defer progress.Close()
			completionErr = d.applyNewSbUpgrading(ctx, current, git.newSHA, flag.Label(), git.oldSHA, "/nonexistent/579-owned-snapshot", false, progress)
		}
	}
	if failFinishing {
		var pgerr *pgconn.PgError
		if !errors.As(completionErr, &pgerr) || pgerr.Code != "23514" {
			t.Errorf("completion error=%v, want real SQLSTATE 23514 finishing failure", completionErr)
		}
		var state, banner string
		if err := control.queryConn.QueryRow(ctx, "SELECT state::text FROM public.upgrade WHERE id=$1", current).Scan(&state); err != nil {
			t.Fatal(err)
		}
		if err := control.queryConn.QueryRow(ctx, "SELECT value FROM public.system_info WHERE key='install_last_error'").Scan(&banner); err != nil {
			t.Fatal(err)
		}
		if state != "completed" || banner != "579 stale failure" {
			t.Errorf("finishing failure state=%s banner=%q, want completed and original diagnostic", state, banner)
		}
		t.Logf("%s reported real finishing failure and preserved completed truth: %v", writer, completionErr)
		return
	}
	if completionErr != nil {
		t.Errorf("completion finishing: %v", completionErr)
	}
	for id, want := range map[int]string{current: "completed", old: "superseded", available: "superseded", retained: "available"} {
		var state string
		if err := control.queryConn.QueryRow(ctx, "SELECT state::text FROM public.upgrade WHERE id=$1", id).Scan(&state); err != nil {
			t.Error(err)
			continue
		}
		if state != want {
			t.Errorf("row %d state=%s, want %s", id, state, want)
		}
	}
	var count int
	if err := control.queryConn.QueryRow(ctx, "SELECT count(*) FROM public.upgrade WHERE id=$1", purged).Scan(&count); err != nil {
		t.Fatal(err)
	}
	if count != 0 {
		t.Errorf("retention kept same-family skipped prerelease %d, want purged", purged)
	}
	for _, key := range []string{"install_last_error", "install_last_error_at", "install_last_bundle_path"} {
		var value string
		if err := control.queryConn.QueryRow(ctx, "SELECT value FROM public.system_info WHERE key=$1", key).Scan(&value); err != nil {
			t.Error(err)
			continue
		}
		if value != "" {
			t.Errorf("%s=%q, want cleared", key, value)
		}
	}
	if observer == nil {
		t.Fatal("completion did not reach window-lift boundary")
	}
	if _, err := observer.Exec(ctx, "CREATE TEMP TABLE completion_external_write (id integer)"); err != nil {
		t.Errorf("fresh external session cannot write after completion: %v", err)
	}
	nctx, ncancel := context.WithTimeout(ctx, time.Second)
	defer ncancel()
	notification, err := observer.WaitForNotification(nctx)
	if err != nil {
		t.Errorf("explicit completion notification: %v", err)
	} else if notification.Channel != "worker_status" || notification.Payload != `{"type":"upgrade_changed"}` {
		t.Errorf("notification=%+v", notification)
	}
	var held bool
	if err := control.queryConn.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM pg_locks WHERE locktype='advisory' AND objid=hashtext('upgrade_daemon')::oid AND pid=$1 AND granted)`, d.queryConn.PgConn().PID()).Scan(&held); err != nil {
		t.Fatal(err)
	}
	if !held {
		t.Error("completion did not restore daemon advisory-lock authority")
	}
	t.Logf("fixture=%s current=%d old=%d available=%d retained=%d purged=%d", db, current, old, available, retained, purged)
	fmt.Printf("579 completion ledger checked in %s\n", db)
}

//go:build livedb

package upgrade

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
)

// Exercise the production flagless completion writer against the disposable
// livedb clone. Only Docker and the serving HTTP endpoint are fixtures. Closing
// the cached connection at the successful health probe models step 11 replacing
// the proxy through which that connection was established on a real upgrade.
func TestCompletionFinishesLedgerAfterCachedConnectionCloses(t *testing.T) {
	root := findProjDir(t)
	ctx, cancel := context.WithTimeout(context.Background(), 90*time.Second)
	defer cancel()
	control := NewService(root, false, "test", "")
	if err := control.LoadConfigAndConnect(ctx); err != nil {
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
	if err := d.LoadConfigAndConnect(ctx); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(d.Close)
	if err := d.acquireAdvisoryLock(ctx); err != nil {
		t.Fatal(err)
	}
	shim := t.TempDir()
	if err := os.WriteFile(filepath.Join(shim, "docker"), []byte("#!/bin/sh\ncase \"$*\" in *'compose ps'*) echo '[]';; *) echo accepting;; esac\n"), 0700); err != nil {
		t.Fatal(err)
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
	if _, err := control.queryConn.Exec(ctx, `UPDATE public.upgrade_retention_caps SET install_purge=false WHERE release_status='prerelease' AND state='superseded'`); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		_, err := control.queryConn.Exec(context.Background(), `UPDATE public.upgrade_retention_caps SET install_purge=true WHERE release_status='prerelease' AND state='superseded'`)
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

	var once sync.Once
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		once.Do(func() {
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
		dsn, err := d.recoveryDSN()
		if err != nil {
			return "", err
		}
		observer, err = pgx.Connect(ctx, dsn)
		if err != nil {
			return "", err
		}
		_, err = observer.Exec(ctx, "LISTEN worker_status")
		return "fixture database already writable", err
	}
	defer func() {
		if observer != nil {
			_ = observer.Close(context.Background())
		}
	}()
	if err := d.completeInProgressUpgrade(ctx, true); err != nil {
		t.Errorf("completion finishing: %v", err)
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

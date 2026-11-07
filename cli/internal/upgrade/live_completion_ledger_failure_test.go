//go:build livedb

package upgrade

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgconn"
)

// The completed row is senior truth even when finishing must yield or SQL
// refuses cleanup. These tests use the real reconnect/advisory-lock protocol
// and actual PostgreSQL failures, not mocked SQL return values.
func TestCompletionLedgerFailurePreservesCompletedTruth(t *testing.T) {
	for _, fault := range []string{"another-upgrader", "banner-sql", "retention-sql"} {
		t.Run(fault, func(t *testing.T) {
			ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
			defer cancel()
			root := findProjDir(t)
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
			d := NewService(root, false, "test", "")
			if err := d.connect(ctx); err != nil {
				t.Fatal(err)
			}
			t.Cleanup(d.Close)
			if err := d.acquireAdvisoryLock(ctx); err != nil {
				t.Fatal(err)
			}
			const sha = "5790000000000000000000000000000000000091"
			var id int
			if err := control.queryConn.QueryRow(ctx, `INSERT INTO public.upgrade(commit_sha,committed_at,summary,state,completed_at,log_relative_file_path)
    VALUES($1,now(),'579 finishing failure fixture','completed',now(),'579-failure.log') RETURNING id`, sha).Scan(&id); err != nil {
				t.Fatal(err)
			}
			t.Cleanup(func() {
				if _, err := control.queryConn.Exec(context.Background(), "DELETE FROM public.upgrade_state_log WHERE upgrade_id=$1", id); err != nil {
					t.Error(err)
				}
				if _, err := control.queryConn.Exec(context.Background(), "DELETE FROM public.upgrade WHERE id=$1", id); err != nil {
					t.Error(err)
				}
			})
			if _, err := control.queryConn.Exec(ctx, `INSERT INTO public.system_info(key,value) VALUES('install_last_error','579 keep until finishing') ON CONFLICT(key) DO UPDATE SET value=EXCLUDED.value`); err != nil {
				t.Fatal(err)
			}
			switch fault {
			case "another-upgrader":
				if err := d.queryConn.Close(ctx); err != nil {
					t.Fatal(err)
				}
				if err := control.acquireAdvisoryLock(ctx); err != nil {
					t.Fatal(err)
				}
			case "banner-sql":
				if _, err := control.queryConn.Exec(ctx, `CREATE FUNCTION public.statbus_579_banner_failure() RETURNS trigger LANGUAGE plpgsql AS $fixture$
     BEGIN IF NEW.key='install_last_error' AND NEW.value='' THEN RAISE EXCEPTION '579 banner cleanup refused' USING ERRCODE='23514'; END IF; RETURN NEW; END; $fixture$;
     CREATE TRIGGER statbus_579_banner_failure BEFORE UPDATE ON public.system_info FOR EACH ROW EXECUTE FUNCTION public.statbus_579_banner_failure()`); err != nil {
					t.Fatal(err)
				}
				t.Cleanup(func() {
					if _, err := control.queryConn.Exec(context.Background(), `DROP TRIGGER statbus_579_banner_failure ON public.system_info; DROP FUNCTION public.statbus_579_banner_failure()`); err != nil {
						t.Error(err)
					}
				})
			case "retention-sql":
				// Renaming the real planner is a reversible schema fixture. The production
				// retention caller must return its real 42883 rather than logging success.
				if _, err := control.queryConn.Exec(ctx, `ALTER FUNCTION public.upgrade_retention_plan(text,integer) RENAME TO statbus_579_retention_plan`); err != nil {
					t.Fatal(err)
				}
				t.Cleanup(func() {
					if _, err := control.queryConn.Exec(context.Background(), `ALTER FUNCTION public.statbus_579_retention_plan(text,integer) RENAME TO upgrade_retention_plan`); err != nil {
						t.Error(err)
					}
				})
			}
			start := time.Now()
			err := d.finishCompletionLedger(id, sha)
			if err == nil {
				t.Fatal("finishing returned success despite a real authority/SQL failure")
			}
			if time.Since(start) > 5*time.Second {
				t.Errorf("deterministic failure retried instead of returning immediately: %s", time.Since(start))
			}
			if fault == "another-upgrader" {
				if !strings.Contains(err.Error(), "another upgrader") {
					t.Errorf("finishing error=%v", err)
				}
				var owns bool
				if err := control.queryConn.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM pg_locks WHERE locktype='advisory' AND objid=hashtext('upgrade_daemon')::oid AND pid=pg_backend_pid() AND granted)`).Scan(&owns); err != nil {
					t.Fatal(err)
				}
				if !owns || !d.queryConn.IsClosed() {
					t.Errorf("authority: other upgrader owns=%t unauthorized session closed=%t", owns, d.queryConn.IsClosed())
				}
			} else {
				var pgerr *pgconn.PgError
				code := "23514"
				if fault == "retention-sql" {
					code = "42883"
				}
				if !errors.As(err, &pgerr) || pgerr.Code != code {
					t.Errorf("finishing error=%v, want SQLSTATE %s", err, code)
				}
			}
			var state string
			if err := control.queryConn.QueryRow(ctx, "SELECT state::text FROM public.upgrade WHERE id=$1", id).Scan(&state); err != nil {
				t.Fatal(err)
			}
			if state != "completed" {
				t.Errorf("finishing rewrote senior truth to %s", state)
			}
			var banner string
			if err := control.queryConn.QueryRow(ctx, "SELECT value FROM public.system_info WHERE key='install_last_error'").Scan(&banner); err != nil {
				t.Fatal(err)
			}
			wantBanner := "579 keep until finishing"
			if fault == "retention-sql" {
				wantBanner = ""
			}
			if banner != wantBanner {
				t.Errorf("banner=%q, want %q", banner, wantBanner)
			}
			t.Logf("%s: completed truth preserved, finishing error surfaced: %v", fault, err)
		})
	}
}

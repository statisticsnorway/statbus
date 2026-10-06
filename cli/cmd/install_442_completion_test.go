//go:build livedb

package cmd

import (
	"context"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/jackc/pgx/v5"
	"github.com/statisticsnorway/statbus/cli/internal/dotenv"
	"github.com/statisticsnorway/statbus/cli/internal/install"
	"github.com/statisticsnorway/statbus/cli/internal/livedbtest"
	"github.com/statisticsnorway/statbus/cli/internal/testgit"
	"strconv"
)

// Real runInstall success/failure defer and SQL completion. Only detection and
// the step table are fixtures, as in the reviewed STATBUS-452 actual-route tests.
func Test442PinnedInstallCompletion(t *testing.T) {
	ctx := context.Background()
	root := livedbtest.ProjectDir()
	dsn := os.Getenv("STATBUS_442_DSN")
	var conn *pgx.Conn
	var err error
	if dsn != "" {
		if root == "" {
			root, err = filepath.Abs("../..")
			if err != nil {
				t.Fatal(err)
			}
		}
		conn, err = pgx.Connect(ctx, dsn)
	} else if root != "" {
		conn, err = connectInstallDB(root)
	} else {
		t.Skip("owned livedb fixture or explicit STATBUS_442_DSN required")
	}
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = conn.Close(ctx) })
	var database string
	if err := conn.QueryRow(ctx, "SELECT current_database()").Scan(&database); err != nil {
		t.Fatal(err)
	}
	if dsn != "" && database != "statbus_442_overnight_1006" || dsn == "" && !strings.HasPrefix(database, "statbus_livedb_") {
		t.Fatalf("refuse non-owned database %q", database)
	}
	for _, mode := range []string{"legacy-call", "legacy-schedule-operator", "operator-retired", "no-event", "cross-sha-event", "stale-event", "failed-install", "normal-candidate"} {
		t.Run(mode, func(t *testing.T) {
			dir := withRunInstallDetectionHooks(t)
			version = "v2026.10.0-rc.12"
			if err := os.Remove(filepath.Join(dir, ".git")); err != nil {
				t.Fatal(err)
			}
			git := func(args ...string) string {
				t.Helper()
				cmd := exec.Command("git", testgit.Args(args...)...)
				cmd.Dir, cmd.Env = dir, testgit.Env()
				out, err := cmd.CombinedOutput()
				if err != nil {
					t.Fatalf("git %v: %v %s", args, err, out)
				}
				return strings.TrimSpace(string(out))
			}
			git("init", "-q", "-b", "main")
			git("config", "commit.gpgsign", "false")
			git("commit", "--allow-empty", "-qm", "442 stable "+mode)
			stable := git("rev-parse", "HEAD")
			git("commit", "--allow-empty", "-qm", "442 exact installed candidate "+mode)
			sha := git("rev-parse", "HEAD")
			cross := git("rev-parse", "HEAD^{tree}")
			env, err := dotenv.Load(filepath.Join(root, ".env"))
			if err != nil {
				t.Fatal(err)
			}
			env.Set("POSTGRES_APP_DB", database)
			if dsn != "" {
				cfg, err := pgx.ParseConfig(dsn)
				if err != nil {
					t.Fatal(err)
				}
				env.Set("CADDY_DB_BIND_ADDRESS", cfg.Host)
				env.Set("CADDY_DB_PORT", strconv.Itoa(int(cfg.Port)))
				env.Set("POSTGRES_ADMIN_USER", cfg.User)
				env.Set("POSTGRES_ADMIN_PASSWORD", cfg.Password)
			}
			env.Set("UPGRADE_CALLBACK", "")
			if err := os.WriteFile(filepath.Join(dir, ".env"), []byte(env.String()), 0600); err != nil {
				t.Fatal(err)
			}
			t.Cleanup(func() {
				for _, q := range []string{
					"DELETE FROM public.upgrade_state_log WHERE upgrade_id IN (SELECT id FROM public.upgrade WHERE commit_sha=ANY($1::text[]))",
					"DELETE FROM public.upgrade WHERE commit_sha=ANY($1::text[])",
				} {
					if _, err := conn.Exec(ctx, q, []string{sha, stable, cross}); err != nil {
						t.Error(err)
					}
				}
			})
			tx, err := conn.Begin(ctx)
			if err != nil {
				t.Fatal(err)
			}
			defer func() { _ = tx.Rollback(ctx) }()
			execSQL := func(q string, args ...any) {
				t.Helper()
				if _, err := tx.Exec(ctx, q, args...); err != nil {
					t.Fatal(err)
				}
			}
			execSQL(`INSERT INTO public.upgrade(commit_sha,committed_at,commit_tags,commit_version,summary,release_status,state)
 VALUES($1,'2026-10-02','{v2026.10.0-rc.12}','v2026.10.0-rc.12','442 candidate','prerelease','available'),
 ($2,'2026-09-25','{v2026.09.3}','v2026.09.3','442 stable','release','available')`, sha, stable)
			if mode == "no-event" || mode == "cross-sha-event" {
				execSQL("DELETE FROM public.upgrade WHERE commit_sha=$1", sha)
				execSQL(`INSERT INTO public.upgrade(commit_sha,committed_at,commit_tags,summary,state,superseded_at) VALUES($1,'2026-10-02','{}','442 terminal without own ranking event','superseded',now())`, sha)
			}
			if mode == "cross-sha-event" {
				execSQL(`INSERT INTO public.upgrade(commit_sha,committed_at,commit_tags,commit_version,summary,release_status,state) VALUES($1,'2026-10-01','{v2026.10.0-rc.11}','v2026.10.0-rc.11','442 unrelated ranking witness','prerelease','available')`, cross)
			}
			if mode != "normal-candidate" && mode != "no-event" && mode != "operator-retired" {
				for _, direction := range []string{"down", "up"} {
					source, err := os.ReadFile(filepath.Join(root, "migrations", "20261001163000_statbus_435_version_first_upgrade_supersession."+direction+".sql"))
					if err != nil {
						t.Fatal(err)
					}
					definition := strings.TrimPrefix(strings.TrimSpace(string(source)), "BEGIN;")
					definition = strings.TrimSuffix(strings.TrimSpace(definition), "END;")
					execSQL(definition)
					if direction == "down" {
						if mode == "legacy-schedule-operator" {
							execSQL("SELECT set_config('statbus.actor','442 scheduling operator',true)")
							execSQL(`SELECT schedule_result, upgrade_id, landed_state, superseded_count FROM public.upgrade_schedule($1, false)`, stable)
							// No pending execution remains in this completion fixture.
							execSQL("UPDATE public.upgrade SET state='superseded',superseded_at=now() WHERE commit_sha=$1", stable)
						} else {
							execSQL("CALL public.upgrade_supersede_older($1, 0)", stable)
						}
					}
				}
			}
			if mode == "operator-retired" || mode == "stale-event" {
				if mode == "stale-event" {
					execSQL("UPDATE public.upgrade SET state='available',superseded_at=NULL WHERE commit_sha=$1", sha)
				}
				execSQL("SELECT set_config('statbus.actor','442 retiring operator',true)")
				execSQL("UPDATE public.upgrade SET state='superseded',superseded_at=now() WHERE commit_sha=$1", sha)
			}
			if err := tx.Commit(ctx); err != nil {
				t.Fatal(err)
			}
			restoreGeneratedSettings = func(string) error { return nil }
			detectInstallState = func(string, string) (install.State, *install.Detail, error) {
				return install.StateNothingScheduled, &install.Detail{}, nil
			}
			failure := errors.New("442 actual install step failure")
			runInstallStepTableTestHook = func() error {
				if mode == "failed-install" {
					return failure
				}
				return nil
			}
			err = runInstall()
			if mode == "failed-install" {
				if !errors.Is(err, failure) {
					t.Fatalf("actual install failure lost: %v", err)
				}
			} else if err != nil {
				t.Fatal(err)
			}
			want := "superseded"
			if mode == "legacy-call" || mode == "legacy-schedule-operator" || mode == "normal-candidate" {
				want = "completed"
			}
			var state string
			if err := conn.QueryRow(ctx, "SELECT state::text FROM public.upgrade WHERE commit_sha=$1", sha).Scan(&state); err != nil {
				t.Fatal(err)
			}
			if state != want {
				t.Fatalf("actual runInstall %s SHA=%s state=%s want=%s", mode, sha, state, want)
			}
			if want == "superseded" {
				guardTx, err := conn.Begin(ctx)
				if err != nil {
					t.Fatal(err)
				}
				_, guardErr := guardTx.Exec(ctx, `UPDATE public.upgrade SET state='completed',completed_at=now(),log_relative_file_path='442-refused.log' WHERE commit_sha=$1`, sha)
				_ = guardTx.Rollback(ctx)
				if guardErr == nil || !strings.Contains(guardErr.Error(), "terminal rows are not resurrectable") {
					t.Fatalf("actual terminal guard did not refuse: %v", guardErr)
				}
			}
			if strings.HasPrefix(mode, "legacy-") {
				var events int
				if err := conn.QueryRow(ctx, `SELECT count(*) FROM public.upgrade_state_log WHERE upgrade_id=(SELECT id FROM public.upgrade WHERE commit_sha=$1) AND new_state IN ('scheduled','completed') AND actor LIKE 'successful pinned ./sb install:%' AND actor_source='self-reported'`, sha).Scan(&events); err != nil {
					t.Fatal(err)
				}
				if events != 2 {
					t.Fatalf("missing attributable rearm/completion events: %d", events)
				}
				matches, err := filepath.Glob(filepath.Join(dir, "tmp", "install-logs", "*.log"))
				if err != nil || len(matches) != 1 {
					t.Fatalf("install log: %v %v", matches, err)
				}
				contents, err := os.ReadFile(matches[0])
				if err != nil || !strings.Contains(string(contents), "retirement_event=") {
					t.Fatalf("synchronous install attribution missing: %v", err)
				}
			}
			// This is the canary gate's exact lifecycle predicate, not artifact proof.
			var canary bool
			if err := conn.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM public.upgrade WHERE commit_sha=$1 AND state='completed')`, sha).Scan(&canary); err != nil {
				t.Fatal(err)
			}
			if canary != (want == "completed") {
				t.Fatalf("canary predicate mismatch: %t", canary)
			}
			t.Logf("owned DB=%s actual runInstall %s exact SHA state=%s canary=%t", database, mode, state, canary)
		})
	}
}

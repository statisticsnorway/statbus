//go:build livedb

package cmd

import (
	"bytes"
	"context"
	"database/sql"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/statisticsnorway/statbus/cli/internal/dotenv"
	"github.com/statisticsnorway/statbus/cli/internal/install"
	"github.com/statisticsnorway/statbus/cli/internal/livedbtest"
	"github.com/statisticsnorway/statbus/cli/internal/testgit"
	"github.com/statisticsnorway/statbus/cli/internal/upgrade"
)

// Retained chronology is fixture data, but event capture, constraints, ancestry
// and the normal runInstall success hook are real. No global truncation.
func Test452KissHistoricalRepairNormalInstall(t *testing.T) {
	root := livedbtest.ProjectDir()
	conn, err := connectInstallDB(root)
	if err != nil {
		t.Fatal(err)
	}
	ctx := context.Background()
	defer conn.Close(ctx)
	var database string
	if err := conn.QueryRow(ctx, "SELECT current_database()").Scan(&database); err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(database, "statbus_452kiss_ab_") {
		t.Fatalf("refuse non-owned database %q", database)
	}
	for _, mode := range []string{"demo-null-claim", "direct-older", "rescheduled-older", "missing-event", "changed-operation", "parked-event", "stale-cas", "older-target", "parked-row"} {
		t.Run(mode, func(t *testing.T) {
			dir := withRunInstallDetectionHooks(t)
			version = "v2026.10.0-rc.17"
			if err := os.Remove(filepath.Join(dir, ".git")); err != nil {
				t.Fatal(err)
			}
			git := func(args ...string) string {
				t.Helper()
				cmd := exec.Command("git", testgit.Args(args...)...)
				cmd.Dir = dir
				cmd.Env = testgit.Env()
				out, e := cmd.CombinedOutput()
				if e != nil {
					t.Fatalf("git %v: %v %s", args, e, out)
				}
				return strings.TrimSpace(string(out))
			}
			git("init", "-q", "-b", "main")
			git("config", "commit.gpgsign", "false")
			git("commit", "--allow-empty", "-qm", "452 old "+mode)
			old := git("rev-parse", "HEAD")
			git("commit", "--allow-empty", "-qm", "452 witness "+mode)
			witness := git("rev-parse", "HEAD")
			git("commit", "--allow-empty", "-qm", "452 installed "+mode)
			installed := git("rev-parse", "HEAD")
			env, e := dotenv.Load(filepath.Join(root, ".env"))
			if e != nil {
				t.Fatal(e)
			}
			env.Set("UPGRADE_CALLBACK", "")
			if e = os.WriteFile(filepath.Join(dir, ".env"), []byte(env.String()), 0600); e != nil {
				t.Fatal(e)
			}
			restoreGeneratedSettings = func(string) error { return nil }
			detectInstallState = func(string, string) (install.State, *install.Detail, error) {
				return install.StateNothingScheduled, &install.Detail{}, nil
			}
			runInstallStepTableTestHook = func() error { return nil }
			var id int
			if e = conn.QueryRow(ctx, `INSERT INTO public.upgrade(commit_sha,committed_at,commit_tags,summary,release_status,state,scheduled_at) VALUES($1,now(),'{}','452 historical old','release','scheduled','2026-10-06 08:30:29+00') RETURNING id`, old).Scan(&id); e != nil {
				t.Fatal(e)
			}
			t.Cleanup(func() {
				for _, sha := range []string{old, witness, installed} {
					_, e := conn.Exec(ctx, "DELETE FROM public.upgrade_state_log WHERE upgrade_id IN (SELECT id FROM public.upgrade WHERE commit_sha=$1)", sha)
					if e != nil {
						t.Error(e)
					}
					_, e = conn.Exec(ctx, "DELETE FROM public.upgrade WHERE commit_sha=$1", sha)
					if e != nil {
						t.Error(e)
					}
				}
			})
			exec := func(q string, args ...any) {
				t.Helper()
				if _, e := conn.Exec(ctx, q, args...); e != nil {
					t.Fatal(e)
				}
			}
			exec("SET application_name='statbus-upgrade-daemon-3288378'")
			exec("UPDATE public.upgrade SET state='in_progress',started_at='2026-10-06 08:30:29.480251+00',log_relative_file_path='452-original.log',backup_path='452-original-snapshot' WHERE id=$1", id)
			exec("UPDATE public.upgrade_state_log SET logged_at='2026-10-06 08:30:29.486358+00' WHERE upgrade_id=$1", id)
			exec(`INSERT INTO public.upgrade(commit_sha,committed_at,commit_tags,summary,state,release_status,started_at,completed_at,log_relative_file_path) VALUES($1,now(),'{}','452 independent install','completed','prerelease','2026-10-06 08:30:49.257126+00','2026-10-06 08:30:49.257127+00','452-witness.log')`, witness)
			exec("SET application_name='statbus-upgrade-daemon-3639343'")
			if mode == "direct-older" {
				// The released direct installer preserves start and nullable claim identity.
				exec(`INSERT INTO public.upgrade(commit_sha,committed_at,commit_tags,summary,state,started_at,completed_at,log_relative_file_path) VALUES($1,now(),'{}','452 deliberate older install','completed',now(),now(),'452-direct.log') ON CONFLICT(commit_sha) DO UPDATE SET state='completed',completed_at=clock_timestamp(),started_at=COALESCE(upgrade.started_at,clock_timestamp()),log_relative_file_path=EXCLUDED.log_relative_file_path`, old)
			} else {
				exec("UPDATE public.upgrade SET state = 'completed', completed_at = now(), docker_images_status = 'ready', failure_code = NULL, error = NULL, log_relative_file_path = COALESCE(log_relative_file_path, $2) WHERE id = $1 RETURNING to_jsonb(upgrade.*)", id, "452-unused.log")
			}
			exec("UPDATE public.upgrade SET completed_at='2026-10-06 08:30:57.125890+00' WHERE id=$1", id)
			exec("UPDATE public.upgrade_state_log SET logged_at='2026-10-06 08:30:57.136881+00' WHERE upgrade_id=$1 AND new_state='completed'", id)
			if mode == "rescheduled-older" {
				exec("SELECT * FROM public.upgrade_schedule($1,false)", old)
				exec("UPDATE public.upgrade SET state='in_progress',started_at=now(),claim_token=gen_random_uuid(),log_relative_file_path='452-later-attempt.log' WHERE id=$1 AND state='scheduled'", id)
				exec("UPDATE public.upgrade SET state = 'completed', completed_at = now(), docker_images_status = 'ready', failure_code = NULL, error = NULL, log_relative_file_path = COALESCE(log_relative_file_path, $2) WHERE id = $1 RETURNING to_jsonb(upgrade.*)", id, "452-unused.log")
			}
			if mode == "missing-event" {
				exec("DELETE FROM public.upgrade_state_log WHERE upgrade_id=$1 AND new_state='completed'", id)
			}
			if mode == "changed-operation" {
				exec("UPDATE public.upgrade_state_log SET query='UPDATE public.upgrade SET state=completed /* unproven */' WHERE upgrade_id=$1 AND new_state='completed'", id)
			}
			if mode == "parked-event" {
				exec("UPDATE public.upgrade_state_log SET old_parked_at='2026-10-06 08:30:40+00' WHERE upgrade_id=$1 AND new_state='completed'", id)
			}
			if mode == "parked-row" {
				exec("UPDATE public.upgrade SET state='in_progress',completed_at=NULL,recovery_parked_at=now(),recovery_parked_reason='disk' WHERE id=$1", id)
			}
			if mode == "older-target" {
				git("checkout", "-q", old)
			}
			if mode == "stale-cas" {
				for _, mutation := range []string{"claim_token=gen_random_uuid()", "backup_path='changed-snapshot'", "completed_at=completed_at+interval '1 second'"} {
					tx, err := conn.Begin(ctx)
					if err != nil {
						t.Fatal(err)
					}
					candidates, err := readOvertakenCompletions(ctx, tx)
					if err != nil {
						t.Fatal(err)
					}
					var selected *overtakenCompletion
					for i := range candidates {
						if candidates[i].id == id {
							selected = &candidates[i]
						}
					}
					if selected == nil {
						t.Fatal("missing positive candidate")
					}
					if changed, err := repairOvertakenCompletion(ctx, tx, *selected, io.Discard); err != nil || changed {
						t.Fatalf("unavailable log gave correction authority: %v %v", changed, err)
					}
					if _, err := tx.Exec(ctx, "UPDATE public.upgrade SET "+mutation+" WHERE id=$1", id); err != nil {
						t.Fatal(err)
					}
					var audit bytes.Buffer
					changed, err := repairOvertakenCompletion(ctx, tx, *selected, &audit)
					if err != nil || changed || audit.Len() != 0 {
						t.Fatalf("stale authority mutation %s: changed=%v err=%v audit=%s", mutation, changed, err, audit.String())
					}
					if err := tx.Rollback(ctx); err != nil {
						t.Fatal(err)
					}
				}
			}
			exec("SET application_name='statbus-cli'")
			if mode == "demo-null-claim" || mode == "stale-cas" {
				// Exercise the actual same-second normal-install log producer.
				time.Sleep(time.Until(time.Now().Truncate(time.Second).Add(time.Second)))
			}
			if err := runInstall(); err != nil {
				t.Fatal(err)
			}
			var state, path string
			var backup sql.NullString
			var completed *string
			if e = conn.QueryRow(ctx, "SELECT state::text,completed_at::text,backup_path,log_relative_file_path FROM public.upgrade WHERE id=$1", id).Scan(&state, &completed, &backup, &path); e != nil {
				t.Fatal(e)
			}
			want := "completed"
			if mode == "parked-row" {
				want = "in_progress"
				if completed != nil {
					t.Error("parked timestamp changed")
				}
			} else if mode == "demo-null-claim" || mode == "stale-cas" {
				want = "superseded"
				if completed != nil {
					t.Errorf("false timestamp not retracted: %s", *completed)
				}
			} else if completed == nil {
				t.Error("legitimate/unproven completion timestamp removed")
			}
			if state != want {
				t.Errorf("%s state=%s want=%s", mode, state, want)
			}
			if mode != "rescheduled-older" && (!backup.Valid || backup.String != "452-original-snapshot") {
				t.Errorf("snapshot evidence changed: %+v", backup)
			}
			if mode == "demo-null-claim" && path != "452-original.log" {
				t.Errorf("log pointer changed: %s", path)
			}
			if mode == "demo-null-claim" || mode == "stale-cas" {
				var currentLog string
				if err := conn.QueryRow(ctx, "SELECT value FROM public.system_info WHERE key='install_last_log_relative_file_path'").Scan(&currentLog); err != nil {
					t.Fatal(err)
				}
				audit, err := os.ReadFile(upgrade.InstallLogAbsPath(dir, currentLog))
				if err != nil {
					t.Fatal(err)
				}
				if !strings.Contains(string(audit), "retract completed_at=2026-10-06T08:30:57.12589Z") || !strings.Contains(string(audit), "witness=") || !strings.Contains(string(audit), witness) || !strings.Contains(string(audit), "completion_event=") {
					t.Fatalf("missing pre-disposition attribution in installer log: %s", audit)
				}
				var eventsBefore, eventsAfter int
				if e = conn.QueryRow(ctx, "SELECT count(*) FROM public.upgrade_state_log WHERE upgrade_id=$1", id).Scan(&eventsBefore); e != nil {
					t.Fatal(e)
				}
				if err := runInstall(); err != nil {
					t.Fatal(err)
				}
				retained, err := os.ReadFile(upgrade.InstallLogAbsPath(dir, currentLog))
				if err != nil || !bytes.Equal(retained, audit) {
					t.Fatalf("normal retry changed original attribution log %s: err=%v", currentLog, err)
				}
				if e = conn.QueryRow(ctx, "SELECT count(*) FROM public.upgrade_state_log WHERE upgrade_id=$1", id).Scan(&eventsAfter); e != nil {
					t.Fatal(e)
				}
				if eventsAfter != eventsBefore {
					t.Errorf("second success mutated repaired history %d->%d", eventsBefore, eventsAfter)
				}
			}
			t.Logf("owned DB=%s normal success historical %s state=%s", database, mode, state)
		})
	}
}

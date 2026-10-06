//go:build livedb

package upgrade

import (
	"context"
	"fmt"
	"github.com/statisticsnorway/statbus/cli/internal/dotenv"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// Exercise the production recovery entry, real PostgreSQL and Git. Docker and
// HTTP are local serving fixtures. The callback writes a file, never a network.
func Test452KissFlaglessAttempt(t *testing.T) {
	for _, mode := range []string{"overtaken", "exact-crash", "descendant-crash", "held-handoff", "mutex-busy", "late-claim", "unknown-binary", "park-resource"} {
		t.Run(mode, func(t *testing.T) {
			t.Setenv("HOME", t.TempDir())
			ctx := context.Background()
			root := findProjDir(t)
			git := newGitRepoFixture(t)
			d := NewService(root, false, "test", git.newSHA)
			if mode == "unknown-binary" {
				d.binaryCommit = "unknown"
			}
			if err := d.LoadConfigAndConnect(ctx); err != nil {
				t.Fatal(err)
			}
			t.Cleanup(d.Close)
			var db string
			if err := d.queryConn.QueryRow(ctx, "SELECT current_database()").Scan(&db); err != nil {
				t.Fatal(err)
			}
			if !is452KissAttemptDatabase(db) {
				t.Fatalf("refuse non-owned DB %q", db)
			}
			t.Logf("owned database=%s mode=%s", db, mode)
			d.projDir = git.dir
			env, err := dotenv.Load(filepath.Join(root, ".env"))
			if err != nil {
				t.Fatal(err)
			}
			callback := filepath.Join(t.TempDir(), "callback.log")
			script := filepath.Join(t.TempDir(), "callback.sh")
			if err := os.WriteFile(script, []byte("#!/bin/sh\nprintf '%s\\n' \"$STATBUS_EVENT\" >> '"+callback+"'\n"), 0700); err != nil {
				t.Fatal(err)
			}
			env.Set("UPGRADE_CALLBACK", script)
			if err := os.WriteFile(filepath.Join(git.dir, ".env"), []byte(env.String()), 0600); err != nil {
				t.Fatal(err)
			}
			var id int
			changed := false
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				if mode == "late-claim" && !changed {
					changed = true
					_, err := d.queryConn.Exec(ctx, "UPDATE public.upgrade SET claim_token=gen_random_uuid() WHERE id=$1", id)
					if err != nil {
						t.Error(err)
					}
				}
				w.WriteHeader(http.StatusOK)
			}))
			defer server.Close()
			d.cachedURL = server.URL + "/rpc/auth_status"
			d.cachedReadyURL = server.URL + "/ready"
			shim := t.TempDir()
			if err := os.WriteFile(filepath.Join(shim, "docker"), []byte("#!/bin/sh\ncase \"$*\" in *'compose ps'*) echo '[]';; *'compose up'*) if [ \"$STATBUS_452_DOCKER_MODE\" = park-resource ]; then echo 'no space left on device' >&2; exit 1; fi; echo accepting;; *) echo accepting;; esac\n"), 0700); err != nil {
				t.Fatal(err)
			}
			t.Setenv("STATBUS_452_DOCKER_MODE", mode)
			t.Setenv("PATH", shim+string(os.PathListSeparator)+os.Getenv("PATH"))
			target := git.oldSHA
			if mode == "exact-crash" {
				target = git.newSHA
			}
			if err := d.queryConn.QueryRow(ctx, `INSERT INTO public.upgrade(commit_sha,committed_at,commit_tags,summary,state,scheduled_at,started_at,log_relative_file_path) VALUES($1,now()-interval '2 days','{}','452 owned route','in_progress',now()-interval '1 hour',now()-interval '59 minutes','452-owned.log') RETURNING id`, target).Scan(&id); err != nil {
				t.Fatal(err)
			}
			ids := []int{id}
			t.Cleanup(func() {
				for _, n := range ids {
					_, err := d.queryConn.Exec(context.Background(), "DELETE FROM public.upgrade_state_log WHERE upgrade_id=$1", n)
					if err != nil {
						t.Error(err)
					}
					_, err = d.queryConn.Exec(context.Background(), "DELETE FROM public.upgrade WHERE id=$1", n)
					if err != nil {
						t.Error(err)
					}
				}
			})
			if mode == "overtaken" {
				var witness int
				if err := d.queryConn.QueryRow(ctx, `INSERT INTO public.upgrade(commit_sha,committed_at,commit_tags,summary,state,started_at,completed_at,log_relative_file_path) VALUES($1,now()-interval '1 day','{}','452 independent install','completed',now()-interval '30 minutes',now()-interval '29 minutes','452-new.log') RETURNING id`, git.newSHA).Scan(&witness); err != nil {
					t.Fatal(err)
				}
				ids = append(ids, witness)
			}
			if _, err := d.queryConn.Exec(ctx, `INSERT INTO public.system_info(key,value) VALUES('install_last_error','452 later failure') ON CONFLICT(key) DO UPDATE SET value=EXCLUDED.value`); err != nil {
				t.Fatal(err)
			}
			d.liftReadOnlyWindowForTest = func(string) (string, error) { return "owned fixture writable", nil }
			if mode == "held-handoff" || mode == "mutex-busy" {
				lock, err := AcquireInstallFlag(git.dir, "452 route fixture")
				if err != nil {
					t.Fatal(err)
				}
				t.Cleanup(func() { ReleaseInstallFlag(lock) })
				if mode == "held-handoff" {
					d.AdoptFlagLock(lock)
				}
			}
			if err := d.completeInProgressUpgrade(ctx); err != nil {
				t.Fatal(err)
			}
			var state, failure string
			if err := d.queryConn.QueryRow(ctx, "SELECT state::text FROM public.upgrade WHERE id=$1", id).Scan(&state); err != nil {
				t.Fatal(err)
			}
			if err := d.queryConn.QueryRow(ctx, "SELECT value FROM public.system_info WHERE key='install_last_error'").Scan(&failure); err != nil {
				t.Fatal(err)
			}
			out, readErr := os.ReadFile(callback)
			want := "completed"
			if mode == "overtaken" {
				want = "superseded"
				if !os.IsNotExist(readErr) {
					t.Errorf("overtaken callback=%q err=%v", out, readErr)
				}
				if failure != "452 later failure" {
					t.Errorf("later failure erased=%q", failure)
				}
			} else if mode == "mutex-busy" || mode == "late-claim" || mode == "unknown-binary" || mode == "park-resource" {
				want = "in_progress"
				if mode == "park-resource" {
					if readErr != nil || string(out) != "parked\n" {
						t.Errorf("park callback=%q err=%v", out, readErr)
					}
				} else if !os.IsNotExist(readErr) {
					t.Errorf("revoked attempt callback=%q err=%v", out, readErr)
				}
				if failure != "452 later failure" {
					t.Errorf("revoked attempt erased later failure: %q", failure)
				}
			} else if readErr != nil || !strings.Contains(string(out), "completed") {
				t.Errorf("genuine crash callback=%q err=%v", out, readErr)
			}
			if mode == "park-resource" {
				flag, err := ReadFlagFile(git.dir)
				if err != nil || flag == nil || flag.ID != id || flag.Phase != PhaseNewSbSwapped {
					t.Fatalf("park recovery intent missing: flag=%+v err=%v", flag, err)
				}
				if IsFlockHeld(git.dir) {
					t.Fatal("parked idle retained mutex")
				}
			}
			if state != want {
				t.Errorf("%s state=%s want=%s", mode, state, want)
			}
			fmt.Printf("452 route %s state=%s callback=%q failure=%q\n", mode, state, out, failure)
		})
	}
}

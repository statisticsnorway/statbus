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

	"github.com/statisticsnorway/statbus/cli/internal/dotenv"
	"github.com/statisticsnorway/statbus/cli/internal/install"
	"github.com/statisticsnorway/statbus/cli/internal/livedbtest"
	"github.com/statisticsnorway/statbus/cli/internal/testgit"
	"github.com/statisticsnorway/statbus/cli/internal/upgrade"
)

// The real normal install defer, with only detection and the step table replaced
// by fixtures. Its real mutex, SQL success hook and release lifecycle still run.
func Test452KissNormalInstallRetiresAttempts(t *testing.T) {
	root := livedbtest.ProjectDir()
	if root == "" {
		t.Fatal("explicit owned fixture required")
	}
	conn, err := connectInstallDB(root)
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = conn.Close(context.Background()) }()
	ctx := context.Background()
	var database string
	if err := conn.QueryRow(ctx, "SELECT current_database()").Scan(&database); err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(database, "statbus_452kiss_ab_") {
		t.Fatalf("refuse non-owned database %q", database)
	}
	for _, mode := range []string{"new-row", "terminal-refresh", "older-install", "parked", "failed", "dev", "bypass"} {
		t.Run(mode, func(t *testing.T) {
			dir := withRunInstallDetectionHooks(t)
			version = "v2026.10.0-rc.17"
			if mode == "dev" {
				version = "dev"
			}
			if mode == "bypass" {
				postUpgradeFixup = true
				t.Setenv("STATBUS_POST_UPGRADE_FIXUP", "1")
			}
			git := func(args ...string) string {
				t.Helper()
				cmd := exec.Command("git", testgit.Args(args...)...)
				cmd.Dir = dir
				cmd.Env = testgit.Env()
				out, err := cmd.CombinedOutput()
				if err != nil {
					t.Fatalf("git %v: %v %s", args, err, out)
				}
				return strings.TrimSpace(string(out))
			}
			// Replace only the synthetic fixtureCheckout git marker with a real repo.
			if err := os.Remove(filepath.Join(dir, ".git")); err != nil {
				t.Fatal(err)
			}
			git("init", "-q", "-b", "main")
			git("config", "commit.gpgsign", "false")
			// Two unique commits define both installation directions.
			git("commit", "--allow-empty", "-qm", "452 owned install old "+mode)
			old := git("rev-parse", "HEAD")
			git("commit", "--allow-empty", "-qm", "452 owned install new "+mode)
			newer := git("rev-parse", "HEAD")
			installed, orphan := newer, old
			if mode == "older-install" {
				installed, orphan = old, newer
				git("checkout", "--detach", old)
			}
			env, err := dotenv.Load(filepath.Join(root, ".env"))
			if err != nil {
				t.Fatal(err)
			}
			env.Set("UPGRADE_CALLBACK", "")
			if err := os.WriteFile(filepath.Join(dir, ".env"), []byte(env.String()), 0600); err != nil {
				t.Fatal(err)
			}
			restoreGeneratedSettings = func(string) error { return nil }
			detectInstallState = func(string, string) (install.State, *install.Detail, error) {
				return install.StateNothingScheduled, &install.Detail{}, nil
			}
			failure := errors.New("452 real step failure")
			runInstallStepTableTestHook = func() error {
				if !upgrade.IsFlockHeld(dir) && mode != "bypass" {
					t.Fatal("step hook does not hold mutex")
				}
				if mode == "failed" {
					return failure
				}
				return nil
			}
			var id int
			if err := conn.QueryRow(ctx, `INSERT INTO public.upgrade(commit_sha,committed_at,commit_tags,summary,state,scheduled_at,started_at,log_relative_file_path,backup_path,error,recovery_parked_at,recovery_parked_reason)
   VALUES($1,now(),'{}','452 owned install orphan','in_progress',now()-interval '1 hour',now()-interval '59 minutes','452-original.log','452-retained-backup','452 retained error',CASE WHEN $2 THEN now() END,CASE WHEN $2 THEN '452 original park' END) RETURNING id`, orphan, mode == "parked").Scan(&id); err != nil {
				t.Fatal(err)
			}
			t.Cleanup(func() {
				for _, sha := range []string{installed, orphan} {
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
			if mode == "terminal-refresh" {
				if _, err := conn.Exec(ctx, `INSERT INTO public.upgrade(commit_sha,committed_at,commit_tags,summary,state,superseded_at) VALUES($1,now(),'{}','452 immutable own row','superseded',now())`, installed); err != nil {
					t.Fatal(err)
				}
			}
			err = runInstall()
			if mode == "failed" {
				if !errors.Is(err, failure) {
					t.Fatalf("expected primary failure got %v", err)
				}
			} else if err != nil {
				t.Fatal(err)
			}
			var state, backup, rowError string
			if err := conn.QueryRow(ctx, "SELECT state::text,backup_path,error FROM public.upgrade WHERE id=$1", id).Scan(&state, &backup, &rowError); err != nil {
				t.Fatal(err)
			}
			want := "superseded"
			if mode == "parked" || mode == "failed" || mode == "dev" || mode == "bypass" {
				want = "in_progress"
			}
			if state != want {
				t.Errorf("%s orphan=%s want=%s", mode, state, want)
			}
			if backup != "452-retained-backup" || rowError != "452 retained error" {
				t.Errorf("retirement altered evidence backup=%q error=%q", backup, rowError)
			}
			if mode == "new-row" || mode == "older-install" {
				var source *string
				if err := conn.QueryRow(ctx, "SELECT from_commit_version FROM public.upgrade WHERE commit_sha=$1", installed).Scan(&source); err != nil {
					t.Fatal(err)
				}
				if source != nil {
					t.Errorf("unproven source guessed %q", *source)
				}
			}
			t.Logf("owned DB=%s actual runInstall %s orphan=%s", database, mode, state)
		})
	}
}

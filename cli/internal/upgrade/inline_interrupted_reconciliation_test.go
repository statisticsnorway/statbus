//go:build livedb

package upgrade

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/statisticsnorway/statbus/cli/internal/testgit"
)

// Actual reconciliation, SQL attempt authority and mutex with explicitly
// synthetic external serving/version/window boundaries. No restore replay or
// released-image guest acceptance is implied.
func TestInlineInterruptedReconciliation(t *testing.T) {
	project := findProjDir(t)
	d := NewService(project, false, "test", "50446ec0e135c567295313a155d0559e39c9af04")
	dsn, err := d.recoveryDSN()
	if err != nil {
		t.Fatal(err)
	}
	cfg, err := pgx.ParseConfig(dsn)
	if err != nil {
		t.Fatal(err)
	}
	privateRC19 := cfg.Database == "statbus_rc19_claim_recovery_1007"
	if !privateRC19 && cfg.Database != fmt.Sprintf("statbus_livedb_%d", os.Getpid()) {
		t.Fatal("refusing mutation outside an owned live-test database")
	}
	if privateRC19 && (cfg.Host != "127.0.0.1" || cfg.Port != 33184 || cfg.User != "postgres") {
		t.Fatal("private claim DB route mismatch")
	}
	if os.Getenv("HOME") != filepath.Join(filepath.Dir(project), "home") {
		t.Fatal("private HOME mismatch")
	}
	if _, err := os.Stat(filepath.Join(project, ".statbus")); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 120*time.Second)
	defer cancel()
	connect := func() *pgx.Conn {
		t.Helper()
		conn, err := pgx.ConnectConfig(ctx, cfg.Copy())
		if err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() { _ = conn.Close(context.Background()) })
		return conn
	}
	control := connect()
	var db, system, version string
	var rows int
	if err := control.QueryRow(ctx, `SELECT current_database(),system_identifier::text,current_setting('server_version_num') FROM pg_control_system()`).Scan(&db, &system, &version); err != nil {
		t.Fatal(err)
	}
	if db != cfg.Database || (privateRC19 && (system != "7693664852495945767" || version != "180006")) {
		t.Fatal("owned cluster identity mismatch")
	}
	if err := control.QueryRow(ctx, `SELECT count(*) FROM public.upgrade`).Scan(&rows); err != nil || rows != 0 {
		t.Fatalf("owned DB not empty: %d %v", rows, err)
	}
	if _, err := os.Stat(flagFilePath(project)); !os.IsNotExist(err) {
		t.Fatal("existing marker, refusing")
	}
	insert := func(t *testing.T, sha, state string) int {
		t.Helper()
		var id int
		if err := control.QueryRow(ctx, `INSERT INTO public.upgrade(commit_sha,committed_at,summary,state,scheduled_at,started_at,claim_token,docker_images_status,release_builds_status)
   VALUES($1,now(),'owned claim recovery probe',$2::public.upgrade_state,now(),CASE WHEN $2='in_progress' THEN now() ELSE NULL END,CASE WHEN $2='in_progress' THEN '10070000-0000-0000-0000-000000000001'::uuid ELSE NULL END,'ready','ready') RETURNING id`, sha, state).Scan(&id); err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() {
			cctx, ccancel := context.WithTimeout(context.Background(), 10*time.Second)
			defer ccancel()
			if _, err := control.Exec(cctx, `DELETE FROM public.upgrade_state_log WHERE upgrade_id=$1`, id); err != nil {
				t.Error(err)
			}
			if _, err := control.Exec(cctx, `DELETE FROM public.upgrade WHERE id=$1`, id); err != nil {
				t.Error(err)
			}
		})
		return id
	}
	snapshot := func(id int) (string, int) {
		t.Helper()
		var state string
		var audits int
		if err := control.QueryRow(ctx, `SELECT state::text,(SELECT count(*) FROM public.upgrade_state_log WHERE upgrade_id=u.id) FROM public.upgrade AS u WHERE id=$1`, id).Scan(&state, &audits); err != nil {
			t.Fatal(err)
		}
		return state, audits
	}
	// Exact refusing argv double under os.TempDir passes the existing testguard.
	bin := t.TempDir()
	tracePath := filepath.Join(bin, "commands")
	if err := os.WriteFile(filepath.Join(bin, "docker"), []byte(`#!/bin/sh
printf '%s\n' "$*" >> "$CLAIM_FOLLOWUP_TRACE"
[ "$*" = 'compose exec db pg_isready -U postgres' ] || exit 99
[ "$CLAIM_FOLLOWUP_HEALTH" != fail ] || exit 1
printf 'accepting connections (synthetic exact argv)\n'
exit 0
`), 0700); err != nil {
		t.Fatal(err)
	}
	t.Setenv("CLAIM_FOLLOWUP_TRACE", tracePath)
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
	if err := d.waitForDBHealth(2 * time.Second); err != nil {
		t.Fatalf("exact health double: %v", err)
	}
	trace, err := os.ReadFile(tracePath)
	if err != nil || string(trace) != "compose exec db pg_isready -U postgres\n" {
		t.Fatalf("unexpected health argv: %q %v", trace, err)
	}
	t.Logf("actual health command captured and succeeded: %s", strings.TrimSpace(string(trace)))
	for _, mode := range []string{"NoPriorOlderCLI", "StandingPark"} {
		t.Run(mode, func(t *testing.T) {
			svc := NewService(project, false, "older CLI", "unknown")
			svc.queryConn = connect()
			id := insert(t, "1007000000000000000000000000000000000088", "scheduled")
			_, before := snapshot(id)
			var parkedID int
			var flagBefore []byte
			if mode == "StandingPark" {
				parkedID = insert(t, "1007000000000000000000000000000000000089", "in_progress")
				if _, err := control.Exec(ctx, "UPDATE public.upgrade SET recovery_parked_at=now(),recovery_parked_reason='owned deterministic park' WHERE id=$1", parkedID); err != nil {
					t.Fatal(err)
				}
				if err := svc.writeUpgradeFlag(parkedID, "1007000000000000000000000000000000000089", nil, "owned:park", "test", false); err != nil {
					t.Fatal(err)
				}
				svc.releaseUpgradeFlagLockKeepingFile()
				flagBefore, _ = os.ReadFile(flagFilePath(project))
				t.Cleanup(func() { _ = svc.removeUpgradeFlag() })
			}
			called := false
			if err := svc.ReconcileInterruptedForInline(ctx, func(string) error { called = true; return nil }); err != nil {
				t.Fatal(err)
			}
			if called {
				t.Fatal("normal path demanded recovery-specific context or detection")
			}
			if state, after := snapshot(id); state != "scheduled" || after != before {
				t.Fatal("normal candidate changed")
			}
			if parkedID != 0 {
				if state, _ := snapshot(parkedID); state != "in_progress" {
					t.Fatal("standing park was reconciled")
				}
				flagAfter, _ := os.ReadFile(flagFilePath(project))
				if string(flagAfter) != string(flagBefore) {
					t.Fatal("standing park marker changed")
				}
			}
			t.Logf("actual normal entry preserved %s, older/unknown executable allowed without future target gate", mode)
		})
	}
	for _, mode := range []string{"OldFlaglessInterrupted", "LiveOldLock", "UnknownExecutable", "RecoveryReadError", "HealthFailure"} {
		t.Run("Inline"+mode, func(t *testing.T) {
			oldSHA := "1007000000000000000000000000000000000099"
			targetSHA := "50446ec0e135c567295313a155d0559e39c9af04"
			oldID := insert(t, oldSHA, "in_progress")
			newID := insert(t, targetSHA, "scheduled")
			svc := NewService(project, false, "test", targetSHA)
			svc.queryConn = connect()
			if mode == "UnknownExecutable" {
				svc.binaryCommit = "unknown"
			}
			if mode == "LiveOldLock" {
				owner := NewService(project, false, "test", oldSHA)
				if err := owner.writeUpgradeFlag(oldID, oldSHA, nil, "owned:live", "test", false); err != nil {
					t.Fatal(err)
				}
				t.Cleanup(func() { owner.releaseUpgradeFlagLockKeepingFile(); _ = owner.removeUpgradeFlag() })
			}
			cctx, ccancel := context.WithCancel(ctx)
			defer ccancel()
			if mode == "RecoveryReadError" {
				ccancel()
			}
			_, oldAudits := snapshot(oldID)
			_, newAudits := snapshot(newID)
			if mode == "HealthFailure" {
				t.Setenv("CLAIM_FOLLOWUP_HEALTH", "fail")
			}
			called := false
			err := svc.ReconcileInterruptedForInline(cctx, func(string) error { called = true; return nil })
			if called {
				t.Fatal("refused recovery invoked installer dispatch callback")
			}
			t.Cleanup(func() { svc.releaseUpgradeFlagLockKeepingFile(); _ = svc.removeUpgradeFlag() })
			var pgErr *pgconn.PgError
			singleton := errors.As(err, &pgErr) && pgErr.Code == "23505" && pgErr.ConstraintName == "upgrade_single_in_progress"
			stateOld, auditOld := snapshot(oldID)
			stateNew, auditNew := snapshot(newID)
			t.Logf("actual inline: mode=%s exact_old_id=%d sha=%s selected_id=%d sha=%s singleton23505=%t old=%s selected=%s error=%v", mode, oldID, oldSHA, newID, targetSHA, singleton, stateOld, stateNew, err)
			wantOld, wantOldAudits := "in_progress", oldAudits
			if mode == "HealthFailure" {
				wantOld, wantOldAudits = "failed", oldAudits+1
			}
			if err == nil || singleton || stateOld != wantOld || stateNew != "scheduled" || auditOld != wantOldAudits || auditNew != newAudits {
				t.Fatalf("arriving inline did not fail closed before claim: %v", err)
			}
			if mode == "LiveOldLock" && !IsFlockHeld(project) {
				t.Fatal("live actor mutex stolen")
			}
		})
	}
	for _, completionMode := range []string{"HealthyCompletion", "FinishingLiftFailure", "CleanupFailure", "RestoredTree", "RestoredExecutable", "PendingConvergence"} {
		t.Run(completionMode, func(t *testing.T) {
			t.Setenv("PATH", bin+string(os.PathListSeparator)+"/usr/bin"+string(os.PathListSeparator)+os.Getenv("PATH"))
			repo := newGitRepoFixture(t)
			if err := os.Symlink(filepath.Join(project, ".env"), filepath.Join(repo.dir, ".env")); err != nil {
				t.Fatal(err)
			}
			if err := os.WriteFile(filepath.Join(repo.dir, ".env.config"), nil, 0600); err != nil {
				t.Fatal(err)
			}
			git := func(args ...string) {
				t.Helper()
				cmd := exec.Command("/usr/bin/git", testgit.Args(args...)...)
				cmd.Env = testgit.Env()
				cmd.Dir = repo.dir
				if out, err := cmd.CombinedOutput(); err != nil {
					t.Fatalf("local git boundary: %v %s", err, out)
				}
			}
			git("checkout", "--detach", repo.oldSHA)
			if err := os.WriteFile(filepath.Join(bin, "docker"), []byte(`#!/bin/sh
printf '%s\n' "$*" >> "$CLAIM_FOLLOWUP_TRACE"
case "$*" in
 'compose exec db pg_isready -U postgres'|'compose up -d --no-build app worker rest proxy') exit 0 ;;
 *) exit 99 ;;
esac
`), 0700); err != nil {
				t.Fatal(err)
			}
			oldTransport := http.DefaultTransport
			httpCalls := 0
			http.DefaultTransport = artifactRetryTransport(func(req *http.Request) (*http.Response, error) {
				if req.URL.Host != "claim-fixture.invalid" || (req.URL.Path != "/ready" && req.URL.Path != "/rpc/auth_status") {
					return nil, fmt.Errorf("external HTTP refused: %s", req.URL)
				}
				httpCalls++
				return &http.Response{StatusCode: 200, Header: make(http.Header), Body: io.NopCloser(strings.NewReader("{}")), Request: req}, nil
			})
			t.Cleanup(func() { http.DefaultTransport = oldTransport })
			oldID := insert(t, repo.oldSHA, "in_progress")
			candidateID := insert(t, repo.newSHA, "scheduled")
			_, oldAudits := snapshot(oldID)
			_, candidateAudits := snapshot(candidateID)
			recoverer := NewService(repo.dir, false, "test", repo.oldSHA)
			recoverer.queryConn = connect()
			t.Cleanup(func() {
				recoverer.removeFile = nil
				recoverer.releaseUpgradeFlagLockKeepingFile()
				_ = recoverer.removeUpgradeArtifacts()
			})
			recoverer.cachedURL = "http://claim-fixture.invalid/rpc/auth_status"
			recoverer.cachedReadyURL = "http://claim-fixture.invalid/ready"
			recoverer.liftReadOnlyWindowForTest = func(string) (string, error) {
				if completionMode == "FinishingLiftFailure" {
					return "", errors.New("owned exact finishing window-lift failure")
				}
				return "synthetic owned window-lift boundary", nil
			}
			if completionMode == "CleanupFailure" {
				recoverer.removeFile = func(path string) error {
					if path == recoverer.flagPath() {
						return errors.New("owned cleanup refusal")
					}
					return os.Remove(path)
				}
			}
			if completionMode == "RestoredTree" {
				git("checkout", "--detach", repo.newSHA)
			}
			if completionMode == "PendingConvergence" {
				if _, err := control.Exec(ctx, "UPDATE public.upgrade SET tree_convergence_required=true WHERE id=$1", oldID); err != nil {
					t.Fatal(err)
				}
			}
			versionSHA := repo.oldSHA
			if completionMode == "RestoredExecutable" {
				versionSHA = repo.newSHA
			}
			if err := os.WriteFile(filepath.Join(repo.dir, "sb"), []byte("#!/bin/sh\n[ \"$*\" = --version ] || exit 99\nprintf 'sb fixture commit "+versionSHA[:8]+"\\n'\n"), 0700); err != nil {
				t.Fatal(err)
			}
			called := false
			integrationErr := recoverer.ReconcileInterruptedForInline(ctx, func(dir string) error {
				called = true
				if dir != repo.dir {
					t.Fatal("wrong recovered project")
				}
				var selectedSHA string
				if err := control.QueryRow(ctx, "SELECT commit_sha FROM public.upgrade WHERE id=$1 AND state='scheduled'", candidateID).Scan(&selectedSHA); err != nil {
					return err
				}
				if selectedSHA != repo.newSHA {
					return fmt.Errorf("selected identity changed")
				}
				return nil
			})
			if completionMode != "HealthyCompletion" {
				state, audits := snapshot(oldID)
				selected, selectedAudits := snapshot(candidateID)
				t.Logf("actual finishing outcome: err=%v callback=%t old=%s old_audit_delta=%d selected=%s selected_audit_delta=%d", integrationErr, called, state, audits-oldAudits, selected, selectedAudits-candidateAudits)
				if integrationErr == nil || called || selected != "scheduled" || selectedAudits != candidateAudits {
					t.Fatal("failed finishing boundary was accepted as successful reconciliation")
				}
				return
			}
			if integrationErr != nil {
				t.Fatal(integrationErr)
			}
			if !called {
				t.Fatal("actual recovery did not reach fresh installer boundary")
			}
			state, audits := snapshot(oldID)
			if state != "completed" || audits != oldAudits+1 || httpCalls < 2 || IsFlockHeld(repo.dir) {
				t.Fatalf("actual authorized completion not durable: state=%s audit=%d healthcalls=%d", state, audits-oldAudits, httpCalls)
			}
			if selected, audits := snapshot(candidateID); selected != "scheduled" || audits != candidateAudits {
				t.Fatal("recovery touched candidate")
			}
			t.Logf("actual authorized old completion: id=%d sha=%s audit_delta=1 synthetic serving probes=%d; candidate untouched", oldID, repo.oldSHA, httpCalls)
		})
	}
}

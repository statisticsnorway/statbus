//go:build livedb

package upgrade

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
)

// Cancel only after the real diagnostic row read, before terminal persistence.
// This observes the actual failure writer, not a copied terminal algorithm.
type failurePersistenceCancelTracer struct {
	cancel context.CancelFunc
	fired  bool
}
type failurePersistenceQueryKey struct{}

func (tr *failurePersistenceCancelTracer) TraceQueryStart(ctx context.Context, _ *pgx.Conn, data pgx.TraceQueryStartData) context.Context {
	return context.WithValue(ctx, failurePersistenceQueryKey{}, data.SQL)
}
func (tr *failurePersistenceCancelTracer) TraceQueryEnd(ctx context.Context, _ *pgx.Conn, data pgx.TraceQueryEndData) {
	sql, _ := ctx.Value(failurePersistenceQueryKey{}).(string)
	if tr.cancel != nil && !tr.fired && data.Err == nil && strings.HasPrefix(sql, "SELECT to_jsonb(u)::text FROM public.upgrade") {
		tr.fired = true
		tr.cancel()
	}
}

func TestFailureTerminalPersistence(t *testing.T) {
	project := findProjDir(t)
	d := NewService(project, false, "test", "1007000000000000000000000000000000000001")
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
	if filepath.Clean(os.Getenv("HOME")) != filepath.Join(filepath.Dir(project), "home") {
		t.Fatal("fixture-private HOME required")
	}
	if _, err := os.Stat(filepath.Join(project, ".statbus")); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 120*time.Second)
	defer cancel()
	connect := func(tr *failurePersistenceCancelTracer) *pgx.Conn {
		t.Helper()
		c := cfg.Copy()
		if tr != nil {
			c.Tracer = tr
		}
		conn, err := pgx.ConnectConfig(ctx, c)
		if err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() { _ = conn.Close(context.Background()) })
		return conn
	}
	control := connect(nil)
	var db, system, version, owner string
	var rows int
	if err := control.QueryRow(ctx, `SELECT current_database(),system_identifier::text,current_setting('server_version_num'),pg_get_userbyid(datdba) FROM pg_control_system(),pg_database WHERE datname=current_database()`).Scan(&db, &system, &version, &owner); err != nil {
		t.Fatal(err)
	}
	if db != cfg.Database || owner != cfg.User {
		t.Fatal("owned database identity mismatch")
	}
	if privateRC19 && (system != "7693664852495945767" || version != "180006") {
		t.Fatal("owned private cluster identity mismatch")
	}
	if err := control.QueryRow(ctx, `SELECT count(*) FROM public.upgrade`).Scan(&rows); err != nil || rows != 0 {
		t.Fatalf("owned DB not empty: %d %v", rows, err)
	}
	for _, path := range []string{flagFilePath(project), filepath.Join(project, "sb.old"), filepath.Join(os.Getenv("HOME"), "statbus-maintenance")} {
		if _, err := os.Stat(path); !os.IsNotExist(err) {
			t.Fatalf("unsafe runtime sentinel %s: %v", path, err)
		}
	}
	// Diagnostic subprocesses must never contact real Docker/systemd/Git services.
	bin := t.TempDir()
	for _, name := range []string{"docker", "journalctl", "git"} {
		if err := os.WriteFile(filepath.Join(bin, name), []byte("#!/bin/sh\nprintf 'diagnostic boundary refused\\n' >&2\nexit 99\n"), 0700); err != nil {
			t.Fatal(err)
		}
	}
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("NOTIFY_SOCKET", "")
	snapshot := func(id int) (string, int) {
		t.Helper()
		var state string
		var audits int
		if err := control.QueryRow(ctx, `SELECT state::text,(SELECT count(*) FROM public.upgrade_state_log WHERE upgrade_id=u.id) FROM public.upgrade AS u WHERE id=$1`, id).Scan(&state, &audits); err != nil {
			t.Fatal(err)
		}
		return state, audits
	}
	for index, mode := range []string{"CanceledAtFinalPersistence", "ClosedWriter", "NilWriter", "NormalFailedCleanup", "PersistentSQLFailure", "ClaimTokenMismatch", "ChangedTerminalRow"} {
		t.Run(mode, func(t *testing.T) {
			sha := fmt.Sprintf("%040x", 1007+index)
			var id int
			if err := control.QueryRow(ctx, `INSERT INTO public.upgrade(commit_sha,committed_at,summary,state,scheduled_at,started_at,claim_token,docker_images_status,release_builds_status) VALUES($1,now(),'failure persistence fixture','in_progress',now(),now(),'10070000-0000-0000-0000-000000000001'::uuid,'ready','ready') RETURNING id`, sha).Scan(&id); err != nil {
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
			operationCtx, operationCancel := context.WithCancel(ctx)
			defer operationCancel()
			tr := &failurePersistenceCancelTracer{}
			if mode == "CanceledAtFinalPersistence" {
				tr.cancel = operationCancel
			}
			svc := NewService(project, false, "test", "1007000000000000000000000000000000000001")
			svc.queryConn = connect(tr)
			svc.activeClaimToken = "10070000-0000-0000-0000-000000000001"
			if err := svc.writeUpgradeFlag(id, sha, nil, "owned:test", "test", false); err != nil {
				t.Fatal(err)
			}
			if !IsFlockHeld(project) {
				t.Fatal("actual marker flock not held")
			}
			t.Cleanup(func() {
				svc.releaseUpgradeFlagLockKeepingFile()
				if err := svc.removeUpgradeFlag(); err != nil {
					t.Error(err)
				}
			})
			if mode == "ClosedWriter" {
				_ = svc.queryConn.Close(ctx)
			}
			if mode == "NilWriter" {
				svc.queryConn = nil
			}
			if mode == "ClaimTokenMismatch" {
				svc.activeClaimToken = "10070000-0000-0000-0000-000000000002"
			}
			if mode == "ChangedTerminalRow" {
				if _, err := control.Exec(ctx, `UPDATE public.upgrade SET state='failed',error='already durable failure' WHERE id=$1`, id); err != nil {
					t.Fatal(err)
				}
			}
			_, beforeAudit := snapshot(id)
			progress := NewUpgradeLog(project, int64(id), mode, time.Now().UTC())
			defer progress.Close()
			var code *UpgradeFailureCode
			if mode == "PersistentSQLFailure" {
				value := UpgradeFailureCode("NOT_A_REAL_FAILURE_CODE")
				code = &value
			}
			svc.failUpgradeWithFlagDisposition(operationCtx, id, code, "owned original failure", progress, false)
			state, audits := snapshot(id)
			_, markerErr := os.Stat(flagFilePath(project))
			marker := markerErr == nil
			t.Logf("actual failure method: mode=%s id=%d sha=%s state=%s audit_delta=%d marker=%t flock=%t cancellation_boundary=%t", mode, id, sha, state, audits-beforeAudit, marker, IsFlockHeld(project), tr.fired)
			if mode == "CanceledAtFinalPersistence" && (!tr.fired || operationCtx.Err() != context.Canceled) {
				t.Fatal("real diagnostic read did not trigger intended cancellation")
			}
			unresolved := mode == "PersistentSQLFailure" || mode == "ClaimTokenMismatch" || mode == "ChangedTerminalRow"
			if unresolved {
				want := "in_progress"
				if mode == "ChangedTerminalRow" {
					want = "failed"
				}
				if state != want || audits != beforeAudit || !marker || IsFlockHeld(project) {
					t.Fatalf("unsettled write lost faithful recovery intent: state=%s marker=%t audit_delta=%d", state, marker, audits-beforeAudit)
				}
				b, err := os.ReadFile(flagFilePath(project))
				if err != nil {
					t.Fatal(err)
				}
				var flag UpgradeFlag
				if err := json.Unmarshal(b, &flag); err != nil {
					t.Fatal(err)
				}
				if flag.ID != id || flag.CommitSHA != sha || flag.OriginalError != "owned original failure" || flag.Phase != PhaseOldSbUpgrading {
					t.Fatal("preserved marker no longer faithfully identifies attempt/error/phase")
				}
			} else if state != "failed" || marker || audits != beforeAudit+1 || IsFlockHeld(project) {
				t.Fatalf("terminal persistence not durable before marker removal: state=%s marker=%t audit_delta=%d", state, marker, audits-beforeAudit)
			}
		})
	}
}

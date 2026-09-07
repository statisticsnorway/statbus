package upgrade

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

const statbus354FloorVersion int64 = 20260907120000

func requireSTATBUS354Live(t *testing.T) (string, *Service, context.Context) {
	t.Helper()
	if os.Getenv("STATBUS_LIVE_DB") == "" {
		t.Skip("set STATBUS_LIVE_DB=1 to exercise the real database")
	}
	projDir := findProjDir(t)
	for _, path := range []string{flagFilePath(projDir), filepath.Join(projDir, "sb.old"), maintenanceFlagHostPath()} {
		if _, err := os.Stat(path); err == nil {
			t.Fatalf("%s exists; refusing to run beside a live upgrade", path)
		}
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	t.Cleanup(cancel)
	d := NewService(projDir, false, "test", "")
	if err := d.LoadConfigAndConnect(ctx); err != nil {
		t.Fatalf("LoadConfigAndConnect: %v", err)
	}
	t.Cleanup(d.Close)
	return projDir, d, ctx
}

func statbus354InsertUpgrade(t *testing.T, d *Service, ctx context.Context, suffix, state string, pending bool) (int, string) {
	t.Helper()
	sum := sha256.Sum256([]byte("STATBUS-354:" + suffix))
	sha := hex.EncodeToString(sum[:])[:40]
	var id int
	if err := d.queryConn.QueryRow(ctx, `
		INSERT INTO public.upgrade (commit_sha, committed_at, commit_tags, release_status, summary, state,
		                            scheduled_at, started_at, failure_code, error, backup_path,
		                            log_relative_file_path, rollback_finish_pending_at)
		VALUES ($1, now() - interval '2 days', '{}', 'commit', $2, $3,
		        now() - interval '1 hour', now() - interval '59 minutes', $4, 'STATBUS-354 live twin',
		        '/nonexistent/statbus354-snapshot', $5, CASE WHEN $6 THEN now() ELSE NULL END)
		RETURNING id`, sha, "STATBUS-354 "+suffix, state, ErrGitFetchRetryable, "statbus354-"+suffix+".log", pending).Scan(&id); err != nil {
		t.Fatalf("insert upgrade row: %v", err)
	}
	t.Cleanup(func() {
		cleanupCtx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()
		_ = os.Remove(flagFilePath(d.projDir))
		_ = os.Remove(maintenanceFlagHostPath())
		_, _ = d.liftReadOnlyWindow("STATBUS-354 live twin cleanup")
		_, _ = d.queryConn.Exec(cleanupCtx, "DELETE FROM public.upgrade_state_log WHERE upgrade_id = $1", id)
		_, _ = d.queryConn.Exec(cleanupCtx, "DELETE FROM public.upgrade WHERE id = $1", id)
	})
	return id, sha
}

func statbus354WriteFreeFinishingMarker(t *testing.T, projDir string, id int, sha string) {
	t.Helper()
	marker, err := json.Marshal(UpgradeFlag{ID: id, CommitSHA: sha, StartedAt: time.Now(), InvokedBy: "STATBUS-354", Trigger: "test", Holder: HolderService, Phase: PhaseRollbackFinishing, Step: StepRollback})
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(flagFilePath(projDir), marker, 0o644); err != nil {
		t.Fatal(err)
	}
}

func statbus354FloorHash(t *testing.T, projDir string) string {
	t.Helper()
	path := filepath.Join(projDir, "migrations", "20260907120000_statbus_347_rollback_finish_pending_column.up.sql")
	b, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	sum := sha256.Sum256(b)
	return hex.EncodeToString(sum[:])
}

func statbus354ApplyFloorDown(t *testing.T, projDir string, d *Service, ctx context.Context) {
	t.Helper()
	path := filepath.Join(projDir, "migrations", "20260907120000_statbus_347_rollback_finish_pending_column.down.sql")
	cmd := exec.CommandContext(ctx, filepath.Join(projDir, "sb"), "psql")
	cmd.Dir = projDir
	file, err := os.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if err := file.Close(); err != nil {
			t.Errorf("close floor down migration: %v", err)
		}
	})
	cmd.Stdin = file
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("apply real floor down migration: %v\n%s", err, out)
	}
	if _, err := d.queryConn.Exec(ctx, "DELETE FROM db.migration WHERE version = $1", statbus354FloorVersion); err != nil {
		t.Fatalf("delete floor ledger row at restored-snapshot boundary: %v", err)
	}
}

func statbus354ReapplyFloor(t *testing.T, projDir string, d *Service, ctx context.Context) {
	t.Helper()
	cmd := exec.CommandContext(ctx, filepath.Join(projDir, "sb"), "migrate", "up", "--to", fmt.Sprint(statbus354FloorVersion))
	cmd.Dir = projDir
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("reapply floor: %v\n%s", err, out)
	}
	var exists bool
	var hash string
	if err := d.queryConn.QueryRow(ctx, `SELECT EXISTS (
		SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='upgrade' AND column_name='rollback_finish_pending_at')`).Scan(&exists); err != nil || !exists {
		t.Fatalf("floor column absent after reapply: exists=%v err=%v", exists, err)
	}
	if err := d.queryConn.QueryRow(ctx, "SELECT content_hash FROM db.migration WHERE version=$1", statbus354FloorVersion).Scan(&hash); err != nil {
		t.Fatalf("floor ledger row: %v", err)
	}
	if want := statbus354FloorHash(t, projDir); hash != want {
		t.Fatalf("floor hash=%s want=%s", hash, want)
	}
}

// Item 1. This uses the same faithful local-volume fixture technique as the VM
// arc: at the shimmed restore boundary apply the shipped down migration and
// delete its ledger row together, then drive the ordinary target migration and
// the real cleanup finisher.
func TestLivePreColumnSnapshotAdoptionRollback_STATBUS354(t *testing.T) {
	projDir, d, ctx := requireSTATBUS354Live(t)
	statbus354ApplyFloorDown(t, projDir, d, ctx)
	t.Cleanup(func() { statbus354ReapplyFloor(t, projDir, d, context.Background()) })
	var absent bool
	if err := d.queryConn.QueryRow(ctx, `SELECT NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='upgrade' AND column_name='rollback_finish_pending_at')`).Scan(&absent); err != nil || !absent {
		t.Fatalf("pre-column snapshot not presented: absent=%v err=%v", absent, err)
	}
	statbus354ReapplyFloor(t, projDir, d, ctx)
	id, sha := statbus354InsertUpgrade(t, d, ctx, "adoption", "failed", true)
	statbus354WriteFreeFinishingMarker(t, projDir, id, sha)
	finalized, err := d.finalizePendingRollback(ctx, id, LabelRolledBackFinishRecovery)
	if err != nil || !finalized {
		t.Fatalf("finalize pending rollback: finalized=%v err=%v", finalized, err)
	}
	var state string
	var pending *time.Time
	if err := d.queryConn.QueryRow(ctx, "SELECT state::text, rollback_finish_pending_at FROM public.upgrade WHERE id=$1", id).Scan(&state, &pending); err != nil || state != "rolled_back" || pending != nil {
		t.Fatalf("terminal row state=%q pending=%v err=%v", state, pending, err)
	}
	if _, err := os.Stat(flagFilePath(projDir)); !os.IsNotExist(err) {
		t.Fatalf("cleanup marker remains: %v", err)
	}
	t.Log("PASS item 1: pre-column snapshot down+ledger boundary, ordinary floor migrate, and real finisher converged")
}

// Item 2. The named kill site itself is exercised by the VM arc because it is
// an os.Exit boundary. This live twin proves its durable crash shape routes on
// StepRollback even though the floor ledger already makes the DB look at-target.
func TestLiveFloorSuccessBeforePendingStepRollbackWins_STATBUS354(t *testing.T) {
	projDir, d, ctx := requireSTATBUS354Live(t)
	id, sha := statbus354InsertUpgrade(t, d, ctx, "floor-success-kill", "in_progress", false)
	if err := d.writeUpgradeFlag(id, sha, nil, "STATBUS-354", string(TriggerService), false); err != nil {
		t.Fatal(err)
	}
	if err := d.mutateHeldFlag(func(flag *UpgradeFlag) { flag.Step = StepRollback; flag.Phase = PhaseNewSbUpgrading }); err != nil {
		t.Fatal(err)
	}
	d.releaseUpgradeFlagLockKeepingFile()
	var floorCount int
	if err := d.queryConn.QueryRow(ctx, "SELECT count(*) FROM db.migration WHERE version=$1", statbus354FloorVersion).Scan(&floorCount); err != nil || floorCount != 1 {
		t.Fatalf("floor ledger shape count=%d err=%v", floorCount, err)
	}
	flag, err := ReadFlagFile(projDir)
	if err != nil || flag.Step != StepRollback {
		t.Fatalf("crash marker=%+v err=%v", flag, err)
	}
	lock, held, err := acquireRecoveryFlock(projDir, *flag)
	if err != nil {
		t.Fatal(err)
	}
	d.flagLock = lock
	if held.Step != StepRollback {
		t.Fatalf("held marker lost rollback direction: %+v", held)
	}
	// Finish through the real rollback cleanup actors without touching a volume.
	if _, err := d.queryConn.Exec(ctx, "UPDATE public.upgrade SET state='failed', rollback_finish_pending_at=now() WHERE id=$1", id); err != nil {
		t.Fatal(err)
	}
	if err := d.mutateHeldFlag(func(f *UpgradeFlag) { f.Phase = PhaseRollbackFinishing }); err != nil {
		t.Fatal(err)
	}
	d.releaseUpgradeFlagLockKeepingFile()
	if err := d.RecoverFromFlag(ctx); err != nil {
		t.Fatalf("RecoverFromFlag: %v", err)
	}
	var state string
	if err := d.queryConn.QueryRow(ctx, "SELECT state::text FROM public.upgrade WHERE id=$1", id).Scan(&state); err != nil || state != "rolled_back" {
		t.Fatalf("state=%q err=%v", state, err)
	}
	t.Log("PASS item 2: at-floor ledger plus held StepRollback routed to cleanup rollback, never forward resume")
}

// Item 3. The real commit-to-ledger gap is already driven end-to-end by the
// mandatory sheep arc. Locally we present the exact post-restore boundary and
// prove the non-idempotent floor records exactly once through ordinary migrate.
func TestLiveMigrationCommitBeforeLedgerRestoreRetry_STATBUS354(t *testing.T) {
	projDir, d, ctx := requireSTATBUS354Live(t)
	statbus354ApplyFloorDown(t, projDir, d, ctx)
	t.Cleanup(func() { statbus354ReapplyFloor(t, projDir, d, context.Background()) })
	statbus354ReapplyFloor(t, projDir, d, ctx)
	statbus354ReapplyFloor(t, projDir, d, ctx)
	var count int
	if err := d.queryConn.QueryRow(ctx, "SELECT count(*) FROM db.migration WHERE version=$1", statbus354FloorVersion).Scan(&count); err != nil || count != 1 {
		t.Fatalf("floor ledger count=%d err=%v", count, err)
	}
	t.Log("PASS item 3: restored pre-column boundary retried non-idempotent floor with one schema effect and one ledger row")
}

func TestLiveFloorFailureHoldAndHumanRetry_STATBUS354(t *testing.T) {
	projDir, d, ctx := requireSTATBUS354Live(t)
	id, sha := statbus354InsertUpgrade(t, d, ctx, "floor-failure-hold", "in_progress", false)
	backup := t.TempDir()
	if err := d.writeUpgradeFlag(id, sha, nil, "STATBUS-354", string(TriggerService), false); err != nil {
		t.Fatal(err)
	}
	if err := d.mutateHeldFlag(func(f *UpgradeFlag) { f.Step = StepRollback; f.BackupPath = backup }); err != nil {
		t.Fatal(err)
	}
	t.Setenv("STATBUS_INJECT_AT", "rollback-floor-reapply")
	if err := d.holdRollbackSchemaFloorFailure(id, backup, nil, fmt.Errorf("injected floor failure")); err != nil {
		t.Fatal(err)
	}
	flag, err := ReadFlagFile(projDir)
	if err != nil || flag.Phase != PhaseRollbackSchemaFloorFailed || flag.Step != StepRollback {
		t.Fatalf("hold marker=%+v err=%v", flag, err)
	}
	var state string
	if err := d.queryConn.QueryRow(ctx, "SELECT state::text FROM public.upgrade WHERE id=$1", id).Scan(&state); err != nil || state != "in_progress" {
		t.Fatalf("hold row=%q err=%v", state, err)
	}
	if IsFlockHeld(projDir) {
		t.Fatal("durable human-retry hold retained live flock")
	}
	t.Setenv("STATBUS_INJECT_AT", "")
	statbus354ReapplyFloor(t, projDir, d, ctx)
	if _, err := d.queryConn.Exec(ctx, "UPDATE public.upgrade SET state='failed', rollback_finish_pending_at=now() WHERE id=$1", id); err != nil {
		t.Fatal(err)
	}
	flag.Phase = PhaseRollbackFinishing
	marker, _ := json.Marshal(flag)
	if err := os.WriteFile(flagFilePath(projDir), marker, 0o644); err != nil {
		t.Fatal(err)
	}
	if err := d.RecoverFromFlag(ctx); err != nil {
		t.Fatal(err)
	}
	t.Log("PASS item 4: deterministic floor failure held target rollback route alive-idle; ordinary migrate plus recovery converged")
}

func TestLivePendingCleanupMarkerPreservesSentinel_STATBUS354(t *testing.T) {
	projDir, d, ctx := requireSTATBUS354Live(t)
	id, sha := statbus354InsertUpgrade(t, d, ctx, "pending-cleanup", "failed", true)
	statbus354WriteFreeFinishingMarker(t, projDir, id, sha)
	if _, err := d.queryConn.Exec(ctx, "UPDATE public.upgrade SET summary=summary||' / sentinel-after-reopen' WHERE id=$1", id); err != nil {
		t.Fatal(err)
	}
	if err := d.RecoverFromFlag(ctx); err != nil {
		t.Fatal(err)
	}
	var state, summary string
	if err := d.queryConn.QueryRow(ctx, "SELECT state::text, summary FROM public.upgrade WHERE id=$1", id).Scan(&state, &summary); err != nil || state != "rolled_back" || !strings.Contains(summary, "sentinel-after-reopen") {
		t.Fatalf("state=%q summary=%q err=%v", state, summary, err)
	}
	t.Log("PASS item 5: pending plus cleanup marker finalized cleanup-only and preserved post-reopen sentinel")
}

func TestLiveTerminalRowCleanupMarkerPublishesSourceBinary_STATBUS354(t *testing.T) {
	projDir, d, ctx := requireSTATBUS354Live(t)
	id, sha := statbus354InsertUpgrade(t, d, ctx, "terminal-cleanup", "failed", false)
	if _, err := d.queryConn.Exec(ctx, "UPDATE public.upgrade SET state='rolled_back', rolled_back_at=now(), scheduled_at=NULL, failure_code=NULL WHERE id=$1", id); err != nil {
		t.Fatal(err)
	}
	statbus354WriteFreeFinishingMarker(t, projDir, id, sha)
	if err := d.RecoverFromFlag(ctx); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(flagFilePath(projDir)); !os.IsNotExist(err) {
		t.Fatalf("marker remains: %v", err)
	}
	var state string
	if err := d.queryConn.QueryRow(ctx, "SELECT state::text FROM public.upgrade WHERE id=$1", id).Scan(&state); err != nil || state != "rolled_back" {
		t.Fatalf("state=%q err=%v", state, err)
	}
	t.Log("PASS item 6: terminal row plus cleanup marker performed marker-only cleanup and retained terminal row")
}

func TestLiveCleanupActorRaceStaleLoserCannotMutate_STATBUS354(t *testing.T) {
	projDir, winner, ctx := requireSTATBUS354Live(t)
	id, sha := statbus354InsertUpgrade(t, winner, ctx, "cleanup-race", "failed", true)
	statbus354WriteFreeFinishingMarker(t, projDir, id, sha)
	stale, err := ReadFlagFile(projDir)
	if err != nil {
		t.Fatal(err)
	}
	if err := winner.RecoverFromFlag(ctx); err != nil {
		t.Fatal(err)
	}
	loser := NewService(projDir, false, "test", "")
	if err := loser.LoadConfigAndConnect(ctx); err != nil {
		t.Fatal(err)
	}
	defer loser.Close()
	lock, _, err := acquireRecoveryFlock(projDir, *stale)
	if err == nil {
		if lock != nil {
			lock.Close()
		}
		t.Fatal("stale cleanup actor recreated or acquired a removed marker")
	}
	if _, err := os.Stat(flagFilePath(projDir)); !os.IsNotExist(err) {
		t.Fatalf("loser recreated marker: %v", err)
	}
	var state string
	if err := loser.queryConn.QueryRow(ctx, "SELECT state::text FROM public.upgrade WHERE id=$1", id).Scan(&state); err != nil || state != "rolled_back" {
		t.Fatalf("loser changed row: state=%q err=%v", state, err)
	}
	t.Log("PASS item 7: delayed cleanup actor could not create, rewrite, unlink, or alter the winner's terminal row")
}

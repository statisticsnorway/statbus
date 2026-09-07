package install

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/statisticsnorway/statbus/cli/internal/dotenv"
	"github.com/statisticsnorway/statbus/cli/internal/upgrade"
)

// TestLiveDetect_PendingRollbackIsCrashedNotReattempt runs the REAL install
// ladder probe (Detect with defaultProbe: real psql, real marker file) on the
// cleanup-only shape: a free-flock service marker whose row is
// rollback_finish_pending_at set with a retained backup_path. The ladder must say
// StateCrashedUpgrade (route to RecoverFromFlag, which is cleanup-only for this
// row) and NEVER StateRestoreReattemptable (which would replay the snapshot
// restore over data accepted after the window lifted).
//
//	STATBUS_LIVE_DB=1 go test -count=1 -run TestLiveDetect -v ./internal/install
func TestLiveDetect_PendingRollbackIsCrashedNotReattempt(t *testing.T) {
	if os.Getenv("STATBUS_LIVE_DB") == "" {
		t.Skip("set STATBUS_LIVE_DB=1 to exercise the real database")
	}
	projDir := liveProjDir(t)
	flagPath := filepath.Join(projDir, "tmp", "upgrade-in-progress.json")
	if _, err := os.Stat(flagPath); err == nil {
		t.Fatalf("a real upgrade marker exists at %s; refusing to run beside a live upgrade", flagPath)
	}

	conn := liveAdminConn(t, projDir)
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	const sha = "3470000000000000000000000000000000000021"
	var id int
	if err := conn.QueryRow(ctx, `
		INSERT INTO public.upgrade (commit_sha, committed_at, commit_tags, release_status, summary, state,
		                            scheduled_at, started_at, error, backup_path, log_relative_file_path, rollback_finish_pending_at)
		VALUES ($1, now() - interval '2 days', '{}', 'commit', 'live detect probe', 'failed',
		        now() - interval '1 hour', now() - interval '59 minutes',
		        'live detect probe', '/nonexistent/live-detect-probe-backup', 'live-detect-probe.log', now())
		RETURNING id`, sha).Scan(&id); err != nil {
		t.Fatalf("insert pending row: %v", err)
	}
	t.Cleanup(func() {
		cctx, ccancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer ccancel()
		if _, err := conn.Exec(cctx, "DELETE FROM public.upgrade_state_log WHERE upgrade_id = $1", id); err != nil {
			t.Errorf("cleanup state log: %v", err)
		}
		if _, err := conn.Exec(cctx, "DELETE FROM public.upgrade WHERE id = $1", id); err != nil {
			t.Errorf("cleanup row: %v", err)
		}
		_ = conn.Close(cctx)
		_ = os.Remove(flagPath)
	})

	// Without the marker: the row alone must NOT read as restore-reattemptable.
	state, detail, err := Detect(projDir, "test")
	if err != nil {
		t.Fatalf("Detect (no marker): %v", err)
	}
	if state == StateRestoreReattemptable {
		t.Fatalf("a rollback_finish_pending_at row was classified restore-reattemptable (row %d); a replay would restore over accepted writes", detail.ReattemptRowID)
	}
	t.Logf("no marker: state=%s", state)

	// With the free-flock marker: crashed-upgrade, routed to RecoverFromFlag.
	marker, _ := json.Marshal(upgrade.UpgradeFlag{ID: id, CommitSHA: sha, StartedAt: time.Now(), InvokedBy: "probe", Trigger: "test", Holder: upgrade.HolderService})
	if err := os.WriteFile(flagPath, marker, 0644); err != nil {
		t.Fatal(err)
	}
	state, detail, err = Detect(projDir, "test")
	if err != nil {
		t.Fatalf("Detect (marker): %v", err)
	}
	if state != StateCrashedUpgrade {
		t.Fatalf("state = %s, want %s for a free-flock service marker over a cleanup-only row", state, StateCrashedUpgrade)
	}
	if detail.Flag == nil || detail.Flag.ID != id {
		t.Fatalf("detail.Flag = %+v, want the planted marker for id %d", detail.Flag, id)
	}
	t.Logf("marker: state=%s flag.id=%d", state, detail.Flag.ID)
}

func liveProjDir(t *testing.T) string {
	t.Helper()
	dir, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 6; i++ {
		if _, err := os.Stat(filepath.Join(dir, ".env")); err == nil {
			if _, err := os.Stat(filepath.Join(dir, "dev.sh")); err == nil {
				return dir
			}
		}
		dir = filepath.Join(dir, "..")
	}
	t.Fatal("project dir (with .env and dev.sh) not found above the test cwd")
	return ""
}

func liveAdminConn(t *testing.T, projDir string) *pgx.Conn {
	t.Helper()
	f, err := dotenv.Load(filepath.Join(projDir, ".env"))
	if err != nil {
		t.Fatal(err)
	}
	get := func(k string) string { v, _ := f.Get(k); return v }
	dsn := "host=" + get("CADDY_DB_BIND_ADDRESS") + " port=" + get("CADDY_DB_PORT") +
		" dbname=" + get("POSTGRES_APP_DB") + " user=" + get("POSTGRES_ADMIN_USER") +
		" password=" + get("POSTGRES_ADMIN_PASSWORD") + " sslmode=disable application_name=live-detect-probe"
	conn, err := pgx.Connect(context.Background(), dsn)
	if err != nil {
		t.Fatalf("connect: %v", err)
	}
	return conn
}

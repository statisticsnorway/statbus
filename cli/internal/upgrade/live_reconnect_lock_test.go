//go:build livedb

package upgrade

import (
	"context"
	"os"
	"testing"
	"time"
)

// TestReconnectKeepsTheDaemonLock: the daemon holds its session advisory lock
// (hashtext('upgrade_daemon')) on queryConn; reconnect replaces both sessions
// and must leave the daemon holding the lock on the new one. The old session
// is the daemon's own, so its lock is never "another upgrader". rc.17's
// postswap-migration-ceiling arc failed exactly here (Upgrade Arc Harness
// 42276884758): the rollback's second reconnect found the lock still held by
// the backend it had just closed (STATBUS-586).
//
// go test -tags livedb -count=1 -run TestReconnectKeepsTheDaemonLock ./internal/upgrade
func TestReconnectKeepsTheDaemonLock(t *testing.T) {
	projDir := findProjDir(t)
	if _, err := os.Stat(flagFilePath(projDir)); err == nil {
		t.Fatalf("a real upgrade marker exists at %s; refusing to run beside a live upgrade", flagFilePath(projDir))
	}
	d := NewService(projDir, false, "test", "")
	ctx, cancel := context.WithTimeout(context.Background(), 120*time.Second)
	defer cancel()
	if err := d.LoadConfigAndConnect(ctx); err != nil {
		t.Fatalf("LoadConfigAndConnect: %v", err)
	}
	t.Cleanup(d.Close)
	if err := d.acquireAdvisoryLock(ctx); err != nil {
		t.Skipf("the daemon lock is held by a running upgrader on this database: %v", err)
	}
	for i := 1; i <= 200; i++ {
		if err := d.reconnect(ctx); err != nil {
			t.Fatalf("reconnect %d: %v", i, err)
		}
		var held bool
		if err := d.queryConn.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM pg_locks
			WHERE locktype = 'advisory' AND objid = hashtext('upgrade_daemon')::oid
			  AND pid = pg_backend_pid() AND granted)`).Scan(&held); err != nil {
			t.Fatal(err)
		}
		if !held {
			t.Fatalf("after reconnect %d the daemon's new session does not hold the lock", i)
		}
	}
	// The old backend may outlive the client's close for a moment (a busy or
	// loaded server reads the Terminate late). Here it is still running a
	// statement when reconnect replaces it, as on the arc's VM.
	_ = d.queryConn.PgConn().Exec(ctx, "SELECT pg_sleep(2)")
	if err := d.reconnect(ctx); err != nil {
		t.Fatalf("reconnect while the old session is still busy: %v", err)
	}
}

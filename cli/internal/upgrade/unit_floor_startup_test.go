package upgrade

import (
	"context"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
)

// STATBUS-559: install stamps unit_floor_state before its deferred service
// start, so that stamp describes a unit that is not running. The service used
// to refresh the stamp only on its poll tick (six hours), so the admin page
// warned "installed but not running" while the upgrader ran. The service must
// stamp once it owns a database session, without waiting for a tick.
func TestStartupUnitFloorStampPublishesOnceConnected(t *testing.T) {
	ctx := context.Background()
	d := &Service{projDir: "/fixture/project", interval: 3 * time.Hour}

	var calls int
	d.stampUnitFloorForTest = func(_ context.Context, conn *pgx.Conn, projDir string, interval time.Duration) {
		calls++
		if conn == nil {
			t.Error("startup stamp called without a connection")
		}
		if projDir != d.projDir {
			t.Errorf("startup stamp projDir = %q, want %q", projDir, d.projDir)
		}
		if interval != d.interval {
			t.Errorf("startup stamp interval = %s, want the configured %s", interval, d.interval)
		}
	}

	d.stampUnitFloorAtStartup(ctx)
	if calls != 0 {
		t.Fatalf("stamped %d time(s) without a database session; the write must wait for one", calls)
	}

	d.queryConn = &pgx.Conn{}
	d.stampUnitFloorAtStartup(ctx)
	if calls != 1 {
		t.Fatalf("startup stamps = %d, want exactly 1 once connected", calls)
	}
}

// The behavioral helper above proves the stamp's shape; this pins its call
// site. Run must stamp after the connection exists (and therefore after
// connectWithBudget) and before the main poll loop, where the first tick is a
// full interval away.
func TestRunStampsUnitFloorAtStartup(t *testing.T) {
	src, err := os.ReadFile(thisRepoFile(t, "cli/internal/upgrade/service.go"))
	if err != nil {
		t.Fatalf("read service.go: %v", err)
	}
	run := extractFuncBody(t, string(src), "func (d *Service) Run(")

	connect := strings.Index(run, "d.connectWithBudget(ctx, startupConnectTimeout)")
	stamp := strings.Index(run, "d.stampUnitFloorAtStartup(ctx)")
	pollLoop := strings.Index(run, "ticker := time.NewTicker(d.interval)")

	if connect < 0 || stamp < 0 || pollLoop < 0 {
		t.Fatalf("Run markers not found (connect=%d stamp=%d pollLoop=%d); test is stale", connect, stamp, pollLoop)
	}
	if stamp < connect {
		t.Error("the startup stamp must run after the database connection is established")
	}
	if stamp > pollLoop {
		t.Error("the startup stamp must run before the poll loop, not wait for its first tick")
	}
}

package upgrade

import (
	"context"
	"strings"
	"testing"
)

// TestRunClaimsScheduledOnStartupAndTick is the fast wiring guard for STATBUS-098:
// the upgrade daemon must claim a pending 'scheduled' row WITHOUT a live NOTIFY,
// via (a) a startup scan and (b) the 30s heartbeat tick — not only on a live
// NOTIFY. A NOTIFY fired while the daemon is down/restarting (e.g. an upgrade's
// DB-restart reconnect window) is LOST (pg NOTIFY is not durable); without these
// two claim paths a web-UI-scheduled upgrade on Albania silently delays up to the
// 6h discovery tick. This source-inspection guard (same idiom as
// TestOnScheduledNotify_NoInsert) catches a regression that removes either claim
// path. The deterministic end-to-end behavioral proof is the VM scenario
// test/install-recovery/arcs/claim-without-notify-arc.sh.
//
// A DB-backed behavioral unit test (pre-seed a 'scheduled' row, drive Run, assert
// state→in_progress) is intentionally NOT attempted here: the upgrade package has
// no DB-backed daemon-loop test harness, and executeScheduled cascades into
// executeUpgrade (docker/git) — that would need new test infra + an
// executeScheduled refactor (a separate ticket if ever wanted). This wiring guard
// + the VM scenario cover the property.
func TestRunClaimsScheduledOnStartupAndTick(t *testing.T) {
	body := funcBody(t, "service.go", "func (d *Service) Run(")

	// (a) STARTUP: the region before the main loop must CLAIM (executeScheduled),
	// not just discover — so a row scheduled while the daemon was down is picked
	// up immediately on (re)start instead of waiting for the 6h discovery tick.
	// The main loop is the 1-tab `for {`; the early signal-select uses `\t\tfor {`.
	mainLoop := strings.Index(body, "\n\tfor {")
	if mainLoop < 0 {
		t.Fatal("could not locate Run()'s main loop (`for {`)")
	}
	if startup := body[:mainLoop]; !strings.Contains(startup, "d.executeScheduled(ctx)") {
		t.Error("Run() startup (before the main loop) must call d.executeScheduled(ctx) — " +
			"STATBUS-098 startup-claim: a row scheduled while the daemon was down must be claimed " +
			"on (re)start, not wait for the 6h discovery tick")
	}

	// (b) 30s HEARTBEAT TICK: the heartbeatTicker.C case must ALSO claim, so a lost
	// NOTIFY is caught within ≤30s regardless. Scope to that case (up to the next
	// select case) so the assertion can't be satisfied by the ticker.C/notify cases.
	hb := strings.Index(body, "case <-heartbeatTicker.C:")
	if hb < 0 {
		t.Fatal("could not locate the heartbeatTicker.C case in Run()")
	}
	hbBlock := body[hb+len("case <-heartbeatTicker.C:"):]
	if next := strings.Index(hbBlock, "case <-"); next >= 0 {
		hbBlock = hbBlock[:next]
	}
	if !strings.Contains(hbBlock, "d.idleHeartbeat(ctx)") {
		t.Error("Run()'s heartbeatTicker.C (30s) case must call d.idleHeartbeat(ctx): " +
			"STATBUS-098 ≤30s claim: a lost NOTIFY must still be claimed within 30s, not wait " +
			"for the 6h discovery tick")
	}

	// Follow the real helper, so relocating the claim cannot silently drop it.
	// Reconnection must precede its DB consumers after a failed recovery reconnect.
	heartbeat := funcBody(t, "service.go", "func (d *Service) idleHeartbeat(")
	previous := strings.Index(heartbeat, "d.ensureConnected(ctx)")
	if previous < 0 {
		t.Fatal("idle heartbeat must reconnect before reading candidate state")
	}
	for _, call := range []string{"d.finalizePendingRollbacks(ctx)", "d.verifyArtifacts(ctx)", "d.executeScheduled(ctx, true)"} {
		position := strings.Index(heartbeat, call)
		if position <= previous {
			t.Fatalf("idle heartbeat must call %s after its preceding connection or recovery step", call)
		}
		previous = position
	}
}

// A recovery reconnect may leave queryConn nil. An unavailable configuration
// must yield safely, not dereference it before the normal reconnect gate.
func TestIdleHeartbeatUnavailableConnection(t *testing.T) {
	d := &Service{projDir: t.TempDir()}
	if _, err := d.recoveryDSN(); err == nil {
		t.Fatal("empty private project unexpectedly has a connection route")
	}
	d.idleHeartbeat(context.Background())
	if d.queryConn != nil || d.listenConn != nil {
		t.Fatal("unavailable private project must not establish database sessions")
	}
}

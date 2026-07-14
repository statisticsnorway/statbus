package upgrade

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// reconnect-hung-bounded (plan upgrade-resume-structural-whole.md piece #3):
// connect() must BOUND a hung dial+handshake by connectTimeout, so the
// applyNewSbUpgrading reconnect — which the #3 watchdog defers gating during (it is a
// legitimately silent step) — cannot block forever. Before this guard, connStr
// had no connect_timeout and callers passed the service-lifetime ctx (no
// deadline), so a wedged pgx.Connect would ping the watchdog forever (the
// blind-unbounded hole). This drives connect() at an unroutable address
// (192.0.2.1, RFC 5737 TEST-NET-1 — packets are dropped, so the dial blocks)
// with a SHORT connectTimeout and asserts it returns a deadline/timeout error
// promptly instead of hanging. (The handshake-phase bound — a connect that
// dials OK but stalls in the startup/auth exchange — rests on pgconn's
// contextWatcher.Watch(ctx), which closes the conn when the ctx deadline fires
// mid-handshake; that is verified by source inspection, not reachable as a fast
// hermetic unit test.)
func TestConnectBoundedByConnectTimeout(t *testing.T) {
	dir := t.TempDir()
	// Minimal .env with the keys connect() requires, pointing at a blackhole.
	// 192.0.2.0/24 is reserved for documentation/tests and is not routable, so
	// the TCP SYN gets no response and the dial blocks until the ctx deadline.
	env := strings.Join([]string{
		"CADDY_DB_BIND_ADDRESS=192.0.2.1",
		"CADDY_DB_PORT=5432",
		"POSTGRES_APP_DB=statbus_test",
		"POSTGRES_ADMIN_USER=postgres",
		"POSTGRES_ADMIN_PASSWORD=irrelevant",
		"",
	}, "\n")
	if err := os.WriteFile(filepath.Join(dir, ".env"), []byte(env), 0644); err != nil {
		t.Fatalf("write .env: %v", err)
	}

	// Shrink the bound so the test doesn't wait 5 minutes; restore after.
	orig := connectTimeout
	connectTimeout = 300 * time.Millisecond
	defer func() { connectTimeout = orig }()

	d := &Service{projDir: dir}

	// Pass a context with NO deadline — exactly the applyNewSbUpgrading reconnect
	// case. The bound MUST come from connectTimeout inside connect(), not from
	// the caller's ctx.
	done := make(chan error, 1)
	go func() { done <- d.connect(context.Background()) }()

	select {
	case err := <-done:
		if err == nil {
			t.Fatal("connect() to a blackhole address must FAIL (timeout), not succeed")
		}
		// The error should reflect a timeout / deadline — pgx wraps
		// context.DeadlineExceeded into its connection error message.
		msg := err.Error()
		if !strings.Contains(msg, "context deadline exceeded") &&
			!strings.Contains(msg, "timeout") &&
			!strings.Contains(msg, "deadline") {
			t.Errorf("connect() error should indicate a timeout/deadline (connectTimeout bound), got: %v", err)
		}
	case <-time.After(10 * time.Second):
		t.Fatal("connect() did NOT return within 10s — connectTimeout is not bounding the dial (the unbounded-reconnect hole is open)")
	}
}

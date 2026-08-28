package upgrade

import (
	"context"
	"net"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

// notifyRecorder listens on a real unixgram socket and counts the datagrams
// sdNotify sends. It observes the PRODUCTION notification path end to end —
// sdNotify dials $NOTIFY_SOCKET — rather than a stand-in, so these tests cannot
// pass against a heartbeat that was refactored to notify nothing.
type notifyRecorder struct {
	mu   sync.Mutex
	msgs []string
	conn net.PacketConn
}

func newNotifyRecorder(t *testing.T) *notifyRecorder {
	t.Helper()
	// NOT t.TempDir(): a unix socket path is capped near 104 bytes and the
	// per-test temp path (which embeds the test name) can exceed it — the bind
	// then fails as "invalid argument" and looks like a broken assertion.
	dir, err := os.MkdirTemp("", "sn")
	if err != nil {
		t.Fatalf("temp dir: %v", err)
	}
	t.Cleanup(func() { _ = os.RemoveAll(dir) })

	sock := filepath.Join(dir, "n")
	conn, err := net.ListenPacket("unixgram", sock)
	if err != nil {
		t.Skipf("unixgram sockets unavailable here (%v) — this pin needs the real sd_notify path", err)
	}
	r := &notifyRecorder{conn: conn}
	t.Cleanup(func() { _ = conn.Close() })

	go func() {
		buf := make([]byte, 256)
		for {
			n, _, err := conn.ReadFrom(buf)
			if err != nil {
				return
			}
			r.mu.Lock()
			r.msgs = append(r.msgs, string(buf[:n]))
			r.mu.Unlock()
		}
	}()

	t.Setenv("NOTIFY_SOCKET", sock)
	return r
}

func (r *notifyRecorder) count() int {
	r.mu.Lock()
	defer r.mu.Unlock()
	n := 0
	for _, m := range r.msgs {
		if strings.Contains(m, "WATCHDOG=1") {
			n++
		}
	}
	return n
}

// blackholeService writes the .env keys connect() requires, pointing at an
// address chosen by the caller, and returns a Service rooted there.
//
//	192.0.2.1 (RFC 5737 TEST-NET-1) — unroutable, so the SYN is dropped and the
//	dial WEDGES until its deadline. This is the "attempt makes no progress" case.
//	127.0.0.1:1 — refused immediately. This is the "attempt fails fast" case.
func connectFixture(t *testing.T, addr, port string) *Service {
	t.Helper()
	dir := t.TempDir()
	env := strings.Join([]string{
		"CADDY_DB_BIND_ADDRESS=" + addr,
		"CADDY_DB_PORT=" + port,
		"POSTGRES_APP_DB=statbus_test",
		"POSTGRES_ADMIN_USER=postgres",
		"POSTGRES_ADMIN_PASSWORD=irrelevant",
		"",
	}, "\n")
	if err := os.WriteFile(filepath.Join(dir, ".env"), []byte(env), 0644); err != nil {
		t.Fatalf("write .env: %v", err)
	}
	return &Service{projDir: dir}
}

// shrinkConnectBounds scales the loop down so tests drive it in milliseconds
// instead of minutes, restoring every var afterwards.
func shrinkConnectBounds(t *testing.T, total, perAttempt, retry time.Duration) {
	t.Helper()
	ot, oa, or := connectTimeout, connectAttemptTimeout, connectRetryDelay
	connectTimeout, connectAttemptTimeout, connectRetryDelay = total, perAttempt, retry
	t.Cleanup(func() { connectTimeout, connectAttemptTimeout, connectRetryDelay = ot, oa, or })
}

// TestWedgedAttemptIsSilentWithinItsBound_STATBUS299 — arm (a).
//
// THE PROPERTY THAT MAKES THE COVER SAFE. A watchdog cover is only worth having
// if it still lets a real hang be detected. The heartbeat therefore fires at
// ATTEMPT BOUNDARIES and never on a timer: while a single attempt is wedged,
// nothing is emitted at all.
//
// So this asserts SILENCE — that no WATCHDOG=1 appears during the first
// attempt's lifetime. If someone were to "improve" this into a background
// ticker, the daemon would ping straight through a genuine deadlock and systemd
// could never kill it; that regression passes every other test in this file and
// fails only this one.
func TestWedgedAttemptIsSilentWithinItsBound_STATBUS299(t *testing.T) {
	rec := newNotifyRecorder(t)
	shrinkConnectBounds(t, 10*time.Second, 2*time.Second, 10*time.Millisecond)
	d := connectFixture(t, "192.0.2.1", "5432") // wedges: no response, ever

	// MUST NOT LEAK THE GOROUTINE. connect() reads the package-level bounds this
	// test rewrites, so a dialer still running after the test returns races
	// t.Cleanup's restore AND the next test's own rewrite of those vars. The
	// race detector reports that against whichever test happens to be running —
	// it failed a PRE-EXISTING test (TestConnectBoundedByConnectTimeout) that
	// had nothing to do with the change. Cancel, then WAIT for the dialer to
	// return, before any cleanup runs.
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() { defer close(done); _ = d.connect(ctx) }()
	defer func() { cancel(); <-done }()

	// Well inside the first attempt: it is still dialling, so it has proved
	// nothing and must have said nothing.
	time.Sleep(700 * time.Millisecond)
	if n := rec.count(); n != 0 {
		t.Errorf("got %d WATCHDOG=1 ping(s) DURING a wedged attempt; want 0.\n"+
			"The heartbeat must attest to progress, not to elapsed time — pinging inside an\n"+
			"attempt that has not completed is exactly what makes a watchdog unable to catch a hang.", n)
	}

	// After the attempt's own bound elapses, the boundary is reached and the
	// loop may report liveness.
	time.Sleep(2 * time.Second)
	if n := rec.count(); n < 1 {
		t.Errorf("got %d ping(s) after the first attempt boundary; want at least 1 — "+
			"the loop completed an attempt and must attest to that progress", n)
	}
}

// TestFailFastAttemptsHeartbeatWithinBudget_STATBUS299 — arm (b).
//
// The complement of (a): when attempts genuinely advance, the phase keeps
// reporting liveness, and the TOTAL patience is unchanged. A refused address
// fails in microseconds, so the loop turns over many times inside a short
// budget — many boundaries, many pings — and still returns at the budget rather
// than running on.
func TestFailFastAttemptsHeartbeatWithinBudget_STATBUS299(t *testing.T) {
	rec := newNotifyRecorder(t)
	shrinkConnectBounds(t, 1500*time.Millisecond, 500*time.Millisecond, 50*time.Millisecond)
	d := connectFixture(t, "127.0.0.1", "1") // refused immediately

	start := time.Now()
	err := d.connect(context.Background())
	elapsed := time.Since(start)

	if err == nil {
		t.Fatal("connect() to a refused port must fail")
	}
	if n := rec.count(); n < 3 {
		t.Errorf("got %d WATCHDOG=1 ping(s) across a budget of fail-fast attempts; want >= 3 — "+
			"a phase making demonstrable progress must keep reporting liveness", n)
	}
	// The budget is a ceiling, not a target: it must not overrun materially.
	if elapsed > connectTimeout+time.Second {
		t.Errorf("connect() took %s for a %s budget — the total bound is not being honoured", elapsed, connectTimeout)
	}
}

// TestFirstFailureSurfacesFast_STATBUS299 — arm (c).
//
// The improvement that is worth having even with no watchdog in the picture. A
// single five-minute attempt takes five minutes to report ANY failure: a wrong
// password was indistinguishable from a down database for the whole budget.
// With sub-attempts the FIRST error is in hand within one attempt bound while
// the overall patience is unchanged.
//
// connectTimeout is left at its PRODUCTION value here on purpose — the point is
// that the first report does not wait for it.
func TestFirstFailureSurfacesFast_STATBUS299(t *testing.T) {
	rec := newNotifyRecorder(t)
	// Only the per-attempt step is shrunk; the total budget stays 5 minutes.
	oa, or := connectAttemptTimeout, connectRetryDelay
	connectAttemptTimeout, connectRetryDelay = 300*time.Millisecond, 50*time.Millisecond
	t.Cleanup(func() { connectAttemptTimeout, connectRetryDelay = oa, or })
	if connectTimeout < time.Minute {
		t.Fatalf("this arm asserts against the production budget; connectTimeout=%s", connectTimeout)
	}

	d := connectFixture(t, "192.0.2.1", "5432") // wedges, so only the per-attempt bound can end it
	// Same no-leak discipline as the silence arm above: this one holds the
	// PRODUCTION 5-minute budget, so a leaked dialer would outlive the whole
	// package run while reading vars other tests rewrite.
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() { defer close(done); _ = d.connect(ctx) }()
	defer func() { cancel(); <-done }()

	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		if rec.count() >= 1 {
			return // first failure reported and attested within seconds
		}
		time.Sleep(50 * time.Millisecond)
	}
	t.Fatalf("no attempt boundary within 5s against a %s budget — the first failure is still "+
		"waiting for the whole budget, which is the coarse design this ticket replaced", connectTimeout)
}

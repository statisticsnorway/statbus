package upgrade

import (
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

// pollCountRe extracts the "N poll(s)" count STATBUS-289 adds to both
// waitForRestReady timeout errors (mirroring the success line's own
// "%d poll(s)" phrasing, :1602). Used instead of a hardcoded expected count
// so the test derives its cross-check from the error itself, not from
// hand-computed pass arithmetic that would silently drift if the loop's
// timing constants ever change.
var pollCountRe = regexp.MustCompile(`(\d+) poll\(s\)`)

// pollCountFromError extracts the poll count STATBUS-289 requires in both
// timeout error messages. Fails the test loudly if the pattern is absent —
// never treated as "0 polls", which would silently mask the very omission
// this ticket closes.
func pollCountFromError(t *testing.T, err error) int {
	t.Helper()
	m := pollCountRe.FindStringSubmatch(err.Error())
	if m == nil {
		t.Fatalf("expected error to name the poll count as \"N poll(s)\", got: %v", err)
	}
	n, convErr := strconv.Atoi(m[1])
	if convErr != nil {
		t.Fatalf("poll count %q did not parse as an integer: %v", m[1], convErr)
	}
	return n
}

// newTestProgress builds a ProgressLog backed by a temp dir so tests can read
// back the narrated lines (mirrors the rc.42 health-check test setup).
func newTestProgress(t *testing.T) *ProgressLog {
	t.Helper()
	projDir := t.TempDir()
	if err := os.MkdirAll(filepath.Join(projDir, "tmp", "upgrade-logs"), 0755); err != nil {
		t.Fatal(err)
	}
	p := NewUpgradeLog(projDir, 1, "v0.0.0-rc.ready", time.Now())
	if p == nil {
		t.Fatal("NewUpgradeLog returned nil")
	}
	return p
}

// TestWaitForRestReady_503ThenReady: the schema cache is still loading (503)
// for the first polls, then /ready=200 — the warmup waits, then proceeds.
func TestWaitForRestReady_503ThenReady(t *testing.T) {
	var n int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if atomic.AddInt32(&n, 1) <= 2 {
			w.WriteHeader(http.StatusServiceUnavailable)
			return
		}
		w.WriteHeader(http.StatusOK)
	}))
	defer srv.Close()

	progress := newTestProgress(t)
	d := &Service{cachedReadyURL: srv.URL}

	if err := d.waitForRestReady(progress, time.Millisecond, time.Millisecond, 5*time.Second); err != nil {
		t.Fatalf("expected ready after 503s, got error: %v", err)
	}
	if got := atomic.LoadInt32(&n); got < 3 {
		t.Errorf("expected at least 3 polls (2×503 then 200), got %d", got)
	}
	logStr := readProgress(t, progress)
	if !strings.Contains(logStr, "PostgREST is ready") {
		t.Errorf("expected progress log to record readiness; got:\n%s", logStr)
	}
}

// TestWaitForRestReady_RefusedThenReady: a transport error (connection
// dropped) and a 503 take the SAME wait path as a clean 503 — the warmup
// tolerates both and proceeds once /ready=200.
func TestWaitForRestReady_RefusedThenReady(t *testing.T) {
	var n int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch atomic.AddInt32(&n, 1) {
		case 1:
			// Simulate connection-refused/reset: hijack and close without a
			// response so the client sees a transport error.
			if hj, ok := w.(http.Hijacker); ok {
				if conn, _, err := hj.Hijack(); err == nil {
					_ = conn.Close()
				}
			}
		case 2:
			w.WriteHeader(http.StatusServiceUnavailable)
		default:
			w.WriteHeader(http.StatusOK)
		}
	}))
	defer srv.Close()

	progress := newTestProgress(t)
	d := &Service{cachedReadyURL: srv.URL}

	if err := d.waitForRestReady(progress, time.Millisecond, time.Millisecond, 5*time.Second); err != nil {
		t.Fatalf("expected warmup to tolerate refused+503 then succeed, got error: %v", err)
	}
	if got := atomic.LoadInt32(&n); got < 3 {
		t.Errorf("expected at least 3 polls (refused, 503, 200), got %d", got)
	}
}

// TestWaitForRestReady_TimeoutSchemaCacheStuck: /ready answers but never
// reaches 200 → the cap-expiry error blames the schema cache (connected but
// 503-throughout) and points at the container logs, NOT config.
func TestWaitForRestReady_TimeoutSchemaCacheStuck(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusServiceUnavailable)
	}))
	defer srv.Close()

	progress := newTestProgress(t)
	d := &Service{cachedReadyURL: srv.URL}

	// A CLOCK THE TEST OWNS, because this test asserts a TIME-DRIVEN behaviour.
	//
	// The loop checks its deadline BEFORE emitting a progress line, so with a
	// real clock and a millisecond budget the whole thing is a race: if one HTTP
	// round trip happens to exceed the budget — routine on a loaded CI runner —
	// the deadline fires on the first pass and the loop returns having logged
	// nothing. That is exactly how this test failed, twice, with greens in
	// between: zero "Still waiting" lines, for reasons having nothing to do with
	// the behaviour under test.
	//
	// Widening the budget would only lower the probability. Instead the clock
	// advances ONLY when the loop sleeps, so real elapsed time is irrelevant and
	// the sequence is fixed: 40ms budget / 2ms poll = the loop makes ~20 passes,
	// each advancing 2ms, and every pass after the first is >= the 1ms progress
	// interval. The lines are then guaranteed, under any load.
	fakeNow := time.Unix(0, 0)
	oldNow, oldSleep := waitForRestReadyNow, waitForRestReadySleep
	waitForRestReadyNow = func() time.Time { return fakeNow }
	waitForRestReadySleep = func(d time.Duration) { fakeNow = fakeNow.Add(d) }
	t.Cleanup(func() { waitForRestReadyNow, waitForRestReadySleep = oldNow, oldSleep })

	err := d.waitForRestReady(progress, 2*time.Millisecond, time.Millisecond, 40*time.Millisecond)
	if err == nil {
		t.Fatal("expected timeout error when /ready never returns 200")
	}
	if !strings.Contains(err.Error(), "schema cache never loaded") {
		t.Errorf("expected schema-cache message, got: %v", err)
	}
	if !strings.Contains(err.Error(), "docker compose logs rest") {
		t.Errorf("expected actionable 'docker compose logs rest', got: %v", err)
	}
	// The connected-but-503 case must NOT mis-blame config.
	if strings.Contains(err.Error(), "config generate") {
		t.Errorf("schema-cache-stuck error must not point at config generate, got: %v", err)
	}
	// The ~progressInterval cadence path ran (load-bearing: it feeds the watchdog).
	logStr := readProgress(t, progress)
	if !strings.Contains(logStr, "Still waiting for PostgREST /ready") {
		t.Errorf("expected periodic 'Still waiting' progress lines; got:\n%s", logStr)
	}

	// STATBUS-289 property 2: the timeout error names how many polls were
	// made — the success line already does ("%d poll(s)", :1602); a timeout
	// after 1 attempt must not read the same as one after 40.
	polls := pollCountFromError(t, err)
	if polls <= 0 {
		t.Errorf("expected a positive poll count in the timeout error, got %d (err: %v)", polls, err)
	}

	// STATBUS-289 property 1: the FINAL pass — the one whose deadline check
	// actually fires the timeout — must still have emitted its own "Still
	// waiting" line first, not just some earlier pass. This test's fixed
	// clock makes this an exact, non-magic-number check rather than an
	// approximation: pollInterval (2ms) is a whole multiple of
	// progressInterval (1ms) and the very first pass never has anything
	// elapsed to report, so — PROVIDED the progress emission fires before
	// the deadline check — every pass from the 2nd through the LAST
	// (inclusive) logs progress, and no others: exactly (polls - 1) lines,
	// deterministically, regardless of the exact pass count. Before
	// STATBUS-289 (deadline check first), the final pass's line is dropped
	// by the early return — exactly (polls - 2) lines — so this assertion is
	// the red-before/green-after discriminator, not the older "log contains
	// at least one line" check above (which passes even with the bug, since
	// earlier passes already logged plenty).
	gotLines := strings.Count(logStr, "Still waiting for PostgREST /ready")
	if wantLines := polls - 1; gotLines != wantLines {
		t.Errorf("expected exactly %d 'Still waiting' line(s) (polls-1, i.e. every pass but the first) since the "+
			"progress emission must fire before the deadline check on the FINAL pass too; got %d. polls=%d, log:\n%s",
			wantLines, gotLines, polls, logStr)
	}
}

// TestWaitForRestReady_TimeoutAdminUnreachable: the admin server never accepts
// a connection (config drift — admin mapping missing) → the cap-expiry error
// blames config and tells the operator to run ./sb config generate, NOT the
// schema cache.
func TestWaitForRestReady_TimeoutAdminUnreachable(t *testing.T) {
	// A server we immediately close: its address now refuses connections.
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {}))
	closedURL := srv.URL
	srv.Close()

	d := &Service{cachedReadyURL: closedURL}

	err := d.waitForRestReady(nil, 2*time.Millisecond, time.Millisecond, 40*time.Millisecond)
	if err == nil {
		t.Fatal("expected timeout error when admin server is unreachable")
	}
	if !strings.Contains(err.Error(), "admin server unreachable") {
		t.Errorf("expected unreachable message, got: %v", err)
	}
	if !strings.Contains(err.Error(), "config generate") {
		t.Errorf("expected actionable './sb config generate', got: %v", err)
	}
	// Never-connected must NOT mis-blame the schema cache.
	if strings.Contains(err.Error(), "schema cache never loaded") {
		t.Errorf("unreachable error must not blame the schema cache, got: %v", err)
	}

	// STATBUS-289 property 2, admin-unreachable branch: this test runs on the
	// REAL clock (no owned-clock seam here), so the exact poll count is
	// machine-speed-dependent — only its presence and positivity are
	// asserted, mirroring the loose bound the schema-cache-stuck test's
	// owned clock lets it tighten to an exact count.
	if polls := pollCountFromError(t, err); polls <= 0 {
		t.Errorf("expected a positive poll count in the timeout error, got %d (err: %v)", polls, err)
	}
}

// TestWaitForRestReady_MissingEnvFailsFast: with no cached URL and no .env,
// readiness resolution fails fast with an actionable error — there is no
// silent fallback that would skip the warmup.
func TestWaitForRestReady_MissingEnvFailsFast(t *testing.T) {
	d := &Service{projDir: t.TempDir()} // no .env present
	err := d.waitForRestReady(nil, time.Millisecond, time.Millisecond, 10*time.Millisecond)
	if err == nil {
		t.Fatal("expected fail-fast error when REST_ADMIN_BIND_ADDRESS cannot be resolved")
	}
	if !strings.Contains(err.Error(), "REST_ADMIN_BIND_ADDRESS") {
		t.Errorf("expected error to name the missing var, got: %v", err)
	}
}

// TestHealthCheck_WarmupPrecedesProbe (structural): healthCheck must poll
// /ready to 200 BEFORE it issues the first functional RPC POST. Asserted by
// recording request order against one server that serves both paths.
func TestHealthCheck_WarmupPrecedesProbe(t *testing.T) {
	var mu sync.Mutex
	var order []string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		order = append(order, r.Method+" "+r.URL.Path)
		mu.Unlock()
		w.WriteHeader(http.StatusOK) // both /ready and the RPC probe return 200
	}))
	defer srv.Close()

	progress := newTestProgress(t)
	d := &Service{
		cachedURL:      srv.URL + "/rpc/auth_status",
		cachedReadyURL: srv.URL + "/ready",
	}

	if err := d.healthCheck(progress, 5, time.Millisecond); err != nil {
		t.Fatalf("healthCheck should pass when /ready and RPC both 200, got: %v", err)
	}

	mu.Lock()
	defer mu.Unlock()
	if len(order) < 2 {
		t.Fatalf("expected at least a /ready then an RPC request, got: %v", order)
	}
	if order[0] != "GET /ready" {
		t.Errorf("first request must be the /ready warmup, got %q (order=%v)", order[0], order)
	}
	// The RPC probe must come strictly after the /ready=200.
	firstRPC := -1
	for i, req := range order {
		if strings.HasSuffix(req, "/rpc/auth_status") {
			firstRPC = i
			break
		}
	}
	if firstRPC <= 0 {
		t.Errorf("expected the RPC probe to run after the /ready warmup; order=%v", order)
	}
}

func readProgress(t *testing.T, p *ProgressLog) string {
	t.Helper()
	b, err := os.ReadFile(p.AbsPath())
	if err != nil {
		t.Fatalf("read progress log: %v", err)
	}
	return string(b)
}

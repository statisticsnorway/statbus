package upgrade

import (
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

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
	if logStr := readProgress(t, progress); !strings.Contains(logStr, "Still waiting for PostgREST /ready") {
		t.Errorf("expected periodic 'Still waiting' progress lines; got:\n%s", logStr)
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

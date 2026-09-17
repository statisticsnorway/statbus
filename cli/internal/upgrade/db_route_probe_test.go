package upgrade

import (
	"context"
	"net"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
)

// STATBUS-143 — the crash-recovery reachability probe must ride the SAME route
// the real connection uses (TCP via the Caddy layer4 proxy on
// CADDY_DB_BIND_ADDRESS:CADDY_DB_PORT), so a probe-pass implies connect-works by
// construction. The old probe reached the db container by a different road
// (docker-exec psql), so with the proxy absent it passed while the real pgx
// connection refused — the severed-proxy dead end.

// closedLocalPort returns a 127.0.0.1 TCP port that is guaranteed CLOSED: it
// binds an ephemeral port, records it, then closes the listener. A connect to it
// gets an immediate RST (connection refused) — deterministic and fast.
func closedLocalPort(t *testing.T) string {
	t.Helper()
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	port := l.Addr().(*net.TCPAddr).Port
	if err := l.Close(); err != nil {
		t.Fatalf("close listener: %v", err)
	}
	return strconv.Itoa(port)
}

func writeEnv(t *testing.T, dir, host, port string) {
	t.Helper()
	env := strings.Join([]string{
		"CADDY_DB_BIND_ADDRESS=" + host,
		"CADDY_DB_PORT=" + port,
		"POSTGRES_APP_DB=statbus_test",
		"POSTGRES_ADMIN_USER=postgres",
		"POSTGRES_ADMIN_PASSWORD=irrelevant",
		"",
	}, "\n")
	if err := os.WriteFile(filepath.Join(dir, ".env"), []byte(env), 0644); err != nil {
		t.Fatalf("write .env: %v", err)
	}
}

// TestEnsureDBReachableFailsWhenConfiguredRouteIsDead is the behavioral kill of
// the false-pass class: with CADDY_DB_BIND/PORT pointed at a CLOSED port,
// EnsureDBReachable MUST fail — it can only ever try the configured route, so a
// live postgres reachable by any OTHER road (docker-exec, a different port)
// cannot make it pass. That is exactly the false pass STATBUS-143 removes.
func TestEnsureDBReachableFailsWhenConfiguredRouteIsDead(t *testing.T) {
	dir := t.TempDir()
	writeEnv(t, dir, "127.0.0.1", closedLocalPort(t))
	d := &Service{projDir: dir}

	err := d.EnsureDBReachable(context.Background())
	if err == nil {
		t.Fatal("EnsureDBReachable must FAIL when the configured route (CADDY_DB_BIND/PORT) is a dead port — even if a DB is reachable by other means")
	}
	// The refusal must name the route so the operator knows where to look.
	if !strings.Contains(err.Error(), "proxy") {
		t.Errorf("the refusal should name the proxy route (check `db` AND `proxy`); got: %v", err)
	}
}

// TestRecoveryDSNSingleSource pins the single-source shape (STATBUS-143): both
// the live connection (connect) and the reachability probe (EnsureDBReachable)
// build their DSN from the ONE recoveryDSN() builder — so they can never drift
// onto different routes again. Source-structure (line comments stripped, so the
// prose mentioning recoveryDSN can't false-match — only the real call counts).
func TestRecoveryDSNSingleSource(t *testing.T) {
	svcSrc, err := os.ReadFile(thisRepoFile(t, "cli/internal/upgrade/service.go"))
	if err != nil {
		t.Fatalf("read service.go: %v", err)
	}
	execSrc, err := os.ReadFile(thisRepoFile(t, "cli/internal/upgrade/exec.go"))
	if err != nil {
		t.Fatalf("read exec.go: %v", err)
	}
	connectBody := extractFuncBody(t, string(svcSrc), "func (d *Service) connect(")
	probeBody := extractFuncBody(t, string(execSrc), "func (d *Service) EnsureDBReachable(")

	if !strings.Contains(connectBody, "d.recoveryDSN()") {
		t.Error("connect() must build its DSN from d.recoveryDSN() (the single-source route builder)")
	}
	if !strings.Contains(probeBody, "d.recoveryDSN()") {
		t.Error("EnsureDBReachable must build its DSN from d.recoveryDSN() (the SAME route connect uses) — the STATBUS-143 fix")
	}
	// And the probe must NOT resurrect the old docker-exec psql road.
	if strings.Contains(probeBody, "migrate.PsqlCommand") {
		t.Error("EnsureDBReachable must NOT use migrate.PsqlCommand (the docker-exec probe that reached the db by a different route than the connection) — deleted by STATBUS-143")
	}
}

// TestRecoveryRouteStartContracts pins AC#2's start-extension: the
// asymmetric-safe start covers db AND proxy (not just the engine), without
// naming proxy to Compose start (which recursively starts proxy's rest
// dependency), and refuses a truly-missing proxy. Held-closed verification is
// a separate, strictly narrower contract with exactly two production callers.
func TestRecoveryRouteStartContracts(t *testing.T) {
	src, err := os.ReadFile(thisRepoFile(t, "cli/internal/upgrade/exec.go"))
	if err != nil {
		t.Fatalf("read exec.go: %v", err)
	}
	routeBody := extractFuncBody(t, string(src), "func (d *Service) StartDatabaseRouteServingMayRun(")
	heldBody := extractFuncBody(t, string(src), "func (d *Service) StartDatabaseRouteServingMustBeStopped(")
	containersBody := extractFuncBody(t, string(src), "func (d *Service) startDatabaseAndItsProxy(")

	if !strings.Contains(routeBody, "d.startDatabaseAndItsProxy(ctx)") {
		t.Error("StartDatabaseRouteServingMayRun must delegate only to dependency-safe existing-container startup before its DB-health wait")
	}
	if !strings.Contains(containersBody, `"compose", "start", "db"`) {
		t.Error("StartDatabaseRouteServingMayRun must use the exact dependency-safe compose argv `docker compose start db`")
	}
	// Negative control: this was the rc.16 product bug. If proxy is named to
	// Compose start, Compose honours proxy->rest depends_on and opens the app.
	if strings.Contains(containersBody, `"compose", "start", "db", "proxy"`) || strings.Contains(containersBody, `"compose", "start", "proxy"`) {
		t.Error("StartDatabaseRouteServingMayRun must not name proxy to `docker compose start`; that recursively starts rest")
	}
	if !strings.Contains(containersBody, `"docker", "start", proxyID`) {
		t.Error("StartDatabaseRouteServingMayRun must start the already-resolved proxy container directly so Compose cannot follow dependencies")
	}
	if strings.Contains(routeBody, "verifyRecoveryClientsStopped") {
		t.Error("route-only StartDatabaseRouteServingMayRun must not reject a legitimately live serving tier")
	}
	if !strings.Contains(containersBody, "proxyContainerMissing") {
		t.Error("StartDatabaseRouteServingMayRun must detect a missing proxy and refuse precisely (newProxyRouteMissingError), not emit an opaque docker error (AC#3)")
	}
	startIdx := strings.Index(heldBody, "d.startDatabaseAndItsProxy(ctx)")
	verifyIdx := strings.Index(heldBody, "d.verifyRecoveryClientsStopped(ctx)")
	healthIdx := strings.Index(heldBody, "d.waitForDBHealth(")
	if startIdx < 0 || verifyIdx < 0 || healthIdx < 0 || startIdx >= verifyIdx || verifyIdx >= healthIdx {
		t.Errorf("StartDatabaseRouteServingMustBeStopped must start dependency-safe containers, immediately run the unchanged fail-closed verifier, then wait for DB health; start@%d verify@%d health@%d", startIdx, verifyIdx, healthIdx)
	}
	if got := strings.Count(string(src), "d.verifyRecoveryClientsStopped(ctx)"); got != 1 {
		t.Fatalf("the held-closed verifier must be invoked only by StartDatabaseRouteServingMustBeStopped; got %d production calls", got)
	}
}

// TestProxyRouteMissingErrorText pins AC#3: the missing-proxy refusal names the
// state and the operator's action (recreate deliberately, then re-run install)
// so a re-run is an actionable path out, not a silent identical error loop.
func TestProxyRouteMissingErrorText(t *testing.T) {
	msg := newProxyRouteMissingError().Error()
	for _, want := range []string{
		"proxy container — does not exist",
		"docker compose up -d proxy",
		"./sb install",
		"CADDY_DB_BIND_ADDRESS",
	} {
		if !strings.Contains(msg, want) {
			t.Errorf("the missing-proxy refusal must be actionable — missing %q in:\n%s", want, msg)
		}
	}
}

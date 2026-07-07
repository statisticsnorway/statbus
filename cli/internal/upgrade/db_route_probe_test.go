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

// TestStartDBForRecoveryStartsTheWholeRoute pins AC#2's start-extension: the
// asymmetric-safe start covers db AND proxy (not just the engine) and refuses a
// truly-missing proxy. The behavioral stopped-proxy green is the mechanic's
// scenario leg; this pins the product shape.
func TestStartDBForRecoveryStartsTheWholeRoute(t *testing.T) {
	src, err := os.ReadFile(thisRepoFile(t, "cli/internal/upgrade/exec.go"))
	if err != nil {
		t.Fatalf("read exec.go: %v", err)
	}
	body := extractFuncBody(t, string(src), "func (d *Service) StartDBForRecovery(")

	if !strings.Contains(body, `"start", "db", "proxy"`) {
		t.Error("StartDBForRecovery must `docker compose start db proxy` — the route, not just the engine (STATBUS-143 AC#2)")
	}
	if !strings.Contains(body, "proxyContainerMissing") {
		t.Error("StartDBForRecovery must detect a missing proxy and refuse precisely (newProxyRouteMissingError), not emit an opaque docker error (AC#3)")
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

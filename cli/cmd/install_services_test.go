package cmd

import (
	"errors"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
	"time"

	"github.com/statisticsnorway/statbus/cli/internal/dbroles"
)

var allFive = []string{"app", "db", "proxy", "rest", "worker"}

func running(svc string) serviceStatus {
	s := serviceStatus{Service: svc, State: "running"}
	if svc == "db" {
		s.Health = "healthy"
	}
	return s
}

func TestServicesNotRunning(t *testing.T) {
	cases := []struct {
		name     string
		statuses []serviceStatus
		want     string
	}{
		{
			name:     "db only (the Finland rerun: proxy, app, worker never created)",
			statuses: []serviceStatus{running("db")},
			want:     "app:missing proxy:missing rest:missing worker:missing",
		},
		{
			name:     "db and proxy",
			statuses: []serviceStatus{running("db"), running("proxy")},
			want:     "app:missing rest:missing worker:missing",
		},
		{
			name:     "all five running",
			statuses: []serviceStatus{running("app"), running("db"), running("proxy"), running("rest"), running("worker")},
			want:     "",
		},
		{
			name: "rest restarting on a stale password",
			statuses: []serviceStatus{running("app"), running("db"), running("proxy"),
				{Service: "rest", State: "restarting"}, running("worker")},
			want: "rest:restarting",
		},
		{
			name: "proxy created but port 80 was taken",
			statuses: []serviceStatus{running("app"), running("db"),
				{Service: "proxy", State: "created"}, running("rest"), running("worker")},
			want: "proxy:created",
		},
		{
			name: "db running but its healthcheck is still starting",
			statuses: []serviceStatus{running("app"), {Service: "db", State: "running", Health: "starting"},
				running("proxy"), running("rest"), running("worker")},
			want: "db:starting",
		},
		{
			name: "db running with no health reported counts as starting",
			statuses: []serviceStatus{running("app"), {Service: "db", State: "running"},
				running("proxy"), running("rest"), running("worker")},
			want: "db:starting",
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			var got []string
			for _, p := range servicesNotRunning(allFive, tc.statuses) {
				got = append(got, p.Service+":"+p.State)
			}
			if strings.Join(got, " ") != tc.want {
				t.Fatalf("got %q, want %q", strings.Join(got, " "), tc.want)
			}
		})
	}
}

func TestServiceProblemsInPlainWords(t *testing.T) {
	got := describeServiceProblems([]serviceProblem{{"proxy", "missing"}, {"rest", "restarting"}, {"worker", "exited"}})
	want := "the web server (proxy) was never started; the API service (rest) keeps restarting; the background worker (worker) has stopped"
	if got != want {
		t.Fatalf("got  %q\nwant %q", got, want)
	}
}

func TestUpgradeServiceRoutePreflight(t *testing.T) {
	oldProbe, oldHealthy := probeUpgradeDatabaseRoute, checkDBHealthyFn
	t.Cleanup(func() { probeUpgradeDatabaseRoute, checkDBHealthyFn = oldProbe, oldHealthy })
	for _, tc := range []struct {
		name    string
		healthy bool
		probe   error
		want    string
	}{
		{"reachable", true, nil, ""},
		{"proxy listener missing while db healthy", true, fmt.Errorf("dial: %w", syscall.ECONNREFUSED), "the web server (proxy) is not listening on the database port"},
		{"database stopped", false, fmt.Errorf("dial: %w", syscall.ECONNREFUSED), "the database (db) is not healthy"},
		{"authentication failed", true, errors.New("28P01 password authentication failed"), "check the database route and login credentials"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			probeUpgradeDatabaseRoute = func(string) error { return tc.probe }
			checkDBHealthyFn = func(string) bool { return tc.healthy }
			err := checkUpgradeDatabaseRoute("unused")
			if tc.want == "" {
				if err != nil {
					t.Fatalf("unexpected error: %v", err)
				}
			} else if err == nil || !strings.Contains(err.Error(), tc.want) {
				t.Fatalf("error = %v, want %q", err, tc.want)
			}
		})
	}
}

func TestInstallProbesDatabaseRouteBeforeStartingUpgradeUnit(t *testing.T) {
	src, err := os.ReadFile("install.go")
	if err != nil {
		t.Fatal(err)
	}
	body := funcBody(t, string(src), "func runInstallService(")
	handoff := strings.Index(body, "if postUpgradeFixup {")
	start := -1
	if handoff >= 0 {
		start = handoff + strings.Index(body[handoff:], "} else {")
	}
	probe := strings.Index(body, "checkUpgradeDatabaseRoute(dir)")
	enable := strings.Index(body, `runCmd("systemctl", "--user", "enable", "--now", instance)`)
	if handoff < 0 || start < handoff || probe < start || enable < probe {
		t.Fatalf("route probe must precede enable --now but not block active service handoff (handoff=%d start=%d probe=%d enable=%d)", handoff, start, probe, enable)
	}
}

func TestParseServiceStatuses(t *testing.T) {
	ndjson := `{"Service":"db","State":"running","Health":"healthy","Name":"statbus-local-db"}
{"Service":"rest","State":"restarting","Health":""}
`
	got, err := parseServiceStatuses([]byte(ndjson))
	if err != nil || len(got) != 2 || got[1].State != "restarting" || got[0].Health != "healthy" {
		t.Fatalf("ndjson: %+v %v", got, err)
	}
	got, err = parseServiceStatuses([]byte(`[{"Service":"app","State":"exited"}]`))
	if err != nil || len(got) != 1 || got[0].State != "exited" {
		t.Fatalf("array: %+v %v", got, err)
	}
	if got, err := parseServiceStatuses([]byte("  \n")); err != nil || len(got) != 0 {
		t.Fatalf("empty: %+v %v", got, err)
	}
}

func TestPublishedPortsRealComposeJSONRecreatesUnboundProxy(t *testing.T) {
	// Docker Compose ps --format json uses Publishers, not the human PORTS column.
	statuses, err := parseServiceStatuses([]byte(`{"Name":"statbus-test-proxy","Service":"proxy","State":"running","Health":"","Publishers":[]}
{"Name":"statbus-test-app","Service":"app","State":"running","Publishers":[{"URL":"127.0.0.1","TargetPort":3000,"PublishedPort":3012,"Protocol":"tcp"}]}`))
	if err != nil {
		t.Fatal(err)
	}
	ports := map[string][]configuredPort{"proxy": {
		{HostIP: "0.0.0.0", Target: 80, Published: "80", Protocol: "tcp"},
		{HostIP: "0.0.0.0", Target: 443, Published: "443", Protocol: "tcp"},
		{HostIP: "0.0.0.0", Target: 443, Published: "443", Protocol: "udp"},
		{HostIP: "127.0.0.1", Target: 5431, Published: "5431", Protocol: "tcp"},
	}, "app": {{HostIP: "127.0.0.1", Target: 3000, Published: "3012", Protocol: "tcp"}}}
	if got := missingPublishedPorts(statuses, ports); len(got["proxy"]) != 4 || len(got["app"]) != 0 {
		t.Fatalf("missing = %+v", got)
	}
	oldConfig, oldProbe, oldRecreate, oldRequired := configuredServicePorts, probeServiceStatuses, recreateServiceWithPorts, requiredServices
	t.Cleanup(func() {
		configuredServicePorts, probeServiceStatuses, recreateServiceWithPorts, requiredServices = oldConfig, oldProbe, oldRecreate, oldRequired
	})
	configuredServicePorts = func(string) (map[string][]configuredPort, error) { return ports, nil }
	probeServiceStatuses = func(string) ([]serviceStatus, error) { return statuses, nil }
	requiredServices = func(string) ([]string, error) { return []string{"app", "proxy"}, nil }
	problems, err := currentServiceProblems("unused")
	if err != nil || len(problems) != 1 || problems[0].Service != "proxy" || problems[0].State != "missing published ports" {
		t.Fatalf("portless running proxy must not pass step 8: %+v, %v", problems, err)
	}
	var recreated []string
	recreateServiceWithPorts = func(_ string, service string) error {
		recreated = append(recreated, service)
		statuses[0].Publishers = []publishedPort{
			{URL: "0.0.0.0", TargetPort: 80, PublishedPort: 80, Protocol: "tcp"},
			{URL: "0.0.0.0", TargetPort: 443, PublishedPort: 443, Protocol: "tcp"},
			{URL: "0.0.0.0", TargetPort: 443, PublishedPort: 443, Protocol: "udp"},
			{URL: "127.0.0.1", TargetPort: 5431, PublishedPort: 5431, Protocol: "tcp"},
		}
		return nil
	}
	if err := reconcilePublishedPorts("unused"); err != nil {
		t.Fatal(err)
	}
	if strings.Join(recreated, ",") != "proxy" {
		t.Fatalf("recreated %v, want proxy only", recreated)
	}
}

// fakeStack drives the step-8 seams without a docker daemon.
type fakeStack struct {
	statuses       []serviceStatus
	upCalls        int
	upErr          error
	onUp           func(*fakeStack)
	passwordsAgree bool
	syncCalls      int
	restarted      []string
	readyStatus    int
}

func installFakeStack(t *testing.T, f *fakeStack) {
	t.Helper()
	oldReq, oldProbe, oldAgree, oldSync, oldRestart, oldUp, oldReady, oldTail :=
		requiredServices, probeServiceStatuses, rolePasswordsAgree, syncRolePasswords, restartPasswordClients, composeUpAll, restReadyStatus, serviceLogTail
	t.Cleanup(func() {
		requiredServices, probeServiceStatuses, rolePasswordsAgree, syncRolePasswords, restartPasswordClients, composeUpAll, restReadyStatus, serviceLogTail =
			oldReq, oldProbe, oldAgree, oldSync, oldRestart, oldUp, oldReady, oldTail
	})
	oldPorts, oldRecreate := configuredServicePorts, recreateServiceWithPorts
	t.Cleanup(func() { configuredServicePorts, recreateServiceWithPorts = oldPorts, oldRecreate })
	configuredServicePorts = func(string) (map[string][]configuredPort, error) { return map[string][]configuredPort{}, nil }
	recreateServiceWithPorts = func(string, string) error { t.Fatal("unexpected recreation"); return nil }
	requiredServices = func(string) ([]string, error) { return allFive, nil }
	probeServiceStatuses = func(string) ([]serviceStatus, error) { return f.statuses, nil }
	rolePasswordsAgree = func(string) (bool, error) { return f.passwordsAgree, nil }
	syncRolePasswords = func(string) ([]dbroles.Mismatch, error) {
		f.syncCalls++
		if f.passwordsAgree {
			return nil, nil
		}
		f.passwordsAgree = true
		// The stale password was what kept rest restarting.
		for i := range f.statuses {
			if f.statuses[i].Service == "rest" {
				f.statuses[i].State = "running"
			}
		}
		return []dbroles.Mismatch{{Role: "authenticator", Reason: "differs"}}, nil
	}
	restartPasswordClients = func(_ string, services []string) error {
		f.restarted = append(f.restarted, services...)
		return nil
	}
	composeUpAll = func(string) error {
		f.upCalls++
		if f.onUp != nil {
			f.onUp(f)
		}
		return f.upErr
	}
	restReadyStatus = func(string) (int, error) { return f.readyStatus, nil }
	serviceLogTail = func(string, string) {}
}

func TestCheckServicesDoneRequiresEveryServiceAndAgreeingPasswords(t *testing.T) {
	f := &fakeStack{statuses: []serviceStatus{running("db")}, passwordsAgree: true}
	installFakeStack(t, f)
	if checkServicesDone("/x") {
		t.Fatal("db only must not be done")
	}
	f.statuses = []serviceStatus{running("app"), running("db"), running("proxy"), running("rest"), running("worker")}
	if !checkServicesDone("/x") {
		t.Fatal("all five running with agreeing passwords must be done")
	}
	f.passwordsAgree = false
	if checkServicesDone("/x") {
		t.Fatal("all five running with a stale role password must not be done")
	}
}

// B1: a box where only db (and a crash-looping rest) survived a failed first
// run. Step 8 must bring up the rest, heal the passwords and restart the
// clients that use them.
func TestRunStartServicesBringsUpEverythingAndHealsPasswords(t *testing.T) {
	dir := dbHealthyDir(t)
	f := &fakeStack{
		statuses: []serviceStatus{running("db"), {Service: "rest", State: "restarting"}},
		onUp: func(f *fakeStack) {
			f.statuses = []serviceStatus{running("app"), running("db"), running("proxy"),
				{Service: "rest", State: "restarting"}, running("worker")}
		},
	}
	installFakeStack(t, f)
	out := captureStdout(t, func() {
		if err := runStartServices(dir); err != nil {
			t.Fatalf("runStartServices: %v", err)
		}
	})
	if f.upCalls != 1 || f.syncCalls != 1 {
		t.Fatalf("up=%d sync=%d", f.upCalls, f.syncCalls)
	}
	if strings.Join(f.restarted, ",") != "rest,worker,app" {
		t.Fatalf("restarted %v", f.restarted)
	}
	for _, want := range []string{"older passwords for authenticator", "All services are running."} {
		if !strings.Contains(out, want) {
			t.Fatalf("output lacks %q:\n%s", want, out)
		}
	}
}

// STATBUS-407: with a surviving DB volume and newly generated credentials,
// rest crash-loops and does not publish its port until its DB role is repaired.
// Pin the production action's ordering, not just this fixture's final state.
func TestRunStartServicesSyncsPasswordsBeforePublishedPorts(t *testing.T) {
	src, err := os.ReadFile(thisRepoFile(t, "cli/cmd/install_services.go"))
	if err != nil {
		t.Fatal(err)
	}
	body := string(src)
	start := strings.Index(body, "func runStartServices(")
	if start < 0 {
		t.Fatal("cannot find runStartServices")
	}
	end := strings.Index(body[start:], "\n// checkDBHealthy")
	if end < 0 {
		t.Fatal("cannot find runStartServices body")
	}
	fn := body[start : start+end]
	up := strings.Index(fn, "composeUpAll(dir)")
	health := strings.Index(fn, "waitForInstallDBHealth(dir,")
	sync := strings.Index(fn, "syncRolePasswords(dir)")
	restart := strings.Index(fn, "restartPasswordClients(dir, passwordClients)")
	ports := strings.Index(fn, "reconcilePublishedPorts(dir)")
	ready := strings.Index(fn, "waitForServicesRunning(dir,")
	if up < 0 || health <= up || sync <= health || restart <= sync || ports <= restart || ready <= ports {
		t.Fatalf("step 8 order must be compose up -> DB health -> password sync -> client restart -> port reconciliation -> service readiness; offsets up=%d health=%d sync=%d restart=%d ports=%d ready=%d", up, health, sync, restart, ports, ready)
	}
}

func TestRunStartServicesOrphanedVolumeRepairsBeforePortProbe(t *testing.T) {
	dir := dbHealthyDir(t)
	f := &fakeStack{
		statuses: []serviceStatus{running("db"), {Service: "rest", State: "restarting"}},
		onUp: func(f *fakeStack) {
			f.statuses = []serviceStatus{running("app"), running("db"), running("proxy"),
				{Service: "rest", State: "restarting"}, running("worker")}
		},
	}
	installFakeStack(t, f)
	configuredServicePorts = func(string) (map[string][]configuredPort, error) {
		if !f.passwordsAgree {
			return nil, errors.New("authenticator is still using the old password; rest port absent")
		}
		return map[string][]configuredPort{}, nil
	}
	if err := runStartServices(dir); err != nil {
		t.Fatalf("orphaned volume should be repaired before port inspection: %v", err)
	}
	if f.syncCalls != 1 || !f.passwordsAgree {
		t.Fatalf("role passwords were not reconciled: %+v", f)
	}
}

func TestRunStartServicesNamesTheServiceThatDoesNotStart(t *testing.T) {
	dir := dbHealthyDir(t)
	f := &fakeStack{
		passwordsAgree: true,
		upErr:          errors.New("exit status 1"),
		onUp: func(f *fakeStack) {
			f.statuses = []serviceStatus{running("app"), running("db"),
				{Service: "proxy", State: "created"}, running("rest"), running("worker")}
		},
	}
	installFakeStack(t, f)
	withShortServiceBudgets(t)
	var err error
	captureStdout(t, func() { err = runStartServices(dir) })
	if err == nil || !strings.Contains(err.Error(), "the web server (proxy) was created but could not start") {
		t.Fatalf("err = %v", err)
	}
	if len(f.restarted) != 0 {
		t.Fatalf("no password changed, nothing should restart: %v", f.restarted)
	}
}

func TestStartEarlyFailuresPrintSixServiceInventory(t *testing.T) {
	for _, failure := range []string{"ports", "database", "passwords"} {
		t.Run(failure, func(t *testing.T) {
			f := &fakeStack{statuses: []serviceStatus{running("db"), {Service: "proxy", State: "restarting"}, {Service: "rest", State: "exited"}, {Service: "app", State: "stopped"}}, passwordsAgree: true}
			installFakeStack(t, f)
			oldUnit := upgradeUnitState
			upgradeUnitState = func() string { return "inactive" }
			t.Cleanup(func() { upgradeUnitState = oldUnit })
			if failure == "ports" {
				configuredServicePorts = func(string) (map[string][]configuredPort, error) { return nil, errors.New("ports unavailable") }
				oldHealth := checkDBHealthyFn
				checkDBHealthyFn = func(string) bool { return true }
				t.Cleanup(func() { checkDBHealthyFn = oldHealth })
			}
			if failure == "database" {
				old := checkDBHealthyFn
				checkDBHealthyFn = func(string) bool { return false }
				t.Cleanup(func() { checkDBHealthyFn = old })
				oldBudget := servicesDBHealthyBudget
				servicesDBHealthyBudget = 0
				t.Cleanup(func() { servicesDBHealthyBudget = oldBudget })
			}
			if failure == "passwords" {
				old := syncRolePasswords
				syncRolePasswords = func(string) ([]dbroles.Mismatch, error) { return nil, errors.New("sync unavailable") }
				t.Cleanup(func() { syncRolePasswords = old })
				oldHealth := checkDBHealthyFn
				checkDBHealthyFn = func(string) bool { return true }
				t.Cleanup(func() { checkDBHealthyFn = oldHealth })
			}
			var err error
			out := captureStdout(t, func() { err = runStartServices(t.TempDir()) })
			if err == nil {
				t.Fatal("expected early failure")
			}
			for _, line := range []string{"the database (db): running (healthy)", "the web server (proxy): restarting", "the API service (rest): exited", "the web app (app): stopped", "the background worker (worker): absent", "the automatic update service (upgrade): inactive"} {
				if !strings.Contains(out, line) {
					t.Fatalf("missing %q in %s", line, out)
				}
			}
		})
	}
}

func TestVerifyInstallServing(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, ".env"), []byte("REST_ADMIN_BIND_ADDRESS=127.0.0.1:3016\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	allUp := []serviceStatus{running("app"), running("db"), running("proxy"), running("rest"), running("worker")}

	t.Run("ready", func(t *testing.T) {
		f := &fakeStack{statuses: allUp, readyStatus: http.StatusOK}
		installFakeStack(t, f)
		var err error
		out := captureStdout(t, func() { err = verifyInstallServing(dir, 0, time.Millisecond) })
		if err != nil || !strings.Contains(out, "API is ready") {
			t.Fatalf("err=%v out=%s", err, out)
		}
	})
	t.Run("rest running but schema cache not loaded", func(t *testing.T) {
		f := &fakeStack{statuses: allUp, readyStatus: http.StatusServiceUnavailable}
		installFakeStack(t, f)
		var err error
		captureStdout(t, func() { err = verifyInstallServing(dir, 0, time.Millisecond) })
		if err == nil || !strings.Contains(err.Error(), "the API service (rest) is running but answered 503") {
			t.Fatalf("err = %v", err)
		}
	})
	t.Run("rest restarting and worker stopped", func(t *testing.T) {
		f := &fakeStack{statuses: []serviceStatus{running("app"), running("db"), running("proxy"),
			{Service: "rest", State: "restarting"}, {Service: "worker", State: "exited"}}}
		installFakeStack(t, f)
		var tailed []string
		serviceLogTail = func(_ string, s string) { tailed = append(tailed, s) }
		var err error
		captureStdout(t, func() { err = verifyInstallServing(dir, 0, time.Millisecond) })
		if err == nil || !strings.Contains(err.Error(), "the API service (rest) keeps restarting; the background worker (worker) has stopped") {
			t.Fatalf("err = %v", err)
		}
		if strings.Join(tailed, ",") != "rest,worker" {
			t.Fatalf("log tails for %v", tailed)
		}
	})
}

func TestRestartingClientsReportOwnLogsAfterBoundedReadiness(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, ".env"), []byte("REST_ADMIN_BIND_ADDRESS=127.0.0.1:3016\n"), 0600); err != nil {
		t.Fatal(err)
	}
	for _, service := range []string{"rest", "app", "worker", "proxy"} {
		t.Run(service, func(t *testing.T) {
			statuses := []serviceStatus{running("app"), running("db"), running("proxy"), running("rest"), running("worker")}
			for i := range statuses {
				if statuses[i].Service == service {
					statuses[i].State = "restarting"
				}
			}
			installFakeStack(t, &fakeStack{statuses: statuses, readyStatus: http.StatusOK})
			var tailed []string
			serviceLogTail = func(_ string, name string) { tailed = append(tailed, name) }
			var err error
			out := captureStdout(t, func() { err = verifyInstallServing(dir, 0, time.Millisecond) })
			if err == nil || !strings.Contains(out, servicePlainName(service)+" keeps restarting; its recent logs are in the install log.") {
				t.Fatalf("service=%s err=%v output=%s", service, err, out)
			}
			if strings.Join(tailed, ",") != service {
				t.Fatalf("wrong service logs: %v", tailed)
			}
		})
	}
}

// dbHealthyDir is a project dir whose db healthcheck the fakes report healthy.
// waitForInstallDBHealth goes through checkDBHealthy (a real docker call), so
// the test swaps it for the stack's view.
func dbHealthyDir(t *testing.T) string {
	t.Helper()
	old := checkDBHealthyFn
	t.Cleanup(func() { checkDBHealthyFn = old })
	checkDBHealthyFn = func(string) bool { return true }
	return t.TempDir()
}

func withShortServiceBudgets(t *testing.T) {
	t.Helper()
	old := servicesRunningBudgetVar
	t.Cleanup(func() { servicesRunningBudgetVar = old })
	servicesRunningBudgetVar = 10 * time.Millisecond
}

func captureStdout(t *testing.T, fn func()) string {
	t.Helper()
	r, w, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	orig := os.Stdout
	os.Stdout = w
	done := make(chan string)
	go func() {
		var b strings.Builder
		buf := make([]byte, 4096)
		for {
			n, err := r.Read(buf)
			b.Write(buf[:n])
			if err != nil {
				break
			}
		}
		done <- b.String()
	}()
	defer func() { os.Stdout = orig }()
	fn()
	_ = w.Close()
	os.Stdout = orig
	return fmt.Sprint(<-done)
}

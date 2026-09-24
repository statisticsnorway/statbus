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

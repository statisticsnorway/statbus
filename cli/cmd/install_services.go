package cmd

// Step 8 "Services" and the final check before "Installation complete".
//
// Step 8 used to be done as soon as the db container was healthy. A proxy that
// failed to start (Finland: Apache held port 80), or a rest container
// restart-looping on a stale password, was then reported "OK" on every rerun
// and surfaced three steps later as a raw dial error (audit B1, B10). Now the
// step is done only when every service in the `all` profile is running, the
// database is healthy, and the database's role passwords equal .env. The final
// check confirms PostgREST's admin /ready answers 200.

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/statisticsnorway/statbus/cli/internal/compose"
	"github.com/statisticsnorway/statbus/cli/internal/dbroles"
	"github.com/statisticsnorway/statbus/cli/internal/dotenv"
	"github.com/statisticsnorway/statbus/cli/internal/upgrade"
)

var failedPublishedPort = regexp.MustCompile(`could not publish host port ([0-9]+)/`)

func servicePortConflictCause(err error) string {
	match := failedPublishedPort.FindStringSubmatch(err.Error())
	if len(match) != 2 {
		return ""
	}
	port, _ := strconv.Atoi(match[1])
	owner := occupiedPortOwner(installPort{"0.0.0.0", port})
	if owner == "" {
		owner = "another program"
	}
	return portConflictGuidance(port, owner)
}

// servicePlainNames are the words the operator sees for each compose service.
var servicePlainNames = map[string]string{
	"db":     "the database (db)",
	"proxy":  "the web server (proxy)",
	"rest":   "the API service (rest)",
	"app":    "the web app (app)",
	"worker": "the background worker (worker)",
}

func servicePlainName(service string) string {
	if n, ok := servicePlainNames[service]; ok {
		return n
	}
	return "the " + service + " service"
}

// serviceStatus is one row of `docker compose ps -a --format json`.
type serviceStatus struct {
	Service    string          `json:"Service"`
	State      string          `json:"State"`
	Health     string          `json:"Health"`
	Publishers []publishedPort `json:"Publishers"`
}

type publishedPort struct {
	URL           string `json:"URL"`
	TargetPort    int    `json:"TargetPort"`
	PublishedPort int    `json:"PublishedPort"`
	Protocol      string `json:"Protocol"`
}

type configuredPort struct {
	HostIP    string `json:"host_ip"`
	Target    int    `json:"target"`
	Published string `json:"published"`
	Protocol  string `json:"protocol"`
}

// Config's ports are the authority, not a fixed list of development ports.
var configuredServicePorts = func(dir string) (map[string][]configuredPort, error) {
	cmd, err := compose.CommandContext(context.Background(), dir, "--profile", "all", "config", "--format", "json")
	if err != nil {
		return nil, err
	}
	out, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("read docker compose port configuration: %w", err)
	}
	var config struct {
		Services map[string]struct {
			Ports []configuredPort `json:"ports"`
		} `json:"services"`
	}
	if err := json.Unmarshal(out, &config); err != nil {
		return nil, fmt.Errorf("parse docker compose port configuration: %w", err)
	}
	if len(config.Services) == 0 {
		return nil, fmt.Errorf("docker compose port configuration has no services")
	}
	ports := make(map[string][]configuredPort, len(config.Services))
	for service, entry := range config.Services {
		ports[service] = entry.Ports
	}
	return ports, nil
}

func missingPublishedPorts(statuses []serviceStatus, configured map[string][]configuredPort) map[string][]configuredPort {
	missing := make(map[string][]configuredPort)
	for _, status := range statuses {
		for _, expected := range configured[status.Service] {
			found := false
			for _, actual := range status.Publishers {
				protocol := expected.Protocol
				if protocol == "" {
					protocol = "tcp"
				}
				// Compose reports the host IP as URL, including 0.0.0.0 for a wildcard.
				if fmt.Sprint(actual.PublishedPort) == expected.Published && actual.TargetPort == expected.Target &&
					actual.Protocol == protocol && (expected.HostIP == "" || actual.URL == expected.HostIP) {
					found = true
					break
				}
			}
			if !found {
				missing[status.Service] = append(missing[status.Service], expected)
			}
		}
	}
	return missing
}

// Give a port-conflict error the host listener, rather than just an exit code.
func portListener(port configuredPort) string {
	// The installer user may not see another user's process without sudo.
	out, err := exec.Command("sudo", "-n", "ss", "-ltnup").Output()
	if err != nil {
		out, err = exec.Command("ss", "-ltnup").Output()
	}
	if err != nil {
		return "listener unavailable (run ss -ltnup as root)"
	}
	for _, line := range strings.Split(string(out), "\n") {
		fields := strings.Fields(line)
		if len(fields) >= 5 && strings.HasSuffix(fields[4], ":"+port.Published) &&
			(port.Protocol == "" || strings.EqualFold(fields[0], port.Protocol)) {
			return strings.TrimSpace(line)
		}
	}
	return "no host listener found by ss -ltnup"
}

var recreateServiceWithPorts = func(dir, service string) error {
	cmd, err := compose.Up(context.Background(), dir, "--profile", "all", "-d", "--force-recreate", "--no-deps", service)
	if err != nil {
		return err
	}
	out, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("%w: %s", err, strings.TrimSpace(string(out)))
	}
	return nil
}

func reconcilePublishedPorts(dir string) error {
	configured, err := configuredServicePorts(dir)
	if err != nil {
		return err
	}
	statuses, err := probeServiceStatuses(dir)
	if err != nil {
		return err
	}
	missing := missingPublishedPorts(statuses, configured)
	services := make([]string, 0, len(missing))
	for service := range missing {
		services = append(services, service)
	}
	sort.Strings(services)
	for _, service := range services {
		fmt.Printf("  %s has missing published ports; recreating it ...\n", servicePlainName(service))
		if err := recreateServiceWithPorts(dir, service); err != nil {
			port := missing[service][0]
			listener := ""
			for _, candidate := range missing[service] {
				if owner := portListener(candidate); !strings.HasPrefix(owner, "no host listener") {
					port, listener = candidate, owner
					break
				}
			}
			if listener == "" {
				listener = portListener(port)
			}
			return fmt.Errorf("%s could not publish host port %s/%s; port listener: %s: %w", servicePlainName(service), port.Published, port.Protocol, listener, err)
		}
	}
	statuses, err = probeServiceStatuses(dir)
	if err != nil {
		return err
	}
	for service, ports := range missingPublishedPorts(statuses, configured) {
		return fmt.Errorf("%s is still missing published host port %s/%s after recreation; port listener: %s", servicePlainName(service), ports[0].Published, ports[0].Protocol, portListener(ports[0]))
	}
	return nil
}

func parseServiceStatuses(out []byte) ([]serviceStatus, error) {
	trimmed := strings.TrimSpace(string(out))
	if trimmed == "" {
		return nil, nil
	}
	if strings.HasPrefix(trimmed, "[") {
		var arr []serviceStatus
		if err := json.Unmarshal([]byte(trimmed), &arr); err != nil {
			return nil, fmt.Errorf("parse docker compose ps json: %w", err)
		}
		return arr, nil
	}
	var res []serviceStatus
	for _, line := range strings.Split(trimmed, "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		var s serviceStatus
		if err := json.Unmarshal([]byte(line), &s); err != nil {
			return nil, fmt.Errorf("parse docker compose ps json line: %w", err)
		}
		res = append(res, s)
	}
	return res, nil
}

// serviceProblem is one required service that is not serving.
type serviceProblem struct {
	Service string
	State   string // "missing", "restarting", "exited", "created", "starting", "unhealthy", ...
}

func (p serviceProblem) plain() string {
	name := servicePlainName(p.Service)
	switch p.State {
	case "missing":
		return name + " was never started"
	case "restarting":
		return name + " keeps restarting"
	case "starting":
		return name + " is still starting"
	case "unhealthy":
		return name + " is running but reports unhealthy"
	case "exited", "dead":
		return name + " has stopped"
	case "created":
		return name + " was created but could not start"
	default:
		return name + " is " + p.State
	}
}

// servicesNotRunning is the pure verdict for step 8: every required service
// must have a running container, and db must also be healthy (its healthcheck
// is pg_isready). "restarting" is never running. Sorted by required order.
func servicesNotRunning(required []string, statuses []serviceStatus) []serviceProblem {
	byService := make(map[string]serviceStatus, len(statuses))
	for _, s := range statuses {
		// With several containers for one service, a running one wins.
		if prev, ok := byService[s.Service]; ok && prev.State == "running" {
			continue
		}
		byService[s.Service] = s
	}
	var problems []serviceProblem
	for _, svc := range required {
		s, ok := byService[svc]
		switch {
		case !ok:
			problems = append(problems, serviceProblem{svc, "missing"})
		case s.State != "running":
			problems = append(problems, serviceProblem{svc, s.State})
		case svc == "db" && s.Health != "healthy":
			state := s.Health
			if state == "" {
				state = "starting"
			}
			problems = append(problems, serviceProblem{svc, state})
		}
	}
	return problems
}

func describeServiceProblems(problems []serviceProblem) string {
	parts := make([]string, 0, len(problems))
	for _, p := range problems {
		parts = append(parts, p.plain())
	}
	return strings.Join(parts, "; ")
}

// requiredServices lists the services of the `all` profile, the set every
// deployment mode runs (runStartServices starts exactly this profile).
var requiredServices = func(dir string) ([]string, error) {
	cmd, err := compose.CommandContext(context.Background(), dir, "--profile", "all", "config", "--services")
	if err != nil {
		return nil, err
	}
	out, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("list services: %w", err)
	}
	services := strings.Fields(string(out))
	if len(services) == 0 {
		return nil, fmt.Errorf("docker compose lists no services for the all profile")
	}
	sort.Strings(services)
	return services, nil
}

var probeServiceStatuses = func(dir string) ([]serviceStatus, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	cmd, err := compose.CommandContext(ctx, dir, "--profile", "all", "ps", "-a", "--format", "json")
	if err != nil {
		return nil, err
	}
	out, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("docker compose ps: %w", err)
	}
	return parseServiceStatuses(out)
}

// currentServiceProblems returns the services not serving right now.
func currentServiceProblems(dir string) ([]serviceProblem, error) {
	required, err := requiredServices(dir)
	if err != nil {
		return nil, err
	}
	statuses, err := probeServiceStatuses(dir)
	if err != nil {
		return nil, err
	}
	problems := servicesNotRunning(required, statuses)
	configured, err := configuredServicePorts(dir)
	if err != nil {
		return nil, err
	}
	missing := missingPublishedPorts(statuses, configured)
	for _, service := range required {
		if len(missing[service]) > 0 {
			problems = append(problems, serviceProblem{service, "missing published ports"})
		}
	}
	return problems, nil
}

// rolePasswordsAgree is a seam over dbroles.CheckProject.
var rolePasswordsAgree = func(dir string) (bool, error) {
	mismatches, err := dbroles.CheckProject(context.Background(), dir)
	if err != nil {
		return false, err
	}
	return len(mismatches) == 0, nil
}

// checkServicesDone is step 8's check: every service running, db healthy, and
// the database role passwords equal to .env.
func checkServicesDone(dir string) bool {
	problems, err := currentServiceProblems(dir)
	if err != nil || len(problems) > 0 {
		return false
	}
	agree, err := rolePasswordsAgree(dir)
	return err == nil && agree
}

// syncRolePasswords is a seam over dbroles.SyncProject.
var syncRolePasswords = func(dir string) ([]dbroles.Mismatch, error) {
	return dbroles.SyncProject(context.Background(), dir)
}

// restartPasswordClients is a seam over `docker compose restart <services>`.
var restartPasswordClients = func(dir string, services []string) error {
	if len(services) == 0 {
		return nil
	}
	cmd, err := compose.CommandContext(context.Background(), dir, append([]string{"restart"}, services...)...)
	if err != nil {
		return err
	}
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

// composeUpAllDefault runs `docker compose --profile all up -d`. Held behind
// the composeUpAll seam (the composeApplyServiceDefault pattern) so tests can
// drive runStartServices without a docker daemon.
func composeUpAllDefault(dir string) error {
	cmd, err := compose.Up(context.Background(), dir, "--profile", "all", "-d")
	if err != nil {
		return err
	}
	return runInstallCommandWithDiagnostic(cmd)
}

var composeUpAll = composeUpAllDefault

// passwordClients are the services that log in with a role password.
var passwordClients = []string{"rest", "worker", "app"}

const (
	servicesDBHealthyBudget = 2 * time.Minute
	servicesPollInterval    = 2 * time.Second
)

// servicesRunningBudgetVar bounds how long step 8 waits for every service to
// be running after `up`. A var so tests can shorten it.
var servicesRunningBudgetVar = 90 * time.Second

// waitForServicesRunning polls until no service has a problem or the budget is
// spent. It returns the last problems seen.
func waitForServicesRunning(dir string, budget, interval time.Duration) ([]serviceProblem, error) {
	deadline := time.Now().Add(budget)
	for {
		problems, err := currentServiceProblems(dir)
		if err == nil && len(problems) == 0 {
			return nil, nil
		}
		if time.Now().After(deadline) {
			return problems, err
		}
		time.Sleep(interval)
	}
}

// runStartServices is step 8's action. `up -d` is idempotent: it creates what
// is missing, recreates what changed and leaves the rest alone. Then the role
// passwords are made equal to .env over the db container's local socket, the
// clients that log in with them are restarted if any changed, and the step
// waits until every service is running, naming any that is not.
func runStartServices(dir string) error {
	fmt.Println("  Starting every service: database, web server, API, web app, background worker ...")
	upErr := composeUpAll(dir)
	if err := reconcilePublishedPorts(dir); err != nil {
		return err
	}

	if !waitForInstallDBHealth(dir, time.Now().Add(servicesDBHealthyBudget), servicesPollInterval) {
		if upErr != nil {
			return fmt.Errorf("the database did not start: %w", upErr)
		}
		return fmt.Errorf("the database did not become ready within %s", servicesDBHealthyBudget)
	}

	changed, err := syncRolePasswords(dir)
	if err != nil {
		return fmt.Errorf("could not make the database passwords match .env.credentials: %w", err)
	}
	if len(changed) > 0 {
		fmt.Printf("  The database held older passwords for %s; they now match .env.credentials.\n", dbroles.RoleNames(changed))
		if err := restartPasswordClients(dir, passwordClients); err != nil {
			fmt.Printf("  Restarting the services that use those passwords did not finish cleanly: %v\n", err)
		}
	}

	problems, probeErr := waitForServicesRunning(dir, servicesRunningBudgetVar, servicesPollInterval)
	if len(problems) > 0 {
		msg := "not every service is running: " + describeServiceProblems(problems)
		if upErr != nil {
			return fmt.Errorf("%s (starting them reported: %v)", msg, upErr)
		}
		return fmt.Errorf("%s", msg)
	}
	if probeErr != nil {
		return fmt.Errorf("could not confirm the services are running: %w", probeErr)
	}
	if upErr != nil {
		// Every service is running now (for example a transient pull or
		// dependency race during up); the goal of the step is met.
		fmt.Printf("  Starting reported %v, but every service is running now.\n", upErr)
	}
	fmt.Println("  All services are running.")
	return nil
}

// checkDBHealthy is the database-only readiness predicate: the db container's
// healthcheck (pg_isready) reports healthy. Used where only the database is
// needed (pre-detect session cleanup, the Seed probe, health waits).
func checkDBHealthy(dir string) bool { return checkDBHealthyFn(dir) }

// The daemon connects to the app database through the host's Caddy TCP port,
// not the container socket used by the earlier install steps. Probe that same
// authenticated route before systemctl enable --now can block for 120 seconds.
var probeUpgradeDatabaseRoute = func(dir string) error {
	return upgrade.NewService(dir, false, "", "").EnsureDBReachable(context.Background())
}

func checkUpgradeDatabaseRoute(dir string) error {
	err := probeUpgradeDatabaseRoute(dir)
	if err == nil {
		return nil
	}
	if !checkDBHealthy(dir) {
		return fmt.Errorf("the database (db) is not healthy; the upgrade service cannot reach it: %w", err)
	}
	if errors.Is(err, syscall.ECONNREFUSED) {
		return fmt.Errorf("the web server (proxy) is not listening on the database port; the upgrade service cannot reach the database: %w", err)
	}
	return fmt.Errorf("the upgrade service cannot reach the database through the web server (proxy); check the database route and login credentials: %w", err)
}

// checkDBHealthyFn is the seam behind checkDBHealthy.
var checkDBHealthyFn = checkDBHealthyDocker

func checkDBHealthyDocker(dir string) bool {
	// Use positional service name `db` rather than `--filter name=db`. The
	// `--filter` flag's `name=` key is rejected by docker-compose v2.x as
	// "unknown filter name" — observed on rune.statbus.org (statbus-no-db
	// container, docker-compose Plugin 2025+). Positional service-name is
	// the supported invocation; the legacy filter-style only worked on
	// older lenient builds that silently accepted unknown filters.
	cmd, buildErr := compose.CommandContext(context.Background(), dir, "ps", "db", "--format", "{{.Health}}")
	if buildErr != nil {
		return false
	}
	out, err := cmd.Output()
	if err != nil {
		return false
	}
	health, err := classifyDockerHealth(string(out))
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: refusing to treat database service as ready: %v\n", err)
		return false
	}
	return health.ready()
}

// restReadyURL is PostgREST's admin /ready on the loopback admin port
// (REST_ADMIN_BIND_ADDRESS, base port + 6).
func restReadyURL(dir string) (string, error) {
	f, err := dotenv.Load(filepath.Join(dir, ".env"))
	if err != nil {
		return "", err
	}
	bind, ok := f.Get("REST_ADMIN_BIND_ADDRESS")
	bind = strings.TrimSpace(bind)
	if !ok || bind == "" {
		return "", fmt.Errorf("REST_ADMIN_BIND_ADDRESS is not set in .env")
	}
	return "http://" + bind + "/ready", nil
}

// restReadyStatus is a seam: the HTTP status of rest's /ready, or an error.
var restReadyStatus = func(url string) (int, error) {
	client := &http.Client{Timeout: 5 * time.Second}
	resp, err := client.Get(url)
	if err != nil {
		return 0, err
	}
	_ = resp.Body.Close()
	return resp.StatusCode, nil
}

// serviceLogTail prints the last lines of a service's log into the install
// output (which the install log captures), so support has it without asking.
var serviceLogTail = func(dir, service string) {
	cmd, err := compose.CommandContext(context.Background(), dir, "logs", "--no-color", "--tail", "30", service)
	if err != nil {
		return
	}
	out, _ := cmd.CombinedOutput()
	if len(out) == 0 {
		return
	}
	fmt.Printf("  Last lines from %s:\n", servicePlainName(service))
	for _, line := range strings.Split(strings.TrimRight(string(out), "\n"), "\n") {
		fmt.Printf("    %s\n", line)
	}
}

const (
	finalCheckBudget   = 2 * time.Minute
	finalCheckInterval = 2 * time.Second
)

// verifyInstallServing is the last check before "Installation complete":
// every service is running and the API answers /ready with 200. On failure it
// names each service that is not serving in plain words and copies its recent
// log into the install output.
func verifyInstallServing(dir string, budget, interval time.Duration) error {
	url, err := restReadyURL(dir)
	if err != nil {
		return fmt.Errorf("cannot check the API service: %w", err)
	}
	deadline := time.Now().Add(budget)
	var (
		problems []serviceProblem
		probeErr error
		status   int
		readyErr error
	)
	for {
		problems, probeErr = currentServiceProblems(dir)
		status, readyErr = restReadyStatus(url)
		if probeErr == nil && len(problems) == 0 && readyErr == nil && status == http.StatusOK {
			fmt.Println("All services are running and the API is ready.")
			return nil
		}
		if time.Now().After(deadline) {
			break
		}
		time.Sleep(interval)
	}

	var reasons []string
	failing := map[string]bool{}
	for _, p := range problems {
		reasons = append(reasons, p.plain())
		failing[p.Service] = true
	}
	if probeErr != nil {
		reasons = append(reasons, "the service list could not be read ("+probeErr.Error()+")")
	}
	if !failing["rest"] && (readyErr != nil || status != http.StatusOK) {
		detail := fmt.Sprintf("answered %d", status)
		if readyErr != nil {
			detail = "did not answer"
		}
		reasons = append(reasons, fmt.Sprintf("the API service (rest) is running but %s when asked whether it is ready", detail))
		failing["rest"] = true
	}
	services := make([]string, 0, len(failing))
	for s := range failing {
		services = append(services, s)
	}
	sort.Strings(services)
	for _, s := range services {
		serviceLogTail(dir, s)
	}
	return fmt.Errorf("the installation is not serving yet: %s", strings.Join(reasons, "; "))
}

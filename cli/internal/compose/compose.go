// Package compose wraps docker compose commands.
package compose

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"strings"
	"time"

	"github.com/statisticsnorway/statbus/cli/internal/config"
)

// Run executes a docker compose command with the given args.
// Inherits stdin/stdout/stderr for interactive use.
func Run(args ...string) error {
	cmd := exec.Command("docker", append([]string{"compose"}, args...)...)
	cmd.Dir = config.ProjectDir()
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

// RunWithProfile executes docker compose with a --profile flag.
func RunWithProfile(profile string, args ...string) error {
	fullArgs := append([]string{"compose", "--profile", profile}, args...)
	cmd := exec.Command("docker", fullArgs...)
	cmd.Dir = config.ProjectDir()
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

// Start brings up services. In development mode, uses --build.
// profile is one of: "all", "all_except_app", "app", or a service name.
func Start(profile string, build bool) error {
	args := []string{"up", "-d"}
	if build {
		args = append(args, "--build")
	}

	// "app" is a service name, not a profile
	if profile == "app" {
		return Run(append(args, "app")...)
	}
	return RunWithProfile(profile, args...)
}

// Stop brings down services.
func Stop(profile string) error {
	args := []string{"down", "--remove-orphans"}
	if profile == "app" {
		return Run(append(args, "app")...)
	}
	return RunWithProfile(profile, args...)
}

// Restart stops then starts services.
func Restart(profile string, build bool) error {
	if err := Stop(profile); err != nil {
		return fmt.Errorf("stop: %w", err)
	}
	return Start(profile, build)
}

// Ps shows running containers.
func Ps() error {
	return Run("ps")
}

// Logs follows logs for all services (or specific ones).
func Logs(services ...string) error {
	args := []string{"logs", "--follow"}
	args = append(args, services...)
	return Run(args...)
}

// Pull pulls images for all services.
func Pull(profile string) error {
	if profile == "" {
		return Run("pull")
	}
	return RunWithProfile(profile, "pull")
}

// Build builds images for all services.
// Profile is required (services are gated behind profiles).
func Build(profile string) error {
	if profile == "" {
		profile = "all"
	}
	return RunWithProfile(profile, "build")
}

// clientServices is the set of containers that act as long-running clients
// of the application database — they hold AccessShareLock on user-data
// tables whenever a query runs. db / proxy / caddy are infrastructure
// and stay up during DDL phases (db is the target; proxy + caddy can
// keep serving maintenance views).
var clientServices = []string{"worker", "app", "rest"}

// QuiesceClients stops worker / app / rest containers in projDir if they
// are currently running, and returns the list of services it actually
// stopped. ResumeClients takes that list back to restart exactly those.
//
// Rationale: install.go's Seed + Migrations steps and applyNewSbUpgrading's
// migrate-up step issue DDL that needs AccessExclusiveLock on tables a
// running worker (or app / rest under load) reads with AccessShareLock.
// Postgres lock manager parks the DDL indefinitely behind the client's
// lock — the R1 deadlock that wedged tcc. Quiescing the clients across
// the DDL window removes the contender; resuming after restores
// service. db / proxy / caddy keep running throughout — db is the DDL
// target, proxy + caddy don't touch the application schema.
//
// Idempotent: probes each client's running state via
// `docker compose ps <svc> --format {{.State}}` and stops only those
// reported running. The returned slice is the precise set Resume will
// restart, so callers can chain Quiesce / DDL / Resume without leaking
// state when the precondition (services were running) didn't hold.
//
// Failure mode: any docker error during a stop is propagated to the
// caller. The caller decides whether to fail-loud (install must not
// proceed with DDL on live services) or log-and-continue (the DDL
// already ran — we're in a degraded resume path).
func QuiesceClients(projDir string) ([]string, error) {
	var stopped []string
	for _, svc := range clientServices {
		state, err := probeServiceState(projDir, svc)
		if err != nil {
			return stopped, fmt.Errorf("probe %s: %w", svc, err)
		}
		if !state.running {
			continue
		}
		cmd := exec.Command("docker", "compose", "stop", svc)
		cmd.Dir = projDir
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		if err := cmd.Run(); err != nil {
			return stopped, fmt.Errorf("docker compose stop %s: %w", svc, err)
		}
		stopped = append(stopped, svc)
	}
	return stopped, nil
}

// ResumeClients starts the named services in projDir. Pairs with the
// slice returned by QuiesceClients — pass it back verbatim so we
// restart exactly the set we stopped (idempotent: passing an empty
// slice is a no-op, useful when Quiesce had nothing to stop).
//
// Uses --no-build so we run the registry image (the local Dockerfile
// is for development builds; production VMs pull the tagged image at
// step 7 / Images). Containers that are NOT in the slice are left
// alone, including ones already up — Resume is additive, not
// authoritative.
func ResumeClients(projDir string, services []string) error {
	if len(services) == 0 {
		return nil
	}
	args := append([]string{"compose", "up", "-d", "--no-build"}, services...)
	cmd := exec.Command("docker", args...)
	cmd.Dir = projDir
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("docker compose up %v: %w", services, err)
	}
	return nil
}

// PsEntry mirrors the fields of `docker compose ps --format json` we care
// about. The JSON keys are upper-camel as Compose v2 emits them.
type PsEntry struct {
	Service string `json:"Service"`
	State   string `json:"State"`
	Image   string `json:"Image"`
}

// ParsePsJSON tolerates both forms of `docker compose ps --format json`:
//   - Compose v2 NDJSON: one entry per line.
//   - Older Compose: a single JSON array.
//
// Empty/whitespace input → empty slice, no error (matches `ps` on an empty
// project).
func ParsePsJSON(out []byte) ([]PsEntry, error) {
	trimmed := bytes.TrimSpace(out)
	if len(trimmed) == 0 {
		return nil, nil
	}
	if trimmed[0] == '[' {
		var arr []PsEntry
		if err := json.Unmarshal(trimmed, &arr); err != nil {
			return nil, fmt.Errorf("parse docker compose ps json array: %w", err)
		}
		return arr, nil
	}
	// NDJSON path. Iterate line-by-line — robust against trailing whitespace
	// and embedded blank lines.
	var entries []PsEntry
	for _, line := range bytes.Split(trimmed, []byte("\n")) {
		line = bytes.TrimSpace(line)
		if len(line) == 0 {
			continue
		}
		var entry PsEntry
		if err := json.Unmarshal(line, &entry); err != nil {
			return nil, fmt.Errorf("parse docker compose ps json line %q: %w", string(line), err)
		}
		entries = append(entries, entry)
	}
	return entries, nil
}

// stoppedStates is the allow-list VerifyStopped checks a service's
// docker-compose-reported state against. Fail-closed by design: this
// guards the pre-restore boundary (rsyncing a database volume out from
// under a still-live postgres is a torn-restore data-corruption pathway),
// so only states docker itself uses to mean "definitely not running"
// pass. "restarting" (a restart policy fighting the stop), "paused"
// (still holds the volume open), and any future/unrecognized docker
// state all fail.
var stoppedStates = map[string]bool{
	"exited":  true,
	"created": true,
	"dead":    true,
}

// notStoppedFrom returns every entry of services whose state per statuses
// is not in stoppedStates, formatted as "service (state)". A service
// absent from statuses entirely counts as stopped. Pure — no I/O — so the
// allow-list classification is unit-testable against fake ps output
// without shelling out to docker.
func notStoppedFrom(statuses []PsEntry, services []string) []string {
	observed := make(map[string]string, len(statuses))
	for _, s := range statuses {
		observed[s.Service] = s.State
	}
	var notStopped []string
	for _, svc := range services {
		state, present := observed[svc]
		if !present || stoppedStates[state] {
			continue
		}
		notStopped = append(notStopped, fmt.Sprintf("%s (%s)", svc, state))
	}
	return notStopped
}

// verifyStopped is VerifyStopped's core: polls probe() every pollInterval
// up to budget, passing the moment every service in services is confirmed
// stopped (per notStoppedFrom). Separated from VerifyStopped so tests can
// supply a fake probe and a short pollInterval instead of shelling out to
// docker and sleeping in real seconds.
func verifyStopped(probe func() ([]PsEntry, error), services []string, budget, pollInterval time.Duration) error {
	deadline := time.Now().Add(budget)
	for {
		statuses, err := probe()
		if err != nil {
			return fmt.Errorf("verify services stopped before restore: %w", err)
		}
		stillNotStopped := notStoppedFrom(statuses, services)
		if len(stillNotStopped) == 0 {
			return nil
		}
		if time.Now().After(deadline) {
			return fmt.Errorf("refusing to restore the database volume: %s still not stopped after 'docker compose stop' — a volume restore must never run under a live service; investigate `docker compose ps -a` and stop it manually before retrying",
				strings.Join(stillNotStopped, ", "))
		}
		time.Sleep(pollInterval)
	}
}

// VerifyStopped positively confirms every service in services is stopped in
// projDir. STATBUS-187: a `docker compose stop` that exits 0 is not proof
// the named containers are actually down — a slow SIGTERM+timeout grace
// period, a race against a concurrent `docker compose up`, or a docker
// daemon hiccup can all leave a container running after a "successful"
// stop. This guards the boundary immediately before a database volume
// rsync: restoring a volume out from under a still-live postgres is a
// torn-restore data-corruption pathway, not a cosmetic gap.
//
// Bounded re-check: polls `docker compose ps -a` every second up to budget
// before failing, so a normal SIGTERM grace period (compose's default is
// 10s) passes without the caller guessing a fixed sleep. On budget
// exhaustion, fails naming every straggler and its last-observed state.
// Never polls unboundedly — a hung dockerd must reach the caller's
// failure path, not spin forever.
func VerifyStopped(projDir string, services []string, budget time.Duration) error {
	// The probe itself is bounded by the same budget as the poll loop: a
	// hung `docker compose ps` (dead/wedged dockerd) must surface as a
	// probe error once the budget is spent, not block cmd.Output() forever
	// underneath the loop's own deadline check.
	ctx, cancel := context.WithTimeout(context.Background(), budget)
	defer cancel()
	probe := func() ([]PsEntry, error) {
		cmd := exec.CommandContext(ctx, "docker", "compose", "ps", "-a", "--format", "json")
		cmd.Dir = projDir
		out, err := cmd.Output()
		if err != nil {
			return nil, fmt.Errorf("docker compose ps -a: %w", err)
		}
		return ParsePsJSON(out)
	}
	return verifyStopped(probe, services, budget, time.Second)
}

// serviceStateView carries the docker-compose-reported view of one
// service for QuiesceClients to decide whether to stop it.
type serviceStateView struct {
	running bool
}

// probeServiceState probes docker compose ps for <svc>'s state. Returns
// running=false when the service isn't defined OR is not in a running
// state. Errors propagate from docker itself (binary missing, daemon
// down) — those are caller-decides territory.
func probeServiceState(projDir, svc string) (serviceStateView, error) {
	cmd := exec.Command("docker", "compose", "ps", svc, "--format", "{{.State}}")
	cmd.Dir = projDir
	out, err := cmd.Output()
	if err != nil {
		return serviceStateView{}, err
	}
	state := strings.TrimSpace(string(out))
	// docker compose ps emits the service's State on its own line; an
	// undefined service yields empty output. "running" is the value
	// from docker's container state machine that means "alive and
	// serving"; "restarting" or "paused" are not what we're protecting
	// against, so treat anything other than "running" as not-quiesced-
	// worthy.
	return serviceStateView{running: state == "running"}, nil
}

// IsDevelopmentMode checks the CADDY_DEPLOYMENT_MODE from .env.
func IsDevelopmentMode() bool {
	// Quick check via environment first
	if mode := os.Getenv("CADDY_DEPLOYMENT_MODE"); mode != "" {
		return mode == "development"
	}
	// Fall back to reading .env
	envPath := config.ProjectDir() + "/.env"
	if data, err := os.ReadFile(envPath); err == nil {
		for _, line := range strings.Split(string(data), "\n") {
			if strings.HasPrefix(line, "CADDY_DEPLOYMENT_MODE=") {
				return strings.TrimPrefix(line, "CADDY_DEPLOYMENT_MODE=") == "development"
			}
		}
	}
	return true // default to development
}

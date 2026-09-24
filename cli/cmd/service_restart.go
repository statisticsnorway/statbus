package cmd

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"runtime"
	"strings"

	"github.com/statisticsnorway/statbus/cli/internal/compose"
	"github.com/statisticsnorway/statbus/cli/internal/config"
	"github.com/statisticsnorway/statbus/cli/internal/upgrade"
)

// Only OS execution is injectable. Tests exercise the actual shared filesystem
// mutex, so order assertions cannot accidentally replace safety with a stub.
type restartOperations struct {
	systemd   bool
	unit      string
	systemctl func(...string) (string, error)
	stack     func(string) error
}

func restartServices(profile string) error {
	ops := restartOperations{
		systemd: runtime.GOOS == "linux", unit: serviceInstance(config.ProjectDir()),
		systemctl: func(args ...string) (string, error) {
			out, err := exec.Command("systemctl", append([]string{"--user"}, args...)...).CombinedOutput()
			return string(out), err
		},
		stack: func(p string) error {
			if err := compose.Stop(p); err != nil {
				return fmt.Errorf("stop: %w", err)
			}
			args := []string{"-d", "--wait", "--wait-timeout", "120"}
			if compose.IsDevelopmentMode() {
				args = append(args, "--build")
			}
			if p == "app" {
				args = append(args, "app")
			} else {
				args = append([]string{"--profile", p}, args...)
			}
			start, err := compose.Up(context.Background(), config.ProjectDir(), args...)
			if err != nil {
				return err
			}
			start.Stdin = os.Stdin
			start.Stdout = os.Stdout
			start.Stderr = os.Stderr
			return start.Run()
		},
	}
	// Linux development environments without systemd have no host daemon to
	// manage. A present but inaccessible user bus is an error, not an inactive unit.
	if ops.systemd {
		if _, err := exec.LookPath("systemctl"); err != nil {
			ops.systemd = false
		}
	}
	return restartServicesWith(config.ProjectDir(), profile, ops)
}

func restartServicesWith(dir, profile string, ops restartOperations) (result error) {
	switch profile {
	case "all", "all_except_app", "app":
	default:
		return fmt.Errorf("unknown restart profile %q; expected all, all_except_app or app", profile)
	}
	lock, prior, preserveRecoveryMarker, err := upgrade.AcquireRestartFlag(dir, profile)
	if err != nil {
		return err
	}
	// Persist intent before disruption. Failure (or a killed process) leaves
	// a closed restart barrier, retried only by the same operator command.
	prepared := prior != nil
	startDaemon := prior != nil && prior.Daemon
	unit := ops.unit
	if prior != nil {
		unit = prior.Unit
	}
	defer func() {
		// The installed unit is Type=notify: start returns after DB connect and
		// LISTEN readiness, BEFORE recovery. Keep the mutex across that boundary.
		if startDaemon {
			// A unit that hit systemd's start-rate limit (repeated failed
			// starts) refuses every further start until its failed state is
			// cleared. Clear it first so a retried restart converges instead
			// of failing the same way forever. Harmless on a healthy unit.
			if out, err := ops.systemctl("reset-failed", unit); err != nil {
				fmt.Printf("Note: clearing the failed state of %s did not succeed: %v: %s\n", unit, err, strings.TrimSpace(out))
			}
			out, err := ops.systemctl("start", unit)
			if err != nil {
				result = errors.Join(result, fmt.Errorf("start upgrade service %s: %w: %s", unit, err, strings.TrimSpace(out)))
			}
		}
		if preserveRecoveryMarker {
			lock.Close()
		} else if prepared && result != nil {
			lock.Close() // retain restart intent, never expose ordinary repair
			result = errors.Join(result, fmt.Errorf("restart incomplete; fix the reported cause, then retry ./sb restart %s; the restart barrier was retained", profile))
		} else {
			upgrade.ReleaseInstallFlag(lock)
		}
	}()
	if prior == nil && profile != "app" && ops.systemd {
		if ops.unit == "" {
			return fmt.Errorf("cannot determine upgrade-service unit (USER is unset); no services were stopped")
		}
		out, err := ops.systemctl("show", ops.unit, "--property=LoadState", "--property=ActiveState")
		if err != nil {
			return fmt.Errorf("inspect upgrade service %s: %w: %s; no services were stopped", ops.unit, err, strings.TrimSpace(out))
		}
		values := map[string]string{}
		for _, line := range strings.Split(out, "\n") {
			if key, value, ok := strings.Cut(line, "="); ok {
				values[key] = value
			}
		}
		switch values["LoadState"] {
		case "not-found": // no installed daemon on this development box
		case "loaded":
			switch values["ActiveState"] {
			case "active", "activating", "reloading":
				fmt.Printf("Stopping upgrade service %s under the upgrade mutex.\n", ops.unit)
				startDaemon = true
			case "inactive": // intentionally stopped: do not resurrect it
			case "failed":
				// It was meant to run and stopped by failing (for example the
				// start-rate limit). Start it again after the restart; the
				// failed state is cleared right before that start.
				fmt.Printf("Upgrade service %s had failed; it will be started again after the restart.\n", ops.unit)
				startDaemon = true
			default:
				return fmt.Errorf("upgrade service %s has state %q; run ./sb install to repair it before restarting; no services were stopped", ops.unit, values["ActiveState"])
			}
		default:
			return fmt.Errorf("cannot restart with upgrade service %s load state %q; no services were stopped", ops.unit, values["LoadState"])
		}
	}
	if !preserveRecoveryMarker {
		intent := upgrade.RestartIntent{Profile: profile, Unit: unit, Daemon: startDaemon}
		if err := upgrade.PrepareRestart(lock, intent); err != nil {
			return fmt.Errorf("persist restart intent: %w", err)
		}
		prepared = true
	}
	if startDaemon {
		out, err := ops.systemctl("stop", unit)
		if err != nil {
			return fmt.Errorf("stop upgrade service %s: %w: %s; application services were not stopped", unit, err, strings.TrimSpace(out))
		}
	}
	if err := ops.stack(profile); err != nil {
		return fmt.Errorf("restart %s application services: %w", profile, err)
	}
	return nil
}

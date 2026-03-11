// Package compose wraps docker compose commands.
package compose

import (
	"fmt"
	"os"
	"os/exec"
	"strings"

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
func Build(profile string) error {
	if profile == "" {
		return Run("build")
	}
	return RunWithProfile(profile, "build")
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

package cmd

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"strings"

	"github.com/spf13/cobra"
	"github.com/statisticsnorway/statbus/cli/internal/compose"
	"github.com/statisticsnorway/statbus/cli/internal/config"
	"github.com/statisticsnorway/statbus/cli/internal/dotenv"
	"github.com/statisticsnorway/statbus/cli/internal/upgrade"
)

func startServices(profile string, build bool) (result error) {
	projDir := config.ProjectDir()
	guard, err := upgrade.AcquireOperatorStartGuard(projDir, "operator:start")
	if err != nil {
		return err
	}
	defer func() { result = errors.Join(result, guard.Release()) }()

	start, err := compose.Up(context.Background(), projDir, startComposeArgs(profile, build)...)
	if err != nil {
		return err
	}
	start.Stdin = os.Stdin
	start.Stdout = os.Stdout
	start.Stderr = os.Stderr
	return start.Run()
}

func startComposeArgs(profile string, build bool) []string {
	args := []string{"-d"}
	if build {
		args = append(args, "--build")
	} else {
		args = append(args, "--no-build")
	}
	if profile == "app" {
		return append(args, "app")
	}
	return append([]string{"--profile", profile}, args...)
}

// A tagged release installation uses published images even if its proxy
// runs in development mode. A source development checkout builds locally.
func startBuildsFromSource(dir string) bool {
	if !compose.IsDevelopmentModeInDir(dir) {
		return false
	}
	f, err := dotenv.Load(filepath.Join(dir, ".env"))
	if err != nil {
		return true
	}
	version, _ := f.Get("VERSION")
	return !strings.HasPrefix(version, "v") || strings.Contains(version, "-g")
}

var startCmd = &cobra.Command{
	Use:   "start [profile]",
	Short: "Start services (default: all)",
	Long: `Start StatBus services using docker compose.

Profiles: all, all_except_app, app
Source development checkouts build images from source (--build).
Release installations use pulled images, including in development mode.`,
	Args: cobra.MaximumNArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		profile := "all"
		if len(args) > 0 {
			profile = args[0]
		}
		build := startBuildsFromSource(config.ProjectDir())
		return startServices(profile, build)
	},
}

var stopCmd = &cobra.Command{
	Use:   "stop [profile]",
	Short: "Stop services (default: all)",
	Long: `Stop StatBus services using docker compose.

Profiles: all, all_except_app, app`,
	Args: cobra.MaximumNArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		profile := "all"
		if len(args) > 0 {
			profile = args[0]
		}
		return compose.Stop(profile)
	},
}

var restartCmd = &cobra.Command{
	Use:   "restart [profile]",
	Short: "Restart services (default: all)",
	Long: `Restart StatBus services (stop then start).
All-stack profiles also reload an active upgrade daemon. Existing upgrade/install
markers refuse before any disruption. An intentionally inactive daemon stays inactive.
Waits for stack health and daemon readiness under the upgrade mutex.
Failed or interrupted restarts retain a barrier: fix the cause and retry this
same command and profile. No manual systemctl operation is needed.

Profiles: all, all_except_app, app`,
	Args: cobra.MaximumNArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		profile := "all"
		if len(args) > 0 {
			profile = args[0]
		}
		return restartServices(profile)
	},
}

var psCmd = &cobra.Command{
	Use:   "ps",
	Short: "Show running containers",
	RunE: func(cmd *cobra.Command, args []string) error {
		return compose.Ps()
	},
}

var logsCmd = &cobra.Command{
	Use:   "logs [services...]",
	Short: "Follow service logs",
	RunE: func(cmd *cobra.Command, args []string) error {
		return compose.Logs(args...)
	},
}

var buildCmd = &cobra.Command{
	Use:   "build [profile]",
	Short: "Build service images from source (development only)",
	Long: `Build Docker images from local Dockerfiles.

Profiles: all, all_except_app, app

This is for development only — standalone/private deployments
use pre-built images from ghcr.io (pulled by 'sb start').`,
	Args: cobra.MaximumNArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		profile := "all"
		if len(args) > 0 {
			profile = args[0]
		}
		return compose.Build(profile)
	},
}

func init() {
	rootCmd.AddCommand(startCmd)
	rootCmd.AddCommand(stopCmd)
	rootCmd.AddCommand(restartCmd)
	rootCmd.AddCommand(psCmd)
	rootCmd.AddCommand(logsCmd)
	rootCmd.AddCommand(buildCmd)
}

package cmd

import (
	"context"
	"errors"
	"os"

	"github.com/spf13/cobra"
	"github.com/statisticsnorway/statbus/cli/internal/compose"
	"github.com/statisticsnorway/statbus/cli/internal/config"
	"github.com/statisticsnorway/statbus/cli/internal/upgrade"
)

func startServices(profile string) (result error) {
	projDir := config.ProjectDir()
	guard, err := upgrade.AcquireOperatorStartGuard(projDir, "operator:start")
	if err != nil {
		return err
	}
	defer func() { result = errors.Join(result, guard.Release()) }()

	// The binary's build identity decides: a source build builds, a release
	// build runs the published images (doc/sb-build-identity.md).
	args, err := startUpArgs(projDir, profile, isReleaseBuild(), string(commitVersion), liveDockerImageOps{}, os.Stdout)
	if err != nil {
		return err
	}
	start, err := compose.Up(context.Background(), projDir, args...)
	if err != nil {
		return err
	}
	start.Stdin = os.Stdin
	start.Stdout = os.Stdout
	start.Stderr = os.Stderr
	return start.Run()
}

var startCmd = &cobra.Command{
	Use:     "start [profile]",
	Short:   "Start services (default: all)",
	GroupID: operationsGroupID,
	Long: `Start StatBus services using docker compose.

Profiles: all, all_except_app, app

A source build rebuilds images from source (--build). A release build checks
that this version's published images are present locally, pulls them only if
they are missing (for example after docker image prune), and starts with
--no-build. See doc/sb-build-identity.md.`,
	Args: cobra.MaximumNArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		profile := "all"
		if len(args) > 0 {
			profile = args[0]
		}
		return startServices(profile)
	},
}

var stopCmd = &cobra.Command{
	Use:     "stop [profile]",
	Short:   "Stop services (default: all)",
	GroupID: operationsGroupID,
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
	Use:     "restart [profile]",
	Short:   "Restart services (default: all)",
	GroupID: operationsGroupID,
	Long: `Restart StatBus services (stop then start).
All-stack profiles also reload an active upgrader. Existing upgrade/install
markers refuse before any disruption. An intentionally inactive daemon stays inactive.
Waits for stack health and daemon readiness under the upgrade mutex.
Failed or interrupted restarts retain a barrier: fix the cause and retry this
same command and profile. No manual systemctl operation is needed.

A source build rebuilds images from source (--build). A release build checks
that this version's published images are present locally, pulls them only if
they are missing (for example after docker image prune), and starts with
--no-build. See doc/sb-build-identity.md.

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
	Use:     "ps",
	Short:   "Show running containers",
	GroupID: operationsGroupID,
	RunE: func(cmd *cobra.Command, args []string) error {
		return compose.Ps()
	},
}

var logsCmd = &cobra.Command{
	Use:     "logs [services...]",
	Short:   "Follow service logs",
	GroupID: operationsGroupID,
	RunE: func(cmd *cobra.Command, args []string) error {
		return compose.Logs(args...)
	},
}

var buildCmd = &cobra.Command{
	Use:     "build [profile]",
	Short:   "Build service images from source (development only)",
	GroupID: developmentGroupID,
	Long: `Build Docker images from local Dockerfiles.

Profiles: all, all_except_app, app

This is a development command: a source build uses it (directly, or via
'sb start'). A release install runs the published ghcr.io images, which
'sb start' pulls when missing. See doc/sb-build-identity.md.`,
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

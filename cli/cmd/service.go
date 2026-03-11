package cmd

import (
	"github.com/spf13/cobra"
	"github.com/statisticsnorway/statbus/cli/internal/compose"
)

var startCmd = &cobra.Command{
	Use:   "start [profile]",
	Short: "Start services (default: all)",
	Long: `Start StatBus services using docker compose.

Profiles: all, all_except_app, app
In development mode, builds images from source (--build).
In standalone/private mode, uses pre-pulled images.`,
	Args: cobra.MaximumNArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		profile := "all"
		if len(args) > 0 {
			profile = args[0]
		}
		build := compose.IsDevelopmentMode()
		return compose.Start(profile, build)
	},
}

var stopCmd = &cobra.Command{
	Use:   "stop [profile]",
	Short: "Stop services (default: all)",
	Args:  cobra.MaximumNArgs(1),
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
	Args:  cobra.MaximumNArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		profile := "all"
		if len(args) > 0 {
			profile = args[0]
		}
		build := compose.IsDevelopmentMode()
		return compose.Restart(profile, build)
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
	Short: "Build service images",
	Args:  cobra.MaximumNArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		profile := ""
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

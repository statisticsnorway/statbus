package cmd

import (
	"github.com/spf13/cobra"
	"github.com/statisticsnorway/statbus/cli/internal/config"
)

var configCmd = &cobra.Command{
	Use:   "config",
	Short: "Manage StatBus configuration",
}

var configGenerateCmd = &cobra.Command{
	Use:   "generate",
	Short: "Generate .env and Caddyfiles from .env.config and .env.credentials",
	Long: `Reads .env.config and .env.credentials (generating defaults if missing),
derives all computed values (ports, memory tuning, URLs), writes .env,
and renders Caddyfile templates from caddy/templates/*.caddyfile.tmpl
into caddy/config/.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		return config.Generate(verbose)
	},
}

var configShowCmd = &cobra.Command{
	Use:   "show",
	Short: "Show current configuration values",
	RunE: func(cmd *cobra.Command, args []string) error {
		// Load .env and display key values
		if err := LoadDotenv(); err != nil {
			return err
		}
		// For now, just run generate in verbose mode to show what's happening
		return config.Generate(true)
	},
}

func init() {
	configCmd.AddCommand(configGenerateCmd)
	configCmd.AddCommand(configShowCmd)
	rootCmd.AddCommand(configCmd)
}

package cmd

import (
	"fmt"
	"runtime/debug"

	"github.com/spf13/cobra"
)

// Set at build time via -ldflags.
var (
	version = "dev"
	commit  = "unknown"
)

var (
	verbose bool
)

var rootCmd = &cobra.Command{
	Use:   "sb",
	Short: "StatBus management CLI",
	Long:  "sb is the management CLI for StatBus — a statistical business registry.",
}

func init() {
	rootCmd.PersistentFlags().BoolVarP(&verbose, "verbose", "v", false, "enable verbose output")
	rootCmd.Version = versionString()
}

func versionString() string {
	if version != "dev" {
		return fmt.Sprintf("%s (commit %s)", version, commit)
	}
	if info, ok := debug.ReadBuildInfo(); ok {
		for _, setting := range info.Settings {
			if setting.Key == "vcs.revision" && len(setting.Value) >= 8 {
				return fmt.Sprintf("dev (commit %s)", setting.Value[:8])
			}
		}
		return fmt.Sprintf("dev (%s)", info.GoVersion)
	}
	return "dev"
}

func Execute() error {
	return rootCmd.Execute()
}

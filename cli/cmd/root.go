package cmd

import (
	"fmt"
	"runtime/debug"

	"github.com/spf13/cobra"
	"github.com/statisticsnorway/statbus/cli/internal/upgrade"
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
	// Operational errors should not drown the user in usage text. The "Error: ..."
	// line stays (printed by cobra unless SilenceErrors is set, which we leave
	// false on purpose — that line is the actual feedback). SilenceUsage just
	// suppresses the "Usage:\n  sb foo\nFlags:\n..." block that cobra appends
	// after every RunE error. For real argument-parse errors (wrong number of
	// args, unknown flag) cobra still prints usage because those happen before
	// RunE; SilenceUsage only affects the post-RunE path.
	SilenceUsage: true,
}

func init() {
	rootCmd.PersistentFlags().BoolVarP(&verbose, "verbose", "v", false, "enable verbose output")
	rootCmd.Version = versionString()
}

func versionString() string {
	if version != "dev" {
		return fmt.Sprintf("%s (commit %s)", version, upgrade.ShortForDisplay(commit))
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

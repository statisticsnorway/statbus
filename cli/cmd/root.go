package cmd

import (
	"fmt"
	"os"
	"runtime/debug"

	"github.com/spf13/cobra"
	"github.com/statisticsnorway/statbus/cli/internal/config"
	"github.com/statisticsnorway/statbus/cli/internal/freshness"
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
	// Stale-binary guard. Runs before every cobra command (cobra skips
	// PersistentPreRun for --help/--version). When ./sb's build commit
	// disagrees with the worktree's cli/ tree, mutating commands hard-
	// fail (exit 2); read-only commands warn-and-proceed. Silent no-op
	// when the build commit is unknown, when projDir isn't a git
	// checkout, or when git is unavailable — see freshness.IsStale.
	PersistentPreRun: stalenessGuard,
}

// stalenessGuard is rootCmd.PersistentPreRun. Extracted as a top-level
// function for readability and to keep the command literal terse.
func stalenessGuard(c *cobra.Command, _ []string) {
	msg := freshness.IsStale(config.ProjectDir(), commit)
	if msg == "" {
		return
	}
	if isMutatingCommand(c) {
		fmt.Fprintln(os.Stderr, msg)
		os.Exit(2)
	}
	fmt.Fprintln(os.Stderr, "WARN: "+msg)
}

// readOnlyCommandPaths is the allowlist of cobra command paths whose
// invocation does NOT mutate state. Stale-binary guard treats any
// command NOT in this set as mutating (hard-fail when stale).
//
// Conservative default: when in doubt, flag as mutating. False
// positives (a "read-only" command flagged as mutating) cost the
// operator a rebuild; false negatives (a mutating command silently
// running stale) cause silent data divergence — the rc63-fixes class
// of bug we're guarding against.
//
// Keys are full cobra command paths ("sb subcmd subsubcmd"). Match by
// CommandPath() exact equality.
var readOnlyCommandPaths = map[string]bool{
	"sb":                       true, // bare invocation prints help
	"sb help":                  true,
	"sb completion":            true,
	"sb completion bash":       true,
	"sb completion zsh":        true,
	"sb completion fish":       true,
	"sb completion powershell": true,
	"sb psql":                  true, // opens an interactive session; doesn't issue mutating SQL itself
	"sb db status":             true,
	"sb db dumps list":         true,
	"sb db seed status":        true,
	"sb db seed fetch":         true, // fetches the artifact; doesn't mutate the DB
	"sb dotenv get":            true,
	"sb dotenv list":           true,
	"sb config show":           true,
	"sb release list":          true,
	"sb release check":         true,
	"sb upgrade list":          true,
	"sb upgrade check":         true,
	"sb ps":                    true,
	"sb logs":                  true,
}

func isMutatingCommand(c *cobra.Command) bool {
	return !readOnlyCommandPaths[c.CommandPath()]
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

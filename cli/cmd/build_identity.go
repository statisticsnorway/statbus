package cmd

import (
	"fmt"
	"regexp"

	"github.com/spf13/cobra"
)

// Build identity: the one answer to "release build or source build?"
// (STATBUS-392, doc/sb-build-identity.md). The binary carries the version it
// was built with in the version ldflag (see root.go). A tag like
// v2026.10.3-rc.01 or v2026.10.3 is a release build: it runs the images
// published for its version. A git-describe with a -<n>-g<sha> suffix, "dev",
// or an empty stamp is a source build: it builds images from the code on
// disk. Start, restart, and command visibility all read this one answer.
var releaseTagPattern = regexp.MustCompile(`^v[0-9]+\.[0-9]+\.[0-9]+(-rc\.[0-9]+)?$`)

// isReleaseBuildVersion is the pure decision, parameterised for tests.
func isReleaseBuildVersion(v string) bool {
	return releaseTagPattern.MatchString(v)
}

// isReleaseBuild reports the identity of THIS binary.
func isReleaseBuild() bool {
	return isReleaseBuildVersion(string(commitVersion))
}

// Command groups drawn by ./sb --help (cobra AddGroup/GroupID).
const (
	operationsGroupID  = "operations"
	developmentGroupID = "development"
)

// devHiddenHint ends the root help on a release build, where the Development
// group is hidden. It names the escape hatch rather than the mechanism.
const devHiddenHint = "Development commands are hidden on a release install; './sb help --all' lists them."

// helpTemplate is cobra's default help template with one change: a group
// heading is drawn only when it has visible commands (hasVisibleInGroup), so
// a release build does not show an empty Development heading.
const helpTemplate = `Usage:{{if .Runnable}}
  {{.UseLine}}{{end}}{{if .HasAvailableSubCommands}}
  {{.CommandPath}} [command]{{end}}{{if gt (len .Aliases) 0}}

Aliases:
  {{.NameAndAliases}}{{end}}{{if .HasExample}}

Examples:
{{.Example}}{{end}}{{if .HasAvailableSubCommands}}{{$cmds := .Commands}}{{if eq (len .Groups) 0}}

Available Commands:{{range $cmds}}{{if (or .IsAvailableCommand (eq .Name "help"))}}
  {{rpad .Name .NamePadding }} {{.Short}}{{end}}{{end}}{{else}}{{range $group := .Groups}}{{if hasVisibleInGroup $ $group.ID}}

{{.Title}}{{range $cmds}}{{if (and (eq .GroupID $group.ID) (or .IsAvailableCommand (eq .Name "help")))}}
  {{rpad .Name .NamePadding }} {{.Short}}{{end}}{{end}}{{end}}{{end}}{{if not .AllChildCommandsHaveGroup}}

Additional Commands:{{range $cmds}}{{if (and (eq .GroupID "") (or .IsAvailableCommand (eq .Name "help")))}}
  {{rpad .Name .NamePadding }} {{.Short}}{{end}}{{end}}{{end}}{{end}}{{end}}{{if .HasAvailableLocalFlags}}

Flags:
{{.LocalFlags.FlagUsages | trimTrailingWhitespaces}}{{end}}{{if .HasAvailableInheritedFlags}}

Global Flags:
{{.InheritedFlags.FlagUsages | trimTrailingWhitespaces}}{{end}}{{if .HasHelpSubCommands}}

Additional help topics:{{range .Commands}}{{if .IsAdditionalHelpTopicCommand}}
  {{rpad .CommandPath .CommandPathPadding}} {{.Short}}{{end}}{{end}}{{end}}{{if .HasAvailableSubCommands}}

Use "{{.CommandPath}} [command] --help" for more information about a command.{{end}}
`

// hasVisibleInGroup reports whether any command in the group would be listed:
// available, or the help command (cobra always lists that one).
func hasVisibleInGroup(c *cobra.Command, groupID string) bool {
	for _, sub := range c.Commands() {
		if sub.GroupID == groupID && (sub.IsAvailableCommand() || sub.Name() == "help") {
			return true
		}
	}
	return false
}

// applyBuildVisibility hides the Development command group on a release build
// and appends devHiddenHint to the root help. Called once from Execute before
// dispatch, so visibility is decided before help is drawn. Hidden means out
// of the way, not removed: cobra still runs a hidden command and renders its
// own --help, because support sometimes needs the developer surface.
func applyBuildVisibility(release bool) {
	if !release {
		return
	}
	for _, c := range rootCmd.Commands() {
		if c.GroupID == developmentGroupID {
			c.Hidden = true
		}
	}
	defaultHelp := rootCmd.HelpFunc()
	rootCmd.SetHelpFunc(func(c *cobra.Command, args []string) {
		defaultHelp(c, args)
		if c == rootCmd {
			// A failed hint write must not mask the help that already rendered.
			_, _ = fmt.Fprintln(c.OutOrStdout(), devHiddenHint)
		}
	})
}

var helpAllFlag bool

// helpCmd replaces cobra's default help command to add --all: on a release
// build it reveals the hidden Development commands before drawing. Behavior
// otherwise matches cobra's default help command.
var helpCmd = &cobra.Command{
	Use:   "help [command]",
	Short: "Help about any command",
	Long: `Help provides help for any command in the application.
On a release install the Development commands are hidden from './sb --help';
'./sb help --all' lists every command.`,
	Args:    cobra.ArbitraryArgs,
	GroupID: operationsGroupID,
	RunE: func(cmd *cobra.Command, args []string) error {
		if helpAllFlag {
			// Reveal the Development commands hidden on a release build.
			// Infra commands hidden in their own right (the freshness probe,
			// install.sh's fetch delegation) stay hidden.
			for _, c := range rootCmd.Commands() {
				if c.GroupID == developmentGroupID {
					c.Hidden = false
				}
			}
		}
		target, _, err := rootCmd.Find(args)
		if err != nil || target == nil {
			cmd.Printf("Unknown help topic %q\n", args)
			return rootCmd.Usage()
		}
		target.InitDefaultHelpFlag()
		target.InitDefaultVersionFlag()
		return target.Help()
	},
}

func init() {
	helpCmd.Flags().BoolVar(&helpAllFlag, "all", false, "list every command, including development commands hidden on a release install")
	rootCmd.SetHelpCommand(helpCmd)
	// AddCommand too: cobra only re-adds the help command at execute time,
	// and the grouped help listing reads Commands.
	rootCmd.AddCommand(helpCmd)
	cobra.AddTemplateFunc("hasVisibleInGroup", hasVisibleInGroup)
	rootCmd.SetHelpTemplate(helpTemplate)
}

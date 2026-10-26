package cmd

import (
	"bytes"
	"reflect"
	"sort"
	"strings"
	"testing"

	"github.com/spf13/cobra"
)

// STATBUS-392 AC4: ./sb --help groups commands as Operations and Development.
// On a release build the Development group is hidden, the help ends with a
// line naming ./sb help --all, ./sb help --all lists every command, and a
// hidden command still runs and shows its own --help (doc/sb-build-identity.md).

// preserveHelpState snapshots the global help surface applyBuildVisibility
// mutates, so subtests can restore it.
func preserveHelpState(t *testing.T) {
	t.Helper()
	savedHelpFunc := rootCmd.HelpFunc()
	savedHidden := map[*cobra.Command]bool{}
	for _, c := range rootCmd.Commands() {
		savedHidden[c] = c.Hidden
	}
	savedHelpAll := helpAllFlag
	t.Cleanup(func() {
		rootCmd.SetHelpFunc(savedHelpFunc)
		for c, hidden := range savedHidden {
			c.Hidden = hidden
		}
		helpAllFlag = savedHelpAll
		rootCmd.SetOut(nil)
	})
}

// renderRootHelp draws the root command's help the way ./sb --help does.
func renderRootHelp(t *testing.T) string {
	t.Helper()
	var buf bytes.Buffer
	rootCmd.SetOut(&buf)
	rootCmd.HelpFunc()(rootCmd, nil)
	return buf.String()
}

// parseHelpGroups reads the grouped command listing: heading -> command names,
// in the order drawn. Flag and usage lines never start a group.
func parseHelpGroups(out string) map[string][]string {
	groups := map[string][]string{}
	var current string
	for _, line := range strings.Split(out, "\n") {
		if !strings.HasPrefix(line, " ") {
			current = ""
			for _, heading := range []string{"Operations", "Development", "Additional Commands"} {
				if line == heading+":" {
					current = heading
				}
			}
			continue
		}
		if current == "" {
			continue
		}
		if fields := strings.Fields(line); len(fields) > 0 {
			groups[current] = append(groups[current], fields[0])
		}
	}
	return groups
}

func lastLine(out string) string {
	lines := strings.Split(strings.TrimRight(out, "\n"), "\n")
	return lines[len(lines)-1]
}

// wantOperations is the operator surface, sorted for comparison.
func wantOperations() []string {
	names := []string{"cert", "completion", "config", "db", "help", "install", "logs", "ps", "psql", "restart", "start", "stop", "support", "uninstall", "upgrade", "upgrader", "users"}
	sort.Strings(names)
	return names
}

// wantDevelopment is the developer surface as composed in this package's test
// binary (main.go additionally mounts `release` in the real binary).
func wantDevelopment() []string {
	names := []string{"assert-db-at-head", "assert-db-content-hash", "build", "dotenv", "migrate", "test", "types"}
	sort.Strings(names)
	return names
}

func sortedNames(names []string) []string {
	out := append([]string{}, names...)
	sort.Strings(out)
	return out
}

func TestRootHelpGroupsReleaseBuild_STATBUS392(t *testing.T) {
	preserveHelpState(t)
	applyBuildVisibility(true)
	out := renderRootHelp(t)
	groups := parseHelpGroups(out)
	// The visible listing is exactly the Operations group: every operator
	// command, no Development heading.
	want := map[string][]string{"Operations": wantOperations()}
	got := map[string][]string{}
	for heading, names := range groups {
		got[heading] = sortedNames(names)
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("release-build help groups = %v, want exactly %v", got, want)
	}
	// The help ends with the pointer to the full list.
	if got := lastLine(out); got != devHiddenHint {
		t.Errorf("release-build help last line = %q, want %q", got, devHiddenHint)
	}
}

func TestRootHelpGroupsSourceBuild_STATBUS392(t *testing.T) {
	preserveHelpState(t)
	applyBuildVisibility(false)
	out := renderRootHelp(t)
	groups := parseHelpGroups(out)
	want := map[string][]string{
		"Operations":  wantOperations(),
		"Development": wantDevelopment(),
	}
	got := map[string][]string{}
	for heading, names := range groups {
		got[heading] = sortedNames(names)
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("source-build help groups = %v, want %v", got, want)
	}
	// Nothing is hidden, so the help ends with cobra's standard footer.
	wantFooter := `Use "sb [command] --help" for more information about a command.`
	if got := lastLine(out); got != wantFooter {
		t.Errorf("source-build help last line = %q, want %q", got, wantFooter)
	}
}

func TestHelpAllListsEveryCommand_STATBUS392(t *testing.T) {
	preserveHelpState(t)
	applyBuildVisibility(true)
	var buf bytes.Buffer
	rootCmd.SetOut(&buf)
	helpAllFlag = true
	if err := helpCmd.RunE(helpCmd, nil); err != nil {
		t.Fatal(err)
	}
	groups := parseHelpGroups(buf.String())
	got := map[string][]string{}
	for heading, names := range groups {
		got[heading] = sortedNames(names)
	}
	want := map[string][]string{
		"Operations":  wantOperations(),
		"Development": wantDevelopment(),
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("help --all groups = %v, want every command %v", got, want)
	}
}

func TestHiddenDevelopmentCommandStillRuns_STATBUS392(t *testing.T) {
	preserveHelpState(t)
	applyBuildVisibility(true)
	// Hidden means out of the way, not removed: cobra still resolves the
	// command, it is still runnable, and its own help still renders.
	found, _, err := rootCmd.Find([]string{"build"})
	if err != nil {
		t.Fatal(err)
	}
	if found != buildCmd {
		t.Fatalf("rootCmd.Find(build) = %v, want the build command", found.Name())
	}
	if !found.Hidden {
		t.Error("build is not hidden on a release build")
	}
	if !found.Runnable() {
		t.Error("build is not runnable on a release build")
	}
	var buf bytes.Buffer
	found.SetOut(&buf)
	if err := found.Help(); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(buf.String(), "Usage:") {
		t.Errorf("build --help rendered %q, want its usage", buf.String())
	}
}

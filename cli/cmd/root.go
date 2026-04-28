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

// Set at build time via -ldflags. RAW build-interface inputs:
//
//   -X 'github.com/statisticsnorway/statbus/cli/cmd.version=...'
//   -X 'github.com/statisticsnorway/statbus/cli/cmd.commit=...'
//
// Don't reference these from business logic — use the typed runtime
// values (commitSHA / commitVersion) below, populated at init from
// these inputs plus debug.ReadBuildInfo() vcs metadata.
var (
	version = "dev"
	commit  = "unknown"
)

// Typed runtime build identity. Names mirror DB columns commit_sha /
// commit_version (see migrations/20260328092344_commit_centric_upgrade_table.up.sql)
// and Go canonical types (cli/internal/upgrade/commit.go).
//
// Resolved once in init() via smart constructors. Empty values mean the
// binary's identity could not be reliably determined — stalenessGuard
// refuses mutating commands in that case (no fallback to guessing).
var (
	commitSHA     upgrade.CommitSHA
	commitVersion upgrade.CommitVersion
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
//
// Two failure modes, both fail-fast on mutating commands:
//
//  1. commitSHA empty — binary has no reliable build identity (built
//     without ldflags AND not from a clean git tree). The freshness
//     check can't run reliably; refuse rather than silently skip.
//     Pre-fix this case silently bypassed the check (task #30 root cause).
//
//  2. commitSHA set but cli/ tree drifted since build — classic stale.
func stalenessGuard(c *cobra.Command, _ []string) {
	if commitSHA == "" {
		const msg = "./sb has no reliable commit identity (built without ldflags, or with uncommitted changes, or non-git build).\n" +
			"  Rebuild from a clean tree: ./dev.sh build-sb"
		if isMutatingCommand(c) {
			fmt.Fprintln(os.Stderr, msg)
			os.Exit(2)
		}
		fmt.Fprintln(os.Stderr, "WARN: "+msg)
		return
	}
	msg := freshness.IsStale(config.ProjectDir(), string(commitSHA))
	if msg == "" {
		return
	}
	if isMutatingCommand(c) {
		fmt.Fprintln(os.Stderr, msg)
		os.Exit(2)
	}
	fmt.Fprintln(os.Stderr, "WARN: "+msg)
}

// resolveCommitSHA resolves the binary's commit identity from layered
// sources, preferring definitive over reliable. Returns empty
// CommitSHA when no source qualifies — callers MUST treat empty as
// "ambiguous identity, refuse mutating".
//
//   Tier 1 (definitive): explicit -ldflags 'cmd.commit=<40-char hex>'.
//   Tier 2 (reliable):   debug.ReadBuildInfo()'s vcs.revision IFF
//                        vcs.modified=false (clean tree at build time).
//   Tier 3 (ambiguous):  empty result, fail-fast on mutating commands.
//
// No fallback: if neither tier yields a validly-shaped CommitSHA, the
// binary is rejected for mutating use. This matches the upgrade-table's
// commit_sha NOT NULL UNIQUE invariant — every persisted upgrade row
// names the commit it corresponds to; every running binary should too.
//
// Thin wrapper over resolveCommitSHAFrom so tests can drive it with
// controlled ldflag/buildinfo inputs (cli/cmd/root_resolve_test.go).
func resolveCommitSHA() upgrade.CommitSHA {
	return resolveCommitSHAFrom(commit, debug.ReadBuildInfo)
}

// resolveCommitSHAFrom is the testable core of resolveCommitSHA.
// Parameterised on the ldflag input + a buildInfo source so unit tests
// can exercise every tier without touching package-level globals.
func resolveCommitSHAFrom(ldflagCommit string, buildInfoFn func() (*debug.BuildInfo, bool)) upgrade.CommitSHA {
	if ldflagCommit != "" && ldflagCommit != "unknown" {
		if c, err := upgrade.NewCommitSHA(ldflagCommit); err == nil {
			return c
		}
	}
	if info, ok := buildInfoFn(); ok && info != nil {
		var rev string
		var modified bool
		for _, s := range info.Settings {
			switch s.Key {
			case "vcs.revision":
				rev = s.Value
			case "vcs.modified":
				modified = s.Value == "true"
			}
		}
		if rev != "" && !modified {
			if c, err := upgrade.NewCommitSHA(rev); err == nil {
				return c
			}
		}
	}
	return ""
}

// resolveCommitVersion: smart-constructs the typed display label from
// the version ldflag. Returns "dev" sentinel when the build wasn't
// stamped with a release tag — versionString picks an alternative
// presentation in that case.
func resolveCommitVersion() upgrade.CommitVersion {
	return upgrade.CommitVersion(version)
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
	commitSHA = resolveCommitSHA()
	commitVersion = resolveCommitVersion()
	rootCmd.PersistentFlags().BoolVarP(&verbose, "verbose", "v", false, "enable verbose output")
	rootCmd.Version = versionString()
}

// versionString renders --version output from the same typed runtime
// vars stalenessGuard consults. Pre-fix (task #30) used a separate
// resolution path that surfaced vcs.revision even when the freshness
// check saw "unknown" — the result was a binary that LOOKED stamped to
// the operator but silently skipped the staleness check.
//
// Three cases, mirroring resolveCommitSHA's tiers:
//   - tagged release (commitVersion != "dev"): "<version> (commit <short>)"
//   - dev build with reliable identity:        "dev (commit <short>)"
//   - dev build, identity unresolvable:        "dev (UNSTAMPED)"
//
// The UNSTAMPED suffix is the loud signal: this binary has no commit
// identity, mutating commands will be refused.
func versionString() string {
	if commitVersion != "" && commitVersion != "dev" {
		return fmt.Sprintf("%s (commit %s)", commitVersion, displayShort(commitSHA))
	}
	if commitSHA != "" {
		return fmt.Sprintf("dev (commit %s)", displayShort(commitSHA))
	}
	return "dev (UNSTAMPED)"
}

// displayShort renders an 8-char commit_short for display from a
// validated CommitSHA. Empty input renders as "unknown" — this only
// happens on the UNSTAMPED branch which already says so explicitly,
// but we keep the string non-empty for callers that splice it.
func displayShort(c upgrade.CommitSHA) string {
	if c == "" {
		return "unknown"
	}
	return string(c)[:8]
}

func Execute() error {
	return rootCmd.Execute()
}

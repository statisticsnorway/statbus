package cmd

import (
	"fmt"
	"os"
	"runtime/debug"

	"github.com/spf13/cobra"
	"github.com/statisticsnorway/statbus/cli/internal/config"
	"github.com/statisticsnorway/statbus/cli/internal/freshness"
	"github.com/statisticsnorway/statbus/cli/internal/inject"
	"github.com/statisticsnorway/statbus/cli/internal/upgrade"
)

// Set at build time via -ldflags. RAW build-interface inputs:
//
//	-X 'github.com/statisticsnorway/statbus/cli/cmd.version=...'
//	-X 'github.com/statisticsnorway/statbus/cli/cmd.commit=...'
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
//
// Self-heal carve-out: commands annotated `selfheal=true` — the recovery
// surface (`install`, `upgrade service`, `upgrade apply-latest`) —
// rebuild + re-exec instead of hard-failing when (2) fires. A wedged
// installation must not require the very wedged binary to be hand-rebuilt
// first. Single-attempt: SelfHealAttemptEnv prevents recursion. Tier-1
// ambiguous identity (case 1) cannot self-heal (no identity to rebuild
// against). See doc/upgrade-timeline.md for the full state matrix and the
// fail-fast audit table.
func stalenessGuard(c *cobra.Command, _ []string) {
	// The freshness probe (`sb committed-drift`) IS the staleness check that
	// dev.sh's rebuild decision calls; running the guard on it would be circular
	// and would leak a WARN into the output dev.sh parses. Always exempt.
	if c.Annotations["freshness_probe"] == "true" {
		return
	}
	// Echoed in every refuse-with-guidance path so the operator's next
	// step is unambiguous: rebuild, then re-invoke the exact command they
	// just typed. Cobra's CommandPath returns "sb release prerelease"
	// without the leading "./"; we prepend it to match how the operator
	// invoked it on the command line.
	reRun := "./" + c.CommandPath()

	if commitSHA == "" {
		// Tier-1/tier-2 ambiguous identity. A binary with no identity can't
		// reliably know what to rebuild against, so self-heal can't help here.
		// STATBUS-085: an identity-less binary CANNOT self-heal (the guard
		// short-circuits here, before the procurement path below — and there is no
		// commit to procure against). So the operator-correct remedy on a
		// no-toolchain box is to RE-FETCH a release binary, which replaces this
		// binary from a properly-tagged build — the documented rescue bootstrap.
		// `./sb install` is NOT the remedy here: it would hit this same branch and
		// exit again. (A Go toolchain box can cross-build; that's the dev fallback.)
		const msg = "./sb has no reliable commit identity (built without ldflags, or with uncommitted changes, or non-git build).\n" +
			"  It cannot self-heal — there is no identity to procure against. Re-fetch a release binary (no toolchain):\n" +
			"    curl -fsSL https://statbus.org/install.sh | bash\n" +
			"  (dev box with a Go toolchain: ./dev.sh cross-build-sb)"
		if isMutatingCommand(c) {
			fmt.Fprintln(os.Stderr, msg)
			fmt.Fprintf(os.Stderr, "  Then re-run: %s\n", reRun)
			os.Exit(2)
		}
		fmt.Fprintln(os.Stderr, "WARN: "+msg)
		return
	}
	msg := freshness.IsStale(config.ProjectDir(), string(commitSHA))
	if msg == "" {
		return
	}
	// Install-recovery injection carve-out. STATBUS_INJECT_AT is set ONLY
	// by the install-recovery harness (inject.EnvActiveAt; empty in every
	// production run — cli/internal/inject/inject.go). When set, a scenario
	// is deliberately orchestrating tree↔binary states (e.g. a mid-upgrade
	// checkout) and drives its OWN recovery: self-healing here (procure a fresh
	// ./sb + re-exec) would swap the binary out from under the scenario and mask
	// the recovery path under test, and the hard-fail path would abort the very
	// recovery command the scenario exercises. Downgrade the
	// guard to advisory in that mode only — production behavior is unchanged
	// because the env var is never set there. Generalizes the per-scenario
	// "install HEAD coherently so the binary isn't stale" workaround
	// (see test/install-recovery/scenarios/1-boot-startup-timeout.sh:101-110).
	if os.Getenv(inject.EnvActiveAt) != "" {
		fmt.Fprintln(os.Stderr, "WARN: "+msg)
		fmt.Fprintln(os.Stderr, "STATBUS_INJECT_AT set (install-recovery injection) — not self-healing; scenario drives recovery.")
		return
	}
	if isMutatingCommand(c) {
		// Self-heal path: a small set of recovery commands annotated with
		// "selfheal" exist precisely to fix the situation a stale binary
		// represents (install, upgrade service, upgrade apply-latest).
		// Rather than refuse-and-tell-the-operator-to-rebuild-by-hand,
		// procure a fresh ./sb (toolchain-free, from the commit-tagged image)
		// here and re-exec into it. The child marks itself via
		// SelfHealAttemptEnv so a recursive failure exits loudly instead of
		// looping.
		if c.Annotations["selfheal"] == "true" && os.Getenv(freshness.SelfHealAttemptEnv) == "" {
			// STATBUS-065: in-flight upgrade recovery defers to the recovery
			// boot, never to a local self-heal. A service-held forward-phase
			// (post_swap/resuming) flag means the binary was already swapped
			// and the recovery boot reconciles tree→binary via the deferred
			// target checkout (Service.Run / runCrashRecovery, STATBUS-060).
			// Procuring + re-exec'ing here would fight that recovery boot.
			// Defer instead; the genuine stale-dev-binary case (no flag,
			// install-held, or pre_swap) still self-heals below. PreSwap is
			// gated OUT by IsServiceNewSbRecovery: it rolls back, so the
			// tree must stay at the source commit.
			if flag, ferr := upgrade.ReadFlagFile(config.ProjectDir()); ferr == nil && flag.IsServiceNewSbRecovery() {
				fmt.Fprintln(os.Stderr, "WARN: "+msg)
				fmt.Fprintln(os.Stderr, "In-flight upgrade recovery (service-held flag, already booted the new binary) — deferring to the recovery boot; not self-healing.")
				return
			}
			fmt.Fprintln(os.Stderr, "WARN: "+msg)
			fmt.Fprintln(os.Stderr, "Self-healing: procuring ./sb for the worktree HEAD from the commit-tagged image (no host toolchain)...")
			if err := freshness.RebuildAndReexec(config.ProjectDir()); err != nil {
				fmt.Fprintf(os.Stderr, "Self-heal procure/exec failed: %v\n", err)
				os.Exit(2)
			}
			// unreachable; syscall.Exec replaced the process on success
			return
		}
		// Recursion guard: we already procured + re-exec'd once, but freshness
		// still fails. Race between procurement and a tree update, or the
		// procured image's ldflags don't match HEAD. Surface and stop.
		if os.Getenv(freshness.SelfHealAttemptEnv) != "" {
			fmt.Fprintln(os.Stderr, "Self-heal failed: procured binary is still reported stale.")
			fmt.Fprintln(os.Stderr, "  Likely a procurement↔tree-update race — re-run the recovery command:")
			fmt.Fprintf(os.Stderr, "  %s\n", reRun)
			os.Exit(2)
		}
		// Non-self-healing mutating command on a stale (but identified) binary:
		// hard-fail. STATBUS-085: msg (freshness.IsStale) now names the
		// toolchain-free `./sb install` refresh; follow it with the operator's own
		// command to re-run (never "after rebuild" — wrong on a no-toolchain box).
		fmt.Fprintln(os.Stderr, msg)
		fmt.Fprintf(os.Stderr, "  Then re-run: %s\n", reRun)
		os.Exit(2)
	}
	fmt.Fprintln(os.Stderr, "WARN: "+msg)
}

// resolveCommitSHA resolves the binary's commit identity from layered
// sources, preferring definitive over reliable. Returns empty
// CommitSHA when no source qualifies — callers MUST treat empty as
// "ambiguous identity, refuse mutating".
//
//	Tier 1 (definitive): explicit -ldflags 'cmd.commit=<40-char hex>'.
//	Tier 2 (reliable):   debug.ReadBuildInfo()'s vcs.revision IFF
//	                     vcs.modified=false (clean tree at build time).
//	Tier 3 (ambiguous):  empty result, fail-fast on mutating commands.
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
	"sb committed-drift":       true, // hidden freshness probe; guard-exempt via annotation, and read-only regardless
	"sb completion":            true,
	"sb completion bash":       true,
	"sb completion zsh":        true,
	"sb completion fish":       true,
	"sb completion powershell": true,
	"sb psql":                  true, // opens an interactive session; doesn't issue mutating SQL itself
	"sb cert show":             true, // reads cert from disk + optional TLS probe; no state mutation
	"sb db status":             true,
	"sb db dumps list":         true,
	"sb db seed status":        true,
	"sb db seed fetch":         true, // fetches the artifact; doesn't mutate the DB
	"sb dotenv get":            true,
	"sb dotenv list":           true,
	"sb config show":           true,
	"sb release list":          true,
	"sb release check":         true,
	"sb release verify-tag":    true, // local repo + GitHub API only; no state mutation
	"sb release verify-images": true, // GitHub API only; no state mutation
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
	// Validate harness-only fault-injection env vars before any subcommand
	// dispatches. A misconfigured combination (typoed class, stall file
	// without a stall class, etc.) must fail loudly so a recovery scenario
	// cannot silently produce a vacuous "pass". Production runs leave the
	// env vars unset and this returns nil immediately.
	if err := inject.Validate(); err != nil {
		fmt.Fprintf(os.Stderr, "FATAL: invalid STATBUS_INJECT_* configuration:\n  %v\n", err)
		os.Exit(2)
	}
	return rootCmd.Execute()
}

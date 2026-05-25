// Package inject provides harness-only fault-injection primitives for
// install-recovery scenarios. Three primitives — KillHere, ErrorHere,
// StallHere — fire at named sites in the production code when activated
// by environment variables. In production (env unset) every primitive is
// a no-op with negligible cost: a single os.Getenv read.
//
// Activation:
//
//   STATBUS_INJECT_AT=<class-name>
//       Selects the active injection class. The class name is matched
//       verbatim against the call-site name passed to the primitive.
//       Class names are registered in this file (see classes); unknown
//       names are rejected at startup by Validate.
//
//   STATBUS_INJECT_STALL_UNTIL_REMOVED_FILE=<path>
//       Only meaningful for stall classes. Names the release file whose
//       deletion ends the stall. The harness creates the file before
//       invoking ./sb, then deletes it to release the stall once it has
//       observed the desired state (e.g. a concurrent install attempt).
//
// Class registry (see classes below):
//
//   Eight Layer 2 kill classes seed the canonical injection points for
//   "killed by the OS / orchestrator" simulation across the upgrade's
//   destructive phases. The canonical case — "killed-by-system-after-
//   migration-commit-before-recorded" — covers the ~ms window between a
//   migration's outer transaction commit and the corresponding INSERT
//   into db.migration, which is the deterministic source of forward-
//   recovery breakage on master (re-attempts fail on "relation already
//   exists"; only restore can complete the recovery coherently).
//
//   One concurrent-install stall class lets a scenario hold the upgrade
//   pipeline at a known site while a second ./sb install attempts to
//   start, exercising probe 2 (live-upgrade) detection.
//
// Naming discipline:
//
//   Each class name describes the real-world failure being simulated,
//   not the call-site identifier. Format:
//
//       <real-world-cause>-<phase>-<detail>
//
//   A scenario author reads the name and instantly knows what is being
//   simulated, without reading the code where the primitive fires.
//
// Validation:
//
//   Validate enforces a strict truth table at process startup. Any
//   inconsistent combination (unknown class, stall file without class,
//   release file set for a non-stall class, stall class missing release
//   file) fails loudly so a misconfigured harness scenario cannot
//   silently produce a vacuous "pass".
//
//   Operators must NOT set these env vars in production. Treat them with
//   the same care as --inside-active-upgrade: if you see them in a
//   production environment, something has gone wrong.
package inject

import (
	"errors"
	"fmt"
	"os"
	"sort"
	"strings"
	"time"
)

// EnvActiveAt is the env var whose value selects the active injection
// class. Empty means "production run — every primitive is a no-op".
const EnvActiveAt = "STATBUS_INJECT_AT"

// EnvStallReleaseFile is the env var naming the release file for stall
// classes. The stall ends when the file is removed by the harness.
const EnvStallReleaseFile = "STATBUS_INJECT_STALL_UNTIL_REMOVED_FILE"

// Kind discriminates the three primitive shapes. Each registered class
// is bound to exactly one Kind; mixing (e.g. activating a Kill class with
// a stall release file) fails Validate.
type Kind int

const (
	// KindKill — primitive exits the process immediately, no defers run.
	// Mirrors SIGKILL semantics for cleanup-skipping.
	KindKill Kind = iota
	// KindError — primitive returns an injected error. Mirrors operation
	// failure return paths (SQL error, syscall failure).
	KindError
	// KindStall — primitive waits on a release file. Used both for
	// concurrent-detection scenarios and as a building block for
	// externally-triggered SIGKILL at a precise pipeline point.
	KindStall
	// KindExternal — registered for inventory completeness; no in-code
	// inject.* call fires for this class. Scenarios that exercise the
	// class do so via external harness orchestration (e.g. start an
	// install, observe the resulting flag state; restart a container,
	// time the next service start). The env var STATBUS_INJECT_AT may
	// be set to a KindExternal name for journal-grep auditability but
	// changes no production behavior. Validate treats it like Kill /
	// Error w.r.t. the stall-release-file rule (set the file → REJECT).
	KindExternal
)

// String yields the human-readable form used in Validate diagnostics.
func (k Kind) String() string {
	switch k {
	case KindKill:
		return "kill"
	case KindError:
		return "error"
	case KindStall:
		return "stall"
	case KindExternal:
		return "external"
	}
	return fmt.Sprintf("Kind(%d)", int(k))
}

// classes is the registry of recognized injection class names. The map
// is intentionally a single source of truth: adding a class here is the
// ONLY place a new injection point becomes valid. Unknown names fail
// Validate, catching typos before they can cause silent "pass".
//
// Additions: the initial seed covers the canonical Layer 2 case (split
// into two stall variants so the harness can deliver real SIGKILL —
// observably different from os.Exit(137) in the parent's WIFEXITED
// status and systemd's recorded terminal state) and the concurrent-
// install detection case. Remaining Layer 2 classes are registered
// here as kill-shape placeholders; their call sites land as scenarios
// surface them.
var classes = map[string]Kind{
	// Layer 2 kill classes — process killed mid-upgrade, recovery via
	// next-install's recoverFromFlag → forward-then-restore pipeline.
	// The canonical "after-migration-commit-before-recorded" case is
	// modeled as two stall variants below (real-SIGKILL harness path).
	"killed-by-system-during-preswap-backup":                 KindKill,
	"killed-by-system-during-preswap-checkout":               KindKill,
	"killed-by-system-during-binary-swap":                    KindKill,
	"killed-by-system-during-individual-migration-execution": KindKill,
	"killed-by-system-between-migrations":                    KindKill,
	"killed-by-system-during-container-restart":              KindKill,
	"killed-by-system-during-builtin-rollback":               KindKill,

	// Canonical Layer 2 case — real-SIGKILL via harness. The migrate
	// subprocess (./sb migrate up under applyPostSwap) stalls at the
	// ~ms window between a migration's outer-transaction commit and
	// the db.migration INSERT; the harness sends real SIGKILL to the
	// chosen target PID for genuine signal semantics. Two variants
	// distinguish the recovery layer being exercised:
	//
	//   migrate-subprocess-killed-after-commit-before-recorded
	//     Harness SIGKILLs the migrate subprocess. Parent's
	//     postSwapFailure catches the subprocess death and runs the
	//     in-process forward-then-restore (Layer 0 in-process
	//     recovery). End state: row=rolled_back via parent's rollback.
	//
	//   upgrade-service-parent-killed-after-commit-before-recorded
	//     Harness SIGKILLs the upgrade-service parent (and the now-
	//     orphan migrate subprocess) while the stall is held. Flag
	//     file remains; row stays in_progress; partial migration
	//     persists with db.migration row missing. Next ./sb install
	//     detects crashed-upgrade and runs Layer 2 recovery via
	//     recoverFromFlag (forward fails on "relation already exists";
	//     falls through to rsync-restore).
	"migrate-subprocess-killed-after-commit-before-recorded":     KindStall,
	"upgrade-service-parent-killed-after-commit-before-recorded": KindStall,

	// Layer 1 territory — systemd TimeoutStartSec drives SIGTERM at
	// the configured timeout. The signal IS catchable (the upgrade-
	// service's signal handler from #101 acts on it), but if the
	// in-flight operation cannot wind down before systemd escalates
	// to SIGKILL, the result is a restart loop. Registered now;
	// scenarios that wire the call sites land later.
	//
	//   service-startup-slower-than-systemd-unit-timeout
	//     The upgrade-service's startup phase (boot migrate up + main-
	//     loop initialization, pre-READY=1) blows past TimeoutStartSec.
	//     systemd SIGTERMs; the service has limited time to handle
	//     gracefully before SIGKILL escalation.
	//
	//   migration-slower-than-systemd-unit-timeout
	//     A single migration's SQL execution exceeds the unit's
	//     remaining timeout budget (after sd_notify EXTEND_TIMEOUT_USEC
	//     ticks, ~120 s each — Fix 1's heartbeat). The harness can
	//     simulate this by stalling at the per-migration loop iteration
	//     in migrate.runUp.
	"service-startup-slower-than-systemd-unit-timeout": KindStall,
	"migration-slower-than-systemd-unit-timeout":       KindStall,

	// Bug 1 — `d416a50a0` introduced a ticker scoped only to the migrate-
	// up subprocess. `extendCancel()` fires before archiveBackup's tar,
	// which on real data (rune: 35 GB) takes minutes. The main goroutine
	// is parked in `runCommand("tar", ...)` with no WATCHDOG=1 emitter;
	// WatchdogSec=120 s expires; systemd SIGABRTs; restart loop forever.
	//
	// Scenario 26 stalls inside archiveBackup for STALL_HOLD_S=180 s
	// (> WatchdogSec=120 s). Without the active-phase ticker covering
	// archiveBackup, NRestarts climbs and the upgrade row never reaches
	// 'completed'. With the fix (wider ticker scope), NRestarts stays
	// at baseline.
	"archive-backup-stall-active-phase-watchdog": KindStall,

	// Concurrent-install detection (probe 2 — live-upgrade refusal).
	"concurrent-install-attempted-during-migrate-up": KindStall,

	// Forensics-surfaced classes from the install state-machine
	// investigation. Each names a real-world failure mode observed in
	// production or surfaced by a near-miss; the scenarios that
	// exercise them land in follow-up commits. Registry-only entry
	// for now reserves the slot in the inventory and gates the
	// scenarios on Validate-known names.
	//
	//   migration-deadlocks-with-running-worker-holding-table-lock (R1)
	//     A worker session holds AccessShareLock on a table while a
	//     migration's CREATE/DROP INDEX (or other DDL) tries to take
	//     AccessExclusiveLock on the same table. Lock manager parks the
	//     migration indefinitely; without a quiesce-services-before-DDL
	//     fix, the upgrade hangs and an operator must intervene.
	//     Harness setup uses start_continuous_worker_workload; the
	//     stall site can be the existing migrate-up site OR a new one
	//     inside the migration's DDL execution.
	//
	//   install-flag-released-without-clean-handoff-detected-as-stale (R3)
	//     Install exits cleanly but leaves the flag file in place; the
	//     upgrade-service on its next tick observes a flag with a dead
	//     holder PID and interprets the state as a crashed install,
	//     clearing the flag. The scenario is pure external orchestration:
	//     run install to clean exit, then observe the service's
	//     behavior. KindExternal — no in-code injection site.
	//
	//   service-watchdog-timeout-during-db-reconnect-after-container-restart (Race D)
	//     The upgrade-service's reconnect loop runs without pinging
	//     WATCHDOG=1 to systemd. If the DB container restart drags the
	//     reconnect past WatchdogSec (~2 min default), systemd SIGABRTs
	//     the service. The fix is to ping WATCHDOG=1 from inside the
	//     loop; the scenario validates restart-counter-bounded recovery.
	//
	//   advisory-lock-attempted-before-db-ready-after-container-restart (Race E)
	//     The DB container is just restarting when the upgrade-service
	//     fires up; the service's first advisory-lock attempt fails on
	//     a not-yet-ready DB and the process exits 42. systemd restarts
	//     after backoff, the second attempt succeeds. KindExternal —
	//     no in-code site; the scenario orchestrates the container
	//     restart timing externally.
	//
	//   seed-restore-runs-on-populated-database-destroying-data (R5) — DATA LOSS
	//     The install state machine routes to the seed-restore step
	//     against a database that already has user data. pg_restore of
	//     the seed dump silently destroys the existing rows. Per
	//     forensics, the fix is to classify DB content before
	//     dispatching the seed step (populated → migrate-forward;
	//     empty → restore). The scenario asserts data survives the
	//     install — the R5 catastrophic-loss detector
	//     (assert_demo_data_present) is the load-bearing check.
	//     KindStall because the harness needs a stall site inside the
	//     seed step to intervene before destructive completion; the
	//     scenario's "external precondition" half is having a populated
	//     DB at install time.
	"migration-deadlocks-with-running-worker-holding-table-lock":          KindStall,
	"install-flag-released-without-clean-handoff-detected-as-stale":       KindExternal,
	"service-watchdog-timeout-during-db-reconnect-after-container-restart": KindStall,
	"advisory-lock-attempted-before-db-ready-after-container-restart":     KindExternal,
	"seed-restore-runs-on-populated-database-destroying-data":             KindStall,
}

// KindOf returns the Kind for a registered class, or (0, false) if the
// name is unknown. Exposed for tests and Validate.
func KindOf(name string) (Kind, bool) {
	k, ok := classes[name]
	return k, ok
}

// classNames returns a sorted list of registered class names, used in
// Validate's diagnostic message so operators see what's available.
func classNames() []string {
	names := make([]string, 0, len(classes))
	for n := range classes {
		names = append(names, n)
	}
	sort.Strings(names)
	return names
}

// Validate enforces the activation truth table at process startup. Call
// from cmd.Execute (./sb root) once, before any subcommand dispatch.
// Returns nil on the production-run path (env vars unset).
//
// Truth table (per the locked design package):
//
//   ACTIVE_AT     STALL_FILE   Verdict
//   ------------- ------------ ---------------------------------------------
//   unset         unset        Valid (production run)
//   unset         set          REJECT — file without class
//   set, unknown  any          REJECT — unknown class name (typo protection)
//   set, kill     unset        Valid
//   set, kill     set          REJECT — release file set for non-stall class
//   set, error    unset        Valid
//   set, error    set          REJECT — release file set for non-stall class
//   set, stall    unset        REJECT — stall requires release file
//   set, stall    set          Valid
//   set, external unset        Valid (no in-code site fires; orchestration external)
//   set, external set          REJECT — release file set for non-stall class
func Validate() error {
	active := os.Getenv(EnvActiveAt)
	stallFile := os.Getenv(EnvStallReleaseFile)

	if active == "" {
		if stallFile != "" {
			return fmt.Errorf("%s is set (%q) but %s is unset — release file requires an active stall class",
				EnvStallReleaseFile, stallFile, EnvActiveAt)
		}
		return nil
	}

	kind, ok := classes[active]
	if !ok {
		return fmt.Errorf("%s=%q is not a known injection class\nvalid classes:\n  %s",
			EnvActiveAt, active, strings.Join(classNames(), "\n  "))
	}

	switch kind {
	case KindKill, KindError, KindExternal:
		if stallFile != "" {
			return fmt.Errorf("%s=%q is a %s class but %s=%q is set — release file is only meaningful for stall classes",
				EnvActiveAt, active, kind, EnvStallReleaseFile, stallFile)
		}
	case KindStall:
		if stallFile == "" {
			return fmt.Errorf("%s=%q is a stall class but %s is unset — stall requires a release file path",
				EnvActiveAt, active, EnvStallReleaseFile)
		}
	default:
		return fmt.Errorf("internal: class %q registered with unhandled Kind %v", active, kind)
	}
	return nil
}

// KillHere — process dies immediately at the named site, no defers run.
// Matches SIGKILL semantics for cleanup-skipping.
//
// The exit code is 137 by convention (128 + SIGKILL=9), aligning with the
// shell-visible status a real SIGKILL produces. Harness assertions can
// match on this code to confirm the kill happened at the intended site
// versus some other process failure.
//
// Calling KillHere with an unknown name is silently a no-op — the same
// shape as the production no-op path. Validate (run at process startup)
// is the single point that rejects unknown active classes.
func KillHere(name string) {
	if os.Getenv(EnvActiveAt) == name {
		os.Exit(137)
	}
}

// ErrorHere — returns an injected error when activated at the named site,
// nil otherwise. Mimics SQL-error / operation-failure return paths so a
// scenario can drive recovery through error branches the harness cannot
// reach via real-world flakiness.
func ErrorHere(name string) error {
	if os.Getenv(EnvActiveAt) == name {
		return fmt.Errorf("injected failure: %s", name)
	}
	return nil
}

// StallHere — process waits at the named site until the release file is
// removed. Used by harness scenarios to hold the upgrade pipeline at a
// known point while the harness observes side effects (e.g. starts a
// second ./sb install and asserts the live-upgrade refusal).
//
// Polling interval is 100ms — short enough that a harness teardown
// observes the release within ~1 tick, long enough to keep the CPU
// budget negligible.
//
// If EnvStallReleaseFile is unset when a stall class is active, the
// primitive returns immediately. This is defensive: Validate is the
// single point that rejects this combination, but the primitive guards
// against a Validate skip (e.g. a future refactor that misses calling
// Validate at startup).
func StallHere(name string) {
	if os.Getenv(EnvActiveAt) != name {
		return
	}
	releaseFile := os.Getenv(EnvStallReleaseFile)
	if releaseFile == "" {
		return
	}
	for {
		if _, err := os.Stat(releaseFile); err != nil {
			if errors.Is(err, os.ErrNotExist) {
				return
			}
			// Any other stat error (permissions, ENOTDIR mid-path) —
			// treat as released so a misconfigured release-file path
			// can't wedge the upgrade indefinitely. Validate already
			// guards against the empty-string case at startup.
			return
		}
		time.Sleep(100 * time.Millisecond)
	}
}

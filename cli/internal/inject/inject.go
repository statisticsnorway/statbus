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
//   the same care as --post-upgrade-fixup: if you see them in a
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

// EnvKillAndRemoveFile names the one-shot ARMING file for KILL classes.
// When set, KillHere fires at the named site IFF the file exists, and
// removes it (os.Remove) BEFORE os.Exit — so the kill fires EXACTLY ONCE
// per arming; an absent file is a no-op. Symmetric with
// EnvStallReleaseFile (both bind a class to a filesystem handle the
// harness controls): the harness ARMS by creating the file; the inject
// CONSUMES it on the single fire.
//
// A filesystem marker is REQUIRED (not a sync.Once / in-memory flag)
// because the upgrade pipeline re-execs the process mid-flight —
// syscall.Exec(sbPath, os.Args, os.Environ()) in newSbUpgradingFailure's
// inline-mode hand-off (service.go) — which preserves the env but wipes
// all in-memory state. The now-inline crash recovery (STATBUS-017) then
// re-enters the same kill site with the env still set; only a consumed-
// on-disk marker stops it re-killing the recovery migrate. The file
// survives the exec; an in-memory one-shot would not.
//
// Naming: intent-first + honest. "AND_REMOVE" is true regardless of order
// (remove precedes exit); "THEN_REMOVE" would be mechanically false.
const EnvKillAndRemoveFile = "STATBUS_INJECT_KILL_AND_REMOVE_FILE"

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

	// STATBUS-071 — the AT-TARGET resume-crash producer. Fires in
	// applyNewSbUpgrading immediately AFTER the migrate step returns success but
	// BEFORE the health check: the earliest instant of the genuine at-target
	// window (db.migration at on-disk max + binary at target ⇒ recovery reads
	// ObservedAlreadyAtNew), maximizing the forward work the resume must redo.
	// DELIBERATELY DUAL-USE — do NOT remove after its first consumer lands:
	//   (1) the transient-db-backoff arc's RESOLVES arm needs an at-target crashed
	//       flag so the post-backoff re-read resolves to FORWARD completion; and
	//   (2) the flagless-selfheal real-path successor (STATBUS-071 comment #17)
	//       needs exactly a real upgrade killed AT-TARGET as the state whose flag
	//       it truncates. One hook serves two queued map needs.
	"killed-by-system-after-migrations-before-completion": KindKill,

	// Canonical Layer 2 case — real-SIGKILL via harness. The migrate
	// subprocess (./sb migrate up under applyNewSbUpgrading) stalls at the
	// ~ms window between a migration's outer-transaction commit and
	// the db.migration INSERT; the harness sends real SIGKILL to the
	// chosen target PID for genuine signal semantics. Two variants
	// distinguish the recovery layer being exercised:
	//
	//   migrate-subprocess-killed-after-commit-before-recorded
	//     Harness SIGKILLs the migrate subprocess. Parent's
	//     newSbUpgradingFailure catches the subprocess death and runs the
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

	// Mid-transaction kill — the GREEN control for the commit↔record boundary
	// (cell b vs the after-commit cells c/e). A migration is parked INSIDE the
	// outer transaction enveloping its statements (after BEGIN, before COMMIT);
	// the harness SIGKILLs the psql child so Postgres aborts the uncommitted tx
	// — leaving NO committed-but-unrecorded state. Recovery re-applies the
	// now-cleanly-pending migration and the upgrade COMPLETES (no wedge). A
	// Go-side StallHere cannot reach mid-tx (the whole tx runs inside the psql
	// subprocess that the Go parent is blocked reading), so this class drives a
	// SQL pause spliced into the migration's stdin by migrate.runPsqlFile via
	// MidTxPauseSQL — see that
	// helper. KindStall: the harness sets a release file (Validate + the
	// wait_for_inject_stall_ready "armed" sentinel); the actual interruption is
	// the SIGKILL, exactly as the after-commit stalls above. Drives scenario
	// 3-postswap-mid-tx-kill.
	"killed-by-system-during-migration-tx-before-commit": KindStall,

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

	// STATBUS-031 — rollback()'s restoreDatabase rsync is heartbeat-SILENT
	// (onAdvance=nil, output to progress.File()). On the STARTUP recovery path
	// (recoverFromFlag → recoveryRollback → rollback → restoreDatabase) NO watchdog
	// ticker is armed, so a >WatchdogSec restore SIGABRTs mid-restore → the flag
	// survives → next boot restores from scratch → indefinite loop. Scenario
	// 4-rollback-restore-watchdog stalls inside restoreDatabase for
	// STALL_HOLD_S > WatchdogSec=120s on a startup-recovery rollback. UNFIXED:
	// NRestarts climbs, the rollback never completes (RED). With the always-ping
	// ticker wrapping rollback() (STATBUS-031): NRestarts stays at baseline, the
	// rollback completes, the flag is removed (GREEN).
	"restore-db-stall-watchdog": KindStall,

	// STATBUS-109 — the transient-backoff proof legs. The recoverFromFlag
	// classify-then-act path (Phase=NewSbUpgrading) reads the observed state to
	// decide direction; a NAMED transient cause (db-unreachable / commit-not-
	// fetched) is retried IN-PROCESS via backoffRetry (clears → re-dispatch;
	// exhausts → data-safe rollback). To PROVE that live, the arc must make the
	// observed-state read fail transiently — and the window between the recovery
	// boot's EnsureDBUp+connect and this verify is a sub-second Go-internal span
	// nothing external can reach. This stall (right before verifyUpgradeObserved
	// StateEx) is the sanctioned way in (AC#5 residue, architect-ruled 2026-07-15):
	// the arc stalls here, induces the transient condition (docker pause db →
	// db-unreachable), releases, and observes the backoff live. The alternatives —
	// racing the sub-second window externally, or pre-boot pauses that never reach
	// this branch — are the forbidden window-racing genre / miss the site entirely.
	"stalled-before-resuming-verify": KindStall,

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
// Truth table (per the locked design package). STALL_FILE is meaningful
// ONLY for stall classes; KILL_FILE (the one-shot arming file) ONLY for
// kill classes. Every cross-combination is rejected so a misconfigured
// scenario fails loudly instead of producing a vacuous "pass".
//
//   ACTIVE_AT     STALL_FILE  KILL_FILE  Verdict
//   ------------- ----------- ---------- -------------------------------------
//   unset         unset       unset      Valid (production run)
//   unset         set         any        REJECT — stall file without class
//   unset         unset       set        REJECT — kill arming file without class
//   set, unknown  any         any        REJECT — unknown class name (typo guard)
//   set, kill     unset       unset      Valid (persistent kill)
//   set, kill     unset       set        Valid (one-shot file-armed kill)
//   set, kill     set         any        REJECT — release file is stall-only
//   set, error    unset       unset      Valid
//   set, error    set         any        REJECT — release file is stall-only
//   set, error    unset       set        REJECT — arming file is kill-only
//   set, stall    set         unset      Valid
//   set, stall    unset       any        REJECT — stall requires release file
//   set, stall    set         set        REJECT — arming file is kill-only
//   set, external unset       unset      Valid (no in-code site; orchestration external)
//   set, external set         any        REJECT — release file is stall-only
//   set, external unset       set        REJECT — arming file is kill-only
func Validate() error {
	active := os.Getenv(EnvActiveAt)
	stallFile := os.Getenv(EnvStallReleaseFile)
	killFile := os.Getenv(EnvKillAndRemoveFile)

	if active == "" {
		if stallFile != "" {
			return fmt.Errorf("%s is set (%q) but %s is unset — release file requires an active stall class",
				EnvStallReleaseFile, stallFile, EnvActiveAt)
		}
		if killFile != "" {
			return fmt.Errorf("%s is set (%q) but %s is unset — arming file requires an active kill class",
				EnvKillAndRemoveFile, killFile, EnvActiveAt)
		}
		return nil
	}

	kind, ok := classes[active]
	if !ok {
		return fmt.Errorf("%s=%q is not a known injection class\nvalid classes:\n  %s",
			EnvActiveAt, active, strings.Join(classNames(), "\n  "))
	}

	switch kind {
	case KindKill:
		// The release file is stall-only; reject it for a kill class. The
		// kill arming file is OPTIONAL here: unset → persistent kill, set →
		// one-shot file-armed kill (both valid).
		if stallFile != "" {
			return fmt.Errorf("%s=%q is a %s class but %s=%q is set — release file is only meaningful for stall classes",
				EnvActiveAt, active, kind, EnvStallReleaseFile, stallFile)
		}
	case KindError, KindExternal:
		if stallFile != "" {
			return fmt.Errorf("%s=%q is a %s class but %s=%q is set — release file is only meaningful for stall classes",
				EnvActiveAt, active, kind, EnvStallReleaseFile, stallFile)
		}
		if killFile != "" {
			return fmt.Errorf("%s=%q is a %s class but %s=%q is set — arming file is only meaningful for kill classes",
				EnvActiveAt, active, kind, EnvKillAndRemoveFile, killFile)
		}
	case KindStall:
		if stallFile == "" {
			return fmt.Errorf("%s=%q is a stall class but %s is unset — stall requires a release file path",
				EnvActiveAt, active, EnvStallReleaseFile)
		}
		if killFile != "" {
			return fmt.Errorf("%s=%q is a %s class but %s=%q is set — arming file is only meaningful for kill classes",
				EnvActiveAt, active, kind, EnvKillAndRemoveFile, killFile)
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
	if os.Getenv(EnvActiveAt) != name {
		return
	}
	// One-shot, file-armed variant. When EnvKillAndRemoveFile is set, the
	// kill is gated on ATOMICALLY consuming the marker: os.Remove returns nil
	// IFF the file existed and was removed, so the kill fires exactly once per
	// arming and a second pass through this site no-ops. This is the load-
	// bearing path for the now-inline crash recovery (STATBUS-017): the
	// upgrade pipeline's syscall.Exec re-exec preserves the env, so the
	// recovery migrate re-enters this exact site; with the marker already
	// consumed it runs clean, modelling a real ONE-TIME OS kill (the migrate
	// re-applies → upgrade completes).
	//
	// Consume-gates-kill is deliberate (NO separate os.Stat). A present-but-
	// unremovable marker (permissions, mid-path race) yields a non-nil error
	// → we DO NOT exit. A stat-then-remove form would be TOCTOU and, worse, a
	// stat-says-present + remove-fails path would re-kill on EVERY pass — the
	// exact wedge this primitive exists to prevent. os.Remove is the single
	// atomic decision point; no defers run after os.Exit, which is fine
	// because the consume already happened.
	if armFile := os.Getenv(EnvKillAndRemoveFile); armFile != "" {
		if err := os.Remove(armFile); err == nil {
			os.Exit(137)
		}
		return
	}
	// Persistent variant — fires every time the class is active. Retained
	// for scenarios that genuinely model a site that re-kills on every pass.
	os.Exit(137)
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
	// Observable marker (STATBUS-071): the harness polls this line to know the
	// stall is REACHED before it acts (e.g. the transient-backoff arc waits for
	// this, then pauses the DB, then removes the release file). Without it a
	// harness can only guess-time the sub-second window to the stall. Emitted once,
	// only on the active-injection path — no-op in production (env unset above).
	fmt.Printf("INJECT: stalling at %q until %s is removed\n", name, releaseFile)
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

// MidTxPauseSQL returns a SQL snippet to splice into the OUTER transaction that
// envelops a migration's statements (after BEGIN, before COMMIT) when the named
// class is active, "" otherwise. It exists because the three
// primitives above are Go-side and cannot reach mid-transaction: a migration's
// whole BEGIN…END runs inside the psql subprocess that migrate.runPsqlFile feeds
// via stdin and then blocks reading. The ONLY way to park a migration after its
// BEGIN but before its COMMIT is to make the SQL itself pause.
//
// runPsqlFile, when this returns non-empty, prepends "BEGIN;\n"+snippet+"\n" to
// the migration's stdin. The migration file's own leading BEGIN then becomes a
// warned no-op ("there is already a transaction in progress" — a WARNING, not an
// error, so ON_ERROR_STOP does not trip), and the file's END commits the single
// outer transaction. Net: the snippet runs after BEGIN, before COMMIT.
//
// The snippet is a long pg_sleep — the park. The harness detects the parked
// subprocess (wait_for_inject_stall_ready) and SIGKILLs the psql CHILD; Postgres
// aborts the uncommitted tx, so NO committed-but-unrecorded state is left behind.
// The recovery re-run has the env unset → "" → unmodified stdin → the migration
// applies cleanly → the upgrade completes. THAT clean re-apply is the GREEN
// property cell b proves (contrast cells c/e, where a committed-but-unrecorded
// migration wedges recovery — STATBUS-017).
//
// The release file (required by Validate for this KindStall class) is the
// harness's "armed" sentinel + wait_for_inject_stall_ready handle, NOT the
// release mechanism — SQL cannot poll a file, so the interruption is the SIGKILL.
// Guarded on the release file being set too, mirroring StallHere's defensive
// check: active class + no release file → no park (Validate already rejects this
// combination at startup; this is belt against a Validate skip).
//
// Production no-op: env unset → "" → runPsqlFile's stdin is byte-identical to
// today. Only a harness run that sets STATBUS_INJECT_AT to this exact class
// changes the stream.
func MidTxPauseSQL(name string) string {
	if os.Getenv(EnvActiveAt) != name {
		return ""
	}
	if os.Getenv(EnvStallReleaseFile) == "" {
		return ""
	}
	// 3600 s upper bound on the park: the harness SIGKILLs the psql child well
	// before this. The bound is a backstop so a harness that forgets to kill
	// cannot hang the migration past runPsqlFile's own 60-min ceiling.
	return "SELECT pg_sleep(3600);"
}

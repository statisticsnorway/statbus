package upgrade

import (
	"context"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"strconv"
	"time"
)

// Historical note (2026-05-23): sdNotifyExtendTimeout was removed from
// this file alongside the active-phase WATCHDOG=1 fix for Race B.
// Original design assumed applyNewSbUpgrading ran in systemd's "activating"
// phase (pre-READY=1), where EXTEND_TIMEOUT_USEC is the right primitive.
// Evidence (Service.Run sends READY=1 before the main loop; applyNewSbUpgrading
// is reached from inside the main loop via executeUpgrade) showed the
// SCHEDULED path's applyNewSbUpgrading runs in the active phase, where
// EXTEND_TIMEOUT_USEC is a no-op against WatchdogSec and only WATCHDOG=1
// resets the watchdog deadline. Confirmed by operator's dev journalctl:
// UNIT_RESULT=watchdog, NRestarts=111 — Fix 1's EXTEND_TIMEOUT_USEC ticker
// did not prevent the watchdog from firing. The helper had no other call
// site, so it was deleted rather than preserved as defensive cover (dead
// code paths must be removed).
//
// Addendum (2026-05-27, plan upgrade-resume-structural-whole.md):
// the original note's "applyNewSbUpgrading always runs active-phase" WAS true only
// for the SCHEDULED path. The exit-42 RESUME path reached applyNewSbUpgrading from
// recoverFromFlag DURING Service.Run startup — before READY=1 — so it ran in
// the START phase under TimeoutStartSec, a fixed budget that can't bound
// DB-size-scaled work, which blew the budget and wedged NO/rune in a
// restart loop (~40 h). The fix (plan piece #2, B1) moves READY=1 + LISTEN to
// BEFORE recoverFromFlag, so the resume now ALSO runs in the ACTIVE phase —
// making "applyNewSbUpgrading always runs active-phase" universally true (#2 makes
// the WHOLE resume active-phase, not just the post-completion tail). The
// EXTEND_TIMEOUT_USEC deletion stays correct: the
// active phase needs only WATCHDOG=1, never the start-phase extender.
//
// What active-phase BUYS today vs. what's still coming: post-#2, WatchdogSec
// (not TimeoutStartSec) governs the resume, and the existing applyNewSbUpgrading
// WATCHDOG=1 ticker keeps it alive across long steps. The ticker is still a
// BLIND 30 s timer here — it pings regardless of whether the pipeline is
// advancing. Plan piece #3 (progress-gated watchdog, separate commit) makes
// the ping conditional on real progress so a genuinely HUNG active-phase step
// is caught. Until #3 lands, the guarantee #2 provides is precisely "the
// resume runs active-phase under WatchdogSec" — no longer start-phase-wedged.

// Heartbeat design (task #42, unified from task #37's 4-commit chain):
//
// A single function, emitHeartbeat, is the SOURCE OF TRUTH for "this
// service is alive and making progress." It fires three signals:
//
//   1. sd_notify(WATCHDOG=1) — systemd's watchdog. With
//      WatchdogSec=120 in the unit file, a 120s silence triggers
//      kill + restart.
//   2. Write the current unix timestamp (seconds since epoch, as
//      decimal text) to <projDir>/tmp/upgrade-service-heartbeat —
//      a file-system-level liveness indicator that external
//      observers inspect without needing the service's API.
//      `./cloud.sh health` (commit cea4eda05) reads the FILE
//      CONTENT to report per-slot heartbeat age, so the content
//      must be the timestamp itself; os.WriteFile also bumps mtime
//      as a side effect so mtime-only readers also work.
//   3. fmt.Print of the log line (handled by ProgressLog.Write) —
//      systemd journal entry identifying the last progress point.
//
// Unification matters because three separate mechanisms drift: a bug
// could update one and miss the others. Every emitHeartbeat call fires
// all three, always. If emitHeartbeat isn't called, progress didn't
// happen — and systemd notices within WatchdogSec.
//
// The Apr 23 2026 statbus_dev hang (task #37) was the motivating
// incident: the old `watchdog` auto-ticker (removed in this commit)
// pinged systemd from its own goroutine, so systemd saw "alive"
// for 9h54m while the main goroutine was parked on a pgx
// cancellation race. Consolidating heartbeats onto the main
// goroutine — via progress.Write, and via a dedicated main-loop
// heartbeat ticker — makes "main goroutine is alive" the correct
// semantic meaning of "service is alive."
//
// For legitimately long-running steps that don't naturally emit
// progress.Write calls (docker pulls, rsync backups), the caller
// wraps the step with a ticker goroutine that emits progress every
// 30s. That goroutine-level ping is a necessary blind-spot: during
// the wrapped step, a simultaneous main-goroutine hang would not be
// caught by systemd. In exchange, legitimate multi-minute subprocess
// work doesn't trigger false restarts. The trade-off is acceptable:
// pullImagesForCommitShort has its own 10-min ctx timeout, so a stuck subprocess
// is bounded.

// sdNotify sends a message to the systemd NOTIFY_SOCKET.
// No-op if not running under systemd (NOTIFY_SOCKET unset).
//
// This is the low-level primitive used by READY=1 at startup and
// WATCHDOG=1 from emitHeartbeat. Callers OTHER than emitHeartbeat
// should be rare — almost all liveness signalling goes through
// emitHeartbeat so the three signals stay unified.
//
// One legitimate ad-hoc callsite is the applyNewSbUpgrading WATCHDOG=1 ticker
// (service.go). applyNewSbUpgrading runs after Service.Run has sent READY=1 on BOTH
// paths: the SCHEDULED path (the main loop dispatches executeUpgrade
// post-READY) and, since plan piece #2 (READY=1 moved before recoverFromFlag),
// the exit-42 RESUME path. So the ticker is active-phase in both cases and
// WATCHDOG=1 (not the deleted EXTEND_TIMEOUT_USEC) is what resets the watchdog
// deadline. (NOTE: the ticker is still a blind 30 s timer — plan piece #3
// progress-gates it so a hung step stops the pings; until then it keeps the
// unit alive across any long step, advancing or not.)
func sdNotify(state string) {
	socket := os.Getenv("NOTIFY_SOCKET")
	if socket == "" {
		return
	}
	conn, err := net.Dial("unixgram", socket)
	if err != nil {
		return
	}
	defer conn.Close()
	conn.Write([]byte(state))
}

// applyNewSbUpgradingStallThreshold is how long applyNewSbUpgrading's gated watchdog
// ticker tolerates output-silence before it STOPS pinging WATCHDOG=1 — at
// which point systemd's WatchdogSec (=120 s per ops/statbus-upgrade.service)
// trips and SIGABRTs the hung unit. 3 min > the 120 s deadline so the gate's
// decision (stop pinging) is what lets the watchdog fire, not a race between
// the two timers: a step that goes silent stops bumping lastAdvanceAt, the
// next tick (≤30 s later) sees sinceLastAdvance ≥ 3 min and skips, and after
// 120 s of skipped pings systemd acts. A live step bumps via per-line output
// (PrefixWriter onLine → progress.bump) or step-boundary progress.Write well
// inside 3 min, so it never trips. The migrate/recreate step — silent for
// minutes on a single big DDL — is exempted via deferGating (it is bounded by
// its OWN runCommandToLog timeout + task #7's cumulative-activating cap).
const applyNewSbUpgradingStallThreshold = 3 * time.Minute

// applyNewSbUpgradingWatchdogCadence is the gated ticker's tick interval: 1/4 of the
// 120 s WatchdogSec budget gives wide jitter tolerance with trivial CPU cost.
const applyNewSbUpgradingWatchdogCadence = 30 * time.Second

// migrateUpTimeoutDefault is the STATBUS-095 ceiling: no migration on the
// upgrade path runs longer than 12 hours. A genuinely big Norway-size migration
// (CREATE INDEX / table rewrite on a huge table) may legitimately need most of a
// day; the prior 30-minute bound was too tight now that boot-migrate applies
// every upgrade's real migration delta (executeUpgrade Step 6b's unconditional
// post-swap handoff). A migration exceeding this is KILLED at the ctx deadline
// (the runCommandToLog CommandContext), the #14 orphan-terminate reaps the
// in-DB backend the host-side SIGKILL leaves behind, and the failed step routes
// by the existing path: observed state reads Behind → in-process rollback →
// rolled_back. This IS the ticket's AC#4 reconciliation — the raise from 30m.
const migrateUpTimeoutDefault = 12 * time.Hour

// migrateUpTimeoutFloor guards the STATBUS_MIGRATE_UP_TIMEOUT override: a value
// below this is clamped up (+ a WARN), so a fat-fingered override cannot make
// the ceiling fire mid-legitimate-migration. 5s is low enough for the
// STATBUS-095 ceiling arc to trigger the same real kill path in SECONDS (AC#2 —
// the load-bearing criterion) yet high enough that no real migration hits it.
const migrateUpTimeoutFloor = 5 * time.Second

// MigrateUpTimeout bounds every `sb migrate up` subprocess the upgrade system
// runs: the boot-migrate schema-skew guard in Service.Run, the applyNewSbUpgrading
// migrate step, and (via cli/cmd — hence exported) the inline `./sb install`
// crash-recovery boot-migrate. A single big DDL on a large DB is legitimately
// SILENT for many minutes — see the applyNewSbUpgradingStallThreshold note above — so
// the migrate sites are exempted from output-gating (always-ping WATCHDOG=1 for
// the duration) and bounded by THIS timeout instead of the watchdog.
//
// One shared value so the sites cannot drift (STATBUS-012): boot-migrate once
// sat at 5 m while the applyNewSbUpgrading site had 30 m — yet after executeUpgrade
// Step 6b's unconditional post-swap handoff it is BOOT-migrate that consumes
// every upgrade's migration delta, making a generous budget on the applyNewSbUpgrading
// site protection for a step that normally no-ops.
//
// STATBUS-095: default migrateUpTimeoutDefault (12h), ENV-OVERRIDABLE via
// STATBUS_MIGRATE_UP_TIMEOUT (a Go duration string, e.g. "20s", "6h"),
// floor-guarded at migrateUpTimeoutFloor. Resolved ONCE at package init from the
// process env — the daemon and the inline `./sb install` read it at start; a
// unit restart picks up a changed env (the ceiling arc arms seconds via a
// restart-for-env dropin). This is exported as a var (not a const) solely to
// carry the env override; every call site is unchanged (`MigrateUpTimeout` as a
// time.Duration value).
var MigrateUpTimeout = resolveMigrateUpTimeout()

// resolveMigrateUpTimeout reads STATBUS_MIGRATE_UP_TIMEOUT and returns the
// effective ceiling: the parsed Go duration when valid and >= the floor; the
// 12h default when unset or unparseable; the floor when a valid-but-too-small
// value is given. Every non-default path WARNs to stderr so an operator (or the
// arc log) sees exactly which ceiling is in force. Reads the env fresh on each
// call so it is directly unit-testable.
func resolveMigrateUpTimeout() time.Duration {
	raw := os.Getenv("STATBUS_MIGRATE_UP_TIMEOUT")
	if raw == "" {
		return migrateUpTimeoutDefault
	}
	d, err := time.ParseDuration(raw)
	if err != nil {
		fmt.Fprintf(os.Stderr, "WARN: STATBUS_MIGRATE_UP_TIMEOUT=%q is not a valid Go duration (%v) — using the default %s\n", raw, err, migrateUpTimeoutDefault)
		return migrateUpTimeoutDefault
	}
	if d < migrateUpTimeoutFloor {
		fmt.Fprintf(os.Stderr, "WARN: STATBUS_MIGRATE_UP_TIMEOUT=%s is below the floor %s — clamping to the floor\n", d, migrateUpTimeoutFloor)
		return migrateUpTimeoutFloor
	}
	return d
}

// runGatedWatchdogTicker is the shared bounded watchdog goroutine (plan
// upgrade-resume-structural-whole.md piece #3). Three callers: applyNewSbUpgrading
// (GATED — real progress, gate closes on stall), and as an ALWAYS-PING cover
// (nil progress) the boot-migrate site in Run() and rollback() (STATBUS-031). It
// fires ping() every cadence IFF progress.shouldPingWatchdog(stall) is true, and
// stops when ctx is done, closing doneCh so the caller can join.
//
// This collapses the prior TWO unconditional tickers (the reconnect-scoped one
// and the applyNewSbUpgrading-remainder one, both blind 30 s timers) into one
// progress-gated loop covering reconnect → migrate → step 11 → step 12. The
// collapse is also a fix: an unconditional ticker is itself
// a blind-watchdog hole — a step hung INSIDE the ticker's scope (e.g. a wedged
// d.reconnect) would ping forever and never let WatchdogSec fire. Gating closes
// that hole: a hung step stops advancing lastAdvanceAt, the gate goes false,
// pings stop, and systemd reaps the unit.
//
// The FIRST tick is gated too (no unconditional initial ping): on entry the
// pipeline has just advanced (waitForDBHealth returned + its progress.Write
// bumped lastAdvanceAt, and the log is seeded to "now" at construction), so the
// gate is open and the deadline is reset before any step can run long. A nil
// progress pings unconditionally (shouldPingWatchdog(nil)==true) — the prior
// behaviour for any untracked caller.
//
// ping is injected so unit tests can drive the loop with a counter instead of a
// real sd_notify socket; production passes a closure that calls
// sdNotify("WATCHDOG=1").
func runGatedWatchdogTicker(ctx context.Context, progress *ProgressLog, stall, cadence time.Duration, ping func(), doneCh chan struct{}) {
	defer close(doneCh)
	if progress.shouldPingWatchdog(stall) {
		ping()
	}
	ticker := time.NewTicker(cadence)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			if progress.shouldPingWatchdog(stall) {
				ping()
			}
		}
	}
}

// heartbeatPath returns the path to the on-disk heartbeat marker.
func heartbeatPath(projDir string) string {
	return filepath.Join(projDir, "tmp", "upgrade-service-heartbeat")
}

// emitHeartbeat fires all three liveness signals in one call. See
// the package-level commentary above for the design rationale.
//
// Called from ProgressLog.Write (every state transition in
// executeUpgrade) and from the main-loop heartbeat ticker (30s
// cadence while idle). Both call sites are on the main goroutine,
// so the heartbeat semantic "main goroutine is alive" is preserved.
//
// Failures are silent: heartbeat is best-effort observability; a
// missing tmp/ directory or a full disk must not propagate into an
// error state on the main service path. If heartbeat fails
// silently, the systemd watchdog will detect the silence and act.
func emitHeartbeat(projDir string) {
	sdNotify("WATCHDOG=1")

	path := heartbeatPath(projDir)
	content := strconv.FormatInt(time.Now().Unix(), 10)
	if err := os.WriteFile(path, []byte(content), 0644); err != nil {
		if !os.IsNotExist(err) {
			return
		}
		// Parent dir missing (fresh install). Create it, then retry
		// once. Still best-effort silent on failure.
		if mkErr := os.MkdirAll(filepath.Dir(path), 0755); mkErr != nil {
			return
		}
		_ = os.WriteFile(path, []byte(content), 0644)
	}
}

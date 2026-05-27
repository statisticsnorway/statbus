package upgrade

import (
	"net"
	"os"
	"path/filepath"
	"strconv"
	"time"
)

// Historical note (2026-05-23): sdNotifyExtendTimeout was removed from
// this file alongside the active-phase WATCHDOG=1 fix for Race B.
// Original design assumed applyPostSwap ran in systemd's "activating"
// phase (pre-READY=1), where EXTEND_TIMEOUT_USEC is the right primitive.
// Evidence (Service.Run sends READY=1 before the main loop; applyPostSwap
// is reached from inside the main loop via executeUpgrade) showed the
// SCHEDULED path's applyPostSwap runs in the active phase, where
// EXTEND_TIMEOUT_USEC is a no-op against WatchdogSec and only WATCHDOG=1
// resets the watchdog deadline. Confirmed by operator's dev journalctl:
// UNIT_RESULT=watchdog, NRestarts=111 — Fix 1's EXTEND_TIMEOUT_USEC ticker
// did not prevent the watchdog from firing. The helper had no other call
// site, so it was deleted rather than preserved as defensive cover (dead
// code paths must be removed).
//
// Addendum (2026-05-27, plan recovery-arc-flaw-timeoutstartsec.md §4a):
// the original note's "applyPostSwap always runs active-phase" is true for
// the SCHEDULED path but FALSE for the exit-42 RESUME path, which reaches
// applyPostSwap from recoverFromFlag DURING Service.Run startup — before
// READY=1 — so on that path applyPostSwap runs in the START phase under
// TimeoutStartSec, where neither WATCHDOG=1 nor the deleted extender helps.
// A 32 GB archiveBackup blew the start budget and wedged NO/rune in a
// restart loop (~40 h). The §4a FIX (A) does NOT change that phase split:
// it reorders archiveBackup to AFTER the terminal state='completed' UPDATE +
// removeUpgradeFlag, so the slow, kill-prone tar runs only once the row is
// already completed — a start-phase SIGTERM during the tar is then harmless
// (the next start finds no flag and no-ops). The EXTEND_TIMEOUT_USEC deletion
// remains correct: the start-phase resume is bounded by TimeoutStartSec as
// intended (a HARD bound on a genuine hang), and the scheduled path's
// active-phase steps are covered by WATCHDOG=1. No code here changed; this
// records why the deletion holds and why the start-phase resume is no longer
// a wedge.

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
// pullImages has its own 10-min ctx timeout, so a stuck subprocess
// is bounded.

// sdNotify sends a message to the systemd NOTIFY_SOCKET.
// No-op if not running under systemd (NOTIFY_SOCKET unset).
//
// This is the low-level primitive used by READY=1 at startup and
// WATCHDOG=1 from emitHeartbeat. Callers OTHER than emitHeartbeat
// should be rare — almost all liveness signalling goes through
// emitHeartbeat so the three signals stay unified.
//
// One legitimate ad-hoc callsite is the applyPostSwap WATCHDOG=1 ticker
// (service.go). On the SCHEDULED path applyPostSwap runs after Service.Run
// has sent READY=1 (the main loop dispatches executeUpgrade post-READY), so
// the ticker is active-phase and WATCHDOG=1 (not the deleted
// EXTEND_TIMEOUT_USEC) is what resets the watchdog deadline. On the exit-42
// RESUME path applyPostSwap runs pre-READY (reached from recoverFromFlag in
// Service.Run startup), so those WATCHDOG=1 pings are no-ops — WatchdogSec
// isn't armed in the activating phase, and TimeoutStartSec is the governing
// bound there. That start-phase resume is safe via §4a FIX A (archiveBackup
// reordered after the terminal UPDATE), not via this ticker.
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

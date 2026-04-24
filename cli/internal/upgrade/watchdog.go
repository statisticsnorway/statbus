package upgrade

import (
	"net"
	"os"
	"path/filepath"
	"strconv"
	"time"
)

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

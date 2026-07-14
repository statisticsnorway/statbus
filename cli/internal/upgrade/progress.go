package upgrade

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"time"
)

// ProgressLog writes timestamped progress to a per-run log file.
//
// Two layouts exist, selected by the constructor:
//   - Upgrade logs: <projDir>/tmp/upgrade-logs/<id>-<safe_version>-<ts>.log,
//     owned by a public.upgrade row. The basename is stored on
//     public.upgrade.log_relative_file_path so the admin UI and the service
//     can locate the file later (e.g. to append the recovery narrative when
//     resurrecting a crashed run).
//   - Install logs: <projDir>/tmp/install-logs/<safe_version>-<ts>.log,
//     owned by a single install invocation (no row authored). The basename
//     is stored in public.system_info under install_last_log_relative_file_path
//     by the successful-completion path.
//
// A transitional symlink <projDir>/tmp/upgrade-progress.log points at the
// active upgrade log. It keeps the legacy Caddy /upgrade-progress.log handle
// (used by maintenance.html) serving fresh content until that handler is
// retired.
type ProgressLog struct {
	projDir string
	relPath string
	absPath string
	file    *os.File

	// lastAdvanceAt is the UnixNano of the most recent pipeline ADVANCE,
	// for the #3 progress-gated watchdog (plan upgrade-resume-structural-whole.md).
	// Bumped by (a) Write (every step boundary) and (b) the PrefixWriter onLine
	// callback (every subprocess output line) threaded through runCommandToLog.
	// The applyNewSbUpgrading WATCHDOG=1 ticker reads sinceLastAdvance() and pings
	// systemd ONLY IF the pipeline advanced within stallThreshold — so a HUNG
	// step (no advance) stops the pings and WatchdogSec fires (bounded), while
	// an advancing step survives. atomic: the ticker goroutine reads while
	// Write / PrefixWriter goroutines bump. Concurrency-safe even on a nil
	// *ProgressLog's zero value is avoided by always constructing via the
	// helpers below, which seed it to "now".
	lastAdvanceAt atomic.Int64

	// deferGating, when true, makes shouldPingWatchdog return true regardless of
	// sinceLastAdvance — used ONLY around the migrate / recreate-database
	// runCommandToLog calls (plan upgrade-resume-structural-whole.md piece #3,
	// "defer gating during the migrate step"). A single legitimate SQL statement
	// (CREATE INDEX on a large table) emits NO output for minutes, so output-
	// gating can't tell it from a hang. But that step is ALREADY hard-bounded by
	// its OWN runCommandToLog timeout (boot 5 min / resume 30 min), and #7
	// (cumulative-activating > 30 min) catches a restart LOOP. So during that
	// step we keep pinging the watchdog (no systemd kill at WatchdogSec=120 s
	// mid-legit-long-migration) — an EXPLICIT BOUNDED defer, NOT the task-#37
	// blind-UNbounded ping. (The host-side SIGKILL does NOT cleanly roll back the
	// in-container psql backend — docker-exec doesn't forward the signal; that
	// orphan is bounded here by the LOOP cap and cleaned by task #14.) atomic:
	// set/cleared on the main goroutine, read by the ticker goroutine.
	deferGating atomic.Bool
}

func upgradeLogsDir(projDir string) string {
	return filepath.Join(projDir, "tmp", "upgrade-logs")
}

func installLogsDir(projDir string) string {
	return filepath.Join(projDir, "tmp", "install-logs")
}

// UpgradeLogAbsPath returns the absolute path on disk for a given per-upgrade
// log basename (the value stored on public.upgrade.log_relative_file_path).
// Returns "" when relPath is empty so callers can short-circuit.
func UpgradeLogAbsPath(projDir, relPath string) string {
	if relPath == "" {
		return ""
	}
	return filepath.Join(upgradeLogsDir(projDir), relPath)
}

// InstallLogAbsPath returns the absolute path on disk for a given install-log
// basename (the value stored in public.system_info.install_last_log_relative_file_path).
// Returns "" when relPath is empty so callers can short-circuit.
func InstallLogAbsPath(projDir, relPath string) string {
	if relPath == "" {
		return ""
	}
	return filepath.Join(installLogsDir(projDir), relPath)
}

func sanitizeVersion(version string) string {
	return strings.Map(func(r rune) rune {
		if (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') || r == '.' || r == '-' {
			return r
		}
		return '_'
	}, version)
}

// BuildLogRelPath returns the per-upgrade log basename derived from id,
// version, and startTime. The value is what gets stored on
// public.upgrade.log_relative_file_path.
func BuildLogRelPath(id int64, version string, startTime time.Time) string {
	return fmt.Sprintf("%d-%s-%s.log",
		id,
		sanitizeVersion(version),
		startTime.UTC().Format("20060102T150405Z"),
	)
}

// buildInstallLogRelPath returns the install-log basename. No id is encoded
// because install invocations do not author a public.upgrade row.
func buildInstallLogRelPath(version string, startTime time.Time) string {
	return fmt.Sprintf("%s-%s.log",
		sanitizeVersion(version),
		startTime.UTC().Format("20060102T150405Z"),
	)
}

// createProgressLogFile creates the log file at absPath and writes the legend
// header. Returns a ProgressLog with a nil file on failure (callers degrade
// to stdout-only logging).
func createProgressLogFile(projDir, relPath, absPath string) *ProgressLog {
	f, err := os.Create(absPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Warning: cannot create progress log %s: %v\n", absPath, err)
		return &ProgressLog{projDir: projDir, relPath: relPath, absPath: absPath}
	}

	// Write legend so every log is self-describing. Best-effort — a write
	// failure here leaves an incomplete legend, not a broken upgrade.
	_, _ = fmt.Fprintf(f, "# Statbus upgrade log v1\n")
	_, _ = fmt.Fprintf(f, "# M <time> content               main service narration\n")
	_, _ = fmt.Fprintf(f, "# O <name> <time> content        child stdout  (name: migrate, docker-compose, git, rsync)\n")
	_, _ = fmt.Fprintf(f, "# E <name> <time> content        child stderr\n")
	_, _ = fmt.Fprintf(f, "# ---\n")

	return &ProgressLog{projDir: projDir, relPath: relPath, absPath: absPath, file: f}
}

// NewUpgradeLog creates a new per-upgrade log under tmp/upgrade-logs/. Use
// RelPath() to get the value to persist on public.upgrade.log_relative_file_path.
func NewUpgradeLog(projDir string, id int64, version string, startTime time.Time) *ProgressLog {
	dir := upgradeLogsDir(projDir)
	_ = os.MkdirAll(dir, 0755) // best-effort; the os.Create right after surfaces any real failure

	relPath := BuildLogRelPath(id, version, startTime)
	absPath := filepath.Join(dir, relPath)

	p := createProgressLogFile(projDir, relPath, absPath)
	refreshLegacySymlink(projDir, relPath)
	return p
}

// NewInstallLog creates a new install-invocation log under tmp/install-logs/.
// No public.upgrade row is authored for install invocations; the basename is
// persisted via public.system_info.install_last_log_relative_file_path on
// successful completion.
func NewInstallLog(projDir string, version string, startTime time.Time) *ProgressLog {
	dir := installLogsDir(projDir)
	_ = os.MkdirAll(dir, 0755) // best-effort; the os.Create right after surfaces any real failure

	relPath := buildInstallLogRelPath(version, startTime)
	absPath := filepath.Join(dir, relPath)

	return createProgressLogFile(projDir, relPath, absPath)
}

// AppendProgressLog opens an existing per-upgrade log in append mode. Used
// by recoverFromFlag and completeInProgressUpgrade so the reconciliation
// narrative lands in the same file the crashed run produced. Returns nil if
// the file cannot be opened; callers fall back to stdout-only logging.
func AppendProgressLog(projDir, relPath string) *ProgressLog {
	if relPath == "" {
		return nil
	}
	absPath := filepath.Join(upgradeLogsDir(projDir), relPath)
	if _, err := os.Stat(absPath); err != nil {
		return nil
	}
	f, err := os.OpenFile(absPath, os.O_APPEND|os.O_WRONLY, 0644)
	if err != nil {
		return nil
	}
	refreshLegacySymlink(projDir, relPath)
	return &ProgressLog{projDir: projDir, relPath: relPath, absPath: absPath, file: f}
}

// refreshLegacySymlink keeps <projDir>/tmp/upgrade-progress.log pointing at
// the currently active per-upgrade log. Best-effort — symlink errors are
// non-fatal.
func refreshLegacySymlink(projDir, relPath string) {
	symlinkPath := filepath.Join(projDir, "tmp", "upgrade-progress.log")
	_ = os.Remove(symlinkPath)                                          // best-effort, see doc comment above
	_ = os.Symlink(filepath.Join("upgrade-logs", relPath), symlinkPath) // best-effort, see doc comment above
}

// RelPath returns the basename of the log file — the value stored on
// public.upgrade.log_relative_file_path.
func (p *ProgressLog) RelPath() string {
	if p == nil {
		return ""
	}
	return p.relPath
}

// AbsPath returns the absolute path to the log file on disk.
func (p *ProgressLog) AbsPath() string {
	if p == nil {
		return ""
	}
	return p.absPath
}

// File returns the underlying log file writer for use by child-process prefix
// writers. Returns io.Discard when the log is nil or already closed.
func (p *ProgressLog) File() io.Writer {
	if p != nil && p.file != nil {
		return p.file
	}
	return io.Discard
}

// Write appends a timestamped line in `M HH:MM:SS content` format AND
// emits the unified heartbeat (sd_notify WATCHDOG=1 + mtime touch on
// tmp/upgrade-service-heartbeat). See watchdog.go for the rationale.
//
// Single signal path: one Write call fires all three liveness signals
// (journal / heartbeat file / systemd watchdog). No drift between them,
// no way for one to tick while another is silent. If Write isn't called,
// progress didn't happen and systemd notices within WatchdogSec.
func (p *ProgressLog) Write(format string, args ...interface{}) {
	msg := fmt.Sprintf(format, args...)
	line := fmt.Sprintf("M %s %s\n", time.Now().Format("15:04:05"), msg)

	fmt.Print(line)

	if p != nil && p.file != nil {
		// Best-effort: stdout (above) is the primary channel; the file is
		// the secondary on-disk narrative. A disk write failure here must
		// not abort the upgrade the log is narrating.
		_, _ = p.file.WriteString(line)
		_ = p.file.Sync()
	}

	// Heartbeat. Nil ProgressLog still fires sd_notify + file touch
	// because the signal is about the service, not the log — but we
	// need projDir from somewhere. Skip when p is nil (one-shot/test
	// paths that don't wire a log); main-loop liveness is handled by
	// its own emitHeartbeat calls.
	if p != nil {
		emitHeartbeat(p.projDir)
		// (a) step-boundary advance for the #3 progress-gated watchdog.
		p.bump()
	}
}

// bump records "the pipeline just advanced" — sets lastAdvanceAt to now.
// Nil-safe. Called from Write (step boundaries) and from the PrefixWriter
// onLine callback (subprocess output lines) threaded through runCommandToLog.
func (p *ProgressLog) bump() {
	if p == nil {
		return
	}
	p.lastAdvanceAt.Store(time.Now().UnixNano())
}

// sinceLastAdvance returns how long since the last bump. A never-bumped log
// (zero value) reports a large duration so a caller that forgot to seed it
// reads as "stalled" rather than "just advanced" (fail-safe: the #3 ticker
// would stop pinging rather than blind-ping). Nil-safe.
func (p *ProgressLog) sinceLastAdvance() time.Duration {
	if p == nil {
		return 0 // nil log ⇒ no pipeline to watch; treat as "fresh" (ticker no-op path)
	}
	last := p.lastAdvanceAt.Load()
	if last == 0 {
		return time.Duration(1<<62 - 1) // effectively "forever stale"
	}
	return time.Since(time.Unix(0, last))
}

// setLastAdvanceForTest forces lastAdvanceAt to a specific time. Test-only
// seam to exercise the stalled path without real sleeps.
func (p *ProgressLog) setLastAdvanceForTest(t time.Time) {
	p.lastAdvanceAt.Store(t.UnixNano())
}

// setDeferGating toggles the "defer watchdog gating" mode (see the deferGating
// field doc). Set true around the migrate / recreate-database runCommandToLog
// calls, cleared after. Nil-safe.
func (p *ProgressLog) setDeferGating(v bool) {
	if p == nil {
		return
	}
	p.deferGating.Store(v)
}

// shouldPingWatchdog is the #3 progress-gated decision the applyNewSbUpgrading
// WATCHDOG=1 ticker consults each tick: ping IFF the pipeline advanced within
// stallThreshold, OR gating is deferred (the migrate/recreate step, bounded by
// its own timeout). A stalled, non-deferred step → no ping → WatchdogSec fires
// (the hung step is caught, bounded). Nil-safe (nil log ⇒ no pipeline to
// watch ⇒ ping, the prior unconditional behaviour for non-tracked callers).
func (p *ProgressLog) shouldPingWatchdog(stallThreshold time.Duration) bool {
	if p == nil {
		return true
	}
	if p.deferGating.Load() {
		return true
	}
	return p.sinceLastAdvance() < stallThreshold
}

// Close closes the log file.
func (p *ProgressLog) Close() {
	if p != nil && p.file != nil {
		_ = p.file.Close() // best-effort; nothing further writes to this log after Close
	}
}

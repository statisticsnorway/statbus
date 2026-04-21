package upgrade

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
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

	// Write legend so every log is self-describing.
	fmt.Fprintf(f, "# Statbus upgrade log v1\n")
	fmt.Fprintf(f, "# M <time> content               main service narration\n")
	fmt.Fprintf(f, "# O <name> <time> content        child stdout  (name: migrate, docker-compose, git, rsync)\n")
	fmt.Fprintf(f, "# E <name> <time> content        child stderr\n")
	fmt.Fprintf(f, "# ---\n")

	return &ProgressLog{projDir: projDir, relPath: relPath, absPath: absPath, file: f}
}

// NewUpgradeLog creates a new per-upgrade log under tmp/upgrade-logs/. Use
// RelPath() to get the value to persist on public.upgrade.log_relative_file_path.
func NewUpgradeLog(projDir string, id int64, version string, startTime time.Time) *ProgressLog {
	dir := upgradeLogsDir(projDir)
	os.MkdirAll(dir, 0755)

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
	os.MkdirAll(dir, 0755)

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
	os.Remove(symlinkPath)
	os.Symlink(filepath.Join("upgrade-logs", relPath), symlinkPath)
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

// Write appends a timestamped line in `M HH:MM:SS content` format.
func (p *ProgressLog) Write(format string, args ...interface{}) {
	msg := fmt.Sprintf(format, args...)
	line := fmt.Sprintf("M %s %s\n", time.Now().Format("15:04:05"), msg)

	fmt.Print(line)

	if p != nil && p.file != nil {
		p.file.WriteString(line)
		p.file.Sync()
	}
}

// Close closes the log file.
func (p *ProgressLog) Close() {
	if p != nil && p.file != nil {
		p.file.Close()
	}
}

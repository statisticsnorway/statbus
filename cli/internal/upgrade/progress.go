package upgrade

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// ProgressLog writes timestamped progress to a version-specific log file.
// A symlink upgrade-progress.log always points to the current version's log,
// so the maintenance page fetches the right content without knowing the version.
type ProgressLog struct {
	path string
	file *os.File
}

// ProgressLogPath returns the per-version log path without creating the file.
// Matches the naming used by NewProgressLog so callers can read a specific
// version's log after the fact (e.g., recoverFromFlag reading the log of the
// upgrade that just crashed, identified by flag.DisplayName).
func ProgressLogPath(projDir, version string) string {
	safe := strings.Map(func(r rune) rune {
		if (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') || r == '.' || r == '-' {
			return r
		}
		return '_'
	}, version)
	return filepath.Join(projDir, "tmp", fmt.Sprintf("upgrade-progress-%s.log", safe))
}

// NewProgressLog creates a progress log for a specific version in projDir/tmp/.
// The version is sanitized for use in filenames (sha-abc → sha-abc, v2026.03.1-rc.6 → v2026.03.1-rc.6).
func NewProgressLog(projDir, version string) *ProgressLog {
	dir := filepath.Join(projDir, "tmp")
	os.MkdirAll(dir, 0755)

	path := ProgressLogPath(projDir, version)
	f, err := os.Create(path)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Warning: cannot create progress log %s: %v\n", path, err)
		return &ProgressLog{path: path}
	}

	// Symlink upgrade-progress.log → version-specific file.
	// Maintenance page fetches /upgrade-progress.log via Caddy.
	symlinkPath := filepath.Join(dir, "upgrade-progress.log")
	os.Remove(symlinkPath) // remove old symlink or file
	os.Symlink(filepath.Base(path), symlinkPath)

	return &ProgressLog{path: path, file: f}
}

// Write appends a timestamped line.
func (p *ProgressLog) Write(format string, args ...interface{}) {
	msg := fmt.Sprintf(format, args...)
	line := fmt.Sprintf("[%s] %s\n", time.Now().Format("15:04:05"), msg)

	fmt.Print(line)

	if p.file != nil {
		p.file.WriteString(line)
		p.file.Sync()
	}
}

// Close closes the log file.
func (p *ProgressLog) Close() {
	if p.file != nil {
		p.file.Close()
	}
}

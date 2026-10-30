package monitor

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// Cache file names under <project>/tmp. The upgrader owns the files; the CLI
// and Caddy only read them. tmp/ is already mounted read-only into the proxy
// as /statbus-tmp, which is how /upgrade-progress.log is served today.
const (
	readingFileName = "monitor.json"
	statusFileName  = "monitor.status"
	// criticalMarkerFileName is the marker Caddy matches with a `file`
	// matcher to answer 503. It exists for critical and unknown readings;
	// a warning or an upgrade stays 200 with the JSON body.
	criticalMarkerFileName = "monitor.critical"
)

// CacheDir is <project>/tmp, where the upgrader writes the reading and the
// marker files. It is a directory path, never part of the public JSON.
func CacheDir(projectDir string) string { return filepath.Join(projectDir, "tmp") }

func readingPath(projectDir string) string {
	return filepath.Join(CacheDir(projectDir), readingFileName)
}

// StatusPath is the one-word status file next to the reading. It exists so an
// operator (or a future poller that cannot read JSON) can see the verdict
// without parsing.
func StatusPath(projectDir string) string {
	return filepath.Join(CacheDir(projectDir), statusFileName)
}

// CriticalMarkerPath is the file Caddy tests for a 503.
func CriticalMarkerPath(projectDir string) string {
	return filepath.Join(CacheDir(projectDir), criticalMarkerFileName)
}

// ReadCache reads the upgrader's last reading. It returns os.ErrNotExist when
// no reading has been written (no upgrader has run yet).
func ReadCache(projectDir string) (Reading, error) {
	data, err := os.ReadFile(readingPath(projectDir))
	if err != nil {
		return Reading{}, err
	}
	var reading Reading
	if err := json.Unmarshal(data, &reading); err != nil {
		return Reading{}, fmt.Errorf("parse %s: %w", readingFileName, err)
	}
	if reading.Checks == nil {
		reading.Checks = []Check{}
	}
	return reading, nil
}

// WriteReading writes the reading and its companion marker files atomically:
// each file is written under a temporary name in the same directory and
// renamed into place, so Caddy and the CLI never read a partial JSON document.
// The critical marker is created for critical and unknown only, which means a
// box that recovers clears the 503 on the next write.
func WriteReading(projectDir string, reading Reading) error {
	if reading.Checks == nil {
		reading.Checks = []Check{}
	}
	data, err := json.MarshalIndent(reading, "", "  ")
	if err != nil {
		return fmt.Errorf("encode reading: %w", err)
	}
	data = append(data, '\n')
	if err := atomicWrite(projectDir, readingFileName, data); err != nil {
		return err
	}
	if err := atomicWrite(projectDir, statusFileName, []byte(string(reading.Status)+"\n")); err != nil {
		return err
	}
	if reading.Status == StatusCritical || reading.Status == StatusUnknown {
		return atomicWrite(projectDir, criticalMarkerFileName, []byte("1\n"))
	}
	if err := os.Remove(CriticalMarkerPath(projectDir)); err != nil && !os.IsNotExist(err) {
		return fmt.Errorf("remove critical marker: %w", err)
	}
	return nil
}

// Stale reports whether the reading is older than the cache freshness window.
// A future timestamp (clock moved backwards) is treated as fresh rather than
// as an impossible negative age.
func Stale(reading Reading, now time.Time) bool {
	if reading.CheckedAt.IsZero() {
		return true
	}
	return now.Sub(reading.CheckedAt) > CacheStaleAfter
}

// AsStale returns the reading a poller must see when the upgrader has stopped:
// the overall verdict becomes unknown, while the last measured checks remain
// visible for diagnosis. The checked_at is left untouched so the consumer can
// report the real age.
func AsStale(reading Reading) Reading {
	reading.Status = StatusUnknown
	return reading
}

// ParseStatus accepts the one-word status file's vocabulary. It is used by
// tests and by the Caddy marker contract; an unrecognised word is unknown.
func ParseStatus(text string) Status {
	switch Status(strings.TrimSpace(text)) {
	case StatusOK:
		return StatusOK
	case StatusWarning:
		return StatusWarning
	case StatusCritical:
		return StatusCritical
	case StatusUpgrading:
		return StatusUpgrading
	default:
		return StatusUnknown
	}
}

func atomicWrite(projectDir, name string, data []byte) error {
	dir := CacheDir(projectDir)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return fmt.Errorf("create %s: %w", dir, err)
	}
	file, err := os.CreateTemp(dir, "."+name+".*")
	if err != nil {
		return fmt.Errorf("create temporary %s: %w", name, err)
	}
	tempPath := file.Name()
	defer os.Remove(tempPath) // no-op after a successful rename
	if _, err := file.Write(data); err != nil {
		_ = file.Close()
		return fmt.Errorf("write %s: %w", name, err)
	}
	if err := file.Chmod(0644); err != nil {
		_ = file.Close()
		return fmt.Errorf("chmod %s: %w", name, err)
	}
	if err := file.Close(); err != nil {
		return fmt.Errorf("close %s: %w", name, err)
	}
	if err := os.Rename(tempPath, filepath.Join(dir, name)); err != nil {
		return fmt.Errorf("rename %s into place: %w", name, err)
	}
	return nil
}

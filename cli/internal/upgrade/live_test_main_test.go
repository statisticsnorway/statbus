package upgrade

import (
	"fmt"
	"os"
	"path/filepath"
	"syscall"
	"testing"
)

// TestMain serializes the opt-in live twins with the internal/install package.
// `go test ./internal/upgrade ./internal/install` runs packages concurrently,
// but both suites use the same real database and upgrade marker. The helper
// subprocess used by the stale-recovery twin inherits the parent's hold and
// bypasses the second acquisition via STATBUS_LIVE_TWIN_LOCK_HELD.
func TestMain(m *testing.M) {
	lock, err := acquireLiveTwinPackageLock()
	if err != nil {
		fmt.Fprintf(os.Stderr, "acquire live-twin package lock: %v\n", err)
		os.Exit(1)
	}
	code := m.Run()
	if lock != nil {
		_ = lock.Close()
	}
	os.Exit(code)
}

func acquireLiveTwinPackageLock() (*os.File, error) {
	if os.Getenv("STATBUS_LIVE_DB") == "" || os.Getenv("STATBUS_LIVE_TWIN_LOCK_HELD") == "1" {
		return nil, nil
	}
	cwd, err := os.Getwd()
	if err != nil {
		return nil, err
	}
	cliDir := cwd
	for {
		if _, statErr := os.Stat(filepath.Join(cliDir, "go.mod")); statErr == nil {
			break
		}
		parent := filepath.Dir(cliDir)
		if parent == cliDir {
			return nil, fmt.Errorf("could not locate cli/go.mod from %s", cwd)
		}
		cliDir = parent
	}
	lockPath := filepath.Join(filepath.Dir(cliDir), "tmp", "live-twins.lock")
	if err := os.MkdirAll(filepath.Dir(lockPath), 0o755); err != nil {
		return nil, err
	}
	lock, err := os.OpenFile(lockPath, os.O_CREATE|os.O_RDWR, 0o644)
	if err != nil {
		return nil, err
	}
	if err := syscall.Flock(int(lock.Fd()), syscall.LOCK_EX); err != nil {
		_ = lock.Close()
		return nil, err
	}
	return lock, nil
}

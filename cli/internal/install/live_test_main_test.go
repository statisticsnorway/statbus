package install

import (
	"fmt"
	"os"
	"path/filepath"
	"syscall"
	"testing"
)

// TestMain serializes the opt-in live twins with the internal/upgrade package.
// Both suites use the same real database and tmp/upgrade-in-progress.json, while
// `go test ./internal/upgrade ./internal/install` otherwise runs packages in
// parallel and lets one test observe the other package's marker.
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
	if os.Getenv("STATBUS_LIVE_DB") == "" {
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

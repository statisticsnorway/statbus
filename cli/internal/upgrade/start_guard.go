package upgrade

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"syscall"
	"time"
)

// OperatorStartGuard serializes an ordinary operator start against recovery's
// canonical marker flock. Existing free parked/crashed markers are held
// verbatim and never rewritten. When no marker exists, a transient install-held
// marker closes the absent-path race and is removed on Release.
type OperatorStartGuard struct {
	lock      *FlagLock
	transient bool
}

// AcquireOperatorStartGuard refuses only a demonstrably live marker holder.
// A free parked/crashed marker remains eligible for ordinary starts, but its
// flock is held for the complete start so recovery cannot enter its closed-route
// precheck concurrently.
func AcquireOperatorStartGuard(projDir, invokedBy string) (*OperatorStartGuard, error) {
	if err := os.MkdirAll(filepath.Join(projDir, "tmp"), 0o755); err != nil {
		return nil, fmt.Errorf("prepare operator start guard: %w", err)
	}
	path := flagFilePath(projDir)
	for attempt := 0; attempt < flagLockIdentityRetryLimit; attempt++ {
		file, err := openCanonicalFlagLocked(path, nil)
		if err == nil {
			return &OperatorStartGuard{lock: &FlagLock{file: file, markerPath: path}}, nil
		}
		if errors.Is(err, syscall.EWOULDBLOCK) || errors.Is(err, syscall.EAGAIN) {
			flag, readErr := ReadFlagFile(projDir)
			if readErr != nil {
				return nil, fmt.Errorf("service start refused: recovery marker is live but unreadable: %w; run ./sb install for diagnosis", readErr)
			}
			label := "upgrade/install recovery"
			if flag != nil {
				label = flag.Label()
			}
			return nil, fmt.Errorf("service start refused while %s holds the recovery lock; wait for it to finish or run ./sb install for diagnosis", label)
		}
		if !os.IsNotExist(err) {
			return nil, fmt.Errorf("probe recovery lock before service start: %w; run ./sb install for diagnosis", err)
		}

		marker := UpgradeFlag{
			StartedAt: time.Now(),
			InvokedBy: invokedBy,
			Trigger:   "start",
			Holder:    HolderInstall,
		}
		data, marshalErr := json.MarshalIndent(marker, "", "  ")
		if marshalErr != nil {
			return nil, fmt.Errorf("marshal operator start guard: %w", marshalErr)
		}
		lock, createErr := createFreshFlagAtomically(projDir, data)
		if os.IsExist(createErr) {
			continue
		}
		if createErr != nil {
			return nil, fmt.Errorf("create operator start guard: %w", createErr)
		}
		return &OperatorStartGuard{lock: lock, transient: true}, nil
	}
	return nil, fmt.Errorf("service start could not establish a stable recovery-lock view; run ./sb install for diagnosis")
}

// Release drops the serialization flock. A transient absent-path claim is
// removed only while its still-canonical inode remains locked.
func (g *OperatorStartGuard) Release() error {
	if g == nil || g.lock == nil || g.lock.file == nil {
		return nil
	}
	defer g.lock.Close()
	if !g.transient {
		return nil
	}
	heldInfo, err := g.lock.file.Stat()
	if err != nil {
		return fmt.Errorf("stat held operator start guard: %w", err)
	}
	path := g.lock.canonicalPath()
	pathInfo, err := os.Stat(path)
	if err != nil {
		return fmt.Errorf("stat operator start guard path: %w", err)
	}
	if !os.SameFile(heldInfo, pathInfo) {
		return fmt.Errorf("operator start guard was replaced before release; refusing to unlink %s", path)
	}
	if err := os.Remove(path); err != nil {
		return fmt.Errorf("remove operator start guard: %w", err)
	}
	return nil
}

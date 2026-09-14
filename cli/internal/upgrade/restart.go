package upgrade

import (
	"encoding/json"
	"fmt"
	"time"
)

// RestartIntent is independent of upgrade/recovery phases. Once PrepareRestart
// persists it, any failure or process death requires the same explicit retry.
// Daemon=false preserves an intentionally inactive or absent daemon on retry.
type RestartIntent struct {
	Profile  string `json:"profile"`
	Prepared bool   `json:"prepared"`
	Unit     string `json:"unit,omitempty"`
	Daemon   bool   `json:"daemon"`
}

func restartRefusal(intent *RestartIntent) error {
	profile := "all"
	if intent != nil {
		profile = intent.Profile
	}
	return fmt.Errorf("a restart is running or did not finish; no install or upgrade may proceed. Wait for the running restart, or retry with ./sb restart %s to restore services and readiness; do not delete the restart marker", profile)
}

// CheckRestartBarrier is read-only and must precede install's DB state probes.
// acquireFlock also checks under the actual flock, closing pre-check races.
func CheckRestartBarrier(dir string) error {
	flag, err := ReadFlagFile(dir)
	if err != nil {
		return fmt.Errorf("inspect restart barrier: %w", err)
	}
	if flag != nil && flag.Trigger == "restart" {
		return restartRefusal(flag.Restart)
	}
	return nil
}

// AcquireRestartFlag claims idle state atomically or re-acquires ONLY matching
// restart intent verbatim. All unrelated recovery markers remain untouched.
func AcquireRestartFlag(dir, profile string) (*FlagLock, *RestartIntent, error) {
	flag, err := ReadFlagFile(dir)
	if err != nil {
		return nil, nil, fmt.Errorf("restart refused: %w. No services were stopped", err)
	}
	if flag != nil {
		if flag.Trigger != "restart" || flag.Holder != HolderInstall {
			return nil, nil, fmt.Errorf("restart refused: an upgrade/install marker already exists. No services were stopped; wait or run ./sb install to recover")
		}
		lock, held, err := acquireRecoveryFlock(dir, *flag)
		if err != nil {
			return nil, nil, err
		}
		if held.Trigger != "restart" || held.Restart == nil || held.Restart.Profile != profile {
			lock.Close()
			return nil, nil, restartRefusal(held.Restart)
		}
		if !held.Restart.Prepared {
			return lock, nil, nil
		}
		return lock, held.Restart, nil
	}
	lock, err := acquireFreshFlock(dir, UpgradeFlag{StartedAt: time.Now(), InvokedBy: "operator:restart", Trigger: "restart", Holder: HolderInstall, Restart: &RestartIntent{Profile: profile}})
	return lock, nil, err
}

// PrepareRestart stores the exact restoration intent before the first stop.
// Writing through the held descriptor preserves the inode used by the flock.
func PrepareRestart(lock *FlagLock, intent RestartIntent) error {
	if lock == nil || lock.file == nil {
		return fmt.Errorf("restart intent requires held mutex")
	}
	intent.Prepared = true
	flag := UpgradeFlag{StartedAt: time.Now(), InvokedBy: "operator:restart", Trigger: "restart", Holder: HolderInstall, Restart: &intent}
	data, err := json.MarshalIndent(flag, "", "  ")
	if err != nil {
		return err
	}
	if _, err = lock.file.Seek(0, 0); err != nil {
		return err
	}
	if err = lock.file.Truncate(0); err != nil {
		return err
	}
	if _, err = lock.file.Write(data); err != nil {
		return err
	}
	return lock.file.Sync()
}

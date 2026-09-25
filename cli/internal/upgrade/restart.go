package upgrade

import (
	"encoding/json"
	"fmt"
	"os"
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
		if flag.Holder == HolderInstall && IsFlockHeld(dir) {
			return LiveInstallHolderRefusal(flag)
		}
		return restartRefusal(flag.Restart)
	}
	return nil
}

// AcquireRestartFlag claims idle state atomically or re-acquires ONLY matching
// restart intent verbatim. All unrelated recovery markers remain untouched.
func AcquireRestartFlag(dir, profile string) (*FlagLock, *RestartIntent, bool, error) {
	flag, err := ReadFlagFile(dir)
	if err != nil {
		return nil, nil, false, fmt.Errorf("restart refused: %w. No services were stopped", err)
	}
	if flag != nil {
		if flag.Trigger != "restart" || flag.Holder != HolderInstall {
			lock, _, err := acquireRecoveryFlock(dir, *flag)
			if err != nil {
				return nil, nil, false, fmt.Errorf("restart refused while recovery is live; no services were stopped; wait or run ./sb install for diagnosis: %w", err)
			}
			// A free parked/crashed marker must not block an operator restart.
			// Hold it verbatim for serialization and preserve it on release.
			return lock, nil, true, nil
		}
		lock, held, err := acquireRecoveryFlock(dir, *flag)
		if err != nil {
			return nil, nil, false, err
		}
		if held.Trigger != "restart" || held.Restart == nil || held.Restart.Profile != profile {
			lock.Close()
			return nil, nil, false, restartRefusal(held.Restart)
		}
		if !held.Restart.Prepared {
			return lock, nil, false, nil
		}
		return lock, held.Restart, false, nil
	}
	lock, err := acquireFreshFlock(dir, UpgradeFlag{StartedAt: time.Now(), PID: os.Getpid(), InvokedBy: "operator:restart", Trigger: "restart", Holder: HolderInstall, Restart: &RestartIntent{Profile: profile}})
	return lock, nil, false, err
}

// PrepareRestart stores the exact restoration intent before the first stop via
// the single atomic marker writer, transferring the flock to the complete
// replacement inode before it becomes canonical.
func PrepareRestart(lock *FlagLock, intent RestartIntent) error {
	if lock == nil || lock.file == nil {
		return fmt.Errorf("restart intent requires held mutex")
	}
	intent.Prepared = true
	flag := UpgradeFlag{StartedAt: time.Now(), PID: os.Getpid(), InvokedBy: "operator:restart", Trigger: "restart", Holder: HolderInstall, Restart: &intent}
	data, err := json.MarshalIndent(flag, "", "  ")
	if err != nil {
		return err
	}
	return replaceHeldFlagAtomically(lock, data, nil)
}

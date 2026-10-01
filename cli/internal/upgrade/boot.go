package upgrade

import (
	"context"
	"errors"
	"fmt"
	"time"
)

const (
	installHeldBootWaitLimit = 2 * time.Minute
	installHeldBootPoll      = 500 * time.Millisecond
	installHeldWatchdogPing  = 10 * time.Second
	exitInstallHeldBootWait  = 75 // EX_TEMPFAIL; RestartPreventExitStatus names it explicitly
)

var errInstallHeldBootWaitExpired = errors.New("installation still owns the upgrade mutex after the daemon boot wait limit")

// waitForInstallHolderBeforeBoot keeps every mutating daemon pre-flight behind
// the canonical install mutex. The holder is logged once, then the bounded wait
// stays watchdog-visible until the install releases the flock.
func (d *Service) waitForInstallHolderBeforeBoot(ctx context.Context) (*UpgradeFlag, error) {
	deadline := time.NewTimer(installHeldBootWaitLimit)
	defer deadline.Stop()
	poll := time.NewTicker(installHeldBootPoll)
	defer poll.Stop()
	watchdog := time.NewTicker(installHeldWatchdogPing)
	defer watchdog.Stop()

	logged := false
	for {
		flag, err := ReadFlagFile(d.projDir)
		if err != nil {
			return nil, fmt.Errorf("inspect upgrade mutex before daemon boot pre-flight: %w", err)
		}
		if flag == nil || flag.Holder != HolderInstall || !IsFlockHeld(d.projDir) {
			return flag, nil
		}
		if !logged {
			fmt.Printf("Upgrade daemon boot deferred: %s; waiting up to %s before config generation or container start\n",
				LiveInstallHolderRefusal(flag), installHeldBootWaitLimit)
			logged = true
		}

		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		case <-deadline.C:
			return nil, errInstallHeldBootWaitExpired
		case <-watchdog.C:
			sdNotify("WATCHDOG=1")
		case <-poll.C:
		}
	}
}

// ensureDatabaseForBoot preserves the target-image recreation required by a
// service-held forward recovery, while every ordinary/preswap boot starts only
// the existing database route and therefore cannot recreate PostgreSQL.
func ensureDatabaseForBoot(
	ctx context.Context,
	flag *UpgradeFlag,
	recreate func(context.Context) error,
	startExisting func(context.Context) error,
) error {
	if flag != nil && flag.IsServiceNewSbRecovery() {
		return recreate(ctx)
	}
	return startExisting(ctx)
}

package upgrade

import (
	"context"
	"errors"
	"fmt"
	"time"
)

const (
	// The shipped unit's TimeoutStartSec is 120s. Leave 90s after this decision
	// for config generation, database start, connect, and READY=1. boot_test.go
	// parses the unit and pins that startup-budget relationship.
	installHeldBootWaitLimit = 30 * time.Second
	installHeldBootPoll      = 500 * time.Millisecond
	installHeldWatchdogPing  = 10 * time.Second
	// EX_TEMPFAIL (75) is NOT free: service.go's rollback-complete tail has
	// exited 75 since the rc.67 trifecta, and that path NEEDS systemd to
	// restart the daemon (its own comment: "Under systemd Restart=always
	// cycles cleanly regardless of code"). The rc.07 upgrade arcs proved the
	// collision live: naming 75 in the unit's RestartPreventExitStatus left
	// every box's upgrade service DOWN after any successful rollback. The
	// boot-wait deferral therefore uses 76, and the two codes must never
	// share a value (boot_test.go pins both sides).
	exitInstallHeldBootWait  = 76 // RestartPreventExitStatus names it explicitly
)

var errInstallHeldBootWaitExpired = errors.New("installation still owns the upgrade mutex after the daemon boot wait limit")

type installHeldBootWaitOptions struct {
	limit    time.Duration
	poll     time.Duration
	watchdog time.Duration
	logf     func(string, ...any)
	notify   func(string)
}

func productionInstallHeldBootWaitOptions() installHeldBootWaitOptions {
	return installHeldBootWaitOptions{
		limit:    installHeldBootWaitLimit,
		poll:     installHeldBootPoll,
		watchdog: installHeldWatchdogPing,
		logf: func(format string, args ...any) {
			fmt.Printf(format, args...)
		},
		notify: sdNotify,
	}
}

// waitForInstallHolderBeforeBoot keeps every mutating daemon pre-flight behind
// the canonical install mutex. A restart also uses HolderInstall for lifecycle
// serialization, but its final act is starting this daemon, so only the install
// trigger defers boot. The holder is logged once, then the bounded wait stays
// watchdog-visible until the install releases the flock.
func (d *Service) waitForInstallHolderBeforeBoot(ctx context.Context) (*UpgradeFlag, error) {
	return d.waitForInstallHolderBeforeBootWithOptions(ctx, productionInstallHeldBootWaitOptions())
}

func (d *Service) waitForInstallHolderBeforeBootWithOptions(ctx context.Context, opts installHeldBootWaitOptions) (*UpgradeFlag, error) {
	deadline := time.NewTimer(opts.limit)
	defer deadline.Stop()
	poll := time.NewTicker(opts.poll)
	defer poll.Stop()
	watchdog := time.NewTicker(opts.watchdog)
	defer watchdog.Stop()

	logged := false
	for {
		flag, err := ReadFlagFile(d.projDir)
		if err != nil {
			// A corrupt flag cannot prove an install hold. When the canonical
			// flock is FREE there is no live install: proceed with a nil flag
			// so recoverFromFlag's FLAG_CORRUPT path removes the marker and
			// self-heals (the flagless-selfheal-at-target and
			// boot-migrate-churn-alive-idle arcs — rc.07 proved that fatalling
			// here wedges the daemon into a StartLimitBurst restart loop
			// before that reader ever runs). When the flock IS held the
			// holder cannot be identified, so fatalling remains the only safe
			// answer: proceeding is exactly the race this interlock forbids.
			if !IsFlockHeld(d.projDir) {
				opts.logf("Upgrade flag unreadable before daemon boot pre-flight (%v); no install flock held — continuing to corrupt-flag recovery\n", err)
				return nil, nil
			}
			return nil, fmt.Errorf("inspect upgrade mutex before daemon boot pre-flight: %w", err)
		}
		if flag == nil || flag.Holder != HolderInstall || flag.Trigger != "install" || !IsFlockHeld(d.projDir) {
			return flag, nil
		}
		if !logged {
			opts.logf("Upgrade daemon boot deferred: %s; waiting up to %s before config generation or container start\n",
				LiveInstallHolderRefusal(flag), opts.limit)
			logged = true
		}

		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		case <-deadline.C:
			return nil, errInstallHeldBootWaitExpired
		case <-watchdog.C:
			opts.notify("WATCHDOG=1")
		case <-poll.C:
		}
	}
}

func installHeldBootWaitExitCode(err error) (int, bool) {
	if errors.Is(err, errInstallHeldBootWaitExpired) {
		return exitInstallHeldBootWait, true
	}
	return 0, false
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

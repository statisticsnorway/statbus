package upgrade

import (
	"context"
	"log"
	"time"

	"github.com/statisticsnorway/statbus/cli/internal/monitor"
)

// monitorTickInterval is how often the upgrader refreshes the cached health
// reading. The CLI treats a reading older than three minutes as unknown, so
// two missed ticks make the staleness visible.
const monitorTickInterval = 60 * time.Second

// startMonitorRefresh runs the health checks once in a goroutine. It is
// deliberately non-blocking and single-flight: the checks include HTTP and
// Docker calls that can take seconds, and a slow measurement must never stall
// the upgrader's tick, heartbeat or upgrade path. Errors are logged and never
// propagate.
func (d *Service) startMonitorRefresh(ctx context.Context) {
	if !d.monitorMu.TryLock() {
		return // a previous refresh is still measuring
	}
	go func() {
		defer d.monitorMu.Unlock()
		reading := monitor.Run(ctx, monitor.DefaultProbes(d.projDir, string(d.version), monitor.PsqlQuery(d.projDir)))
		d.persistMonitorReading(reading)
	}()
}

// persistMonitorReading writes one reading and its markers. The write mutex
// keeps the periodic writer and the upgrading writer from interleaving.
func (d *Service) persistMonitorReading(reading monitor.Reading) {
	d.monitorWriteMu.Lock()
	defer d.monitorWriteMu.Unlock()
	// A check run that started before executeUpgrade may finish during it.
	// Whatever it measured, the public verdict while upgrading is the planned
	// upgrade, so a late normal reading cannot overwrite the upgrading one.
	if d.monitorUpgrading.Load() && reading.Status != monitor.StatusUpgrading {
		reading = d.upgradingReading()
	}
	if err := monitor.WriteReading(d.projDir, reading); err != nil {
		log.Printf("monitor: write health reading: %v", err)
	}
}

// upgradingReading is the planned-upgrade reading: the status and timestamp
// are live, the checks are the last ones measured. A poller then sees an
// upgrade in progress instead of a failure while containers restart.
func (d *Service) upgradingReading() monitor.Reading {
	base, err := monitor.ReadCache(d.projDir)
	if err != nil {
		base = monitor.Reading{}
	}
	return monitor.UpgradingReading(base, string(d.version), time.Now())
}

// startUpgradingReading writes the upgrading reading immediately and refreshes
// its checked_at every monitorTickInterval until the returned stop function is
// called. It never reads or writes the upgrader's database connection: the
// checks that need SQL go through PsqlQuery, so it cannot race the upgrade
// pipeline's exclusive use of queryConn.
func (d *Service) startUpgradingReading(ctx context.Context) func() {
	upgradeCtx, cancel := context.WithCancel(ctx)
	done := make(chan struct{})
	go func() {
		defer close(done)
		d.persistMonitorReading(d.upgradingReading())
		ticker := time.NewTicker(monitorTickInterval)
		defer ticker.Stop()
		for {
			select {
			case <-upgradeCtx.Done():
				return
			case <-ticker.C:
				d.persistMonitorReading(d.upgradingReading())
			}
		}
	}()
	return func() {
		cancel()
		<-done
	}
}

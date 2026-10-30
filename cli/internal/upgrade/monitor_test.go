package upgrade

import (
	"context"
	"os"
	"testing"
	"time"

	"github.com/statisticsnorway/statbus/cli/internal/monitor"
)

func waitForStatus(t *testing.T, projectDir string, want monitor.Status) monitor.Reading {
	t.Helper()
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		reading, err := monitor.ReadCache(projectDir)
		if err == nil && reading.Status == want {
			return reading
		}
		time.Sleep(20 * time.Millisecond)
	}
	reading, err := monitor.ReadCache(projectDir)
	t.Fatalf("reading did not become %s: %+v (err=%v)", want, reading, err)
	return monitor.Reading{}
}

// TestUpgradingReadingIsWrittenAndClearsTheCriticalMarker covers the public
// contract of STATBUS-541 during an upgrade: status upgrading (exit 1), the
// checks carry over for diagnosis, and Caddy's 503 marker is gone.
func TestUpgradingReadingIsWrittenAndClearsTheCriticalMarker(t *testing.T) {
	projectDir := t.TempDir()
	previous := monitor.Reading{
		Status:    monitor.StatusCritical,
		CheckedAt: time.Now().Add(-time.Minute).UTC(),
		Version:   "v2026.10.5",
		Checks:    []monitor.Check{{Name: monitor.CheckServices, Status: monitor.StatusCritical, Detail: "4/5 running"}},
	}
	if err := monitor.WriteReading(projectDir, previous); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(monitor.CriticalMarkerPath(projectDir)); err != nil {
		t.Fatalf("test setup: critical marker missing: %v", err)
	}

	d := &Service{projDir: projectDir, version: "v2026.10.6"}
	d.monitorUpgrading.Store(true)
	stop := d.startUpgradingReading(context.Background())
	reading := waitForStatus(t, projectDir, monitor.StatusUpgrading)
	stop()

	if reading.Version != "v2026.10.6" {
		t.Errorf("version = %q, want the upgrading binary's version", reading.Version)
	}
	if len(reading.Checks) != 1 || reading.Checks[0].Name != monitor.CheckServices {
		t.Errorf("checks did not carry over: %+v", reading.Checks)
	}
	if _, err := os.Stat(monitor.CriticalMarkerPath(projectDir)); !os.IsNotExist(err) {
		t.Errorf("critical marker still present during upgrade: %v", err)
	}
}

// TestLateNormalReadingCannotOverwriteTheUpgradingStatus covers the goroutine
// boundary: a check run that started before executeUpgrade may finish during
// it, and must still leave the public verdict as upgrading.
func TestLateNormalReadingCannotOverwriteTheUpgradingStatus(t *testing.T) {
	projectDir := t.TempDir()
	d := &Service{projDir: projectDir, version: "v2026.10.6"}
	d.monitorUpgrading.Store(true)
	d.persistMonitorReading(monitor.Reading{
		Status:    monitor.StatusOK,
		CheckedAt: time.Now().UTC(),
		Version:   "v2026.10.6",
		Checks:    []monitor.Check{{Name: monitor.CheckServices, Status: monitor.StatusOK, Detail: "5/5 running"}},
	})
	reading, err := monitor.ReadCache(projectDir)
	if err != nil {
		t.Fatal(err)
	}
	if reading.Status != monitor.StatusUpgrading {
		t.Fatalf("status = %s, want upgrading", reading.Status)
	}

	// After the upgrade the same writer returns to the measured status.
	d.monitorUpgrading.Store(false)
	d.persistMonitorReading(monitor.Reading{
		Status:    monitor.StatusOK,
		CheckedAt: time.Now().UTC(),
		Version:   "v2026.10.6",
		Checks:    []monitor.Check{{Name: monitor.CheckServices, Status: monitor.StatusOK, Detail: "5/5 running"}},
	})
	reading, err = monitor.ReadCache(projectDir)
	if err != nil {
		t.Fatal(err)
	}
	if reading.Status != monitor.StatusOK {
		t.Fatalf("status after upgrade = %s, want ok", reading.Status)
	}
}

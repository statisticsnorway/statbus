package cmd

import (
	"bytes"
	"context"
	"strings"
	"testing"
	"time"

	"github.com/statisticsnorway/statbus/cli/internal/monitor"
)

// healthyProbes is the monitor package's fixture shape for the CLI tests: all
// checks OK, no Docker or database needed.
func healthyProbes(now time.Time) monitor.Probes {
	return monitor.Probes{
		Services: func(context.Context) (monitor.ServiceResult, error) {
			return monitor.ServiceResult{Running: 5, Total: 5, DBHealthy: true}, nil
		},
		API: func(context.Context) (bool, error) { return true, nil },
		Site: func(context.Context) (monitor.SiteResult, error) {
			return monitor.SiteResult{Answered: true, HasCert: true, CertDays: 90}, nil
		},
		Disk: func(context.Context) (monitor.DiskResult, error) {
			return monitor.DiskResult{FreeGB: 100, MinimumGB: 20, RecommendedGB: 40}, nil
		},
		Backups: func(context.Context) (monitor.BackupResult, error) {
			return monitor.BackupResult{Enabled: true, Newest: now.Add(-time.Hour), Interval: 24 * time.Hour}, nil
		},
		Upgrader: func(context.Context) (monitor.UpgraderResult, error) {
			return monitor.UpgraderResult{Applicable: true, Active: true}, nil
		},
		Worker:  func(context.Context) (monitor.WorkerResult, error) { return monitor.WorkerResult{}, nil },
		Now:     func() time.Time { return now },
		Version: "v2026.10.5",
	}
}

func TestLoadMonitorReadingUsesCacheThenFallsBackToLive(t *testing.T) {
	projectDir := t.TempDir()
	now := time.Date(2026, 10, 30, 12, 0, 0, 0, time.UTC)
	probes := healthyProbes(now)
	probes.Disk = func(context.Context) (monitor.DiskResult, error) {
		return monitor.DiskResult{FreeGB: 10, MinimumGB: 20, RecommendedGB: 40}, nil
	}

	// No reading yet: run the checks live.
	live, fromCache := loadMonitorReading(context.Background(), projectDir, false, probes, now)
	if fromCache || live.Status != monitor.StatusCritical {
		t.Fatalf("no cache: fromCache=%t status=%s", fromCache, live.Status)
	}

	// A fresh reading is reported as written, even if the probes would differ.
	cached := monitor.Reading{
		Status:    monitor.StatusWarning,
		CheckedAt: now.Add(-time.Minute),
		Version:   "v2026.10.5",
		Checks:    []monitor.Check{{Name: monitor.CheckDisk, Status: monitor.StatusWarning, Detail: "30 GB free"}},
	}
	if err := monitor.WriteReading(projectDir, cached); err != nil {
		t.Fatal(err)
	}
	got, fromCache := loadMonitorReading(context.Background(), projectDir, false, probes, now)
	if !fromCache || got.Status != monitor.StatusWarning {
		t.Fatalf("fresh cache: fromCache=%t status=%s", fromCache, got.Status)
	}

	// Older than three minutes: unknown, but still from the cache.
	stale := cached
	stale.CheckedAt = now.Add(-5 * time.Minute)
	if err := monitor.WriteReading(projectDir, stale); err != nil {
		t.Fatal(err)
	}
	got, fromCache = loadMonitorReading(context.Background(), projectDir, false, probes, now)
	if !fromCache || got.Status != monitor.StatusUnknown {
		t.Fatalf("stale cache: fromCache=%t status=%s", fromCache, got.Status)
	}

	// --live ignores the cache.
	got, fromCache = loadMonitorReading(context.Background(), projectDir, true, probes, now)
	if fromCache || got.Status != monitor.StatusCritical {
		t.Fatalf("live: fromCache=%t status=%s", fromCache, got.Status)
	}
}

func TestRunMonitorStatusTextIsTheNagiosShapeAndExitCode(t *testing.T) {
	projectDir := t.TempDir()
	now := time.Date(2026, 10, 30, 12, 0, 0, 0, time.UTC)
	probes := healthyProbes(now)
	var out, errOut bytes.Buffer
	code := runMonitorStatus(context.Background(), projectDir, true, "text", probes, now, &out, &errOut)
	if code != 0 {
		t.Fatalf("exit code = %d, want 0 (stderr %q)", code, errOut.String())
	}
	lines := strings.Split(strings.TrimRight(out.String(), "\n"), "\n")
	if lines[0] != "StatBus OK - all checks passed" {
		t.Fatalf("summary = %q", lines[0])
	}
	if len(lines) != 1+7 {
		t.Fatalf("lines = %d, want 8: %q", len(lines), lines)
	}
}

func TestRunMonitorStatusJSONIsThePinnedReadingShape(t *testing.T) {
	projectDir := t.TempDir()
	now := time.Date(2026, 10, 30, 12, 0, 0, 0, time.UTC)
	var out, errOut bytes.Buffer
	code := runMonitorStatus(context.Background(), projectDir, true, "json", healthyProbes(now), now, &out, &errOut)
	if code != 0 {
		t.Fatalf("exit code = %d", code)
	}
	for _, key := range []string{`"status": "ok"`, `"checked_at"`, `"version": "v2026.10.5"`, `"checks"`, `"name": "services"`, `"detail": "5/5 running"`} {
		if !strings.Contains(out.String(), key) {
			t.Errorf("JSON output missing %s:\n%s", key, out.String())
		}
	}
	if strings.Contains(out.String(), projectDir) {
		t.Errorf("JSON output leaked the project path:\n%s", out.String())
	}
}

func TestRunMonitorStatusRunsLiveAndSaysSoWhenNoCacheExists(t *testing.T) {
	projectDir := t.TempDir()
	now := time.Date(2026, 10, 30, 12, 0, 0, 0, time.UTC)
	var out, errOut bytes.Buffer
	code := runMonitorStatus(context.Background(), projectDir, false, "text", healthyProbes(now), now, &out, &errOut)
	if code != 0 {
		t.Fatalf("exit code = %d", code)
	}
	if !strings.Contains(errOut.String(), "No cached reading found; ran the checks now.") {
		t.Fatalf("stderr = %q", errOut.String())
	}
}

func TestRunMonitorStatusRejectsAnUnknownFormat(t *testing.T) {
	var out, errOut bytes.Buffer
	code := runMonitorStatus(context.Background(), t.TempDir(), true, "prometheus", healthyProbes(time.Now()), time.Now(), &out, &errOut)
	if code != exitUsage {
		t.Fatalf("exit code = %d, want %d", code, exitUsage)
	}
	if out.Len() != 0 || !strings.Contains(errOut.String(), "the formats are text and json") {
		t.Fatalf("out=%q err=%q", out.String(), errOut.String())
	}
}

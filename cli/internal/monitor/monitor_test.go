package monitor

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"
)

// fixtureProbes returns probes that all report healthy, with Overrides applied
// by the caller. Every test starts from this so one failing probe is visibly
// the only reason for a non-OK verdict.
func fixtureProbes(now time.Time) Probes {
	return Probes{
		Services: func(context.Context) (ServiceResult, error) {
			return ServiceResult{Running: 5, Total: 5, DBHealthy: true}, nil
		},
		API: func(context.Context) (bool, error) { return true, nil },
		Site: func(context.Context) (SiteResult, error) {
			return SiteResult{Answered: true, HasCert: true, CertDays: 90}, nil
		},
		Disk: func(context.Context) (DiskResult, error) {
			return DiskResult{FreeGB: 100, MinimumGB: 20, RecommendedGB: 40}, nil
		},
		Backups: func(context.Context) (BackupResult, error) {
			return BackupResult{Enabled: true, Newest: time.Now().Add(-time.Hour), Interval: 24 * time.Hour}, nil
		},
		Upgrader: func(context.Context) (UpgraderResult, error) {
			return UpgraderResult{Applicable: true, Active: true}, nil
		},
		Worker:  func(context.Context) (WorkerResult, error) { return WorkerResult{}, nil },
		Now:     func() time.Time { return now },
		Version: "v2026.10.5",
	}
}

func checkByName(t *testing.T, checks []Check, name string) Check {
	t.Helper()
	for _, check := range checks {
		if check.Name == name {
			return check
		}
	}
	t.Fatalf("check %q not reported; got %+v", name, checks)
	return Check{}
}

func TestEveryCheckHasAKnownVerdictUnderHealthyProbes(t *testing.T) {
	now := time.Date(2026, 10, 30, 12, 0, 0, 0, time.UTC)
	reading := Run(context.Background(), fixtureProbes(now))
	if reading.Status != StatusOK {
		t.Fatalf("healthy probes: %s %+v", reading.Status, reading.Checks)
	}
	wantNames := []string{CheckServices, CheckAPI, CheckSite, CheckDisk, CheckBackups, CheckUpgrader, CheckWorker}
	if len(reading.Checks) != len(wantNames) {
		t.Fatalf("checks = %d, want %d", len(reading.Checks), len(wantNames))
	}
	for i, name := range wantNames {
		if reading.Checks[i].Name != name {
			t.Errorf("check %d = %q, want %q", i, reading.Checks[i].Name, name)
		}
		if reading.Checks[i].Status != StatusOK {
			t.Errorf("%s = %s (%s), want ok", name, reading.Checks[i].Status, reading.Checks[i].Detail)
		}
	}
	if !reading.CheckedAt.Equal(now) {
		t.Errorf("checked_at = %s, want %s", reading.CheckedAt, now)
	}
	if reading.Version != "v2026.10.5" {
		t.Errorf("version = %q", reading.Version)
	}
}

func TestCheckFixtures(t *testing.T) {
	now := time.Date(2026, 10, 30, 12, 0, 0, 0, time.UTC)
	cases := []struct {
		name   string
		probe  func(*Probes)
		check  string
		status Status
		detail string
	}{
		{
			name:   "services complete and healthy",
			probe:  func(*Probes) {},
			check:  CheckServices,
			status: StatusOK,
			detail: "5/5 running",
		},
		{
			name: "services missing one",
			probe: func(p *Probes) {
				p.Services = func(context.Context) (ServiceResult, error) {
					return ServiceResult{Running: 4, Total: 5, DBHealthy: true}, nil
				}
			},
			check:  CheckServices,
			status: StatusCritical,
			detail: "4/5 running",
		},
		{
			name: "services database unhealthy",
			probe: func(p *Probes) {
				p.Services = func(context.Context) (ServiceResult, error) {
					return ServiceResult{Running: 5, Total: 5, DBHealthy: false}, nil
				}
			},
			check:  CheckServices,
			status: StatusCritical,
			detail: "5/5 running, database not healthy",
		},
		{
			name: "api ready",
			probe: func(*Probes) {
			},
			check:  CheckAPI,
			status: StatusOK,
			detail: "API ready",
		},
		{
			name: "api not ready",
			probe: func(p *Probes) {
				p.API = func(context.Context) (bool, error) { return false, nil }
			},
			check:  CheckAPI,
			status: StatusCritical,
			detail: "API not ready",
		},
		{
			name: "site certificate healthy",
			probe: func(*Probes) {
			},
			check:  CheckSite,
			status: StatusOK,
			detail: "certificate 90 days left",
		},
		{
			name: "site certificate warning",
			probe: func(p *Probes) {
				p.Site = func(context.Context) (SiteResult, error) {
					return SiteResult{Answered: true, HasCert: true, CertDays: 14}, nil
				}
			},
			check:  CheckSite,
			status: StatusWarning,
			detail: "certificate expires in 14 days",
		},
		{
			name: "site certificate critical",
			probe: func(p *Probes) {
				p.Site = func(context.Context) (SiteResult, error) {
					return SiteResult{Answered: true, HasCert: true, CertDays: 3}, nil
				}
			},
			check:  CheckSite,
			status: StatusCritical,
			detail: "certificate expires in 3 days",
		},
		{
			name: "site did not answer",
			probe: func(p *Probes) {
				p.Site = func(context.Context) (SiteResult, error) {
					return SiteResult{Answered: false}, nil
				}
			},
			check:  CheckSite,
			status: StatusCritical,
			detail: "site did not answer",
		},
		{
			name: "site answered without TLS",
			probe: func(p *Probes) {
				p.Site = func(context.Context) (SiteResult, error) {
					return SiteResult{Answered: true}, nil
				}
			},
			check:  CheckSite,
			status: StatusOK,
			detail: "site answered",
		},
		{
			name: "disk recommended",
			probe: func(p *Probes) {
				p.Disk = func(context.Context) (DiskResult, error) {
					return DiskResult{FreeGB: 30, MinimumGB: 20, RecommendedGB: 40}, nil
				}
			},
			check:  CheckDisk,
			status: StatusWarning,
			detail: "30 GB free",
		},
		{
			name: "disk below minimum",
			probe: func(p *Probes) {
				p.Disk = func(context.Context) (DiskResult, error) {
					return DiskResult{FreeGB: 10, MinimumGB: 20, RecommendedGB: 40}, nil
				}
			},
			check:  CheckDisk,
			status: StatusCritical,
			detail: "10 GB free",
		},
		{
			name: "backup fresh",
			probe: func(*Probes) {
			},
			check:  CheckBackups,
			status: StatusOK,
			detail: "newest backup 1h ago",
		},
		{
			name: "backup late",
			probe: func(p *Probes) {
				p.Backups = func(context.Context) (BackupResult, error) {
					return BackupResult{Enabled: true, Newest: time.Now().Add(-27 * time.Hour), Interval: 24 * time.Hour}, nil
				}
			},
			check:  CheckBackups,
			status: StatusWarning,
			detail: "newest backup 27h ago",
		},
		{
			name: "backup stopped",
			probe: func(p *Probes) {
				p.Backups = func(context.Context) (BackupResult, error) {
					return BackupResult{Enabled: true, Newest: time.Now().Add(-60 * time.Hour), Interval: 24 * time.Hour}, nil
				}
			},
			check:  CheckBackups,
			status: StatusCritical,
			detail: "newest backup 60h ago",
		},
		{
			name: "backups disabled",
			probe: func(p *Probes) {
				p.Backups = func(context.Context) (BackupResult, error) {
					return BackupResult{Enabled: false}, nil
				}
			},
			check:  CheckBackups,
			status: StatusOK,
			detail: "backups disabled",
		},
		{
			name: "no backups yet",
			probe: func(p *Probes) {
				p.Backups = func(context.Context) (BackupResult, error) {
					return BackupResult{Enabled: true, Interval: 24 * time.Hour}, nil
				}
			},
			check:  CheckBackups,
			status: StatusCritical,
			detail: "no backups yet",
		},
		{
			name: "upgrader active",
			probe: func(*Probes) {
			},
			check:  CheckUpgrader,
			status: StatusOK,
			detail: "upgrader active",
		},
		{
			name: "upgrader inactive",
			probe: func(p *Probes) {
				p.Upgrader = func(context.Context) (UpgraderResult, error) {
					return UpgraderResult{Applicable: true, Active: false}, nil
				}
			},
			check:  CheckUpgrader,
			status: StatusWarning,
			detail: "upgrader inactive",
		},
		{
			name: "upgrade failed",
			probe: func(p *Probes) {
				p.Upgrader = func(context.Context) (UpgraderResult, error) {
					return UpgraderResult{Applicable: true, Active: true, Failed: true}, nil
				}
			},
			check:  CheckUpgrader,
			status: StatusWarning,
			detail: "upgrade failed",
		},
		{
			name: "upgrade parked",
			probe: func(p *Probes) {
				p.Upgrader = func(context.Context) (UpgraderResult, error) {
					return UpgraderResult{Applicable: true, Active: true, Parked: true}, nil
				}
			},
			check:  CheckUpgrader,
			status: StatusCritical,
			detail: "upgrade parked",
		},
		{
			name: "upgrader not applicable",
			probe: func(p *Probes) {
				p.Upgrader = func(context.Context) (UpgraderResult, error) {
					return UpgraderResult{Applicable: false}, nil
				}
			},
			check:  CheckUpgrader,
			status: StatusOK,
			detail: "upgrader not applicable",
		},
		{
			name: "worker healthy",
			probe: func(*Probes) {
			},
			check:  CheckWorker,
			status: StatusOK,
			detail: "0 failed in the last hour, 0 stuck",
		},
		{
			name: "worker some failures",
			probe: func(p *Probes) {
				p.Worker = func(context.Context) (WorkerResult, error) {
					return WorkerResult{FailedLastHour: 2}, nil
				}
			},
			check:  CheckWorker,
			status: StatusWarning,
			detail: "2 failed in the last hour, 0 stuck",
		},
		{
			name: "worker failure flood",
			probe: func(p *Probes) {
				p.Worker = func(context.Context) (WorkerResult, error) {
					return WorkerResult{FailedLastHour: 9}, nil
				}
			},
			check:  CheckWorker,
			status: StatusCritical,
			detail: "9 failed in the last hour, 0 stuck",
		},
		{
			name: "worker stuck",
			probe: func(p *Probes) {
				p.Worker = func(context.Context) (WorkerResult, error) {
					return WorkerResult{Stuck: 1}, nil
				}
			},
			check:  CheckWorker,
			status: StatusCritical,
			detail: "0 failed in the last hour, 1 stuck",
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			probes := fixtureProbes(now)
			tc.probe(&probes)
			reading := Run(context.Background(), probes)
			check := checkByName(t, reading.Checks, tc.check)
			if check.Status != tc.status || check.Detail != tc.detail {
				t.Fatalf("%s = %s %q, want %s %q", check.Name, check.Status, check.Detail, tc.status, tc.detail)
			}
		})
	}
}

func TestProbeErrorsAreUnknownAndDoNotAbortTheReading(t *testing.T) {
	now := time.Date(2026, 10, 30, 12, 0, 0, 0, time.UTC)
	probes := fixtureProbes(now)
	probes.Worker = func(context.Context) (WorkerResult, error) {
		return WorkerResult{}, errors.New("psql not found")
	}
	reading := Run(context.Background(), probes)
	worker := checkByName(t, reading.Checks, CheckWorker)
	if worker.Status != StatusUnknown {
		t.Fatalf("worker = %s, want unknown", worker.Status)
	}
	// The other checks still ran and still say OK.
	if api := checkByName(t, reading.Checks, CheckAPI); api.Status != StatusOK {
		t.Fatalf("api = %s, want ok", api.Status)
	}
	if reading.Status != StatusUnknown {
		t.Fatalf("overall = %s, want unknown", reading.Status)
	}
}

func TestOverallIsTheWorstCheck(t *testing.T) {
	cases := []struct {
		name   string
		checks []Check
		want   Status
	}{
		{"all ok", []Check{{Status: StatusOK}, {Status: StatusOK}}, StatusOK},
		{"warning beats ok", []Check{{Status: StatusOK}, {Status: StatusWarning}}, StatusWarning},
		{"critical beats warning", []Check{{Status: StatusWarning}, {Status: StatusCritical}}, StatusCritical},
		{"unknown beats critical", []Check{{Status: StatusCritical}, {Status: StatusUnknown}}, StatusUnknown},
		{"empty is ok", nil, StatusOK},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := Overall(tc.checks); got != tc.want {
				t.Fatalf("Overall = %s, want %s", got, tc.want)
			}
		})
	}
}

func TestStatusExitCodesAreTheNagiosContract(t *testing.T) {
	cases := map[Status]int{
		StatusOK:        0,
		StatusWarning:   1,
		StatusUpgrading: 1,
		StatusCritical:  2,
		StatusUnknown:   3,
	}
	for status, want := range cases {
		if got := status.ExitCode(); got != want {
			t.Errorf("%s exit code = %d, want %d", status, got, want)
		}
	}
}

func TestRenderTextStartsWithTheNagiosSummaryThenOneLinePerCheck(t *testing.T) {
	now := time.Date(2026, 10, 30, 12, 0, 0, 0, time.UTC)
	probes := fixtureProbes(now)
	probes.Disk = func(context.Context) (DiskResult, error) {
		return DiskResult{FreeGB: 30, MinimumGB: 20, RecommendedGB: 40}, nil
	}
	reading := Run(context.Background(), probes)
	lines := strings.Split(strings.TrimRight(RenderText(reading, now), "\n"), "\n")
	if len(lines) != 1+len(reading.Checks) {
		t.Fatalf("lines = %d, want %d: %q", len(lines), 1+len(reading.Checks), lines)
	}
	if lines[0] != "StatBus WARNING - disk 30 GB free" {
		t.Fatalf("summary = %q", lines[0])
	}
	if lines[1] != "services ok - 5/5 running" {
		t.Fatalf("first check line = %q", lines[1])
	}
	if !strings.Contains(strings.Join(lines, "\n"), "disk warning - 30 GB free") {
		t.Fatalf("disk line missing: %q", lines)
	}
}

func TestSummaryForUpgradingAndStale(t *testing.T) {
	now := time.Date(2026, 10, 30, 12, 0, 0, 0, time.UTC)
	upgrading := UpgradingReading(Reading{}, "v2026.10.5", now)
	if got := Summary(upgrading, now); got != "StatBus UPGRADING - upgrade in progress" {
		t.Fatalf("upgrading summary = %q", got)
	}
	stale := AsStale(Reading{Status: StatusOK, CheckedAt: now.Add(-10 * time.Minute)})
	if got := Summary(stale, now); got != "StatBus UNKNOWN - reading is 10m old" {
		t.Fatalf("stale summary = %q", got)
	}
}

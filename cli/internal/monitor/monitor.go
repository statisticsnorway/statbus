// Package monitor judges StatBus's own health once and reports that one
// reading to every consumer: the CLI, the cached file the upgrader refreshes,
// and the public /monitor response Caddy serves from that file.
//
// The check engine is deliberately small and injectable. Every probe is a
// function so tests can produce OK, WARNING, CRITICAL and UNKNOWN fixtures
// without a database, Docker or the network. Probes return plain, fixed-shape
// values; the check functions turn those values into a status and a detail
// sentence built from constants and numbers only. Nothing a probe learns that
// could identify this box (paths, addresses, user names, log text) reaches a
// detail string.
package monitor

import (
	"context"
	"fmt"
	"strings"
	"time"
)

// Status is the verdict of one check and of the reading as a whole.
//
// Severity is the contract the CLI exit code and the Nagios/Icinga plugin
// shape are built on: ok 0, warning 1, critical 2, unknown 3. "upgrading" is
// an overall status only: a planned upgrade is visible to a poller but is not
// an outage, so it shares warning's exit code.
type Status string

const (
	StatusOK        Status = "ok"
	StatusWarning   Status = "warning"
	StatusCritical  Status = "critical"
	StatusUnknown   Status = "unknown"
	StatusUpgrading Status = "upgrading"
)

// Severity ranks a status for "the overall status is the worst check".
// Unknown outranks critical: a critical check is a known outage, an unknown
// check is an answer the box could not produce, and a poller must not treat
// the second as better than the first.
func (s Status) Severity() int {
	switch s {
	case StatusOK:
		return 0
	case StatusWarning, StatusUpgrading:
		return 1
	case StatusCritical:
		return 2
	default:
		return 3
	}
}

// ExitCode is the process exit code for a status, matching the Nagios/Icinga
// plugin contract: 0 ok, 1 warning, 2 critical, 3 unknown.
func (s Status) ExitCode() int { return s.Severity() }

// Upper is the status spelled for the Nagios-shaped first line.
func (s Status) Upper() string {
	switch s {
	case StatusOK:
		return "OK"
	case StatusWarning:
		return "WARNING"
	case StatusCritical:
		return "CRITICAL"
	case StatusUpgrading:
		return "UPGRADING"
	default:
		return "UNKNOWN"
	}
}

// Check is one health reading. Its JSON form is the public contract: name,
// status and detail, nothing else.
type Check struct {
	Name   string `json:"name"`
	Status Status `json:"status"`
	Detail string `json:"detail"`
}

// Reading is one complete health reading, cached by the upgrader and read by
// the CLI. Every exported field is part of the public /monitor JSON; add a
// field here only if it is safe for an unauthenticated reader.
type Reading struct {
	Status    Status    `json:"status"`
	CheckedAt time.Time `json:"checked_at"`
	Version   string    `json:"version"`
	Checks    []Check   `json:"checks"`
}

// Check names. They are stable identifiers used by dependent monitoring items
// and by operators reading the template, so they are constants, not literals
// at call sites.
const (
	CheckServices = "services"
	CheckAPI      = "api"
	CheckSite     = "site"
	CheckDisk     = "disk"
	CheckBackups  = "backups"
	CheckUpgrader = "upgrader"
	CheckWorker   = "worker"
)

// Fixed thresholds. They are constants with the reasoning next to them so a
// future change is a decision, not a drift.
const (
	// A certificate inside three weeks of expiry is a warning; inside one
	// week it is an outage waiting for a renewal that may need a human.
	certWarningDays  = 21
	certCriticalDays = 7

	// Backups run on BACKUP_INTERVAL (24h by default). Two hours of grace
	// covers a dump that starts a little late; more than two intervals
	// without a dump means the scheduled backup is not running.
	backupGrace = 2 * time.Hour

	// A handful of failed tasks can be normal after an import or a schema
	// change; a flood means the worker is not keeping up. One stuck
	// processing task older than an hour is already abnormal.
	workerFailedWarning = 5
	workerStuckWarning  = 1

	// A cached reading older than this means the upgrader's 60 s tick has
	// stopped. The CLI reports unknown rather than presenting stale news.
	CacheStaleAfter = 3 * time.Minute
)

// Probes are the seams of the check engine. Any nil probe yields an UNKNOWN
// check; callers that have only some capabilities can say so structurally
// instead of printing a misleading OK.
type Probes struct {
	Services func(context.Context) (ServiceResult, error)
	API      func(context.Context) (bool, error)
	Site     func(context.Context) (SiteResult, error)
	Disk     func(context.Context) (DiskResult, error)
	Backups  func(context.Context) (BackupResult, error)
	Upgrader func(context.Context) (UpgraderResult, error)
	Worker   func(context.Context) (WorkerResult, error)

	Now     func() time.Time
	Version string
}

// ServiceResult is the state of the five serving containers and the database
// healthcheck every deployment runs.
type ServiceResult struct {
	Running   int
	Total     int
	DBHealthy bool
}

// SiteResult is whether the advertised site answered and, when it serves TLS,
// how long the certificate has left.
type SiteResult struct {
	Answered bool
	HasCert  bool
	CertDays int
}

// DiskResult is free space at the measured filesystem and the policy that
// applies to it (from diskpolicy, so install, upgrade and monitoring cannot
// disagree about the threshold).
type DiskResult struct {
	FreeGB        uint64
	MinimumGB     uint64
	RecommendedGB uint64
}

// BackupResult is the newest logical backup and the configured cadence.
// Enabled is false when the operator opted out with BACKUP_ENABLED=false.
type BackupResult struct {
	Enabled  bool
	Newest   time.Time
	Interval time.Duration
}

// UpgraderResult is the upgrader's unit state plus any upgrade that failed
// recently or is parked waiting for an operator. Applicable is false on a
// platform with no systemd user units, where inactivity is not a defect.
type UpgraderResult struct {
	Applicable bool
	Active     bool
	Failed     bool
	Parked     bool
}

// WorkerResult is the task queue's health over the last hour.
type WorkerResult struct {
	FailedLastHour int
	Stuck          int
}

// Overall returns the worst status among checks, ignoring the check name.
func Overall(checks []Check) Status {
	worst := StatusOK
	for _, check := range checks {
		if check.Status.Severity() > worst.Severity() {
			worst = check.Status
		}
	}
	return worst
}

// Run performs every check now and returns one reading. Probe errors become
// UNKNOWN for that check; they never abort the reading, so one unavailable
// measurement cannot hide the rest.
func Run(ctx context.Context, probes Probes) Reading {
	now := time.Now().UTC()
	if probes.Now != nil {
		now = probes.Now().UTC()
	}
	checks := []Check{
		servicesCheck(ctx, probes.Services),
		apiCheck(ctx, probes.API),
		siteCheck(ctx, probes.Site),
		diskCheck(ctx, probes.Disk),
		backupsCheck(ctx, probes.Backups),
		upgraderCheck(ctx, probes.Upgrader),
		workerCheck(ctx, probes.Worker),
	}
	return Reading{
		Status:    Overall(checks),
		CheckedAt: now,
		Version:   probes.Version,
		Checks:    checks,
	}
}

// UpgradingReading turns a reading (usually the previous cached one) into the
// planned-upgrade reading the upgrader writes while it is applying an upgrade.
// The checks carry over so a poller sees what was last measured; the overall
// status and timestamp are the live part.
func UpgradingReading(base Reading, version string, now time.Time) Reading {
	if base.Checks == nil {
		base.Checks = []Check{}
	}
	return Reading{
		Status:    StatusUpgrading,
		CheckedAt: now.UTC(),
		Version:   version,
		Checks:    base.Checks,
	}
}

func servicesCheck(ctx context.Context, probe func(context.Context) (ServiceResult, error)) Check {
	if probe == nil {
		return unknownCheck(CheckServices, "not measured")
	}
	result, err := probe(ctx)
	if err != nil {
		return unknownCheck(CheckServices, "not measured")
	}
	detail := fmt.Sprintf("%d/%d running", result.Running, result.Total)
	if !result.DBHealthy {
		detail += ", database not healthy"
	}
	status := StatusOK
	if result.Running < result.Total || !result.DBHealthy {
		status = StatusCritical
	}
	return Check{Name: CheckServices, Status: status, Detail: detail}
}

func apiCheck(ctx context.Context, probe func(context.Context) (bool, error)) Check {
	if probe == nil {
		return unknownCheck(CheckAPI, "not measured")
	}
	ready, err := probe(ctx)
	if err != nil {
		return Check{Name: CheckAPI, Status: StatusCritical, Detail: "API not ready"}
	}
	if !ready {
		return Check{Name: CheckAPI, Status: StatusCritical, Detail: "API not ready"}
	}
	return Check{Name: CheckAPI, Status: StatusOK, Detail: "API ready"}
}

func siteCheck(ctx context.Context, probe func(context.Context) (SiteResult, error)) Check {
	if probe == nil {
		return unknownCheck(CheckSite, "not measured")
	}
	result, err := probe(ctx)
	if err != nil {
		return unknownCheck(CheckSite, "not measured")
	}
	if !result.Answered {
		return Check{Name: CheckSite, Status: StatusCritical, Detail: "site did not answer"}
	}
	if !result.HasCert {
		return Check{Name: CheckSite, Status: StatusOK, Detail: "site answered"}
	}
	switch {
	case result.CertDays <= certCriticalDays:
		return Check{Name: CheckSite, Status: StatusCritical, Detail: fmt.Sprintf("certificate expires in %d days", result.CertDays)}
	case result.CertDays <= certWarningDays:
		return Check{Name: CheckSite, Status: StatusWarning, Detail: fmt.Sprintf("certificate expires in %d days", result.CertDays)}
	default:
		return Check{Name: CheckSite, Status: StatusOK, Detail: fmt.Sprintf("certificate %d days left", result.CertDays)}
	}
}

func diskCheck(ctx context.Context, probe func(context.Context) (DiskResult, error)) Check {
	if probe == nil {
		return unknownCheck(CheckDisk, "not measured")
	}
	result, err := probe(ctx)
	if err != nil {
		return unknownCheck(CheckDisk, "not measured")
	}
	detail := fmt.Sprintf("%d GB free", result.FreeGB)
	switch {
	case result.FreeGB < result.MinimumGB:
		return Check{Name: CheckDisk, Status: StatusCritical, Detail: detail}
	case result.FreeGB < result.RecommendedGB:
		return Check{Name: CheckDisk, Status: StatusWarning, Detail: detail}
	default:
		return Check{Name: CheckDisk, Status: StatusOK, Detail: detail}
	}
}

func backupsCheck(ctx context.Context, probe func(context.Context) (BackupResult, error)) Check {
	if probe == nil {
		return unknownCheck(CheckBackups, "not measured")
	}
	result, err := probe(ctx)
	if err != nil {
		return unknownCheck(CheckBackups, "not measured")
	}
	if !result.Enabled {
		return Check{Name: CheckBackups, Status: StatusOK, Detail: "backups disabled"}
	}
	if result.Newest.IsZero() {
		return Check{Name: CheckBackups, Status: StatusCritical, Detail: "no backups yet"}
	}
	interval := result.Interval
	if interval <= 0 {
		interval = 24 * time.Hour
	}
	age := time.Since(result.Newest)
	if age < 0 {
		age = 0
	}
	detail := fmt.Sprintf("newest backup %dh ago", int(age.Hours()))
	switch {
	case age > 2*interval+backupGrace:
		return Check{Name: CheckBackups, Status: StatusCritical, Detail: detail}
	case age > interval+backupGrace:
		return Check{Name: CheckBackups, Status: StatusWarning, Detail: detail}
	default:
		return Check{Name: CheckBackups, Status: StatusOK, Detail: detail}
	}
}

func upgraderCheck(ctx context.Context, probe func(context.Context) (UpgraderResult, error)) Check {
	if probe == nil {
		return unknownCheck(CheckUpgrader, "not measured")
	}
	result, err := probe(ctx)
	if err != nil {
		return unknownCheck(CheckUpgrader, "not measured")
	}
	if !result.Applicable {
		return Check{Name: CheckUpgrader, Status: StatusOK, Detail: "upgrader not applicable"}
	}
	if !result.Active {
		return Check{Name: CheckUpgrader, Status: StatusWarning, Detail: "upgrader inactive"}
	}
	if result.Parked {
		return Check{Name: CheckUpgrader, Status: StatusCritical, Detail: "upgrade parked"}
	}
	if result.Failed {
		return Check{Name: CheckUpgrader, Status: StatusWarning, Detail: "upgrade failed"}
	}
	return Check{Name: CheckUpgrader, Status: StatusOK, Detail: "upgrader active"}
}

func workerCheck(ctx context.Context, probe func(context.Context) (WorkerResult, error)) Check {
	if probe == nil {
		return unknownCheck(CheckWorker, "not measured")
	}
	result, err := probe(ctx)
	if err != nil {
		return unknownCheck(CheckWorker, "not measured")
	}
	detail := fmt.Sprintf("%d failed in the last hour, %d stuck", result.FailedLastHour, result.Stuck)
	switch {
	case result.Stuck >= workerStuckWarning:
		return Check{Name: CheckWorker, Status: StatusCritical, Detail: detail}
	case result.FailedLastHour > workerFailedWarning:
		return Check{Name: CheckWorker, Status: StatusCritical, Detail: detail}
	case result.FailedLastHour > 0:
		return Check{Name: CheckWorker, Status: StatusWarning, Detail: detail}
	default:
		return Check{Name: CheckWorker, Status: StatusOK, Detail: detail}
	}
}

func unknownCheck(name, detail string) Check {
	return Check{Name: name, Status: StatusUnknown, Detail: detail}
}

// Summary is the Nagios-shaped first line: the overall status and the check
// that produced it. A stale reading is named as stale rather than repeating
// the old check's detail as if it were current.
func Summary(reading Reading, now time.Time) string {
	if reading.Status == StatusUpgrading {
		return "StatBus UPGRADING - upgrade in progress"
	}
	if reading.Status == StatusOK {
		return "StatBus OK - all checks passed"
	}
	if reading.Status == StatusUnknown {
		if age := now.Sub(reading.CheckedAt); age > CacheStaleAfter {
			return fmt.Sprintf("StatBus UNKNOWN - reading is %dm old", int(age.Minutes()))
		}
	}
	worst := Check{Status: StatusOK}
	for _, check := range reading.Checks {
		if check.Status.Severity() >= worst.Status.Severity() && check.Status != StatusOK {
			worst = check
		}
	}
	if worst.Name == "" {
		return "StatBus " + reading.Status.Upper() + " - no checks reported"
	}
	return fmt.Sprintf("StatBus %s - %s %s", reading.Status.Upper(), worst.Name, worst.Detail)
}

// RenderText renders the Nagios/Icinga plugin output: the summary line, then
// one line per check.
func RenderText(reading Reading, now time.Time) string {
	var b strings.Builder
	b.WriteString(Summary(reading, now))
	b.WriteString("\n")
	for _, check := range reading.Checks {
		fmt.Fprintf(&b, "%s %s - %s\n", check.Name, check.Status, check.Detail)
	}
	return b.String()
}

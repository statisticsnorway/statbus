// Package install diagnoses the state of a StatBus install directory and
// drives the unified ./sb install entrypoint. This file contains DetectState,
// the pure probe function consumed by cli/cmd/install.
//
// Detection policy (locked):
//  1. No .env.config ........................... StateFresh (use binary's version)
//  2. Flag file present + flock held ........... StateLiveUpgrade (refuse)
//  3. Flag file present + flock free ........... StateCrashedUpgrade (recover)
//  4. Config present, credentials missing ...... StateHalfConfigured
//  5. Config + creds, DB down .................. StateDBUnreachable
//  6. DB up, no public.upgrade ................. StateLegacyNoUpgradeTable
//  7. Scheduled row present .................... StateScheduledUpgrade
//  8. Failed row w/ retained backup_path ....... StateRestoreReattemptable (STATBUS-111)
//  9. Everything there, no scheduled row ....... StateNothingScheduled
//
// StateNothingScheduled is NOT an error: a healthy existing install with no
// pending upgrade is the normal steady state, and `./sb install` on it runs
// the idempotent step-table as a config-refresh checkpoint. Operators who
// want to upgrade run `./sb upgrade schedule <v>` first.
//
// Single source of truth for TargetVersion: the binary's ldflags version on a
// fresh install; the scheduled row's version on an upgrade. No caller supplies
// a --version flag.
package install

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/statisticsnorway/statbus/cli/internal/migrate"
	"github.com/statisticsnorway/statbus/cli/internal/upgrade"
)

// State is the diagnosed state of an install directory.
type State int

const (
	StateFresh State = iota
	StateLiveUpgrade
	StateCrashedUpgrade
	StateHalfConfigured
	StateDBUnreachable
	StateLegacyNoUpgradeTable
	StateScheduledUpgrade
	StateRestoreReattemptable
	StateNothingScheduled
)

func (s State) String() string {
	switch s {
	case StateFresh:
		return "fresh"
	case StateLiveUpgrade:
		return "live-upgrade"
	case StateCrashedUpgrade:
		return "crashed-upgrade"
	case StateHalfConfigured:
		return "half-configured"
	case StateDBUnreachable:
		return "db-unreachable"
	case StateLegacyNoUpgradeTable:
		return "legacy-no-upgrade-table"
	case StateScheduledUpgrade:
		return "scheduled-upgrade"
	case StateRestoreReattemptable:
		return "restore-reattemptable"
	case StateNothingScheduled:
		return "nothing-scheduled"
	default:
		return fmt.Sprintf("unknown(%d)", int(s))
	}
}

// ScheduledRow is the minimal projection of a public.upgrade row awaiting apply.
type ScheduledRow struct {
	ID        int64
	CommitSHA string
	Version   string // commit_version shape: CalVer tag, describe-off-tag, or 8-char commit_short
}

// Detail is the evidence surfaced alongside a State.
type Detail struct {
	Flag                *upgrade.UpgradeFlag // populated for StateLive/StateCrashedUpgrade
	CurrentVersion      string               // binary's compile-time ldflags version
	TargetVersion       string               // what the caller should install (binary version or scheduled row's version)
	ScheduledRowID      int64                // populated for StateScheduledUpgrade
	TargetCommitSHA     string               // populated for StateScheduledUpgrade
	TargetDisplayName   string               // populated for StateScheduledUpgrade
	ReattemptRowID      int64                // populated for StateRestoreReattemptable (the failed row to re-attempt)
	ReattemptBackupPath string               // populated for StateRestoreReattemptable (the retained snapshot to restore)
}

// Probe abstracts the environment queries Detect makes. The default probe hits
// the real filesystem and runs psql. Tests inject fakes.
type Probe interface {
	FileExists(path string) bool
	ReadFlag(projDir string) (*upgrade.UpgradeFlag, bool, error)
	DBReachable(projDir string) bool
	HasUpgradeTable(projDir string) (bool, error)
	QueryScheduledUpgrade(projDir string) (*ScheduledRow, error)
	QueryReattemptableRestore(projDir string) (rowID int64, backupPath string, found bool, err error)
}

// Detect runs the full ladder with the default probe.
func Detect(projDir, currentVersion string) (State, *Detail, error) {
	return DetectWith(projDir, currentVersion, defaultProbe{})
}

// DetectWith runs the ladder with a caller-supplied probe.
func DetectWith(projDir, currentVersion string, probe Probe) (State, *Detail, error) {
	detail := &Detail{CurrentVersion: currentVersion, TargetVersion: currentVersion}

	if !probe.FileExists(filepath.Join(projDir, ".env.config")) {
		return StateFresh, detail, nil
	}

	flag, alive, err := probe.ReadFlag(projDir)
	if err != nil {
		return 0, nil, fmt.Errorf("read upgrade flag: %w", err)
	}
	if flag != nil {
		detail.Flag = flag
		if alive {
			return StateLiveUpgrade, detail, nil
		}
		return StateCrashedUpgrade, detail, nil
	}

	if !probe.FileExists(filepath.Join(projDir, ".env.credentials")) {
		return StateHalfConfigured, detail, nil
	}

	if !probe.DBReachable(projDir) {
		return StateDBUnreachable, detail, nil
	}

	hasTable, err := probe.HasUpgradeTable(projDir)
	if err != nil {
		return 0, nil, fmt.Errorf("check public.upgrade existence: %w", err)
	}
	if !hasTable {
		return StateLegacyNoUpgradeTable, detail, nil
	}

	row, err := probe.QueryScheduledUpgrade(projDir)
	if err != nil {
		return 0, nil, fmt.Errorf("query scheduled upgrade: %w", err)
	}
	if row != nil {
		detail.ScheduledRowID = row.ID
		detail.TargetCommitSHA = row.CommitSHA
		detail.TargetDisplayName = row.Version
		detail.TargetVersion = row.Version
		return StateScheduledUpgrade, detail, nil
	}

	// STATBUS-111: a restore-broke row (state='failed' with a retained
	// backup_path) is RE-ATTEMPTABLE — `./sb install` replays the interrupted
	// snapshot restore rather than dead-ending at the idempotent step-table.
	// Probed AFTER the scheduled-row check (a genuinely scheduled upgrade wins)
	// and BEFORE nothing-scheduled. Human-gated: only the install ladder reaches
	// here; the service's flag-based recovery is inert on this path (the flag was
	// removed at the restore-broke terminal).
	rid, bpath, found, err := probe.QueryReattemptableRestore(projDir)
	if err != nil {
		return 0, nil, fmt.Errorf("query reattemptable restore: %w", err)
	}
	if found {
		detail.ReattemptRowID = rid
		detail.ReattemptBackupPath = bpath
		return StateRestoreReattemptable, detail, nil
	}

	return StateNothingScheduled, detail, nil
}

// defaultProbe is the production Probe: real filesystem + psql subprocess.
type defaultProbe struct{}

func (defaultProbe) FileExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}

func (defaultProbe) ReadFlag(projDir string) (*upgrade.UpgradeFlag, bool, error) {
	flag, err := upgrade.ReadFlagFile(projDir)
	if err != nil || flag == nil {
		return flag, false, err
	}
	return flag, upgrade.IsFlockHeld(projDir), nil
}

func (defaultProbe) DBReachable(projDir string) bool {
	out, err := runQuery(projDir, 5*time.Second, "SELECT 1")
	if err != nil {
		return false
	}
	return strings.TrimSpace(out) == "1"
}

func (defaultProbe) HasUpgradeTable(projDir string) (bool, error) {
	sql := `SELECT 1 FROM pg_class c
            JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'public' AND c.relname = 'upgrade' LIMIT 1`
	out, err := runQuery(projDir, 10*time.Second, sql)
	if err != nil {
		return false, err
	}
	return strings.TrimSpace(out) == "1", nil
}

func (defaultProbe) QueryScheduledUpgrade(projDir string) (*ScheduledRow, error) {
	// Oldest pending row wins; the scheduler enforces at-most-one.
	// Use commit_sha as the version fallback — the version column was
	// added by migration 20260415183106 and may not exist on servers
	// that haven't run it yet.
	sql := `SELECT id, commit_sha, commit_sha
              FROM public.upgrade
             WHERE state = 'scheduled' AND started_at IS NULL
             ORDER BY id ASC LIMIT 1`
	out, err := runQuery(projDir, 10*time.Second, sql)
	if err != nil {
		return nil, err
	}
	line := strings.TrimSpace(out)
	if line == "" {
		return nil, nil
	}
	parts := strings.Split(line, "|")
	if len(parts) < 3 {
		return nil, fmt.Errorf("unexpected scheduled-upgrade row: %q", line)
	}
	id, err := strconv.ParseInt(parts[0], 10, 64)
	if err != nil {
		return nil, fmt.Errorf("parse id from %q: %w", parts[0], err)
	}
	return &ScheduledRow{
		ID:        id,
		CommitSHA: parts[1],
		Version:   parts[2],
	}, nil
}

// QueryReattemptableRestore finds a restore-broke row to re-attempt: the most
// recent state='failed' row that still has a retained backup_path. STATBUS-111.
//
// PIN 2 co-extensiveness (proven by enumerating every state='failed' writer in
// cli/internal/upgrade/service.go): failed-WITH-retained-backup_path is produced
// ONLY by the restore-broke terminals —
//   - rollback() degraded terminal (LabelFailedRollbackIncomplete)
//   - rollback() git-restore ABORT terminal (LabelFailedAbort)
//   - recoveryRollback pair-terminal (two rollback crash-deaths, LabelFailedRollbackIncomplete)
//
// The two OTHER failed writers cannot produce the combination:
//   - failUpgrade runs ONLY before the snapshot (pre-backupDatabase) → backup_path NULL.
//   - completeInProgressUpgrade's post-restart health-fail runs ONLY when NO
//     service flag is held, but backup_path is written only post-swap under a
//     held flag (released solely at a terminal write) → a no-flag in_progress
//     row never carries backup_path.
//
// Invariant: backup_path-set ⟹ post-swap ⟹ flag held until terminal. So the
// probe needs no structural discriminator; state='failed' AND backup_path
// present is exactly the restore-broke set.
func (defaultProbe) QueryReattemptableRestore(projDir string) (int64, string, bool, error) {
	out, err := runQuery(projDir, 10*time.Second,
		`SELECT id, backup_path FROM public.upgrade
		  WHERE state = 'failed' AND backup_path IS NOT NULL
		  ORDER BY id DESC LIMIT 1`)
	if err != nil {
		return 0, "", false, err
	}
	line := strings.TrimSpace(out)
	if line == "" {
		return 0, "", false, nil
	}
	parts := strings.SplitN(line, "|", 2)
	if len(parts) < 2 {
		return 0, "", false, fmt.Errorf("unexpected reattemptable-restore row: %q", line)
	}
	id, perr := strconv.ParseInt(strings.TrimSpace(parts[0]), 10, 64)
	if perr != nil {
		return 0, "", false, fmt.Errorf("parse id from %q: %w", parts[0], perr)
	}
	backupPath := strings.TrimSpace(parts[1])
	if backupPath == "" {
		return 0, "", false, nil
	}
	return id, backupPath, true, nil
}

// LiveMaxMigrationVersion queries db.migration for the highest applied
// migration version, returning the bare 14-digit string (or "" when the
// table is empty / query fails). Best-effort: errors are swallowed and
// reported as "" so the diagnostic caller can degrade gracefully when
// the DB is uncontactable or the schema is mid-migration.
//
// Used by logInstallState (cli/cmd/install.go) to enrich the
// StateNothingScheduled diagnostic with DB-vs-disk migration drift.
// Operators previously hit "Detected install state: nothing-scheduled"
// + "Existing install, no upgrade scheduled; running idempotent
// step-table to refresh" while the DB actually had pending migrations
// — message implied "nothing to do" when 4+ migrations were about to
// apply via the step-table.
func LiveMaxMigrationVersion(projDir string) string {
	out, err := runQuery(projDir, 10*time.Second,
		"SELECT COALESCE(MAX(version)::text, '') FROM db.migration")
	if err != nil {
		return ""
	}
	return strings.TrimSpace(out)
}

// OnDiskMaxMigrationVersion scans migrations/*.up.{sql,psql} and returns
// the highest 14-digit version timestamp found, or "" when the directory
// is empty / unreadable. Best-effort: errors degrade to "".
func OnDiskMaxMigrationVersion(projDir string) string {
	entries, err := os.ReadDir(filepath.Join(projDir, "migrations"))
	if err != nil {
		return ""
	}
	latest := ""
	for _, e := range entries {
		name := e.Name()
		if !strings.HasSuffix(name, ".up.sql") && !strings.HasSuffix(name, ".up.psql") {
			continue
		}
		version := strings.SplitN(name, "_", 2)[0]
		if len(version) == 14 && version > latest {
			latest = version
		}
	}
	return latest
}

// runQuery runs a single-value psql query with pipe separator and no header.
// Returns the raw output (pipe-delimited, newline-terminated) or an error.
func runQuery(projDir string, timeout time.Duration, sql string) (string, error) {
	psqlPath, prefix, env, err := migrate.PsqlCommand(projDir)
	if err != nil {
		return "", err
	}
	args := append(append([]string{}, prefix...),
		"-v", "ON_ERROR_STOP=on",
		"-X", "-A", "-t", "-F", "|",
		"-c", sql)
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, psqlPath, args...)
	cmd.Dir = projDir
	cmd.Env = env
	out, err := cmd.CombinedOutput()
	if err != nil {
		return "", fmt.Errorf("psql: %w (%s)", err, strings.TrimSpace(string(out)))
	}
	return string(out), nil
}

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
//  6. DB up, no public.upgrade:
//     - this installer's own unfinished setup .. StateFreshDBIncomplete (continue)
//     - otherwise (pre-1.0 database) ........... StateLegacyNoUpgradeTable (refuse)
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
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/statisticsnorway/statbus/cli/internal/migrate"
	"github.com/statisticsnorway/statbus/cli/internal/upgrade"
)

// State is the diagnosed state of an install directory.
type State int

// ErrDatabaseUnavailable is the only detection error permitting a step-table
// repair fallback. It is attached only to positively identified connection
// failures, never to query, configuration, command construction or parse errors.
var ErrDatabaseUnavailable = errors.New("database unavailable")

func unclassifiableResponse(format string, args ...any) error {
	return fmt.Errorf(format, args...)
}

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
	StateFreshDBIncomplete
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
	case StateFreshDBIncomplete:
		return "fresh-db-incomplete"
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
	FileExists(path string) (bool, error)
	ReadFlag(projDir string) (*upgrade.UpgradeFlag, bool, error)
	DBReachable(projDir string) (bool, error)
	HasUpgradeTable(projDir string) (bool, error)
	InspectSchemaHistory(projDir string) (SchemaHistory, error)
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

	hasConfig, err := probe.FileExists(filepath.Join(projDir, ".env.config"))
	if err != nil {
		return 0, nil, fmt.Errorf("check .env.config: %w", err)
	}
	if !hasConfig {
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

	hasCredentials, err := probe.FileExists(filepath.Join(projDir, ".env.credentials"))
	if err != nil {
		return 0, nil, fmt.Errorf("check .env.credentials: %w", err)
	}
	if !hasCredentials {
		return StateHalfConfigured, detail, nil
	}

	reachable, err := probe.DBReachable(projDir)
	if err != nil {
		return 0, nil, fmt.Errorf("probe database reachability: %w", err)
	}
	if !reachable {
		return StateDBUnreachable, detail, nil
	}

	hasTable, err := probe.HasUpgradeTable(projDir)
	if err != nil {
		return 0, nil, fmt.Errorf("check public.upgrade existence: %w", err)
	}
	if !hasTable {
		history, err := probe.InspectSchemaHistory(projDir)
		if err != nil {
			return 0, nil, fmt.Errorf("inspect schema history: %w", err)
		}
		if history.IsUnfinishedFreshInstall() {
			return StateFreshDBIncomplete, detail, nil
		}
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

// upgradeTableMigrationVersion is the migration that creates public.upgrade.
// Migration versions, unlike applied_at timestamps, are release provenance:
// restoring or applying an old release today cannot make its versions modern.
const upgradeTableMigrationVersion = "20260311174120"

// SchemaHistory is what the database says about how it was set up, used only
// when public.upgrade is absent to tell a pre-1.0 database from a fresh install
// that stopped after the database was created (STATBUS-394 follow-up: Finland's
// rerun after step 8 was refused as "pre-1.0").
type SchemaHistory struct {
	// AppliedMigrations counts rows in db.migration (0 when the table is absent).
	AppliedMigrations int64
	// AppliedVersions is the complete set of db.migration versions.
	AppliedVersions []string
	// HasApplicationSchema is true when any public application table exists.
	HasApplicationSchema bool
}

// IsUnfinishedFreshInstall is the pure verdict. Two shapes are this installer's
// own unfinished work:
//   - init-db.sh only: no migration applied and no application tables (the DB
//     container initialised the empty cluster; Seed and Migrations never ran).
//   - migration history containing only versions newer than the migration that
//     introduced public.upgrade. This is unambiguous modern provenance. A full
//     replay also contains old versions, so it is conservatively refused if it
//     somehow has no public.upgrade table.
//
// Everything else without public.upgrade is a pre-1.0 database, including a
// database with application tables but no migration history at all.
func (h SchemaHistory) IsUnfinishedFreshInstall() bool {
	if h.AppliedMigrations == 0 {
		return !h.HasApplicationSchema
	}
	if int64(len(h.AppliedVersions)) != h.AppliedMigrations {
		return false
	}
	for _, version := range h.AppliedVersions {
		if version <= upgradeTableMigrationVersion {
			return false
		}
	}
	return true
}

// defaultProbe is the production Probe: real filesystem + psql subprocess.
type defaultProbe struct{}

func (defaultProbe) FileExists(path string) (bool, error) {
	_, err := os.Stat(path)
	if errors.Is(err, os.ErrNotExist) {
		return false, nil
	}
	return err == nil, err
}

func (defaultProbe) ReadFlag(projDir string) (*upgrade.UpgradeFlag, bool, error) {
	flag, err := upgrade.ReadFlagFile(projDir)
	if err != nil || flag == nil {
		return flag, false, err
	}
	return flag, upgrade.IsFlockHeld(projDir), nil
}

func (defaultProbe) DBReachable(projDir string) (bool, error) {
	out, err := runQuery(projDir, 5*time.Second, "SELECT 1")
	if err != nil {
		return false, err
	}
	if strings.TrimSpace(out) != "1" {
		return false, unclassifiableResponse("unexpected SELECT 1 probe output: %q", out)
	}
	return true, nil
}

func (defaultProbe) HasUpgradeTable(projDir string) (bool, error) {
	sql := `SELECT 1 FROM pg_class c
            JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'public' AND c.relname = 'upgrade' LIMIT 1`
	out, err := runQuery(projDir, 10*time.Second, sql)
	if err != nil {
		return false, err
	}
	return parseUpgradeTableOutput(out)
}

func parseUpgradeTableOutput(out string) (bool, error) {
	switch strings.TrimSpace(out) {
	case "1":
		return true, nil
	case "":
		return false, nil
	default:
		return false, unclassifiableResponse("unexpected public.upgrade probe output: %q", out)
	}
}

func (defaultProbe) InspectSchemaHistory(projDir string) (SchemaHistory, error) {
	out, err := runQuery(projDir, 10*time.Second,
		`SELECT to_regclass('db.migration') IS NOT NULL,
                        EXISTS (
                          SELECT 1
                            FROM pg_class AS c
                            JOIN pg_namespace AS n ON n.oid = c.relnamespace
                           WHERE n.nspname = 'public'
                             AND c.relkind IN ('r', 'p')
                        )`)
	if err != nil {
		return SchemaHistory{}, err
	}
	hasMigrationTable, hasAppSchema, err := parseTwoBools(out)
	if err != nil {
		return SchemaHistory{}, err
	}
	history := SchemaHistory{HasApplicationSchema: hasAppSchema}
	if !hasMigrationTable {
		return history, nil
	}
	out, err = runQuery(projDir, 10*time.Second,
		`SELECT count(*), COALESCE(string_agg(version::text, ',' ORDER BY version), '') FROM db.migration`)
	if err != nil {
		return SchemaHistory{}, err
	}
	return parseSchemaHistoryCounts(out, history)
}

func parseTwoBools(out string) (bool, bool, error) {
	parts := strings.Split(strings.TrimSpace(out), "|")
	if len(parts) != 2 {
		return false, false, unclassifiableResponse("unexpected schema probe output: %q", out)
	}
	first, err := parseBoolToken(parts[0])
	if err != nil {
		return false, false, err
	}
	second, err := parseBoolToken(parts[1])
	if err != nil {
		return false, false, err
	}
	return first, second, nil
}

func parseBoolToken(token string) (bool, error) {
	switch token {
	case "t":
		return true, nil
	case "f":
		return false, nil
	default:
		return false, unclassifiableResponse("unexpected boolean probe token %q", token)
	}
}

func parseSchemaHistoryCounts(out string, history SchemaHistory) (SchemaHistory, error) {
	parts := strings.Split(strings.TrimSpace(out), "|")
	if len(parts) != 2 {
		return SchemaHistory{}, unclassifiableResponse("unexpected migration history output: %q", out)
	}
	count, err := strconv.ParseInt(parts[0], 10, 64)
	if err != nil {
		return SchemaHistory{}, unclassifiableResponse("parse migration count %q: %v", parts[0], err)
	}
	history.AppliedMigrations = count
	if count == 0 {
		if parts[1] != "" {
			return SchemaHistory{}, unclassifiableResponse("unexpected migration versions for empty history: %q", parts[1])
		}
		return history, nil
	}
	if parts[1] == "" {
		return SchemaHistory{}, unclassifiableResponse("missing migration versions for count %d", count)
	}
	history.AppliedVersions = strings.Split(parts[1], ",")
	if int64(len(history.AppliedVersions)) != count {
		return SchemaHistory{}, unclassifiableResponse("migration count %d does not match %d versions", count, len(history.AppliedVersions))
	}
	for _, version := range history.AppliedVersions {
		if len(version) != 14 {
			return SchemaHistory{}, unclassifiableResponse("unexpected migration version %q", version)
		}
		if _, err := strconv.ParseInt(version, 10, 64); err != nil {
			return SchemaHistory{}, unclassifiableResponse("parse migration version %q: %v", version, err)
		}
	}
	return history, nil
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
	return parseScheduledUpgradeRow(out)
}

func parseScheduledUpgradeRow(out string) (*ScheduledRow, error) {
	line := strings.TrimSpace(out)
	if line == "" {
		return nil, nil
	}
	parts := strings.Split(line, "|")
	if len(parts) != 3 {
		return nil, unclassifiableResponse("unexpected scheduled-upgrade row: %q", line)
	}
	id, err := strconv.ParseInt(parts[0], 10, 64)
	if err != nil {
		return nil, unclassifiableResponse("parse id from %q: %v", parts[0], err)
	}
	if id <= 0 || strings.TrimSpace(parts[1]) == "" || strings.TrimSpace(parts[2]) == "" {
		return nil, unclassifiableResponse("invalid scheduled-upgrade row: %q", line)
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
// by the restore-broke terminals —
//   - rollback() degraded terminal (LabelFailedRollbackIncomplete)
//   - rollback() git-restore ABORT terminal (LabelFailedAbort)
//   - recoveryRollback pair-terminal (two rollback crash-deaths, LabelFailedRollbackIncomplete)
//
// One explicitly marked exception is NOT restore-broke, and the SCHEMA marks it
// (STATBUS-347): restoreAndFinalize sets rollback_finish_pending_at after a
// healthy restore, BEFORE it lifts SQL/HTTP, then removes the marker and writes
// rolled_back. A crash or marker-unlink failure in that handoff leaves
// failed+backup_path+pending. The lift commits recovery to cleanup-only completion,
// so snapshot replay is no longer a valid transition. The probe excludes it IN THE
// QUERY; no text is parsed. The daemon retries marker cleanup and the final UPDATE only.
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
		    AND rollback_finish_pending_at IS NULL
		  ORDER BY id DESC`)
	if err != nil {
		return 0, "", false, err
	}
	return parseReattemptableRestoreRows(out)
}

func parseReattemptableRestoreRows(out string) (int64, string, bool, error) {
	var firstID int64
	var firstPath string
	for _, line := range strings.Split(strings.TrimSpace(out), "\n") {
		if strings.TrimSpace(line) == "" {
			continue
		}
		parts := strings.SplitN(line, "|", 2)
		if len(parts) < 2 {
			return 0, "", false, unclassifiableResponse("unexpected reattemptable-restore row: %q", line)
		}
		id, err := strconv.ParseInt(strings.TrimSpace(parts[0]), 10, 64)
		if err != nil {
			return 0, "", false, unclassifiableResponse("parse id from %q: %v", parts[0], err)
		}
		if id <= 0 {
			return 0, "", false, unclassifiableResponse("invalid reattemptable-restore id: %d", id)
		}
		backupPath := strings.TrimSpace(parts[1])
		if backupPath == "" {
			return 0, "", false, unclassifiableResponse("empty backup path in reattemptable-restore row: %q", line)
		}
		if firstPath == "" {
			firstID, firstPath = id, backupPath
		}
	}
	return firstID, firstPath, firstPath != "", nil
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
	cmd, buildErr := migrate.CommandContext(ctx, projDir, psqlPath, args...)
	if buildErr != nil {
		return "", fmt.Errorf("construct psql query: %w", buildErr)
	}
	cmd.Env = env
	out, err := cmd.CombinedOutput()
	if err != nil {
		if connectionUnavailable(string(out)) {
			return "", fmt.Errorf("psql: %w: %v (%s)", ErrDatabaseUnavailable, err, strings.TrimSpace(string(out)))
		}
		return "", fmt.Errorf("psql: %w (%s)", err, strings.TrimSpace(string(out)))
	}
	return string(out), nil
}

// Connection-specific psql/docker diagnostics prove the DB was not reachable.
// A subprocess timeout on its own does not prove this (the SQL could be slow).
// Unknown diagnostics, including SQL permissions and incompatible schema, stay
// ordinary errors and must stop install before it changes anything.
func connectionUnavailable(output string) bool {
	lower := strings.ToLower(output)
	// A server-side SQL error can contain arbitrary user-controlled text,
	// including the words "connection refused". It proves the DB answered.
	if strings.Contains(lower, "error:") && !strings.Contains(lower, "psql: error:") {
		return false
	}
	for _, marker := range []string{
		"connection refused", "connection timed out", "connection to server timed out", "timeout expired",
		"could not connect to server", "no route to host",
		"is the server running locally and accepting connections",
		"is the server running on that host and accepting tcp/ip connections",
		"service \"db\" is not running", "container is not running",
	} {
		if strings.Contains(lower, marker) {
			return true
		}
	}
	return false
}

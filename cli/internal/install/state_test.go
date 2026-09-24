package install

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/upgrade"
)

// fakeProbe is a table-driven Probe for DetectWith tests. Each field captures
// what the corresponding probe method should return; unset fields yield the
// zero value (nil, false, etc.), which matches the "missing" state the ladder
// expects at each step.
type fakeProbe struct {
	files           map[string]bool
	flag            *upgrade.UpgradeFlag
	flagAlive       bool
	flagErr         error
	dbReachable     bool
	dbErr           error
	hasUpgradeTable bool
	hasUpgradeErr   error
	history         SchemaHistory
	historyErr      error
	scheduledRow    *ScheduledRow
	scheduledErr    error
	reattemptRowID  int64
	reattemptBackup string
	reattemptFound  bool
	reattemptErr    error
}

func (p *fakeProbe) FileExists(path string) (bool, error) { return p.files[path], nil }
func (p *fakeProbe) ReadFlag(string) (*upgrade.UpgradeFlag, bool, error) {
	return p.flag, p.flagAlive, p.flagErr
}
func (p *fakeProbe) DBReachable(string) (bool, error)     { return p.dbReachable, p.dbErr }
func (p *fakeProbe) HasUpgradeTable(string) (bool, error) { return p.hasUpgradeTable, p.hasUpgradeErr }
func (p *fakeProbe) InspectSchemaHistory(string) (SchemaHistory, error) {
	return p.history, p.historyErr
}
func (p *fakeProbe) QueryScheduledUpgrade(string) (*ScheduledRow, error) {
	return p.scheduledRow, p.scheduledErr
}
func (p *fakeProbe) QueryReattemptableRestore(string) (int64, string, bool, error) {
	return p.reattemptRowID, p.reattemptBackup, p.reattemptFound, p.reattemptErr
}

func TestDetectionMalformedOutputsAndAvailabilityEvidence(t *testing.T) {
	for _, out := range []string{"junk", "x|/backup", "1|", "1|/backup\njunk", "-1|/backup"} {
		t.Run("restore "+out, func(t *testing.T) {
			if _, _, _, err := parseReattemptableRestoreRows(out); err == nil {
				t.Fatalf("accepted malformed restore output %q", out)
			}
		})
	}
	for _, out := range []string{"junk", "0|sha|sha", "1||sha", "1|sha|", "1|sha|sha|extra"} {
		if _, err := parseScheduledUpgradeRow(out); err == nil {
			t.Errorf("accepted malformed scheduled output %q", out)
		}
	}
	for _, tc := range []struct {
		diagnostic  string
		unavailable bool
	}{
		{"psql: connection to server at localhost failed: Connection refused", true},
		{"psql: connection to server timed out", true},
		{"service \"db\" is not running", true},
		{"ERROR: permission denied for table upgrade", false},
		{"ERROR: relation public.upgrade does not exist", false},
		{"construct psql query failed", false},
		{"context deadline exceeded", false},
	} {
		if got := connectionUnavailable(tc.diagnostic); got != tc.unavailable {
			t.Errorf("connectionUnavailable(%q) = %v, want %v", tc.diagnostic, got, tc.unavailable)
		}
	}
}

func TestDetectWith(t *testing.T) {
	const projDir = "/proj"
	cfgPath := filepath.Join(projDir, ".env.config")
	credPath := filepath.Join(projDir, ".env.credentials")

	cases := []struct {
		name        string
		probe       fakeProbe
		wantState   State
		wantErr     bool
		checkDetail func(*testing.T, *Detail)
	}{
		{
			name:      "fresh: no .env.config",
			probe:     fakeProbe{},
			wantState: StateFresh,
			checkDetail: func(t *testing.T, d *Detail) {
				if d.TargetVersion != "v2026.04.0-test" {
					t.Errorf("TargetVersion = %q, want binary version", d.TargetVersion)
				}
			},
		},
		{
			name: "live upgrade: flag with flock held",
			probe: fakeProbe{
				files:     map[string]bool{cfgPath: true, credPath: true},
				flag:      &upgrade.UpgradeFlag{ID: 42, CommitTags: []string{"v2026.04.0"}},
				flagAlive: true, // flock held → live
			},
			wantState: StateLiveUpgrade,
			checkDetail: func(t *testing.T, d *Detail) {
				if d.Flag == nil || d.Flag.ID != 42 {
					t.Errorf("expected flag with ID 42, got %+v", d.Flag)
				}
			},
		},
		{
			name: "crashed upgrade: flag with flock free",
			probe: fakeProbe{
				files:     map[string]bool{cfgPath: true, credPath: true},
				flag:      &upgrade.UpgradeFlag{ID: 1, CommitTags: []string{"v2026.04.0"}},
				flagAlive: false,
			},
			wantState: StateCrashedUpgrade,
		},
		{
			name: "ghost flag: flock free → crashed (not live)",
			probe: fakeProbe{
				files:     map[string]bool{cfgPath: true, credPath: true},
				flag:      &upgrade.UpgradeFlag{CommitSHA: "abc1234f0000000000000000000000000000abcd"},
				flagAlive: false, // flock free — ghost flag from completed upgrade
			},
			wantState: StateCrashedUpgrade,
			checkDetail: func(t *testing.T, d *Detail) {
				if d.Flag == nil || d.Flag.CommitSHA != "abc1234f0000000000000000000000000000abcd" {
					t.Errorf("expected flag with the ghost CommitSHA, got %+v", d.Flag)
				}
			},
		},
		{
			name: "half-configured: .env.config present, .env.credentials absent",
			probe: fakeProbe{
				files: map[string]bool{cfgPath: true},
			},
			wantState: StateHalfConfigured,
		},
		{
			name: "db unreachable: configured but DB down",
			probe: fakeProbe{
				files:       map[string]bool{cfgPath: true, credPath: true},
				dbReachable: false,
			},
			wantState: StateDBUnreachable,
		},
		{
			name: "legacy: pre-1.0 DB, application schema without migration history",
			probe: fakeProbe{
				files:           map[string]bool{cfgPath: true, credPath: true},
				dbReachable:     true,
				hasUpgradeTable: false,
				history:         SchemaHistory{HasApplicationSchema: true},
			},
			wantState: StateLegacyNoUpgradeTable,
		},
		{
			name: "legacy: pre-1.0 DB migrated by an old release",
			probe: fakeProbe{
				files:           map[string]bool{cfgPath: true, credPath: true},
				dbReachable:     true,
				hasUpgradeTable: false,
				history: SchemaHistory{
					AppliedMigrations:    2,
					AppliedVersions:      []string{"20240128000000", "20240201000000"},
					HasApplicationSchema: true,
				},
			},
			wantState: StateLegacyNoUpgradeTable,
		},
		{
			name: "legacy: old migrations applied today remain pre-1.0",
			probe: fakeProbe{
				files:           map[string]bool{cfgPath: true, credPath: true},
				dbReachable:     true,
				hasUpgradeTable: false,
				history: SchemaHistory{
					AppliedMigrations:    2,
					AppliedVersions:      []string{"20240128000000", "20260310000000"},
					HasApplicationSchema: true,
				},
			},
			wantState: StateLegacyNoUpgradeTable,
		},
		{
			name: "legacy: enterprise-only schema without migration history",
			probe: fakeProbe{
				files:           map[string]bool{cfgPath: true, credPath: true},
				dbReachable:     true,
				hasUpgradeTable: false,
				history:         SchemaHistory{HasApplicationSchema: true},
			},
			wantState: StateLegacyNoUpgradeTable,
		},
		{
			name: "fresh-db-incomplete: init-db.sh only, install stopped before Seed",
			probe: fakeProbe{
				files:           map[string]bool{cfgPath: true, credPath: true},
				dbReachable:     true,
				hasUpgradeTable: false,
				history:         SchemaHistory{},
			},
			wantState: StateFreshDBIncomplete,
		},
		{
			name: "fresh-db-incomplete: interrupted run has only post-upgrade-era versions",
			probe: fakeProbe{
				files:           map[string]bool{cfgPath: true, credPath: true},
				dbReachable:     true,
				hasUpgradeTable: false,
				history: SchemaHistory{
					AppliedMigrations:    2,
					AppliedVersions:      []string{"20260312000000", "20260401000000"},
					HasApplicationSchema: true,
				},
			},
			wantState: StateFreshDBIncomplete,
		},
		{
			name: "migrated DB with public.upgrade never consults schema history",
			probe: fakeProbe{
				files:           map[string]bool{cfgPath: true, credPath: true},
				dbReachable:     true,
				hasUpgradeTable: true,
				historyErr:      errors.New("must not be called"),
			},
			wantState: StateNothingScheduled,
		},
		{
			name: "schema history probe error surfaces",
			probe: fakeProbe{
				files:           map[string]bool{cfgPath: true, credPath: true},
				dbReachable:     true,
				hasUpgradeTable: false,
				historyErr:      errors.New("psql exploded"),
			},
			wantErr: true,
		},
		{
			name: "scheduled upgrade: row present",
			probe: fakeProbe{
				files:           map[string]bool{cfgPath: true, credPath: true},
				dbReachable:     true,
				hasUpgradeTable: true,
				scheduledRow: &ScheduledRow{
					ID:        7,
					CommitSHA: "abcdef0000000000000000000000000000000001",
					Version:   "v2026.05.0-rc.1",
				},
			},
			wantState: StateScheduledUpgrade,
			checkDetail: func(t *testing.T, d *Detail) {
				if d.ScheduledRowID != 7 {
					t.Errorf("ScheduledRowID = %d, want 7", d.ScheduledRowID)
				}
				if d.TargetCommitSHA != "abcdef0000000000000000000000000000000001" {
					t.Errorf("TargetCommitSHA = %q", d.TargetCommitSHA)
				}
				if d.TargetVersion != "v2026.05.0-rc.1" {
					t.Errorf("TargetVersion = %q, want scheduled row's version", d.TargetVersion)
				}
				if d.TargetDisplayName != "v2026.05.0-rc.1" {
					t.Errorf("TargetDisplayName = %q", d.TargetDisplayName)
				}
			},
		},
		{
			name: "nothing scheduled: configured, no row",
			probe: fakeProbe{
				files:           map[string]bool{cfgPath: true, credPath: true},
				dbReachable:     true,
				hasUpgradeTable: true,
				scheduledRow:    nil,
			},
			wantState: StateNothingScheduled,
		},
		{
			// STATBUS-111: no scheduled row, but a restore-broke row (failed +
			// retained backup_path) → re-attemptable, not a dead-end.
			name: "restore re-attemptable: failed row with retained backup_path",
			probe: fakeProbe{
				files:           map[string]bool{cfgPath: true, credPath: true},
				dbReachable:     true,
				hasUpgradeTable: true,
				scheduledRow:    nil,
				reattemptFound:  true,
				reattemptRowID:  9,
				reattemptBackup: "/backup/pre-upgrade-active",
			},
			wantState: StateRestoreReattemptable,
			checkDetail: func(t *testing.T, d *Detail) {
				if d.ReattemptRowID != 9 {
					t.Errorf("ReattemptRowID = %d, want 9", d.ReattemptRowID)
				}
				if d.ReattemptBackupPath != "/backup/pre-upgrade-active" {
					t.Errorf("ReattemptBackupPath = %q", d.ReattemptBackupPath)
				}
			},
		},
		{
			// A scheduled upgrade WINS over a lingering restore-broke row (probe
			// order: scheduled before reattemptable).
			name: "scheduled wins over a reattemptable restore-broke row",
			probe: fakeProbe{
				files:           map[string]bool{cfgPath: true, credPath: true},
				dbReachable:     true,
				hasUpgradeTable: true,
				scheduledRow:    &ScheduledRow{ID: 12, CommitSHA: "beef", Version: "v9"},
				reattemptFound:  true,
				reattemptRowID:  9,
				reattemptBackup: "/backup/x",
			},
			wantState: StateScheduledUpgrade,
		},
		{
			name: "flag-read error propagates",
			probe: fakeProbe{
				files:   map[string]bool{cfgPath: true, credPath: true},
				flagErr: errors.New("boom"),
			},
			wantErr: true,
		},
		{
			name: "upgrade-table probe error propagates",
			probe: fakeProbe{
				files:         map[string]bool{cfgPath: true, credPath: true},
				dbReachable:   true,
				hasUpgradeErr: errors.New("boom"),
			},
			wantErr: true,
		},
		{
			name: "scheduled-row probe error propagates",
			probe: fakeProbe{
				files:           map[string]bool{cfgPath: true, credPath: true},
				dbReachable:     true,
				hasUpgradeTable: true,
				scheduledErr:    errors.New("boom"),
			},
			wantErr: true,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			state, detail, err := DetectWith(projDir, "v2026.04.0-test", &tc.probe)
			if tc.wantErr {
				if err == nil {
					t.Fatalf("expected error, got nil (state=%s)", state)
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if state != tc.wantState {
				t.Errorf("state = %s, want %s", state, tc.wantState)
			}
			if detail == nil {
				t.Fatal("detail unexpectedly nil")
			}
			if detail.CurrentVersion != "v2026.04.0-test" {
				t.Errorf("CurrentVersion = %q, want v2026.04.0-test", detail.CurrentVersion)
			}
			if tc.checkDetail != nil {
				tc.checkDetail(t, detail)
			}
		})
	}
}

func TestStateString(t *testing.T) {
	cases := []struct {
		state State
		want  string
	}{
		{StateFresh, "fresh"},
		{StateLiveUpgrade, "live-upgrade"},
		{StateCrashedUpgrade, "crashed-upgrade"},
		{StateHalfConfigured, "half-configured"},
		{StateDBUnreachable, "db-unreachable"},
		{StateLegacyNoUpgradeTable, "legacy-no-upgrade-table"},
		{StateScheduledUpgrade, "scheduled-upgrade"},
		{StateNothingScheduled, "nothing-scheduled"},
		{StateFreshDBIncomplete, "fresh-db-incomplete"},
		{State(99), "unknown(99)"},
	}
	for _, c := range cases {
		if got := c.state.String(); got != c.want {
			t.Errorf("State(%d).String() = %q, want %q", c.state, got, c.want)
		}
	}
}

// TestReattemptableRestoreQueryExcludesPendingByColumn pins STATBUS-347: the
// cleanup-only rollback row is excluded IN SQL on rollback_finish_pending_at,
// never by parsing `error` text in Go. A reader that has to recognise a prefix
// is a reader that can be fooled by a typo; the column cannot.
func TestReattemptableRestoreQueryExcludesPendingByColumn(t *testing.T) {
	src, err := os.ReadFile("state.go")
	if err != nil {
		t.Fatal(err)
	}
	body := extractFuncSource(t, string(src), "func (defaultProbe) QueryReattemptableRestore(")
	if !strings.Contains(body, "rollback_finish_pending_at IS NULL") {
		t.Fatal("QueryReattemptableRestore no longer excludes rollback_finish_pending_at rows in SQL; a healthy restored box could be replayed")
	}
	if strings.Contains(string(src), "IsRollbackFinishPendingError") {
		t.Fatal("state.go still classifies restore-reattemptable rows by error-text prefix")
	}
}

func TestParseReattemptableRestoreRowsFirstRowWins(t *testing.T) {
	out := "12|/backups/restore-broke-newest\n9|/backups/restore-broke-older"
	id, backupPath, found, err := parseReattemptableRestoreRows(out)
	if err != nil {
		t.Fatalf("parseReattemptableRestoreRows: %v", err)
	}
	if !found || id != 12 || backupPath != "/backups/restore-broke-newest" {
		t.Fatalf("got id=%d backup=%q found=%t; want the newest restore-broke row", id, backupPath, found)
	}
}

func TestParseReattemptableRestoreRowsMalformedIsAnError(t *testing.T) {
	if _, _, _, err := parseReattemptableRestoreRows("12"); err == nil {
		t.Fatal("a row without the backup_path column parsed as a valid restore target")
	}
}

// TestDetectFreshDefaultProbe exercises the default probe against an empty
// directory — the only ladder step that doesn't require a running database or
// subprocess is the .env.config check, and it must return StateFresh.
func TestDetectFreshDefaultProbe(t *testing.T) {
	state, detail, err := Detect(t.TempDir(), "v0.0.0-test")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if state != StateFresh {
		t.Errorf("state = %s, want %s", state, StateFresh)
	}
	if detail.CurrentVersion != "v0.0.0-test" || detail.TargetVersion != "v0.0.0-test" {
		t.Errorf("version fields = current=%q target=%q, want both v0.0.0-test",
			detail.CurrentVersion, detail.TargetVersion)
	}
}

// extractFuncSource returns the text of the function whose signature starts
// with sig, up to the next top-level func. Mirrors the source-inspection
// helpers in the upgrade package.
func extractFuncSource(t *testing.T, src, sig string) string {
	t.Helper()
	start := strings.Index(src, sig)
	if start < 0 {
		t.Fatalf("function %q not found", sig)
	}
	rest := src[start+len(sig):]
	end := strings.Index(rest, "\nfunc ")
	if end < 0 {
		return src[start:]
	}
	return src[start : start+len(sig)+end]
}

func TestParseSchemaHistory(t *testing.T) {
	has, app, err := parseTwoBools("t|f\n")
	if err != nil || !has || app {
		t.Fatalf("parseTwoBools = %v %v %v", has, app, err)
	}
	for _, input := range []string{"junk|junk", "t|no", "yes|f"} {
		if _, _, err := parseTwoBools(input); err == nil {
			t.Errorf("parseTwoBools(%q) unexpectedly succeeded", input)
		}
	}
	h, err := parseSchemaHistoryCounts("3|20240101000000,20240202000000,20260310000000\n", SchemaHistory{HasApplicationSchema: true})
	if err != nil {
		t.Fatal(err)
	}
	if h.AppliedMigrations != 3 || len(h.AppliedVersions) != 3 || h.AppliedVersions[0] != "20240101000000" || !h.HasApplicationSchema {
		t.Fatalf("parsed %+v", h)
	}
	h, err = parseSchemaHistoryCounts("0|", SchemaHistory{})
	if err != nil || len(h.AppliedVersions) != 0 {
		t.Fatalf("empty history parsed %+v %v", h, err)
	}
	for _, input := range []string{"garbage", "2|20240101000000", "1|junk", "0|20240101000000"} {
		if _, err := parseSchemaHistoryCounts(input, SchemaHistory{}); err == nil {
			t.Errorf("parseSchemaHistoryCounts(%q) unexpectedly succeeded", input)
		}
	}
}

func TestParseUpgradeTableOutput(t *testing.T) {
	for _, tc := range []struct {
		input string
		want  bool
	}{
		{input: "1\n", want: true},
		{input: "\n", want: false},
	} {
		got, err := parseUpgradeTableOutput(tc.input)
		if err != nil || got != tc.want {
			t.Errorf("parseUpgradeTableOutput(%q) = %v, %v; want %v, nil", tc.input, got, err, tc.want)
		}
	}
	for _, input := range []string{"0", "junk", "t"} {
		if _, err := parseUpgradeTableOutput(input); err == nil {
			t.Errorf("parseUpgradeTableOutput(%q) unexpectedly succeeded", input)
		}
	}
}

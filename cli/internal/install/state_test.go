package install

import (
	"errors"
	"path/filepath"
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
	hasUpgradeTable bool
	hasUpgradeErr   error
	scheduledRow    *ScheduledRow
	scheduledErr    error
	reattemptRowID  int64
	reattemptBackup string
	reattemptFound  bool
	reattemptErr    error
}

func (p *fakeProbe) FileExists(path string) bool { return p.files[path] }
func (p *fakeProbe) ReadFlag(string) (*upgrade.UpgradeFlag, bool, error) {
	return p.flag, p.flagAlive, p.flagErr
}
func (p *fakeProbe) DBReachable(string) bool              { return p.dbReachable }
func (p *fakeProbe) HasUpgradeTable(string) (bool, error) { return p.hasUpgradeTable, p.hasUpgradeErr }
func (p *fakeProbe) QueryScheduledUpgrade(string) (*ScheduledRow, error) {
	return p.scheduledRow, p.scheduledErr
}
func (p *fakeProbe) QueryReattemptableRestore(string) (int64, string, bool, error) {
	return p.reattemptRowID, p.reattemptBackup, p.reattemptFound, p.reattemptErr
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
			name: "legacy: DB up, no public.upgrade table",
			probe: fakeProbe{
				files:           map[string]bool{cfgPath: true, credPath: true},
				dbReachable:     true,
				hasUpgradeTable: false,
			},
			wantState: StateLegacyNoUpgradeTable,
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
		{State(99), "unknown(99)"},
	}
	for _, c := range cases {
		if got := c.state.String(); got != c.want {
			t.Errorf("State(%d).String() = %q, want %q", c.state, got, c.want)
		}
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

package monitor

import (
	"encoding/json"
	"os"
	"regexp"
	"strings"
	"testing"
	"time"
)

func sampleReading(status Status, now time.Time) Reading {
	return Reading{
		Status:    status,
		CheckedAt: now,
		Version:   "v2026.10.5",
		Checks:    []Check{{Name: CheckServices, Status: status, Detail: "5/5 running"}},
	}
}

func TestWriteReadingIsAtomicAndReadable(t *testing.T) {
	projectDir := t.TempDir()
	now := time.Date(2026, 10, 30, 12, 0, 0, 0, time.UTC)
	if err := WriteReading(projectDir, sampleReading(StatusOK, now)); err != nil {
		t.Fatal(err)
	}
	reading, err := ReadCache(projectDir)
	if err != nil {
		t.Fatal(err)
	}
	if reading.Status != StatusOK || reading.Version != "v2026.10.5" || !reading.CheckedAt.Equal(now) {
		t.Fatalf("reading = %+v", reading)
	}
	if len(reading.Checks) != 1 || reading.Checks[0].Name != CheckServices {
		t.Fatalf("checks = %+v", reading.Checks)
	}
	status, err := os.ReadFile(StatusPath(projectDir))
	if err != nil {
		t.Fatal(err)
	}
	if ParseStatus(string(status)) != StatusOK {
		t.Fatalf("status file = %q", status)
	}
	// No temporary files survive the rename.
	entries, err := os.ReadDir(CacheDir(projectDir))
	if err != nil {
		t.Fatal(err)
	}
	for _, entry := range entries {
		if strings.HasPrefix(entry.Name(), ".") {
			t.Errorf("temporary file left behind: %s", entry.Name())
		}
	}
}

func TestCriticalMarkerFollowsTheReading(t *testing.T) {
	projectDir := t.TempDir()
	now := time.Now().UTC()
	for _, tc := range []struct {
		status      Status
		wantMarker  bool
		description string
	}{
		{StatusOK, false, "ok"},
		{StatusWarning, false, "warning"},
		{StatusUpgrading, false, "upgrading"},
		{StatusCritical, true, "critical"},
		{StatusUnknown, true, "unknown"},
	} {
		t.Run(tc.description, func(t *testing.T) {
			if err := WriteReading(projectDir, sampleReading(tc.status, now)); err != nil {
				t.Fatal(err)
			}
			_, err := os.Stat(CriticalMarkerPath(projectDir))
			if got := err == nil; got != tc.wantMarker {
				t.Fatalf("marker exists = %t, want %t (err=%v)", got, tc.wantMarker, err)
			}
		})
	}
}

func TestReadCacheMissingIsNotExist(t *testing.T) {
	_, err := ReadCache(t.TempDir())
	if !os.IsNotExist(err) {
		t.Fatalf("err = %v, want not exist", err)
	}
}

func TestStaleAfterThreeMinutesAndAsStaleIsUnknown(t *testing.T) {
	now := time.Date(2026, 10, 30, 12, 0, 0, 0, time.UTC)
	fresh := sampleReading(StatusOK, now.Add(-3*time.Minute))
	if Stale(fresh, now) {
		t.Fatal("exactly three minutes old must still be fresh")
	}
	stale := sampleReading(StatusOK, now.Add(-3*time.Minute-time.Second))
	if !Stale(stale, now) {
		t.Fatal("older than three minutes must be stale")
	}
	if AsStale(stale).Status != StatusUnknown {
		t.Fatalf("stale reading status = %s, want unknown", AsStale(stale).Status)
	}
	if AsStale(stale).CheckedAt != stale.CheckedAt {
		t.Fatal("stale conversion must keep checked_at")
	}
}

func TestUpgradingReadingKeepsChecksAndTimeIsFresh(t *testing.T) {
	now := time.Date(2026, 10, 30, 12, 0, 0, 0, time.UTC)
	previous := sampleReading(StatusCritical, now.Add(-time.Minute))
	reading := UpgradingReading(previous, "v2026.10.6", now)
	if reading.Status != StatusUpgrading {
		t.Fatalf("status = %s", reading.Status)
	}
	if len(reading.Checks) != 1 || reading.Checks[0].Name != CheckServices {
		t.Fatalf("checks = %+v", reading.Checks)
	}
	if reading.Version != "v2026.10.6" || !reading.CheckedAt.Equal(now) {
		t.Fatalf("reading = %+v", reading)
	}
}

func TestPublicJSONHasOnlyTheAllowedFieldsAndFixedPhraseDetails(t *testing.T) {
	now := time.Date(2026, 10, 30, 12, 0, 0, 0, time.UTC)
	reading := Run(t.Context(), fixtureProbes(now))
	data, err := json.Marshal(reading)
	if err != nil {
		t.Fatal(err)
	}
	var top map[string]json.RawMessage
	if err := json.Unmarshal(data, &top); err != nil {
		t.Fatal(err)
	}
	allowedTop := map[string]bool{"status": true, "checked_at": true, "version": true, "checks": true}
	for key := range top {
		if !allowedTop[key] {
			t.Errorf("public JSON exposes unexpected top-level field %q", key)
		}
	}
	for _, key := range []string{"status", "checked_at", "version", "checks"} {
		if _, ok := top[key]; !ok {
			t.Errorf("public JSON is missing %q", key)
		}
	}

	var checks []map[string]json.RawMessage
	if err := json.Unmarshal(top["checks"], &checks); err != nil {
		t.Fatal(err)
	}
	allowedCheck := map[string]bool{"name": true, "status": true, "detail": true}
	for _, raw := range checks {
		for key := range raw {
			if !allowedCheck[key] {
				t.Errorf("public JSON exposes unexpected check field %q", key)
			}
		}
	}

	detailPhrases := []*regexpPhrase{
		{name: CheckServices, pattern: `^[0-9]+/[0-9]+ running(, database not healthy)?$`},
		{name: CheckAPI, pattern: `^API (ready|not ready)$`},
		{name: CheckSite, pattern: `^(site answered|site did not answer|certificate [0-9]+ days left|certificate expires in [0-9]+ days|not measured)$`},
		{name: CheckDisk, pattern: `^[0-9]+ GB free$`},
		{name: CheckBackups, pattern: `^(newest backup [0-9]+h ago|no backups yet|backups disabled|not measured)$`},
		{name: CheckUpgrader, pattern: `^(upgrader active|upgrader inactive|upgrade parked|upgrade failed|upgrader not applicable|not measured)$`},
		{name: CheckWorker, pattern: `^[0-9]+ failed in the last hour, [0-9]+ stuck$`},
	}
	for _, check := range reading.Checks {
		var ok bool
		for _, phrase := range detailPhrases {
			if phrase.name == check.Name {
				ok = phrase.matches(check.Detail)
				break
			}
		}
		if !ok {
			t.Errorf("%s detail %q is not a fixed phrase with numbers", check.Name, check.Detail)
		}
	}
}

// regexpPhrase keeps the allowed-detail table readable without hiding the
// regular expressions.
type regexpPhrase struct {
	name    string
	pattern string
}

func (p regexpPhrase) matches(detail string) bool {
	return regexp.MustCompile(p.pattern).MatchString(detail)
}

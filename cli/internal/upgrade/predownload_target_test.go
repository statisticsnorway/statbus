package upgrade

import "testing"

// TestSelectNewestDownloadCandidate locks down the version-targeting decision
// for the background image pre-download (STATBUS-047 item A). The defect this
// guards against: the daemon used to pre-download the OLDEST discovered rows
// (`ORDER BY discovered_at LIMIT 3`) and never re-checked them against the
// installed version, so after an upgrade it ground through ancient releases the
// box would never install. The replacement picks the single newest release
// strictly newer than installed — these cases assert exactly that.
func TestSelectNewestDownloadCandidate(t *testing.T) {
	// mk builds a candidate slice from (version, sha) pairs.
	mk := func(pairs ...string) []downloadCandidate {
		var cs []downloadCandidate
		for i := 0; i+1 < len(pairs); i += 2 {
			cs = append(cs, downloadCandidate{Version: pairs[i], CommitSHA: pairs[i+1]})
		}
		return cs
	}

	tests := []struct {
		name       string
		installed  string
		candidates []downloadCandidate
		wantOK     bool
		wantVer    string
		wantSHA    string
	}{
		{
			name:       "picks newest strictly newer than installed",
			installed:  "v2026.05.6-rc.01",
			candidates: mk("v2026.05.1", "aaaaaaaa", "v2026.06.0-rc.02", "bbbbbbbb", "v2026.05.6-rc.02", "cccccccc"),
			wantOK:     true,
			wantVer:    "v2026.06.0-rc.02",
			wantSHA:    "bbbbbbbb",
		},
		{
			name:       "refuses everything older than installed",
			installed:  "v2026.06.0",
			candidates: mk("v2026.05.1", "aaaaaaaa", "v2026.05.6-rc.01", "bbbbbbbb"),
			wantOK:     false,
		},
		{
			name:       "none when already at latest (equal to installed)",
			installed:  "v2026.06.0-rc.02",
			candidates: mk("v2026.06.0-rc.02", "aaaaaaaa"),
			wantOK:     false,
		},
		{
			name:       "stable release supersedes its own prereleases",
			installed:  "v2026.06.0-rc.02",
			candidates: mk("v2026.06.0", "aaaaaaaa"),
			wantOK:     true,
			wantVer:    "v2026.06.0",
			wantSHA:    "aaaaaaaa",
		},
		{
			name:       "a prerelease is NOT newer than its stable release",
			installed:  "v2026.06.0",
			candidates: mk("v2026.06.0-rc.99", "aaaaaaaa"),
			wantOK:     false,
		},
		{
			name:       "ignores non-CalVer candidates, picks the valid newer one",
			installed:  "v2026.05.0",
			candidates: mk("deadbeef", "aaaaaaaa", "v2026.06.0", "bbbbbbbb", "not-a-version", "cccccccc"),
			wantOK:     true,
			wantVer:    "v2026.06.0",
			wantSHA:    "bbbbbbbb",
		},
		{
			name:       "all candidates non-CalVer yields none",
			installed:  "v2026.05.0",
			candidates: mk("deadbeef", "aaaaaaaa", "abc12345", "bbbbbbbb"),
			wantOK:     false,
		},
		{
			name:       "non-CalVer installed version yields none (never guess an ordering)",
			installed:  "dev",
			candidates: mk("v2026.06.0", "aaaaaaaa"),
			wantOK:     false,
		},
		{
			name:       "empty candidate set yields none",
			installed:  "v2026.05.0",
			candidates: nil,
			wantOK:     false,
		},
		{
			name:       "picks the newest among several all newer (input ascending)",
			installed:  "v2026.01.0",
			candidates: mk("v2026.03.0", "aaaaaaaa", "v2026.02.0", "bbbbbbbb", "v2026.05.1", "cccccccc"),
			wantOK:     true,
			wantVer:    "v2026.05.1",
			wantSHA:    "cccccccc",
		},
		{
			name:       "order independence (input descending) — still newest",
			installed:  "v2026.01.0",
			candidates: mk("v2026.05.1", "cccccccc", "v2026.02.0", "bbbbbbbb", "v2026.03.0", "aaaaaaaa"),
			wantOK:     true,
			wantVer:    "v2026.05.1",
			wantSHA:    "cccccccc",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, ok := selectNewestDownloadCandidate(tt.installed, tt.candidates)
			if ok != tt.wantOK {
				t.Fatalf("ok = %v, want %v (got %+v)", ok, tt.wantOK, got)
			}
			if !tt.wantOK {
				return
			}
			if got.Version != tt.wantVer {
				t.Errorf("Version = %q, want %q", got.Version, tt.wantVer)
			}
			if got.CommitSHA != tt.wantSHA {
				t.Errorf("CommitSHA = %q, want %q", got.CommitSHA, tt.wantSHA)
			}
		})
	}
}

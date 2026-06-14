package upgrade

import (
	"reflect"
	"testing"
)

// TestSelectStaleBelowInstalled locks down the tier-independent "retire anything
// not newer than installed" decision behind STATBUS-050 (STATBUS-047 B2). The
// defect it guards: the SQL upgrade_supersede_older proc's release_status
// hierarchy guard cannot retire a genuine older RELEASE when the installed
// version is a PRERELEASE (release > prerelease in the tier order), so older
// releases lingered in 'available' as phantom upgrades. This rule compares CalVer
// versions only — never the tier — and judges each row by its NEWEST tag.
func TestSelectStaleBelowInstalled(t *testing.T) {
	row := func(id int, tags ...string) staleCandidate {
		return staleCandidate{ID: id, Tags: tags}
	}

	tests := []struct {
		name       string
		installed  string
		candidates []staleCandidate
		want       []int
	}{
		{
			// THE rune case (STATBUS-047 B2): genuine releases (v2026.05.1/2/3, each
			// double-tagged with its final rc) older than an installed prerelease
			// (rc.02). The proc's tier guard spared them (release > prerelease);
			// version order retires them. Tier-independence is the whole point.
			name:      "retires older releases when installed is a newer prerelease (tier-independent)",
			installed: "v2026.06.0-rc.02",
			candidates: []staleCandidate{
				row(133, "v2026.05.3-rc.01", "v2026.05.3"),
				row(79, "v2026.05.2-rc.06", "v2026.05.2"),
				row(74, "v2026.05.1-rc.01", "v2026.05.1"),
			},
			want: []int{133, 79, 74},
		},
		{
			name:      "keeps rows strictly newer than installed, retires the rest",
			installed: "v2026.06.0-rc.02",
			candidates: []staleCandidate{
				row(133, "v2026.05.3", "v2026.05.3-rc.01"), // older release  → retire
				row(200, "v2026.06.0"),                     // stable > its rc → keep
				row(201, "v2026.06.1-rc.01"),               // newer          → keep
			},
			want: []int{133},
		},
		{
			name:       "retires a row equal to installed (not an upgrade)",
			installed:  "v2026.06.0-rc.02",
			candidates: []staleCandidate{row(1, "v2026.06.0-rc.02")},
			want:       []int{1},
		},
		{
			name:       "keeps a row strictly newer than installed",
			installed:  "v2026.05.6-rc.01",
			candidates: []staleCandidate{row(1, "v2026.06.0-rc.02")},
			want:       nil,
		},
		{
			// Robustness: judge by the NEWEST tag, not commit_version. Installed sits
			// between the row's rc and its release; the release tag is still ahead, so
			// the row IS an upgrade and must NOT be retired. This is why the rule reads
			// commit_tags and takes the max, rather than trusting commit_version (which
			// on the rune rows is the rc string by array ordering).
			name:       "double-tagged row judged by its newest tag, not the rc",
			installed:  "v2026.05.1-rc.01",
			candidates: []staleCandidate{row(1, "v2026.05.1-rc.01", "v2026.05.1")},
			want:       nil,
		},
		{
			name:      "tier works both directions: older prerelease AND older release retired",
			installed: "v2026.06.0",
			candidates: []staleCandidate{
				row(1, "v2026.05.9-rc.01"), // older prerelease → retire
				row(2, "v2026.05.9"),       // older release    → retire
			},
			want: []int{1, 2},
		},
		{
			name:       "non-CalVer installed version retires nothing (never guess an ordering)",
			installed:  "dev",
			candidates: []staleCandidate{row(1, "v2026.05.1")},
			want:       nil,
		},
		{
			name:       "rows with no CalVer tag are left alone",
			installed:  "v2026.06.0",
			candidates: []staleCandidate{row(1, "deadbeef"), row(2)},
			want:       nil,
		},
		{
			name:       "row with mixed tags judged by its newest valid tag",
			installed:  "v2026.06.0",
			candidates: []staleCandidate{row(1, "not-a-version", "v2026.05.1")}, // valid tag older → retire
			want:       []int{1},
		},
		{
			name:       "empty candidate set yields nothing",
			installed:  "v2026.06.0",
			candidates: nil,
			want:       nil,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := selectStaleBelowInstalled(tt.installed, tt.candidates)
			if !reflect.DeepEqual(got, tt.want) {
				t.Errorf("selectStaleBelowInstalled(%q) = %v, want %v", tt.installed, got, tt.want)
			}
		})
	}
}

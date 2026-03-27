package upgrade

import (
	"testing"
	"time"
)

func TestValidateVersion(t *testing.T) {
	valid := []string{
		"v2026.03.0",
		"v2026.03.1",
		"v2026.12.99",
		"v2026.03.0-rc.1",
		"v2026.03.0-beta.2",
		"v2026.03.0-alpha.1",
		"sha-abc1234",
		"sha-abc1234f",
		"sha-abcdef1234567890abcdef1234567890abcdef12",
	}
	for _, v := range valid {
		if !ValidateVersion(v) {
			t.Errorf("expected valid: %q", v)
		}
	}

	invalid := []string{
		"",
		"2026.03.0",          // missing v prefix
		"v2026.3.0",          // single-digit month
		"v26.03.0",           // two-digit year
		"sha-xyz123",         // non-hex
		"sha-ab",             // too short (< 7)
		"v2026.03.0-",        // trailing dash
		"latest",             // not a version
		"sha-ABCDEF1",        // uppercase hex
		"v2026.03.0 --force", // injection attempt
	}
	for _, v := range invalid {
		if ValidateVersion(v) {
			t.Errorf("expected invalid: %q", v)
		}
	}
}

func TestFilterByChannel(t *testing.T) {
	releases := []Release{
		{TagName: "v2026.03.0", Prerelease: false},
		{TagName: "v2026.03.1-rc.1", Prerelease: true},
		{TagName: "v2026.04.0", Prerelease: false},
		{TagName: "v2026.04.1-beta.1", Prerelease: true},
	}

	stable := FilterByChannel(releases, "stable")
	if len(stable) != 2 {
		t.Fatalf("stable: got %d, want 2", len(stable))
	}
	if stable[0].TagName != "v2026.03.0" || stable[1].TagName != "v2026.04.0" {
		t.Errorf("stable: wrong releases: %v", stable)
	}

	all := FilterByChannel(releases, "prerelease")
	if len(all) != 4 {
		t.Fatalf("prerelease: got %d, want 4", len(all))
	}

}

func TestHasMigrationsFromChanges(t *testing.T) {
	cases := []struct {
		body string
		want bool
	}{
		{"Added new migration for users table", true},
		{"migrate up required after this release", true},
		{"MIGRATION: schema changes included", true},
		{"Fixed a bug in the login flow", false},
		{"Updated dependencies and refactored auth", false},
	}
	for _, c := range cases {
		got := HasMigrationsFromChanges(c.body)
		if got != c.want {
			t.Errorf("HasMigrationsFromChanges(%q) = %v, want %v", c.body, got, c.want)
		}
	}
}

func TestCompareVersions(t *testing.T) {
	cases := []struct {
		a, b string
		want int
	}{
		// Same version
		{"v2026.03.0", "v2026.03.0", 0},
		// Patch ordering
		{"v2026.03.0", "v2026.03.1", -1},
		{"v2026.03.1", "v2026.03.0", 1},
		// RC ordering — the key case: rc.9 < rc.17
		{"v2026.03.0-rc.9", "v2026.03.0-rc.17", -1},
		{"v2026.03.0-rc.17", "v2026.03.0-rc.9", 1},
		{"v2026.03.0-rc.1", "v2026.03.0-rc.2", -1},
		// Stable > prerelease (fewer parts = stable = newer)
		{"v2026.03.0", "v2026.03.0-rc.17", 1},
		{"v2026.03.0-rc.17", "v2026.03.0", -1},
		// Year/month ordering
		{"v2026.03.0", "v2026.04.0", -1},
		{"v2025.12.0", "v2026.01.0", -1},
		// SHA tags are incomparable without git history — returns 0
		{"sha-abc1234f", "sha-def5678a", 0},
		{"sha-abc1234f", "sha-abc1234f", 0},
		// Mixed: SHA vs CalVer — incomparable
		{"sha-abc1234f", "v2026.03.0", 0},
		{"v2026.03.0", "sha-abc1234f", 0},
	}
	for _, c := range cases {
		got := CompareVersions(c.a, c.b)
		if got != c.want {
			t.Errorf("CompareVersions(%q, %q) = %d, want %d", c.a, c.b, got, c.want)
		}
	}
}

func TestReleaseSummary(t *testing.T) {
	r := Release{
		TagName:    "v2026.03.0",
		Name:       "March Release",
		Prerelease: false,
		Published:  time.Date(2026, 3, 1, 0, 0, 0, 0, time.UTC),
	}
	got := ReleaseSummary(r)
	if got != "March Release - 2026-03-01" {
		t.Errorf("got %q", got)
	}

	// Falls back to TagName when Name is empty
	r.Name = ""
	got = ReleaseSummary(r)
	if got != "v2026.03.0 - 2026-03-01" {
		t.Errorf("got %q", got)
	}

	// Pre-release suffix
	r.Prerelease = true
	got = ReleaseSummary(r)
	if got != "v2026.03.0 (pre-release) - 2026-03-01" {
		t.Errorf("got %q", got)
	}
}

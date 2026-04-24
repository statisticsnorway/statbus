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
	}
	for _, v := range valid {
		if !ValidateVersion(v) {
			t.Errorf("expected valid: %q", v)
		}
	}

	// Rc.63: versionRegex tightened to CalVer-only. Every string
	// here was accepted pre-rc.63 (the sha-* alternation) OR is a
	// common non-CalVer shape; all now rejected.
	invalid := []string{
		"",
		"2026.03.0",          // missing v prefix
		"v2026.3.0",          // single-digit month
		"v26.03.0",           // two-digit year
		"v2026.03.0-",        // trailing dash
		"latest",             // not a version
		"v2026.03.0 --force", // injection attempt
		// Rc.63 regression guard: sha- prefix no longer accepted here.
		"sha-abc1234f",
		"sha-abcdef1234567890abcdef1234567890abcdef12",
		"sha-xyz123",
		"sha-ab",
		"sha-ABCDEF1",
	}
	for _, v := range invalid {
		if ValidateVersion(v) {
			t.Errorf("expected invalid: %q", v)
		}
	}
}

// TestSelectLatestTag covers the pure channel→tag selection logic
// used by `./sb release check --channel` and install.sh. Hermetic —
// no network I/O.
func TestSelectLatestTag(t *testing.T) {
	releases := []Release{
		{TagName: "v2026.03.0", Prerelease: false, Draft: false},
		{TagName: "v2026.03.1-rc.1", Prerelease: true, Draft: false},
		{TagName: "v2026.04.0", Prerelease: false, Draft: false},
		{TagName: "v2026.04.1-beta.1", Prerelease: true, Draft: false},
		{TagName: "v2026.04.2-rc.5", Prerelease: true, Draft: false},
		{TagName: "v2026.99.0-draft", Prerelease: true, Draft: true}, // ignored
	}

	cases := []struct {
		name      string
		channel   string
		want      string
		wantError bool
	}{
		{"stable picks latest CalVer", "stable", "v2026.04.0", false},
		{"prerelease picks latest RC", "prerelease", "v2026.04.2-rc.5", false},
		{"edge returns empty", "edge", "", false},
		{"unknown channel errors", "nightly", "", true},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got, err := selectLatestTag(releases, c.channel)
			if (err != nil) != c.wantError {
				t.Fatalf("err=%v, wantError=%v", err, c.wantError)
			}
			if got != c.want {
				t.Errorf("got %q, want %q", got, c.want)
			}
		})
	}

	// Degraded cases: empty release list.
	t.Run("empty stable errors", func(t *testing.T) {
		_, err := selectLatestTag([]Release{}, "stable")
		if err == nil {
			t.Errorf("expected error on empty stable set")
		}
	})
	t.Run("empty prerelease errors", func(t *testing.T) {
		_, err := selectLatestTag([]Release{}, "prerelease")
		if err == nil {
			t.Errorf("expected error on empty prerelease set")
		}
	})
	t.Run("only-draft does not satisfy stable", func(t *testing.T) {
		_, err := selectLatestTag([]Release{
			{TagName: "v2026.04.0", Prerelease: false, Draft: true},
		}, "stable")
		if err == nil {
			t.Errorf("expected error when only release is a draft")
		}
	})
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
		// Regression: double-v prefix from dev.sh + service.go must not break comparison
		{"v2026.03.1-rc.2", "vv2026.03.0-10-g74a3353e5", 1},
		// Mixed prefix: with/without v should compare equal
		{"v2026.03.0", "2026.03.0", 0},
		{"2026.03.1-rc.2", "2026.03.0", 1},
		// git-describe format (non-tagged commit) vs tagged version
		{"v2026.03.1-rc.2", "v2026.03.0-10-g74a3353e5", 1},
		// Rc.63: sha- prefix is no longer a valid input to CompareVersions
		// (callers must ValidateVersion upstream). Tests for sha- inputs
		// moved out — behaviour is now undefined (but non-panicking) for
		// non-CalVer strings.
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

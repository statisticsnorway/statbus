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

// TestClassifyReleaseShape pins the single shared shape classifier. The
// critical guard: a non-rc hyphenated CalVer tag (-beta/-alpha/-foo) is
// ShapeUnknown, NOT a prerelease — "hyphen != prerelease".
func TestClassifyReleaseShape(t *testing.T) {
	cases := []struct {
		in   string
		want ReleaseShape
	}{
		// Clean release tags (with and without the "v" prefix).
		{"v2026.05.1", ShapeRelease},
		{"2026.05.1", ShapeRelease},
		{"v2026.12.99", ShapeRelease},
		// Release-candidate tags → prerelease.
		{"v2026.05.1-rc.1", ShapePrerelease},
		{"v2026.05.1-rc.17", ShapePrerelease},
		{"2026.05.1-rc.5", ShapePrerelease},
		// Non-rc hyphenated CalVer tags → unknown (the footgun shape). These
		// are valid tag SYNTAX (ValidateVersion accepts them) but match no
		// channel and never claim release/prerelease status.
		{"v2026.05.1-beta.1", ShapeUnknown},
		{"v2026.05.1-alpha.1", ShapeUnknown},
		{"v2026.05.1-foo", ShapeUnknown},
		{"v2026.05.1-rcx", ShapeUnknown}, // "rc" without the dot is not an RC
		// Commit references → commit.
		{"dev", ShapeCommit},
		{"", ShapeCommit},
		{"v2026.04.0-7-gf483d1d2e", ShapeCommit},      // git-describe off a release
		{"v2026.04.0-rc.15-1-gf483d1d2e", ShapeCommit}, // git-describe off an rc
		// Garbage / invalid CalVer → unknown.
		{"latest", ShapeUnknown},
		{"v2026.5.0", ShapeUnknown}, // single-digit month is not valid CalVer
	}
	for _, c := range cases {
		if got := ClassifyReleaseShape(c.in); got != c.want {
			t.Errorf("ClassifyReleaseShape(%q) = %d, want %d", c.in, got, c.want)
		}
	}
}

// TestReleaseShapeReleaseStatus pins the shape→release_status_type mapping.
// ShapeUnknown maps to the neutral "commit" rung — never "release".
func TestReleaseShapeReleaseStatus(t *testing.T) {
	cases := []struct {
		shape ReleaseShape
		want  string
	}{
		{ShapeRelease, "release"},
		{ShapePrerelease, "prerelease"},
		{ShapeCommit, "commit"},
		{ShapeUnknown, "commit"},
	}
	for _, c := range cases {
		if got := c.shape.ReleaseStatus(); got != c.want {
			t.Errorf("ReleaseShape(%d).ReleaseStatus() = %q, want %q", c.shape, got, c.want)
		}
	}
}

// TestFilterTagsByChannel pins the EXCLUSIVE per-channel allowlist in BOTH
// directions (accept-list + reject-list). The headline guard (AC#2): an
// arbitrary non-rc hyphenated tag is rejected by stable AND prerelease AND
// edge — it must never be discovered as an installable upgrade anywhere.
func TestFilterTagsByChannel(t *testing.T) {
	const betaTag = "v2026.05.1-beta.1" // the footgun shape

	tags := []GitTag{
		{TagName: "v2026.03.0"},     // release
		{TagName: "v2026.04.0"},     // release
		{TagName: "v2026.04.1-rc.1"}, // rc / prerelease
		{TagName: "v2026.04.2-rc.5"}, // rc / prerelease
		{TagName: betaTag},          // non-rc hyphenated — matches NO channel
	}

	cases := []struct {
		channel string
		want    []string
	}{
		// stable accepts only no-hyphen release tags; rejects rc + beta.
		{"stable", []string{"v2026.03.0", "v2026.04.0"}},
		// prerelease accepts only -rc. tags; rejects release + beta.
		{"prerelease", []string{"v2026.04.1-rc.1", "v2026.04.2-rc.5"}},
		// edge accepts release + rc (binary self-update tracks both); rejects beta.
		{"edge", []string{"v2026.03.0", "v2026.04.0", "v2026.04.1-rc.1", "v2026.04.2-rc.5"}},
		// an unrecognized channel name admits nothing.
		{"nightly", nil},
	}

	for _, c := range cases {
		t.Run(c.channel, func(t *testing.T) {
			got := tagNamesOf(FilterTagsByChannel(tags, c.channel))
			if !sameStringSet(got, c.want) {
				t.Errorf("FilterTagsByChannel(_, %q) = %v, want %v", c.channel, got, c.want)
			}
			// Reject-list invariant: the non-rc hyphenated tag is never admitted.
			for _, n := range got {
				if n == betaTag {
					t.Errorf("channel %q admitted the non-rc hyphenated tag %q — footgun not closed", c.channel, betaTag)
				}
			}
		})
	}
}

func tagNamesOf(tags []GitTag) []string {
	var names []string
	for _, t := range tags {
		names = append(names, t.TagName)
	}
	return names
}

// sameStringSet reports whether a and b contain the same elements (order-
// independent). FilterTagsByChannel preserves input order, but the tests
// assert on membership, not ordering.
func sameStringSet(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	seen := make(map[string]int, len(a))
	for _, s := range a {
		seen[s]++
	}
	for _, s := range b {
		seen[s]--
		if seen[s] < 0 {
			return false
		}
	}
	return true
}

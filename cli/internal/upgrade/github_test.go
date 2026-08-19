package upgrade

import (
	"testing"
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

// TestSelectLatestTag was deleted here together with selectLatestTag itself
// (STATBUS-255). Its cases are not lost, and the accounting is written down
// rather than assumed:
//
//   - "stable picks latest CalVer" and "prerelease picks latest RC" — covered
//     against the LIVE resolver by TestPrereleaseChannelMeansLatestRC_STATBUS255,
//     including the release-cutting day where a stable tag and a newer RC coexist.
//   - "edge returns empty" and "unknown channel errors" — covered by
//     TestEdgeAndUnknownChannelsUnchanged_STATBUS255, which also pins that an
//     unknown channel ERRORS rather than resolving to an empty tag.
//   - "empty set errors" — covered by the same file's classification test.
//   - "only-draft does not satisfy stable" — now true BY CONSTRUCTION rather than
//     by a filter: a GitHub draft publishes no git tag, and resolution reads git
//     tags. There is nothing left to filter, so there is nothing left to test.
//
// The rule this test asserted also survives as apiRuleOracle in
// channel_resolution_git_test.go, verified against this implementation before
// the deletion.

// TestFilterByChannel went with FilterByChannel itself (STATBUS-255). It
// filtered API Releases by GitHub's prerelease FLAG; the surviving equivalent is
// FilterTagsByChannel, which filters git tags by their SHAPE and is tested at
// the bottom of this file — including the exclusivity property that a stray
// hyphenated tag matches no channel.

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

// TestReleaseSummary went with ReleaseSummary itself (STATBUS-255). It rendered
// a human line for a GitHub API Release — "v2026.04.0 (pre-release)" and such —
// and its last production caller was RunCheck, which now prints from a GitTag.
// There is no Release left to summarise.

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
		{"v2026.04.0-7-gf483d1d2e", ShapeCommit},       // git-describe off a release
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
		{TagName: "v2026.03.0"},      // release
		{TagName: "v2026.04.0"},      // release
		{TagName: "v2026.04.1-rc.1"}, // rc / prerelease
		{TagName: "v2026.04.2-rc.5"}, // rc / prerelease
		{TagName: betaTag},           // non-rc hyphenated — matches NO channel
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

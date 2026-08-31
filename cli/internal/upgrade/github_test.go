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
		a, b        string
		want        int
		wantOrdered bool
	}{
		// Same version
		{"v2026.03.0", "v2026.03.0", 0, true},
		// Patch ordering
		{"v2026.03.0", "v2026.03.1", -1, true},
		{"v2026.03.1", "v2026.03.0", 1, true},
		// RC ordering — the key case: rc.9 < rc.17
		{"v2026.03.0-rc.9", "v2026.03.0-rc.17", -1, true},
		{"v2026.03.0-rc.17", "v2026.03.0-rc.9", 1, true},
		{"v2026.03.0-rc.1", "v2026.03.0-rc.2", -1, true},
		// Stable > prerelease (fewer parts = stable = newer)
		{"v2026.03.0", "v2026.03.0-rc.17", 1, true},
		{"v2026.03.0-rc.17", "v2026.03.0", -1, true},
		// Year/month ordering
		{"v2026.03.0", "v2026.04.0", -1, true},
		{"v2025.12.0", "v2026.01.0", -1, true},
		// Mixed prefix: with/without v should compare equal
		{"v2026.03.0", "2026.03.0", 0, true},
		{"2026.03.1-rc.2", "2026.03.0", 1, true},
		// Double-v (dev.sh + service.go bug) still ORDERS — the leading-v
		// tolerance CompareVersions has always had is preserved deliberately,
		// so STATBUS-293 fixes one behaviour without quietly changing another.
		{"vv2026.03.0", "v2026.03.1", -1, true},

		// ── STATBUS-293: NOT RELEASE-ORDERABLE ───────────────────────────────
		// Each of these previously returned a confident int from the lexical
		// fallback. The int is now meaningless and ordered is false.
		//
		// The two SHAs are the real ones from arc run 33115731212, and they are
		// the whole defect in two lines: identical in kind, opposite in result,
		// separated only by their FIRST HEX CHARACTER. "2026" sorts above
		// "063d860a" and below "5399acd8", so the same box installed at two
		// different commits either was or was not offered every stable release
		// back to v2026.03.0 as an upgrade.
		{"v2026.05.5", "063d860a", 0, false}, // used to say "newer" → offered downgrades
		{"v2026.05.5", "5399acd8", 0, false}, // used to say "older" → correct, by luck
		// git-describe with distance past a tag: a commit reference, not a
		// release. Previously ordered (and asserted so); now explicitly not.
		{"v2026.03.1-rc.2", "v2026.03.0-10-g74a3353e5", 0, false},
		{"v2026.03.1-rc.2", "vv2026.03.0-10-g74a3353e5", 0, false},
		{"v2026.08.0-rc.11", "v2026.08.0-rc.11-2-g063d860a", 0, false},
		// The literal dev placeholder, and the empty string.
		{"v2026.05.5", "dev", 0, false},
		{"v2026.05.5", "", 0, false},
		// Two identical commit refs are the SAME COMMIT but that is not a
		// statement about release ordering — the a==b fast path must not
		// smuggle them past the gate as "equal versions".
		{"063d860a", "063d860a", 0, false},
	}
	for _, c := range cases {
		got, gotOrdered := CompareVersions(c.a, c.b)
		if gotOrdered != c.wantOrdered {
			t.Errorf("CompareVersions(%q, %q) ordered = %v, want %v", c.a, c.b, gotOrdered, c.wantOrdered)
			continue
		}
		if gotOrdered && got != c.want {
			t.Errorf("CompareVersions(%q, %q) = %d, want %d", c.a, c.b, got, c.want)
		}
	}
}

// TestCompareVersionsIsSymmetricallyUnordered_STATBUS293 pins that
// unorderability does not depend on argument position. The defect was
// asymmetric in its CONSEQUENCE — only the installed-side operand was ever a
// commit in the failing path — so a fix that gated on one side would look
// correct against every test written from that path's point of view while
// leaving the mirror image live for the next caller.
func TestCompareVersionsIsSymmetricallyUnordered_STATBUS293(t *testing.T) {
	for _, pair := range [][2]string{
		{"v2026.05.5", "063d860a"},
		{"v2026.05.5", "5399acd8"},
		{"v2026.08.0-rc.11", "v2026.08.0-rc.11-2-g063d860a"},
		{"v2026.05.5", "dev"},
	} {
		if _, ok := CompareVersions(pair[0], pair[1]); ok {
			t.Errorf("CompareVersions(%q, %q) reported an ordering; expected none", pair[0], pair[1])
		}
		if _, ok := CompareVersions(pair[1], pair[0]); ok {
			t.Errorf("CompareVersions(%q, %q) reported an ordering; expected none (reversed operands)", pair[1], pair[0])
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
		// stable stays RESTRICTIVE: no-hyphen release tags only; rejects rc + beta.
		{"stable", []string{"v2026.03.0", "v2026.04.0"}},
		// STATBUS-307: prerelease is a SUPERSET of stable, not its sibling.
		//
		// v2026.08.1 and v2026.08.1-rc.01 are two names for ONE COMMIT — a
		// release IS the final gated prerelease, promoted. So a box following
		// prereleases legitimately runs releases too, and this case previously
		// encoded the opposite: it expected a stable tag to FAIL on a prerelease
		// box. That expectation was the disjoint model, and it is what made
		// discovery hide releases from prerelease boxes while scheduleStep warned
		// that a stable target was "off channel" when it was not.
		//
		// beta is still rejected here — the superset is release + rc, not
		// "anything hyphenated".
		{"prerelease", []string{"v2026.03.0", "v2026.04.0", "v2026.04.1-rc.1", "v2026.04.2-rc.5"}},
		// RETIRED edge admits NOTHING (King, 2026-08-19). It used to admit release
		// + rc together, because the edge binary self-update tracked both. Now it
		// is just an unrecognised name, and the exclusive-allowlist shape means an
		// unrecognised name matches no tag at all — so a box carrying a stale
		// edge value is offered nothing rather than offered everything, which is
		// the safe direction for a value nobody chose.
		{"edge", nil},
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

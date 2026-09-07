package upgrade

import (
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"
)

func TestGithubDoRetriesRateLimitThenSucceeds_STATBUS341(t *testing.T) {
	var requests int
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		requests++
		if requests == 1 {
			w.Header().Set("X-RateLimit-Remaining", "0")
			http.Error(w, "rate limited", http.StatusForbidden)
			return
		}
		_, _ = io.WriteString(w, "ok")
	}))
	defer server.Close()

	originalWait := githubRetryWait
	githubRetryWait = func(time.Duration) {}
	t.Cleanup(func() { githubRetryWait = originalWait })

	req, err := githubRequest(http.MethodGet, server.URL)
	if err != nil {
		t.Fatal(err)
	}
	resp, err := githubDo(req)
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = resp.Body.Close() }()
	if resp.StatusCode != http.StatusOK || requests != 2 {
		t.Fatalf("status=%d requests=%d, want 200 after two requests", resp.StatusCode, requests)
	}
}

func TestGithubRetryDelayPastHTTPDateIsZero_STATBUS341(t *testing.T) {
	now := time.Date(2026, 9, 7, 13, 0, 0, 0, time.UTC)
	past := now.Add(-90 * time.Second).UTC().Format(http.TimeFormat)
	if got := githubRetryDelay(past, 7*time.Second, now); got != 0 {
		t.Fatalf("past HTTP-date Retry-After must mean retry now, got %v", got)
	}
	future := now.Add(20 * time.Second).UTC().Format(http.TimeFormat)
	if got := githubRetryDelay(future, 7*time.Second, now); got != 20*time.Second {
		t.Fatalf("future HTTP-date must be honoured, got %v", got)
	}
	if got := githubRetryDelay("not-a-date", 7*time.Second, now); got != 7*time.Second {
		t.Fatalf("unparseable Retry-After must use the fallback, got %v", got)
	}
}

func TestGithubDoHonorsHTTPDateRetryAfter_STATBUS341(t *testing.T) {
	var waited time.Duration
	serverTime := time.Now().Add(90 * time.Second).UTC().Truncate(time.Second)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Retry-After", serverTime.Format(http.TimeFormat))
		http.Error(w, "rate limited", http.StatusTooManyRequests)
	}))
	defer server.Close()

	originalWait := githubRetryWait
	githubRetryWait = func(delay time.Duration) { waited = delay }
	t.Cleanup(func() { githubRetryWait = originalWait })

	req, err := githubRequest(http.MethodGet, server.URL)
	if err != nil {
		t.Fatal(err)
	}
	resp, err := githubDo(req)
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = resp.Body.Close() }()
	if waited < 88*time.Second || waited > 90*time.Second {
		t.Fatalf("HTTP-date Retry-After wait = %s, want approximately 90s", waited)
	}
	if got := githubRetryDelay(time.Now().Add(10*time.Minute).Format(http.TimeFormat), time.Second, time.Now()); got != 300*time.Second {
		t.Fatalf("HTTP-date Retry-After cap = %s, want 5m", got)
	}
}

func TestGithubRequestAuthorizationIsOptional_STATBUS341(t *testing.T) {
	t.Setenv("GITHUB_TOKEN", "")
	req, err := githubRequest(http.MethodGet, "https://example.invalid")
	if err != nil {
		t.Fatal(err)
	}
	if got := req.Header.Get("Authorization"); got != "" {
		t.Fatalf("tokenless Authorization = %q, want absent", got)
	}

	t.Setenv("GITHUB_TOKEN", "test-token")
	req, err = githubRequest(http.MethodGet, "https://example.invalid")
	if err != nil {
		t.Fatal(err)
	}
	if got := req.Header.Get("Authorization"); got != "Bearer test-token" {
		t.Fatalf("Authorization = %q, want Bearer token", got)
	}
}

func TestGitFetchEnvironmentAuthorizationIsOptional_STATBUS341(t *testing.T) {
	t.Setenv("GITHUB_TOKEN", "")
	if env := gitFetchEnv(); env != nil {
		t.Fatalf("tokenless fetch env = %#v, want nil inherited environment", env)
	}

	t.Setenv("GITHUB_TOKEN", "test-token")
	env := gitFetchEnv()
	joined := strings.Join(env, "\n")
	for _, want := range []string{
		"GIT_CONFIG_COUNT=1",
		"GIT_CONFIG_KEY_0=http.extraheader",
		"GIT_CONFIG_VALUE_0=Authorization: Bearer test-token",
	} {
		if !strings.Contains(joined, want) {
			t.Errorf("fetch environment lacks %q", want)
		}
	}
}

func TestGitRateLimitFailureClassification_STATBUS341(t *testing.T) {
	for _, output := range []string{
		"remote: HTTP 403: API rate limit exceeded",
		"fatal: 429 too many requests; rate-limit active",
		"rate limit response: HTTP 401",
	} {
		if !isGitRateLimitFailure(output) {
			t.Errorf("expected retryable rate-limit output: %q", output)
		}
	}
	if isGitRateLimitFailure("fatal: authentication failed (HTTP 403)") {
		t.Error("ordinary authentication failure must not be classified as rate limiting")
	}
}

func TestDiscoverTagsViaGitUsesAuthEnvAndBoundedRetry_STATBUS341(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("fake git is a shell script")
	}
	tests := []struct {
		name      string
		failure   string
		wantCalls int
		wantErr   bool
	}{
		{name: "rate limit retries then gives up", failure: "rate", wantCalls: preswapFetchMaxAttempts, wantErr: true},
		{name: "ordinary failure is not retried", failure: "ordinary", wantCalls: 1, wantErr: true},
		{name: "authenticated success", failure: "none", wantCalls: 1, wantErr: false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			dir := t.TempDir()
			fakeBin := filepath.Join(dir, "bin")
			if err := os.Mkdir(fakeBin, 0755); err != nil {
				t.Fatal(err)
			}
			trace := filepath.Join(dir, "trace")
			count := filepath.Join(dir, "count")
			script := `#!/bin/sh
case " $* " in
  *" fetch "*)
    n=0; [ ! -f "$COUNT_FILE" ] || n=$(cat "$COUNT_FILE"); n=$((n + 1)); printf '%s' "$n" > "$COUNT_FILE"
    printf 'count=%s\nkey=%s\nvalue=%s\nargs=%s\n' "${GIT_CONFIG_COUNT-}" "${GIT_CONFIG_KEY_0-}" "${GIT_CONFIG_VALUE_0-}" "$*" >> "$TRACE_FILE"
    case "$FAILURE" in
      rate) echo 'remote: HTTP 403: API rate limit exceeded' >&2; exit 1 ;;
      ordinary) echo 'fatal: authentication failed' >&2; exit 1 ;;
    esac
    ;;
  *" tag "*) printf 'v2026.09.1\t0123456789012345678901234567890123456789\t0123456789012345678901234567890123456789\t2026-09-01T00:00:00Z\t\n' ;;
esac
`
			gitPath := filepath.Join(fakeBin, "git")
			if err := os.WriteFile(gitPath, []byte(script), 0755); err != nil {
				t.Fatal(err)
			}
			t.Setenv("PATH", fakeBin+string(os.PathListSeparator)+os.Getenv("PATH"))
			t.Setenv("COUNT_FILE", count)
			t.Setenv("TRACE_FILE", trace)
			t.Setenv("FAILURE", tt.failure)
			t.Setenv("GITHUB_TOKEN", "secret-test-token")
			originalWait := gitDiscoveryRetryWait
			gitDiscoveryRetryWait = func(time.Duration) {}
			t.Cleanup(func() { gitDiscoveryRetryWait = originalWait })

			_, err := DiscoverTagsViaGit(dir)
			if (err != nil) != tt.wantErr {
				t.Fatalf("DiscoverTagsViaGit error = %v, wantErr %v", err, tt.wantErr)
			}
			data, readErr := os.ReadFile(trace)
			if readErr != nil {
				t.Fatal(readErr)
			}
			got := string(data)
			if calls := strings.Count(got, "count="); calls != tt.wantCalls {
				t.Fatalf("fetch calls = %d, want %d; trace:\n%s", calls, tt.wantCalls, got)
			}
			for _, want := range []string{"key=http.extraheader", "value=Authorization: Bearer secret-test-token"} {
				if !strings.Contains(got, want) {
					t.Fatalf("trace lacks %q:\n%s", want, got)
				}
			}
			for _, line := range strings.Split(got, "\n") {
				if strings.HasPrefix(line, "args=") && strings.Contains(line, "secret-test-token") {
					t.Fatalf("token leaked into git argv:\n%s", got)
				}
			}
		})
	}
}

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

package upgrade

import (
	"strings"
	"testing"
)

// STATBUS-255. Channel resolution used to ask the GitHub RELEASES API for one
// fact — GitHub's prerelease FLAG — that the tag name already carries.
//
// The unauthenticated API allows 60 requests/hour PER IP. All seven niue slots
// share one, dev polls every five minutes, and on 2026-08-19 the window
// exhausted and every notify job 403'd. That is structural, not bad luck, and
// any statistical office behind a shared IP or corporate NAT inherits it.
//
// THE CUSTOMER FRAME IS THE TEST: an NSO box must never need a GitHub token to
// follow a release channel.

// TestChannelResolutionMatchesTheAPIAnswer_STATBUS255 is the equivalence proof.
// The same tag set, resolved both ways, must give the SAME answer — otherwise
// this is not a rate-limit fix, it is a behaviour change wearing one.
func TestChannelResolutionMatchesTheAPIAnswer_STATBUS255(t *testing.T) {
	// A realistic set: stables, RCs, a release-cutting day where a stable and a
	// newer RC coexist, and tags that match no channel.
	releases := []Release{
		{TagName: "v2026.08.0", Prerelease: false},
		{TagName: "v2026.08.1-rc.1", Prerelease: true},
		{TagName: "v2026.08.1-rc.2", Prerelease: true},
		{TagName: "v2026.07.3", Prerelease: false},
		{TagName: "v2026.07.4-beta.1", Prerelease: true}, // valid CalVer, non-rc suffix
	}
	var names []string
	for _, r := range releases {
		names = append(names, r.TagName)
	}

	for _, channel := range []string{"stable", "prerelease"} {
		viaAPI, apiErr := selectLatestTag(releases, channel)
		viaGit, gitErr := selectLatestTagFromNames(names, channel)

		if (apiErr == nil) != (gitErr == nil) {
			t.Fatalf("[%s] the two paths disagree about whether resolution succeeds: api=%v git=%v", channel, apiErr, gitErr)
		}
		if viaAPI != viaGit {
			t.Errorf(`[%s] GIT RESOLUTION DISAGREES WITH THE API ANSWER: api=%q git=%q.

This must be a rate-limit fix, not a behaviour change: the same tag set has to
resolve to the same tag, or boxes following a channel would silently move to a
different version than they do today.`, channel, viaAPI, viaGit)
		}
	}
}

// TestPrereleaseChannelMeansLatestRC_STATBUS255 preserves the asymmetry that
// looks like a bug and is not: on a release-cutting day a stable tag exists at
// HEAD, and the prerelease channel must STILL select the newest RC. Getting
// this wrong would silently move every prerelease box onto stable.
func TestPrereleaseChannelMeansLatestRC_STATBUS255(t *testing.T) {
	names := []string{"v2026.08.1", "v2026.08.2-rc.1", "v2026.08.0"}

	got, err := selectLatestTagFromNames(names, "prerelease")
	if err != nil {
		t.Fatal(err)
	}
	if got != "v2026.08.2-rc.1" {
		t.Errorf("the prerelease channel means LATEST RC — a stable tag must not win it; got %q", got)
	}

	got, err = selectLatestTagFromNames(names, "stable")
	if err != nil {
		t.Fatal(err)
	}
	if got != "v2026.08.1" {
		t.Errorf("the stable channel must select the newest RELEASE, never an RC; got %q", got)
	}
}

// TestClassificationIsNotASecondCopyOfTheRule_STATBUS255: the channel decision
// reuses ClassifyReleaseShape. Two copies of "what counts as a prerelease" drift
// — and this copy decides which version a box installs.
func TestClassificationIsNotASecondCopyOfTheRule_STATBUS255(t *testing.T) {
	src := readUpgradeGithubSource(t)
	body := extractFuncBody(t, src, "func selectLatestTagFromNames(")

	if !strings.Contains(body, "ClassifyReleaseShape(") {
		t.Error("channel classification must reuse ClassifyReleaseShape — the same rule the rest of the package and the instance script already apply")
	}
	if strings.Contains(body, `"-rc."`) {
		t.Error(`a second literal "-rc." test is a second copy of the rule; it will drift from ClassifyReleaseShape, and this copy decides which version a box installs`)
	}

	// A valid CalVer tag with a non-rc suffix belongs to NO channel — same as
	// the API path, where it was never a release either.
	if _, err := selectLatestTagFromNames([]string{"v2026.08.1-beta.1"}, "prerelease"); err == nil {
		t.Error("a -beta. tag must match no channel; treating any hyphen as a prerelease would put boxes on unsupported builds")
	}
	if _, err := selectLatestTagFromNames([]string{"v2026.08.1-beta.1"}, "stable"); err == nil {
		t.Error("a -beta. tag is not a stable release either")
	}
}

// TestResolutionPathMakesNoAPICall_STATBUS255 is the property the ticket exists
// for, pinned at the source: nothing on the resolution path may reach
// api.github.com. Behavioural proof is impossible here without a network, so
// the pin is structural — and it is the whole point, so it is stated loudly.
func TestResolutionPathMakesNoAPICall_STATBUS255(t *testing.T) {
	src := readUpgradeGithubSource(t)

	for _, fn := range []string{
		"func ResolveChannelToLatestTagAt(",
		"func selectLatestTagFromNames(",
	} {
		body := extractFuncBody(t, src, fn)
		for _, forbidden := range []string{"FetchReleases(", "apiBase", "api.github.com", "http.NewRequest"} {
			if strings.Contains(body, forbidden) {
				t.Errorf(`%s reaches the GitHub API (%q) — the resolution path must not.

60 requests/hour per IP, shared by every slot on the host: this is what 403'd
the whole fleet on 2026-08-19. An NSO box must never need a token to follow a
channel.`, fn, forbidden)
			}
		}
	}

	// And it must actually use the git path.
	body := extractFuncBody(t, src, "func ResolveChannelToLatestTagAt(")
	if !strings.Contains(body, "DiscoverTagsViaGit(") {
		t.Error("resolution must read tags over git (DiscoverTagsViaGit) — unlimited, credential-free, and already how the service discovers tags everywhere else")
	}
}

// TestEdgeAndUnknownChannelsUnchanged_STATBUS255: edge resolves to the empty
// tag as before, and an unknown channel is still an error rather than an empty
// success — an empty tag treated as "no upgrade available" would silently
// freeze a box on a typo.
func TestEdgeAndUnknownChannelsUnchanged_STATBUS255(t *testing.T) {
	got, err := ResolveChannelToLatestTagAt(t.TempDir(), "edge")
	if err != nil || got != "" {
		t.Errorf("edge must resolve to the empty tag with no error and no git call; got %q, %v", got, err)
	}
	if _, err := ResolveChannelToLatestTagAt(t.TempDir(), "nonsense"); err == nil {
		t.Error("an unknown channel must ERROR — resolving it to an empty tag would read as 'nothing to upgrade to' and freeze the box on a typo")
	}
}

func readUpgradeGithubSource(t *testing.T) string {
	t.Helper()
	return string(packageGoSources(t)["github.go"])
}

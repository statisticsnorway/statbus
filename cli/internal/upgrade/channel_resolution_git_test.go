package upgrade

import (
	"fmt"
	"regexp"
	"sort"
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
//
// It compares against apiRuleOracle — the fixed statement of what the GitHub
// releases API path meant — rather than against that path's implementation,
// which no longer exists. The oracle was verified against the real
// implementation while both were in the tree; see the note above apiRuleOracle.
func TestChannelResolutionMatchesTheAPIAnswer_STATBUS255(t *testing.T) {
	// A realistic set: stables, RCs, a release-cutting day where a stable and a
	// newer RC coexist, and tags that match no channel.
	releases := []apiRelease{
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
		viaAPI, apiErr := apiRuleOracle(releases, channel)
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

	// STATBUS-307 widened what counts as satisfying this rule, and strengthened
	// it in the process. Reusing ClassifyReleaseShape still qualifies, but
	// delegating to TagMatchesChannel qualifies MORE: that function is the single
	// definition of channel membership, and it calls ClassifyReleaseShape itself.
	//
	// This test caught a real defect during that change. selectLatestTagFromNames
	// carried its own release↔stable / prerelease↔prerelease mapping — a second
	// copy not of "what counts as a prerelease" but of "what counts as ON
	// CHANNEL". The superset fix corrected TagMatchesChannel and would have left
	// this copy untouched, so a prerelease box resolving its latest tag would
	// still have skipped every stable release while discovery admitted them. The
	// fix was to delegate, which is why the direct call is gone.
	if !strings.Contains(body, "ClassifyReleaseShape(") && !strings.Contains(body, "TagMatchesChannel(") {
		t.Error("channel classification must reuse the shared rule — ClassifyReleaseShape, or TagMatchesChannel which is built on it — never a private copy")
	}
	// The membership mapping must not be re-derived here either. A local
	// `channel == "stable"` test alongside a shape switch is exactly the second
	// copy that survived the superset fix and had to be removed.
	if strings.Contains(body, `channel == "stable"`) || strings.Contains(body, `channel == "prerelease"`) {
		t.Error(`a local channel-name comparison is a second copy of the membership rule; delegate to TagMatchesChannel so one definition decides what is on channel`)
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

// TestRetiredAndUnknownChannelsError: an unknown channel must ERROR rather than
// resolve to an empty tag. An empty tag reads downstream as "nothing to upgrade
// to", so a typo — or a stale value — would freeze a box silently instead of
// telling anyone.
//
// EDGE IS NOW ONE OF THOSE UNKNOWN VALUES, and this test changed deliberately
// rather than to match the code. It previously asserted that edge resolves to
// ("", nil): that was correct while edge existed, because a box tracking master
// genuinely had no tag to resolve. The King retired edge on 2026-08-19, so no
// role derives it and no box can be put on it on purpose — the value can now
// only arrive from a stale config, and silence is the wrong answer to it.
func TestRetiredAndUnknownChannelsError(t *testing.T) {
	for _, channel := range []string{"edge", "nonsense", ""} {
		got, err := ResolveChannelToLatestTagAt(t.TempDir(), channel)
		if err == nil {
			t.Errorf(`channel %q resolved to %q with NO error.

An unrecognised channel must be loud. Resolving it to an empty tag reads as
"nothing to upgrade to" downstream, which freezes the box on a stale or
mistyped value with nothing in the logs to explain it.`, channel, got)
		}
	}
}

func readUpgradeGithubSource(t *testing.T) string {
	t.Helper()
	return string(packageGoSources(t)["github.go"])
}

// TestDiscoveryMakesNoAPICall_STATBUS255 completes the entry: RESOLUTION going
// through git was only half of it. `sb upgrade check` — the command that
// actually exhausted the quota and 403'd all seven notify jobs — never went
// through the resolver at all; it called FetchReleases directly.
//
// A fix that left that call in place would have closed the wrong caller and let
// the fleet keep failing, so the pin covers BOTH: no path a box takes to learn
// what versions exist may reach api.github.com.
func TestDiscoveryMakesNoAPICall_STATBUS255(t *testing.T) {
	src := readUpgradeServiceSource(t)
	body := extractFuncBody(t, src, "func (d *Service) RunCheck(")

	if strings.Contains(body, "FetchReleases(") {
		t.Error(`RunCheck reaches the GitHub releases API.

This is THE command that exhausted the quota: 60 requests/hour per IP, seven
slots on one IP, dev polling every five minutes. Every field it needs — tag
name, commit, timestamp, and a release status it ALREADY derived from the tag
name — is available over git, which is unlimited and needs no credential.`)
	}
	if !strings.Contains(body, "DiscoverTagsViaGit(") {
		t.Error("RunCheck must discover over git — the same unlimited, credential-free path the rest of the service already uses")
	}

	// The safety this rests on is that a tag WITHOUT a published release cannot
	// install. That is not this function's job, but it is this function's
	// PREMISE, so it is asserted here: if the readiness gate ever disappears,
	// git-derived discovery becomes able to attempt an install with no assets.
	if !strings.Contains(src, "Release assets not ready for %s") {
		t.Error(`the readiness gate that makes git-derived discovery safe is gone.

Git returns every tag, including one pushed without a release. That is safe ONLY
because a candidate whose assets are not ready stays SCHEDULED with a visible
wait message rather than being installed or losing operator intent. Without that
gate, discovery over git could attempt an install against a tag with no binary.`)
	}
}

// ─────────────────────────────────────────────────────────────────────────────
// THE FIXED ORACLE, and the one instant it can be validated.
//
// The equivalence proof above compared the new git resolver against
// selectLatestTag — the live API implementation. That is a circular oracle: it
// says "the same as that thing over there", so it proves agreement without ever
// stating what the rule IS, and it dies the moment the implementation it points
// at is deleted.
//
// apiRuleOracle replaces it by STATING THE RULE, fixed, as intent: what the
// GitHub releases API path meant by "the latest tag on this channel". A fixed
// oracle is better than a same-as-that-thing oracle for exactly the reason it is
// riskier to introduce — someone has to transcribe the rule, and a transcription
// can be wrong.
//
// That risk is not managed by care. It is KILLED, in one step, at the one
// instant it is checkable: while the original is still in the tree.
// TestFixedOracleTranscribesTheLiveRule below runs both over the same inputs and
// requires identical answers. After the live implementation is deleted, that
// check is impossible — there is nothing left to compare against — which is why
// the order is add-oracle → verify-against-original → delete, never any other.

// apiRelease is the oracle's OWN shape: exactly the three fields the rule reads.
//
// It is deliberately not the production Release type. An oracle that borrows a
// production type stops being fixed the moment that type changes, and the type
// in question is being deleted in this same change — so borrowing it would have
// made the oracle uncompilable, or worse, quietly re-anchored to whatever
// replaced it.
type apiRelease struct {
	TagName    string
	Prerelease bool
	Draft      bool
}

// apiRuleOracle is the rule the GitHub releases API path applied, transcribed
// once and then held fixed:
//
//	edge                 → no tag at all (nothing to resolve).
//	stable               → the highest-CalVer release GitHub did NOT flag as a
//	                       prerelease.
//	prerelease           → the highest-CalVer release GitHub DID flag as a
//	                       prerelease. Deliberately not "all releases": the
//	                       operator-facing meaning of the prerelease channel is
//	                       LATEST RC, so on a release-cutting day a stable tag at
//	                       HEAD must not win it.
//	drafts               → never eligible on any channel.
//	anything else        → an error, never an empty tag: an empty tag reads as
//	                       "nothing to upgrade to" and would freeze a box on a typo.
func apiRuleOracle(releases []apiRelease, channel string) (string, error) {
	var wantPrerelease bool
	switch channel {
	case "edge":
		return "", nil
	case "stable":
		wantPrerelease = false
	case "prerelease":
		wantPrerelease = true
	default:
		return "", fmt.Errorf("unknown channel %q (valid: stable, prerelease, edge)", channel)
	}
	var eligible []apiRelease
	for _, r := range releases {
		if !r.Draft && r.Prerelease == wantPrerelease {
			eligible = append(eligible, r)
		}
	}
	if len(eligible) == 0 {
		return "", fmt.Errorf("no %s release published", channel)
	}
	sort.Slice(eligible, func(i, j int) bool {
		ord, ordered := CompareVersions(eligible[i].TagName, eligible[j].TagName)
		return ordered && ord > 0
	})
	return eligible[0].TagName, nil
}

// VERIFY THE ARTIFACT YOU SHIP, NOT A PREDECESSOR OF IT.
//
// This oracle was verified TWICE, and the second run was not ceremony. The first
// check compared an EARLIER oracle — one that took the production Release type.
// That type is deleted in this same change, so the oracle had to be localised to
// its own apiRelease shape afterwards. Localising and stopping there would have
// shipped an artifact that was never compared to anything: a transcription of a
// transcription, with no original left to check it against.
//
// So the FINAL oracle — localised shape and all — was re-run against the
// original implementation, extracted verbatim from git rather than retyped,
// before the deletion. The re-localisation looked mechanical. So did the two
// defects that got closest to shipping this week: a mutation that silently hit
// the wrong site, and a check that examined a predecessor. Mechanical is what
// both of those looked like beforehand.
//
// THE TRANSCRIPTION CHECK RAN HERE, AND IS GONE — deliberately, not by neglect.
//
// The check drove the shipped apiRuleOracle and the live selectLatestTag over
// the same inputs — the release-cutting day, drafts, a channel with nothing
// published, edge, an unknown channel, an empty set: thirty comparisons, and the
// count was asserted so a check that examined fewer could not pass quietly. They
// agreed on every one. Then, in the same change, selectLatestTag was deleted and
// this check went with it: its subject no longer exists, so it cannot be run
// again by anyone, at any later date.
//
// That is why the order was fixed and not a preference: oracle → verify against
// the original → delete. A fixed oracle carries exactly one risk, that someone
// transcribes the rule wrongly, and that risk is checkable during exactly one
// instant — while the original is still in the tree. Verifying after the
// deletion is not slower; it is impossible.

// TestEveryDiscoveryPathFiltersByChannel_STATBUS291 pins the property that a
// box is never OFFERED a version outside its channel — at EVERY path that
// discovers versions, including ones that do not exist yet.
//
// The defect: `./sb upgrade check` on ua (born rc.10, channel stable) listed
// v2026.08.0-rc.11 as available. The service's own discovery filtered; RunCheck,
// reached by the CLI, did not — it registered every tag merely NEWER than the
// running version. Two discovery paths, one rule, and only one applied it.
//
// THE ENUMERATION IS DERIVED FROM THE SOURCE, NOT LISTED HERE, and that is the
// point of the test rather than a detail of it. A hardcoded list of the two
// known paths could not fail for a THIRD path — it would never examine one — so
// a test claiming "any new discoverer is caught" while iterating a literal
// would be making a promise its own code does not keep. Instead: find every
// function whose body calls DiscoverTagsViaGit, and require each to filter.
// A path that does not exist today is covered the day someone writes it.
func TestEveryDiscoveryPathFiltersByChannel_STATBUS291(t *testing.T) {
	src := readUpgradeServiceSource(t)

	discoverers := functionsCalling(t, src, "DiscoverTagsViaGit(")
	if len(discoverers) < 2 {
		// Zero-scope guard: a scan that finds nothing must fail rather than
		// pass. Both known discoverers (discover, RunCheck) must be found, or
		// the scan itself has stopped working and is silently asserting nothing.
		t.Fatalf("found %d function(s) calling DiscoverTagsViaGit (%v) — expected at least the 2 known discovery paths; the scan is broken, so this test is asserting nothing", len(discoverers), discoverers)
	}

	for _, fn := range discoverers {
		body := extractFuncBody(t, src, fn)
		if !strings.Contains(body, "FilterTagsByChannel(") {
			t.Errorf(`%s discovers release tags without filtering by channel.

A discovery path that does not filter OFFERS a box versions it must never take:
this is how a stable production box came to list a release candidate as
available (STATBUS-291, observed on ua). Every path that learns what versions
exist must apply the SAME channel rule.

The filter belongs in the discovery path itself — NOT in the shared
upsertCandidate helper, which registerStep also reaches. That helper carries the
named-target path behind `+"`./sb upgrade register/apply`"+`, and filtering there would
block deliberate off-channel installs fleet-wide (STATBUS-258).`, fn)
		}
	}
}

// functionsCalling returns the declaration line of every top-level function in
// src whose body contains needle — the material the derived enumeration above
// needs, in the form extractFuncBody already consumes.
func functionsCalling(t *testing.T, src, needle string) []string {
	t.Helper()
	decl := regexp.MustCompile(`(?m)^func (?:\([^)]*\) )?[A-Za-z0-9_]+\(`)
	locs := decl.FindAllStringIndex(src, -1)

	var out []string
	for i, loc := range locs {
		bodyEnd := len(src)
		if i+1 < len(locs) {
			bodyEnd = locs[i+1][0]
		}
		if strings.Contains(src[loc[0]:bodyEnd], needle) {
			out = append(out, src[loc[0]:loc[1]])
		}
	}
	return out
}

// TestDeliberateOffChannelTargetIsAnnounced_STATBUS291 pins the OTHER half, and
// the asymmetry is the design: automatic discovery FILTERS, a deliberately named
// target is ANNOUNCED and proceeds.
//
// A human who types a version is giving an instruction, not receiving an offer,
// and refusing it would break the candidate-addressed deployment that replaced
// the retired master-to-X buttons (STATBUS-258). But putting a prerelease on a
// production installation is a real deviation, and an unannounced deviation is
// how a box quietly stops being what the fleet believes it is.
//
// Pinned because silence is the failure mode that leaves no trace: if this
// print is ever dropped, nothing at runtime complains — the deviation simply
// stops being visible, which is precisely the class of defect this whole
// evening has been about.
func TestDeliberateOffChannelTargetIsAnnounced_STATBUS291(t *testing.T) {
	src := readUpgradeServiceSource(t)
	body := extractFuncBody(t, src, "func (d *Service) scheduleStep(")

	if !strings.Contains(body, "TagMatchesChannel(") {
		t.Error(`scheduleStep no longer checks whether a named target is on the box's channel.

Scheduling a prerelease onto a stable production box is a deliberate deviation.
It is allowed — a named target is an instruction (STATBUS-258) — but it must be
ANNOUNCED. Without this check the deviation happens in silence.`)
	}
	if !strings.Contains(body, "not on this box's") {
		t.Error(`scheduleStep no longer PRINTS the off-channel notice.

Detecting the deviation and saying nothing is the same as not detecting it. The
operator must see, at the moment it happens, that this box is being given a
version its channel would never have offered.`)
	}
	// It must ANNOUNCE, not refuse: a returned error here would break the
	// deliberate-deployment path the announcement exists to accompany.
	if strings.Contains(body, "not on this box's") &&
		strings.Contains(body, `return fmt.Errorf("channel`) {
		t.Error("scheduleStep REFUSES an off-channel named target — it must announce and proceed (STATBUS-258 deliberate deployment must not be blocked)")
	}
}

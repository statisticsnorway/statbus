// Package upgrade handles GitHub Releases discovery and upgrade execution.
package upgrade

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"
)

const (
	owner = "statisticsnorway"
	repo  = "statbus"
)

// Asset is a release asset (binary, manifest, etc.).
type Asset struct {
	Name               string `json:"name"`
	BrowserDownloadURL string `json:"browser_download_url"`
	Size               int64  `json:"size"`
}

// Manifest is the release-manifest.json attached to each release.
type Manifest struct {
	Version       string            `json:"version"`
	CommitSHA     string            `json:"commit_sha"`
	Prerelease    bool              `json:"prerelease"`
	Images        map[string]string `json:"images"`
	HasMigrations bool              `json:"has_migrations"`
	Binaries      map[string]struct {
		URL    string `json:"url"`
		SHA256 string `json:"sha256"`
	} `json:"binaries"`
}

// versionRegex validates CalVer tag strings. Tightened in rc.63 to
// release-tag shape ONLY — pre-rc.63 the regex also accepted
// `sha-<7-40 hex>`, which required every caller to distinguish the
// two alternatives. Post-rc.63 ValidateVersion answers exactly one
// question: is this a release tag. For untagged commit references,
// callers now carry typed CommitSHA / CommitShort values instead of
// inspecting strings.
var versionRegex = regexp.MustCompile(`^v\d{4}\.\d{2}\.\d+(-[\w.]+)?$`)

// ValidateVersion reports whether v is a valid CalVer release tag
// (v<YYYY>.<MM>.<patch>[-suffix]). Equivalent to NewReleaseTag's
// validation — the function is kept for backward-compat with
// call sites that don't need the typed value.
func ValidateVersion(v string) bool {
	return versionRegex.MatchString(v)
}

// ReleaseShape is the structural classification of a version/tag string.
// It is the single source of truth for "what kind of reference is this" —
// the one shape→channel/status mapping used by BOTH discovery (service.go)
// and the installer (install.go), so no site invents its own heuristic.
//
// Critically it does NOT treat every hyphen as a prerelease: ONLY the -rc.N
// shape is a prerelease. Any other hyphenated CalVer suffix (-beta.1, -foo,
// a typo) is ShapeUnknown — a recognizable-but-unsupported shape that matches
// NO release channel and is never offered as an installable upgrade.
type ReleaseShape int

const (
	// ShapeUnknown: not a supported release-family reference — an empty
	// string, a CalVer tag with a non-rc hyphenated suffix (v2026.05.1-beta.1),
	// or any string that is neither a clean release tag, a clean RC tag, nor a
	// commit reference. Matches no channel.
	ShapeUnknown ReleaseShape = iota
	// ShapeCommit: an untagged commit reference — the literal "dev" or a
	// git-describe string with distance past a tag ("...-N-g<hex>", including
	// "...-rc.K-N-g<hex>"). Tracked by the edge channel's commit discovery,
	// not by release-tag filtering.
	ShapeCommit
	// ShapeRelease: a clean CalVer release tag with no suffix, e.g. v2026.05.1.
	ShapeRelease
	// ShapePrerelease: a clean CalVer release-candidate tag, e.g. v2026.05.1-rc.5.
	ShapePrerelease
)

// gitDescribeDistanceRe matches the "-g<hex>" tail `git describe` appends to
// an untagged commit past a tag (e.g. "v2026.04.0-7-gf483d1d2e").
var gitDescribeDistanceRe = regexp.MustCompile(`-g[0-9a-f]+$`)

// ClassifyReleaseShape classifies a version/tag string by structural shape.
// Accepts inputs with or without the leading "v". This is the single shared
// classifier — see ReleaseShape for why hyphen != prerelease.
func ClassifyReleaseShape(ver string) ReleaseShape {
	bare := strings.TrimPrefix(ver, "v")
	if bare == "" || bare == "dev" {
		return ShapeCommit
	}
	// git-describe with distance past a tag → an untagged commit, not the tag
	// it descends from. Checked before the CalVer test because the describe
	// tail can dangle off an -rc. tag ("...-rc.15-1-gf483d1d2e").
	if gitDescribeDistanceRe.MatchString(bare) {
		return ShapeCommit
	}
	// Must be a syntactically valid CalVer tag to be a release or an RC.
	if !ValidateVersion("v" + bare) {
		return ShapeUnknown
	}
	if strings.Contains(bare, "-rc.") {
		return ShapePrerelease
	}
	if strings.Contains(bare, "-") {
		// Valid CalVer but a non-rc suffix (e.g. -beta.1): recognizable but
		// unsupported. Not a release, not an RC — matches no channel.
		return ShapeUnknown
	}
	return ShapeRelease
}

// ReleaseStatus maps a shape to the public.release_status_type value
// (commit | prerelease | release) recorded in the upgrade table. ShapeUnknown
// maps to the neutral lowest rung "commit": an unrecognized shape never claims
// release or prerelease status, so it cannot wrongly supersede a real release
// in the GREATEST() promotion logic.
func (s ReleaseShape) ReleaseStatus() string {
	switch s {
	case ShapeRelease:
		return "release"
	case ShapePrerelease:
		return "prerelease"
	default: // ShapeCommit, ShapeUnknown
		return "commit"
	}
}

// githubRequest creates an HTTP request with optional auth from GITHUB_TOKEN env var.
// Authenticated requests get 5000 req/hr instead of 60 req/hr.
func githubRequest(method, url string) (*http.Request, error) {
	req, err := http.NewRequest(method, url, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("User-Agent", "statbus-upgrade-service")
	if token := os.Getenv("GITHUB_TOKEN"); token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	return req, nil
}

// githubDo executes a request with rate-limit retry on 403 + Retry-After.
func githubDo(req *http.Request) (*http.Response, error) {
	client := &http.Client{Timeout: 30 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	if resp.StatusCode == http.StatusForbidden {
		if ra := resp.Header.Get("Retry-After"); ra != "" {
			_ = resp.Body.Close()
			if seconds, err := strconv.Atoi(ra); err == nil && seconds > 0 && seconds <= 300 {
				time.Sleep(time.Duration(seconds) * time.Second)
				return client.Do(req)
			}
		}
	}
	return resp, nil
}

// FetchManifest downloads the release-manifest.json for a given version.
// Uses githubRequest/githubDo for auth, timeout, and rate-limit handling.
func FetchManifest(version string) (*Manifest, error) {
	url := fmt.Sprintf("https://github.com/%s/%s/releases/download/%s/release-manifest.json", owner, repo, version)
	req, err := githubRequest("GET", url)
	if err != nil {
		return nil, fmt.Errorf("fetch manifest: %w", err)
	}

	resp, err := githubDo(req)
	if err != nil {
		return nil, fmt.Errorf("fetch manifest: %w", err)
	}
	defer func() { _ = resp.Body.Close() }()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("manifest not found for %s (HTTP %d)", version, resp.StatusCode)
	}

	var m Manifest
	if err := json.NewDecoder(resp.Body).Decode(&m); err != nil {
		return nil, fmt.Errorf("decode manifest: %w", err)
	}
	return &m, nil
}

// ResolveChannelToLatestTag resolves a channel name to the current latest
// release tag — FROM GIT TAGS, with no GitHub API call and no credential
// (STATBUS-255).
//
// This is the sole resolution site used by install.sh (via `./sb install`),
// `./sb install` itself, and `./sb release check --channel`. Keeping it sole is
// what keeps those three aligned; a second resolver would let them disagree
// about what "the stable channel" points at.
//
// WHY IT NO LONGER ASKS THE API. It used to call FetchReleases purely to read
// GitHub's prerelease FLAG — a fact fully derivable from the tag name. The
// unauthenticated API allows 60 requests/hour PER IP, and all seven niue slots
// share one: on 2026-08-19 the window exhausted and every notify job 403'd (run
// 32247740861). With dev polling every five minutes that is structural, not bad
// luck. Any statistical office behind a shared IP or a corporate NAT inherits
// exactly the same failure.
//
// THE CUSTOMER FRAME DECIDES THE SHAPE: an NSO box must never need a GitHub
// token to follow a release channel. `git fetch --tags` is unlimited,
// credential-free, and already how the service discovers tags everywhere else.
//
// CLASSIFICATION REUSES ClassifyReleaseShape — the same rule
// ops/create-new-statbus-installation.sh applies over plain git, and the same
// one the rest of this package already trusts. Deliberately not a second
// `strings.Contains(tag, "-rc.")`: two copies of one rule drift, and this one
// decides which version a box installs.
func ResolveChannelToLatestTag(channel string) (string, error) {
	return ResolveChannelToLatestTagAt(".", channel)
}

// ResolveChannelToLatestTagAt is the testable inner variant — projDir is the
// repository the tags are read from.
func ResolveChannelToLatestTagAt(projDir, channel string) (string, error) {
	// EDGE IS RETIRED (King ruled 2026-08-19). It used to return ("", nil) here —
	// "resolve to no tag" — which was how a box that tracked master said "there
	// is nothing to resolve". No role derives edge any more, so the value can
	// only arrive from a stale config, and an unknown channel must ERROR rather
	// than return an empty tag: an empty tag reads downstream as "nothing to
	// upgrade to", which would freeze such a box silently instead of telling
	// anyone.
	switch channel {
	case "stable", "prerelease":
		// fall through
	default:
		return "", fmt.Errorf("unknown channel %q (valid: stable, prerelease)", channel)
	}

	tags, err := DiscoverTagsViaGit(projDir)
	if err != nil {
		return "", fmt.Errorf("discover tags via git: %w", err)
	}
	return selectLatestTagFromNames(tagNames(tags), channel)
}

// tagNames projects the discovered tags to their names. Resolution needs only
// the name — every other field DiscoverTagsViaGit returns describes the commit,
// not the channel.
func tagNames(tags []GitTag) []string {
	out := make([]string, 0, len(tags))
	for _, t := range tags {
		out = append(out, t.TagName)
	}
	return out
}

// selectLatestTagFromNames is selectLatestTag's semantics over tag NAMES, with
// the channel decided by shape rather than by GitHub's flag.
//
// SEMANTICS PRESERVED EXACTLY, including the one that looks like a bug and is
// not: the prerelease channel means "latest RC", so it selects ONLY
// prerelease-shaped tags. A stable tag at HEAD must not beat the newest RC on a
// release-cutting day — that asymmetry is deliberate, and it is why the API
// path filtered explicitly rather than reusing its own channel filter, whose
// prerelease arm returned ALL releases.
//
// WHAT IS LOST WITH THE API, stated rather than discovered later: GitHub's
// DRAFT flag. A draft release publishes NO git tag, so a draft is invisible
// here — which is the behaviour we want (an unpublished draft must never be
// resolvable), reached by construction instead of by a filter.
func selectLatestTagFromNames(names []string, channel string) (string, error) {
	var filtered []string
	for _, name := range names {
		switch ClassifyReleaseShape(name) {
		case ShapeRelease:
			if channel == "stable" {
				filtered = append(filtered, name)
			}
		case ShapePrerelease:
			if channel == "prerelease" {
				filtered = append(filtered, name)
			}
		}
		// ShapeCommit / ShapeUnknown match no channel — same as the API path,
		// where a non-CalVer or odd-suffix tag was never a release either.
	}
	if len(filtered) == 0 {
		return "", fmt.Errorf("no %s release published", channel)
	}
	// Every surviving name is ShapeRelease or ShapePrerelease, both CalVer by
	// construction, so all of them are orderable. VERIFIED rather than assumed
	// (STATBUS-293): sorting is where an unorderable element does its damage
	// silently — sort.Slice's comparator cannot report a problem, so a pair
	// with no defined ordering would simply produce an arbitrary "latest"
	// release and no one would ever see why. Self-comparison is the cheapest
	// orderability probe: it consults the same gate CompareVersions applies.
	for _, name := range filtered {
		if _, ordered := CompareVersions(name, name); !ordered {
			return "", fmt.Errorf(
				"tag %q matches channel %s but has no CalVer ordering — refusing to choose a latest release from an unorderable set",
				name, channel)
		}
	}
	sort.Slice(filtered, func(i, j int) bool {
		ord, ordered := CompareVersions(filtered[i], filtered[j])
		return ordered && ord > 0
	})
	return filtered[0], nil
}

// calVerOrderableRegex matches exactly what CompareVersions can meaningfully
// order, AFTER that function's own leading-"v" normalization. It is
// deliberately NOT versionRegex: ValidateVersion answers "is this a
// well-formed release tag" (single leading v, required), while this answers
// the different question "can this participate in a CalVer ordering". The
// looser leading-v handling is inherited on purpose — CompareVersions has
// always TrimLeft'd, so a "vv2026..." string produced by the dev.sh /
// service.go double-v bug still orders exactly as it did before. Narrowing
// that here would fix nothing and would silently change a second behaviour
// while fixing the first.
var calVerOrderableRegex = regexp.MustCompile(`^\d{4}\.\d{2}\.\d+(-[\w.]+)?$`)

// CompareVersions reports the CalVer ordering of a and b: -1 if a < b, 0 if
// equal, 1 if a > b. The SECOND RETURN IS THE POINT: it is false when no such
// ordering exists, and the int is then meaningless and must not be read.
//
// WHY THE CONTRACT IS ENFORCED HERE AND NOT MERELY DOCUMENTED (STATBUS-293).
// This function used to state exactly the same precondition in prose — "both
// inputs MUST be CalVer release tags… passing a non-CalVer string produces an
// undefined (but non-panicking) ordering" — and then answer anyway, with a
// confident int, by falling through to LEXICAL comparison of the raw strings.
//
// That is how a box installed at commit 063d860a came to be offered every
// stable release back to v2026.03.0 as an "available upgrade": the segment
// compare reached Atoi("063d860a"), failed, fell back to comparing the TEXT
// "2026" against "063d860a", and concluded that a May release was newer than
// the code actually running. The answer inverted on the FIRST HEX CHARACTER of
// the installed commit — SHAs starting 0 or 1 sort below "2026" and offered
// downgrades; 3-9 and a-f sorted above and behaved correctly. A defect whose
// trigger is one random character produces months of green followed by an
// inexplicable red, which is precisely what it did.
//
// An undefined answer that is INDISTINGUISHABLE from a defined one is not a
// documented limitation; it is a wrong answer wearing the same clothes as a
// right one. A caller cannot guard against a hazard it cannot see, so the
// prose precondition put the burden on exactly the people least able to carry
// it — and four of the eight call sites did in fact get it wrong. The
// comparability flag moves that burden to the compiler: there is no longer a
// way to spell the unguarded call.
//
// Incomparability is NOT an error condition — a box installed from a commit is
// a perfectly normal, supported state — so this returns a bool rather than an
// error. The caller's job is not to report a failure; it is to choose the
// right behaviour for "these two things have no release ordering", which
// differs per site and is spelled out at each one.
func CompareVersions(a, b string) (ordering int, ordered bool) {
	// Normalize: strip leading "v" so "v2026.03.0" and "2026.03.0" compare equally.
	// Uses TrimLeft to also handle double-v ("vv2026...") from dev.sh + service.go bug.
	a = strings.TrimLeft(a, "v")
	b = strings.TrimLeft(b, "v")

	// THE GATE. Checked after normalization and before ANY comparison —
	// including the a == b fast path below, which would otherwise report two
	// identical commit SHAs as "equal versions". They are the same commit, but
	// that is not a statement about release ordering, and callers asking this
	// function are asking about release ordering.
	if !calVerOrderableRegex.MatchString(a) || !calVerOrderableRegex.MatchString(b) {
		return 0, false
	}

	if a == b {
		return 0, true
	}

	partsA := versionParts(a)
	partsB := versionParts(b)

	minLen := len(partsA)
	if len(partsB) < minLen {
		minLen = len(partsB)
	}

	for i := 0; i < minLen; i++ {
		numA, errA := strconv.Atoi(partsA[i])
		numB, errB := strconv.Atoi(partsB[i])
		if errA == nil && errB == nil {
			if numA < numB {
				return -1, true
			}
			if numA > numB {
				return 1, true
			}
			continue
		}
		// Lexical fallback, now REACHABLE ONLY for the suffix segments of two
		// gate-approved CalVer strings (e.g. "rc" vs "beta") — never for a
		// commit SHA, which the gate rejected before we got here. That is the
		// whole difference between this being a tie-break and it being the
		// STATBUS-293 defect.
		if partsA[i] < partsB[i] {
			return -1, true
		}
		if partsA[i] > partsB[i] {
			return 1, true
		}
	}

	// A version WITHOUT a prerelease suffix is NEWER than one with it.
	// v2026.03.0 > v2026.03.0-rc.17 (stable release supersedes all its RCs)
	if len(partsA) < len(partsB) {
		return 1, true
	}
	if len(partsA) > len(partsB) {
		return -1, true
	}
	return 0, true
}

// versionParts splits a version string into comparable segments.
// "v2026.03.0-rc.17" → ["v2026", "03", "0", "rc", "17"]
func versionParts(v string) []string {
	var parts []string
	current := ""
	for _, c := range v {
		if c == '.' || c == '-' {
			if current != "" {
				parts = append(parts, current)
			}
			current = ""
		} else {
			current += string(c)
		}
	}
	if current != "" {
		parts = append(parts, current)
	}
	return parts
}

// HasMigrationsFromChanges does a heuristic check on the release body.
func HasMigrationsFromChanges(body string) bool {
	lower := strings.ToLower(body)
	return strings.Contains(lower, "migration") || strings.Contains(lower, "migrate")
}

// GitTag represents a version tag discovered via git fetch.
//
// There is deliberately no Prerelease bool here: a tag's release/prerelease
// nature is NOT a stored property derived from "does the name contain a
// hyphen" (the old footgun). It is computed on demand from the tag's shape
// via ClassifyReleaseShape, the single shared classifier — so discovery, the
// channel filter, and the installer never disagree.
type GitTag struct {
	TagName     string
	CommitSHA   string
	PublishedAt time.Time
}

// DiscoverTagsViaGit fetches tags from the remote and returns parsed version tags.
// Uses git protocol — no API rate limit, works without GITHUB_TOKEN.
func DiscoverTagsViaGit(projDir string) ([]GitTag, error) {
	// Fetch latest tags from remote, pruning tags deleted upstream.
	// Without --prune-tags, deleted tags persist locally forever.
	// No --force: install-verified was deleted in rc.62, so there is no
	// moving tag to force-overwrite locally. A force here would have
	// hidden rune's rc.59/rc.60 root causes.
	if err := runCommand(projDir, "git", "fetch", "--tags", "--prune-tags"); err != nil {
		return nil, fmt.Errorf("git fetch --tags: %w", err)
	}

	// List version tags with SHA and creation date.
	// %(objectname) is the tag object SHA for annotated tags.
	// %(*objectname) is the dereferenced commit SHA (empty for lightweight tags).
	// %(creatordate:iso-strict) is the tag creation timestamp.
	out, err := runCommandOutput(projDir, "git", "tag", "-l", "v*",
		"--sort=-version:refname",
		"--format=%(refname:short)\t%(*objectname)\t%(objectname)\t%(creatordate:iso-strict)\t%(*committerdate:iso-strict)")
	if err != nil {
		return nil, fmt.Errorf("git tag -l: %w", err)
	}

	var tags []GitTag
	for _, line := range strings.Split(strings.TrimSpace(out), "\n") {
		if line == "" {
			continue
		}
		parts := strings.SplitN(line, "\t", 5)
		if len(parts) < 4 {
			continue
		}
		tagName := parts[0]
		// For annotated tags, *objectname is the commit SHA.
		// For lightweight tags, *objectname is empty — use objectname instead.
		commitSHA := parts[1]
		if commitSHA == "" {
			commitSHA = parts[2]
		}
		publishedAt, _ := time.Parse(time.RFC3339, parts[3])
		if len(parts) > 4 && parts[4] != "" {
			// Annotated tag: use the dereferenced commit date
			publishedAt, _ = time.Parse(time.RFC3339, parts[4])
		}

		if !ValidateVersion(tagName) {
			continue
		}

		tags = append(tags, GitTag{
			TagName:     tagName,
			CommitSHA:   commitSHA,
			PublishedAt: publishedAt,
		})
	}
	return tags, nil
}

// FilterTagsByChannel returns the tags whose SHAPE the given channel admits.
//
// Channels are EXCLUSIVE allowlists of tag shapes — a tag belongs to a channel
// only if its shape is explicitly admitted, never by default:
//   - stable     → clean CalVer release tags only (no suffix)
//   - prerelease → release-candidate tags only (-rc.N)
//
// The edge channel, which admitted both shapes for its binary self-update, is
// retired (King, 2026-08-19) and admits nothing: an unrecognised channel name
// matches NO tag, so a box carrying a stale value is offered nothing rather
// than being offered everything.
//
// Any other shape — a non-rc hyphenated tag (-beta/-foo/typo), a commit ref,
// or anything under an unrecognized channel name — matches NO channel and is
// never discovered as an installable upgrade. This is the guard against a
// stray hyphenated tag appearing one click from install on every prerelease
// box: pre-fix the prerelease branch returned ALL tags, so any future
// non-rc tag shape would have been offered there (dev included).
func FilterTagsByChannel(tags []GitTag, channel string) []GitTag {
	var out []GitTag
	for _, t := range tags {
		if TagMatchesChannel(t.TagName, channel) {
			out = append(out, t)
		}
	}
	return out
}

// TagMatchesChannel is the per-tag rule the filter above is built from, and it
// is exported because a second caller needs the SAME answer for ONE tag:
// scheduleStep announces when a deliberately named target is off the box's
// channel (STATBUS-291).
//
// It exists so there is exactly one definition of "on channel". Re-deriving
// that judgement at the announce site would let the two drift, and the failure
// would be silent in the worse direction — a deviation that stopped being
// announced because someone changed only the filter.
func TagMatchesChannel(tagName, channel string) bool {
	shape := ClassifyReleaseShape(tagName)
	switch channel {
	case "stable":
		return shape == ShapeRelease
	case "prerelease":
		return shape == ShapePrerelease
	}
	// Unrecognised channel (including the retired "edge") admits nothing —
	// a box carrying a stale value is offered nothing rather than everything.
	return false
}

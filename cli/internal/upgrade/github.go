// Package upgrade handles GitHub Releases discovery and upgrade execution.
package upgrade

import (
	"encoding/json"
	"fmt"
	"io"
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

// Release represents a GitHub Release.
type Release struct {
	TagName    string    `json:"tag_name"`
	Name       string    `json:"name"`
	Body       string    `json:"body"`
	Prerelease bool      `json:"prerelease"`
	Draft      bool      `json:"draft"`
	HTMLURL    string    `json:"html_url"`
	Published  time.Time `json:"published_at"`
	Assets     []Asset   `json:"assets"`
	TargetSHA  string    `json:"target_commitish"`
}

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

// FetchReleases queries the GitHub Releases API.
func FetchReleases() ([]Release, error) {
	url := fmt.Sprintf("https://api.github.com/repos/%s/%s/releases?per_page=30", owner, repo)
	req, err := githubRequest("GET", url)
	if err != nil {
		return nil, err
	}

	resp, err := githubDo(req)
	if err != nil {
		return nil, fmt.Errorf("fetch releases: %w", err)
	}
	defer func() { _ = resp.Body.Close() }()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("GitHub API returned %d: %s", resp.StatusCode, string(body))
	}

	var releases []Release
	if err := json.NewDecoder(resp.Body).Decode(&releases); err != nil {
		return nil, fmt.Errorf("decode releases: %w", err)
	}

	// Filter out drafts
	var filtered []Release
	for _, r := range releases {
		if !r.Draft {
			filtered = append(filtered, r)
		}
	}
	return filtered, nil
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

// FilterByChannel returns releases matching the given channel.
func FilterByChannel(releases []Release, channel string) []Release {
	switch channel {
	case "stable":
		var stable []Release
		for _, r := range releases {
			if !r.Prerelease {
				stable = append(stable, r)
			}
		}
		return stable
	case "prerelease":
		return releases // all releases
	// "pinned" channel removed — use skip in the UI instead
	default:
		return releases
	}
}

// selectLatestTag is the pure (no-network) logic that picks the latest
// release tag from an already-fetched set of releases. Returns:
//   - channel=edge       → ("", nil); caller handles "no artifact to check".
//   - channel=stable     → highest-CalVer non-prerelease release tag, or error if none.
//   - channel=prerelease → highest-CalVer prerelease tag, or error if none.
//   - unrecognised       → error listing accepted channels.
//
// Hermetic: the test suite drives selectLatestTag with canned
// []Release inputs; ResolveChannelToLatestTag wraps it with the
// network call.
func selectLatestTag(releases []Release, channel string) (string, error) {
	switch channel {
	case "edge":
		return "", nil
	case "stable", "prerelease":
		// fall through
	default:
		return "", fmt.Errorf("unknown channel %q (valid: stable, prerelease, edge)", channel)
	}

	// Filter. Note: FilterByChannel("prerelease") returns ALL releases
	// (both stable and prerelease). The operator-facing semantic of the
	// prerelease channel is "latest RC", so filter explicitly here —
	// otherwise a stable tag at HEAD would beat the newest RC on a
	// release-cutting day.
	var filtered []Release
	switch channel {
	case "stable":
		for _, r := range releases {
			if !r.Prerelease && !r.Draft {
				filtered = append(filtered, r)
			}
		}
	case "prerelease":
		for _, r := range releases {
			if r.Prerelease && !r.Draft {
				filtered = append(filtered, r)
			}
		}
	}
	if len(filtered) == 0 {
		return "", fmt.Errorf("no %s release published", channel)
	}
	// Sort newest-first via CompareVersions (CalVer+RC ordering).
	sort.Slice(filtered, func(i, j int) bool {
		return CompareVersions(filtered[i].TagName, filtered[j].TagName) > 0
	})
	return filtered[0].TagName, nil
}

// ResolveChannelToLatestTag resolves a channel name to the current
// latest release tag. Wraps selectLatestTag with the live GitHub API.
// See selectLatestTag for the resolution semantics per channel.
//
// This is the sole resolution site used by both install.sh (via
// `./sb install`) and `./sb release check --channel`, so the two
// stay aligned.
func ResolveChannelToLatestTag(channel string) (string, error) {
	if channel == "edge" {
		return "", nil
	}
	releases, err := FetchReleases()
	if err != nil {
		return "", fmt.Errorf("fetch releases: %w", err)
	}
	return selectLatestTag(releases, channel)
}

// ReleaseSummary returns a human-readable summary of a release.
func ReleaseSummary(r Release) string {
	name := r.Name
	if name == "" {
		name = r.TagName
	}
	pre := ""
	if r.Prerelease {
		pre = " (pre-release)"
	}
	return fmt.Sprintf("%s%s - %s", name, pre, r.Published.Format("2006-01-02"))
}

// Commit represents a GitHub commit (for edge channel discovery).
type Commit struct {
	SHA     string       `json:"sha"`
	HTMLURL string       `json:"html_url"`
	Commit  CommitDetail `json:"commit"`
}

// CommitDetail is the nested commit info from the GitHub API.
type CommitDetail struct {
	Message string `json:"message"`
}

// FetchCommits queries the GitHub Commits API for recent master commits.
func FetchCommits(count int) ([]Commit, error) {
	url := fmt.Sprintf("https://api.github.com/repos/%s/%s/commits?sha=master&per_page=%d", owner, repo, count)
	req, err := githubRequest("GET", url)
	if err != nil {
		return nil, err
	}

	resp, err := githubDo(req)
	if err != nil {
		return nil, fmt.Errorf("fetch commits: %w", err)
	}
	defer func() { _ = resp.Body.Close() }()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("GitHub API returned %d: %s", resp.StatusCode, string(body))
	}

	var commits []Commit
	if err := json.NewDecoder(resp.Body).Decode(&commits); err != nil {
		return nil, fmt.Errorf("decode commits: %w", err)
	}
	return commits, nil
}

// CompareVersions returns -1 if a < b, 0 if equal, 1 if a > b.
// Both inputs MUST be CalVer release tags — callers that hold untagged
// commit references should not reach here (they're not ordered by
// release version). Callers guard via ValidateVersion upstream;
// passing a non-CalVer string produces an undefined (but non-panicking)
// ordering derived from lexical segment comparison.
func CompareVersions(a, b string) int {
	// Normalize: strip leading "v" so "v2026.03.0" and "2026.03.0" compare equally.
	// Uses TrimLeft to also handle double-v ("vv2026...") from dev.sh + service.go bug.
	a = strings.TrimLeft(a, "v")
	b = strings.TrimLeft(b, "v")

	if a == b {
		return 0
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
				return -1
			}
			if numA > numB {
				return 1
			}
			continue
		}
		if partsA[i] < partsB[i] {
			return -1
		}
		if partsA[i] > partsB[i] {
			return 1
		}
	}

	// A version WITHOUT a prerelease suffix is NEWER than one with it.
	// v2026.03.0 > v2026.03.0-rc.17 (stable release supersedes all its RCs)
	if len(partsA) < len(partsB) {
		return 1
	}
	if len(partsA) > len(partsB) {
		return -1
	}
	return 0
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
//   - edge       → release + RC tags (the edge binary self-update tracks both)
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
		shape := ClassifyReleaseShape(t.TagName)
		var admit bool
		switch channel {
		case "stable":
			admit = shape == ShapeRelease
		case "prerelease":
			admit = shape == ShapePrerelease
		case "edge":
			admit = shape == ShapeRelease || shape == ShapePrerelease
		}
		if admit {
			out = append(out, t)
		}
	}
	return out
}

// GitCommit represents a commit discovered via git fetch for the edge channel.
type GitCommit struct {
	SHA         string
	PublishedAt time.Time
	Summary     string
}

// DiscoverCommitsViaGit fetches master and returns recent commits.
// Uses git protocol — no API rate limit.
func DiscoverCommitsViaGit(projDir string, count int) ([]GitCommit, error) {
	// Fetch latest master from remote
	if err := runCommand(projDir, "git", "fetch", "origin", "master", "--quiet"); err != nil {
		return nil, fmt.Errorf("git fetch origin master: %w", err)
	}

	// Get recent commits: SHA, author date (ISO), and subject line
	out, err := runCommandOutput(projDir, "git", "log", "origin/master",
		fmt.Sprintf("--format=%%H\t%%aI\t%%s"),
		fmt.Sprintf("-n%d", count))
	if err != nil {
		return nil, fmt.Errorf("git log: %w", err)
	}

	var commits []GitCommit
	for _, line := range strings.Split(strings.TrimSpace(out), "\n") {
		if line == "" {
			continue
		}
		parts := strings.SplitN(line, "\t", 3)
		if len(parts) < 3 {
			continue
		}
		publishedAt, _ := time.Parse(time.RFC3339, parts[1])
		commits = append(commits, GitCommit{
			SHA:         parts[0],
			PublishedAt: publishedAt,
			Summary:     parts[2],
		})
	}
	return commits, nil
}

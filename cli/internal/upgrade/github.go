// Package upgrade handles GitHub Releases discovery and upgrade execution.
package upgrade

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"regexp"
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
	Version    string            `json:"version"`
	CommitSHA  string            `json:"commit_sha"`
	Prerelease bool              `json:"prerelease"`
	Images     map[string]string `json:"images"`
	HasMigrations bool           `json:"has_migrations"`
	Binaries   map[string]struct {
		URL    string `json:"url"`
		SHA256 string `json:"sha256"`
	} `json:"binaries"`
}

// versionRegex validates version tags and commit SHAs.
var versionRegex = regexp.MustCompile(`^(v\d{4}\.\d{2}\.\d+(-[\w.]+)?|sha-[a-f0-9]{7,40})$`)

// ValidateVersion checks if a version string is valid.
func ValidateVersion(v string) bool {
	return versionRegex.MatchString(v)
}

// githubRequest creates an HTTP request with optional auth from GITHUB_TOKEN env var.
// Authenticated requests get 5000 req/hr instead of 60 req/hr.
func githubRequest(method, url string) (*http.Request, error) {
	req, err := http.NewRequest(method, url, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("User-Agent", "statbus-upgrade-daemon")
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
			resp.Body.Close()
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
	defer resp.Body.Close()

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
	defer resp.Body.Close()

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
	defer resp.Body.Close()

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
// For CalVer tags (vYYYY.MM.PATCH-rc.N): parses numeric segments for correct ordering.
// For SHA tags: returns 0 (incomparable without git history — use CompareByCommitOrder instead).
func CompareVersions(a, b string) int {
	if a == b {
		return 0
	}
	// SHA tags have no inherent ordering — they need git ancestry comparison.
	if strings.HasPrefix(a, "sha-") || strings.HasPrefix(b, "sha-") {
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
type GitTag struct {
	TagName     string
	CommitSHA   string
	PublishedAt time.Time
	Prerelease  bool
}

// DiscoverTagsViaGit fetches tags from the remote and returns parsed version tags.
// Uses git protocol — no API rate limit, works without GITHUB_TOKEN.
func DiscoverTagsViaGit(projDir string) ([]GitTag, error) {
	// Fetch latest tags from remote, pruning tags deleted upstream.
	// Without --prune-tags, deleted tags persist locally forever.
	if err := runCommand(projDir, "git", "fetch", "--tags", "--prune-tags", "--force", "--quiet"); err != nil {
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

		prerelease := strings.Contains(tagName, "-")

		tags = append(tags, GitTag{
			TagName:     tagName,
			CommitSHA:   commitSHA,
			PublishedAt: publishedAt,
			Prerelease:  prerelease,
		})
	}
	return tags, nil
}

// FilterTagsByChannel returns tags matching the given channel.
func FilterTagsByChannel(tags []GitTag, channel string) []GitTag {
	if channel == "stable" {
		var stable []GitTag
		for _, t := range tags {
			if !t.Prerelease {
				stable = append(stable, t)
			}
		}
		return stable
	}
	return tags // prerelease: all tags
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

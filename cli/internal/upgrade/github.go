// Package upgrade handles GitHub Releases discovery and upgrade execution.
package upgrade

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"regexp"
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

// FetchReleases queries the GitHub Releases API.
func FetchReleases() ([]Release, error) {
	url := fmt.Sprintf("https://api.github.com/repos/%s/%s/releases?per_page=30", owner, repo)
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("User-Agent", "statbus-upgrade-daemon")

	resp, err := http.DefaultClient.Do(req)
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
func FetchManifest(version string) (*Manifest, error) {
	url := fmt.Sprintf("https://github.com/%s/%s/releases/download/%s/release-manifest.json", owner, repo, version)
	resp, err := http.Get(url)
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
	case "pinned":
		return nil // no discovery
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

// HasMigrationsFromChanges does a heuristic check on the release body.
func HasMigrationsFromChanges(body string) bool {
	lower := strings.ToLower(body)
	return strings.Contains(lower, "migration") || strings.Contains(lower, "migrate")
}

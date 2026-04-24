// Package release provides artifact-readiness probes for StatBus releases.
package release

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"
)

const (
	githubOrg = "statisticsnorway"
	githubRepo = "statbus"
)

// CheckResult records the outcome of one readiness probe.
type CheckResult struct {
	Name string
	OK   bool
	Err  string
}

// requiredAssets is the full list of assets uploaded by the create-release job
// in .github/workflows/release.yaml.
var requiredAssets = []string{
	"sb-linux-amd64",
	"sb-linux-arm64",
	"sb-darwin-amd64",
	"sb-darwin-arm64",
	"checksums.txt",
	"release-manifest.json",
	"snapshot.pg_dump",
	"snapshot.json",
}

// dockerServices are the four images built by release.yaml's build-images job.
var dockerServices = []string{"app", "db", "worker", "proxy"}

// CheckAssets verifies that all expected GitHub Release assets for the given
// tag are present. tag must be a full version string (e.g. "v2026.04.0-rc.9").
func CheckAssets(tag string) []CheckResult {
	return checkAssetsAt("https://api.github.com", tag)
}

// CheckManifests verifies that all four Docker images for the given tag exist
// on ghcr.io. Checks run in parallel.
//
// Image lookup strategy (rc.63+):
//
//  1. Resolve tag → commit_sha via the GitHub API once, up front. Trim to
//     8-char commit_short. This is the canonical image tag produced by
//     .github/workflows/release.yaml (one image per commit identity, no
//     CalVer-tagged variant).
//  2. For each image, HEAD the manifest at commit_short first.
//  3. On 404, HEAD the manifest at the CalVer tag itself — backward compat
//     for rc.61 and earlier releases, where images were tagged by both
//     commit_short AND the CalVer tag.
//
// If tag→commit_short resolution fails entirely (GitHub unreachable, tag
// doesn't exist), per-image checks fall back to pure-CalVer lookup.
func CheckManifests(tag string) []CheckResult {
	return checkManifestsAt("https://api.github.com", "https://ghcr.io", tag)
}

// checkAssetsAt is the testable inner variant; apiBase is the GitHub API root.
func checkAssetsAt(apiBase, tag string) []CheckResult {
	url := fmt.Sprintf("%s/repos/%s/%s/releases/tags/%s", apiBase, githubOrg, githubRepo, tag)
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return errorResults(assetNames(), fmt.Sprintf("build request: %v", err))
	}
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("User-Agent", "statbus-release-check")
	if auth := githubAuthHeader(); auth != "" {
		req.Header.Set("Authorization", auth)
	}

	resp, err := httpClient().Do(req)
	if err != nil {
		return errorResults(assetNames(), fmt.Sprintf("request failed: %v", err))
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusNotFound {
		return errorResults(assetNames(), fmt.Sprintf("tag %s not found on GitHub", tag))
	}
	if resp.StatusCode != http.StatusOK {
		return errorResults(assetNames(), fmt.Sprintf("GitHub API returned HTTP %d", resp.StatusCode))
	}

	var release struct {
		Assets []struct {
			Name string `json:"name"`
		} `json:"assets"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&release); err != nil {
		return errorResults(assetNames(), fmt.Sprintf("decode response: %v", err))
	}

	present := make(map[string]bool, len(release.Assets))
	for _, a := range release.Assets {
		present[a.Name] = true
	}

	results := make([]CheckResult, len(requiredAssets))
	for i, name := range requiredAssets {
		if present[name] {
			results[i] = CheckResult{Name: "asset: " + name, OK: true}
		} else {
			results[i] = CheckResult{Name: "asset: " + name, OK: false, Err: "not uploaded yet"}
		}
	}
	return results
}

// checkManifestsAt is the testable inner variant; apiBase is the GitHub
// API root (for commit_short resolution), registryBase is the OCI
// registry root (e.g. "https://ghcr.io").
//
// Resolves the CalVer tag to commit_short once up front, then runs
// per-image checks in parallel. Each per-image check tries commit_short
// first and falls back to the CalVer tag on 404 (backward compat for
// rc.61 and earlier).
func checkManifestsAt(apiBase, registryBase, tag string) []CheckResult {
	// Best-effort resolution; empty commitShort disables the commit_short
	// probe and leaves only the CalVer fallback (matches pre-rc.63
	// behaviour).
	commitShort, resolveErr := resolveTagToCommitShort(apiBase, tag)

	results := make([]CheckResult, len(dockerServices))
	var wg sync.WaitGroup
	for i, svc := range dockerServices {
		wg.Add(1)
		go func(i int, svc string) {
			defer wg.Done()
			image := fmt.Sprintf("%s/statbus-%s", githubOrg, svc)
			results[i] = checkManifest(registryBase, image, tag, commitShort, resolveErr)
		}(i, svc)
	}
	wg.Wait()
	return results
}

// resolveTagToCommitShort resolves a CalVer tag name (e.g. "v2026.04.0-rc.62")
// to its 8-char commit_short via the GitHub API. Works for both lightweight
// and annotated tags (the /commits/{ref} endpoint dereferences either).
func resolveTagToCommitShort(apiBase, tag string) (string, error) {
	url := fmt.Sprintf("%s/repos/%s/%s/commits/%s", apiBase, githubOrg, githubRepo, tag)
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return "", fmt.Errorf("build request: %w", err)
	}
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("User-Agent", "statbus-release-check")
	if auth := githubAuthHeader(); auth != "" {
		req.Header.Set("Authorization", auth)
	}
	resp, err := httpClient().Do(req)
	if err != nil {
		return "", fmt.Errorf("request failed: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("GitHub API returned HTTP %d", resp.StatusCode)
	}
	var body struct {
		SHA string `json:"sha"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
		return "", fmt.Errorf("decode response: %w", err)
	}
	if len(body.SHA) < 8 {
		return "", fmt.Errorf("unexpected short SHA from API: %q", body.SHA)
	}
	return body.SHA[:8], nil
}

// checkManifest probes a single image by commit_short first (rc.63+ image
// tag scheme), falling back to CalVer on 404 (rc.61 and earlier, where
// release.yaml still published CalVer-tagged image variants). The display
// name reflects which tag form succeeded so the operator sees the physical
// lookup.
//
// resolveErr is non-nil when commit_short resolution failed earlier; in
// that case the function skips the commit_short probe and attempts only
// the CalVer fallback. commitShort is "" when resolveErr != nil.
func checkManifest(registryBase, image, calverTag, commitShort string, resolveErr error) CheckResult {
	parts := strings.SplitN(image, "/", 2)
	shortName := image
	if len(parts) == 2 {
		shortName = parts[1]
	}

	token, err := ghcrPullToken(registryBase, image)
	if err != nil {
		return CheckResult{
			Name: fmt.Sprintf("image: %s:%s", shortName, calverTag),
			OK:   false,
			Err:  fmt.Sprintf("auth: %v", err),
		}
	}

	// Phase 1: try commit_short (rc.63+ canonical). Skip if resolution
	// failed earlier.
	if commitShort != "" {
		status, err := headManifest(registryBase, image, commitShort, token)
		if err == nil && status == http.StatusOK {
			return CheckResult{
				Name: fmt.Sprintf("image: %s:%s → sha %s", shortName, calverTag, commitShort),
				OK:   true,
			}
		}
		// Fall through to CalVer only on 404 — other errors (network,
		// auth, 5xx) are genuine and should not be masked by a second
		// attempt.
		if err != nil {
			return CheckResult{
				Name: fmt.Sprintf("image: %s:%s → sha %s", shortName, calverTag, commitShort),
				OK:   false,
				Err:  fmt.Sprintf("commit_short probe failed: %v", err),
			}
		}
		if status != http.StatusNotFound {
			return CheckResult{
				Name: fmt.Sprintf("image: %s:%s → sha %s", shortName, calverTag, commitShort),
				OK:   false,
				Err:  fmt.Sprintf("commit_short probe: HTTP %d", status),
			}
		}
		// 404 on commit_short → fall through to CalVer backward-compat path.
	}

	// Phase 2: try CalVer tag (rc.61 and earlier). Also the sole probe
	// when commit_short resolution failed.
	status, err := headManifest(registryBase, image, calverTag, token)
	if err != nil {
		return CheckResult{
			Name: fmt.Sprintf("image: %s:%s", shortName, calverTag),
			OK:   false,
			Err:  fmt.Sprintf("request failed: %v", err),
		}
	}
	if status == http.StatusOK {
		return CheckResult{
			Name: fmt.Sprintf("image: %s:%s (legacy CalVer tag)", shortName, calverTag),
			OK:   true,
		}
	}
	// Both probes failed. Surface a message that names both attempts
	// when commit_short resolution succeeded; name only the CalVer
	// attempt otherwise.
	if commitShort != "" {
		return CheckResult{
			Name: fmt.Sprintf("image: %s:%s → sha %s", shortName, calverTag, commitShort),
			OK:   false,
			Err:  fmt.Sprintf("not found at commit_short or CalVer tag (HTTP %d)", status),
		}
	}
	reason := fmt.Sprintf("HTTP %d", status)
	if resolveErr != nil {
		reason = fmt.Sprintf("commit_short unresolved (%v); CalVer HTTP %d", resolveErr, status)
	}
	return CheckResult{
		Name: fmt.Sprintf("image: %s:%s", shortName, calverTag),
		OK:   false,
		Err:  reason,
	}
}

// headManifest issues a HEAD against the OCI manifest endpoint and returns
// the status code. Separated from checkManifest for reuse across the
// commit_short probe and the CalVer fallback.
func headManifest(registryBase, image, tag, token string) (int, error) {
	url := fmt.Sprintf("%s/v2/%s/manifests/%s", registryBase, image, tag)
	req, err := http.NewRequest("HEAD", url, nil)
	if err != nil {
		return 0, fmt.Errorf("build request: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Accept", strings.Join([]string{
		"application/vnd.oci.image.index.v1+json",
		"application/vnd.docker.distribution.manifest.list.v2+json",
		"application/vnd.docker.distribution.manifest.v2+json",
	}, ","))
	resp, err := httpClient().Do(req)
	if err != nil {
		return 0, err
	}
	resp.Body.Close()
	return resp.StatusCode, nil
}

// ghcrPullToken returns a bearer token for pulling from the given registry.
// Uses GITHUB_TOKEN if set (works directly with ghcr.io); otherwise performs
// an anonymous token exchange with the registry token endpoint.
func ghcrPullToken(registryBase, image string) (string, error) {
	if tok := os.Getenv("GITHUB_TOKEN"); tok != "" {
		return tok, nil
	}
	// Anonymous token exchange — scope is per-image.
	url := fmt.Sprintf("%s/token?scope=repository:%s:pull&service=ghcr.io", registryBase, image)
	resp, err := httpClient().Do(mustGET(url))
	if err != nil {
		return "", fmt.Errorf("token endpoint: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("token endpoint returned HTTP %d", resp.StatusCode)
	}
	var tok struct {
		Token string `json:"token"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&tok); err != nil {
		return "", fmt.Errorf("decode token: %w", err)
	}
	if tok.Token == "" {
		return "", fmt.Errorf("empty token in response")
	}
	return tok.Token, nil
}

// httpClient returns a shared client with a reasonable timeout.
func httpClient() *http.Client {
	return &http.Client{Timeout: 15 * time.Second}
}

func githubAuthHeader() string {
	if tok := os.Getenv("GITHUB_TOKEN"); tok != "" {
		return "Bearer " + tok
	}
	return ""
}

// assetNames returns the display names for all required assets (used in
// error-result construction before we know which assets exist).
func assetNames() []string {
	names := make([]string, len(requiredAssets))
	for i, a := range requiredAssets {
		names[i] = "asset: " + a
	}
	return names
}

func errorResults(names []string, msg string) []CheckResult {
	out := make([]CheckResult, len(names))
	for i, n := range names {
		out[i] = CheckResult{Name: n, OK: false, Err: msg}
	}
	return out
}

func mustGET(url string) *http.Request {
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		panic(fmt.Sprintf("mustGET(%q): %v", url, err))
	}
	return req
}

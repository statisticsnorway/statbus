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
func CheckManifests(tag string) []CheckResult {
	return checkManifestsAt("https://ghcr.io", tag)
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

// checkManifestsAt is the testable inner variant; registryBase is the OCI
// registry root (e.g. "https://ghcr.io").
func checkManifestsAt(registryBase, tag string) []CheckResult {
	results := make([]CheckResult, len(dockerServices))
	var wg sync.WaitGroup
	for i, svc := range dockerServices {
		wg.Add(1)
		go func(i int, svc string) {
			defer wg.Done()
			image := fmt.Sprintf("%s/statbus-%s", githubOrg, svc)
			results[i] = checkManifest(registryBase, image, tag)
		}(i, svc)
	}
	wg.Wait()
	return results
}

func checkManifest(registryBase, image, tag string) CheckResult {
	// Display name: just the image short name + tag (e.g. "statbus-app:v2026.04.0-rc.9")
	parts := strings.SplitN(image, "/", 2)
	shortName := image
	if len(parts) == 2 {
		shortName = parts[1]
	}
	name := fmt.Sprintf("image: %s:%s", shortName, tag)

	token, err := ghcrPullToken(registryBase, image)
	if err != nil {
		return CheckResult{Name: name, OK: false, Err: fmt.Sprintf("auth: %v", err)}
	}

	url := fmt.Sprintf("%s/v2/%s/manifests/%s", registryBase, image, tag)
	req, err := http.NewRequest("HEAD", url, nil)
	if err != nil {
		return CheckResult{Name: name, OK: false, Err: fmt.Sprintf("build request: %v", err)}
	}
	req.Header.Set("Authorization", "Bearer "+token)
	// Accept multi-arch index and single-arch manifests.
	req.Header.Set("Accept", strings.Join([]string{
		"application/vnd.oci.image.index.v1+json",
		"application/vnd.docker.distribution.manifest.list.v2+json",
		"application/vnd.docker.distribution.manifest.v2+json",
	}, ","))

	resp, err := httpClient().Do(req)
	if err != nil {
		return CheckResult{Name: name, OK: false, Err: fmt.Sprintf("request failed: %v", err)}
	}
	resp.Body.Close()

	if resp.StatusCode == http.StatusOK {
		return CheckResult{Name: name, OK: true}
	}
	return CheckResult{Name: name, OK: false, Err: fmt.Sprintf("HTTP %d", resp.StatusCode)}
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

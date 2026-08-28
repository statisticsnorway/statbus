package upgrade

import (
	"encoding/json"
	"fmt"
	"net/http"
	"time"
)

// ghcrRegistryBase is the ghcr.io host, overridable per-call so tests can
// point at an httptest server instead of the real registry. Passed
// explicitly rather than as a package var: the probe has no other state,
// and an explicit parameter needs no save/restore around concurrent tests.
const ghcrRegistryBase = "https://ghcr.io"

// GhcrProbeStatus is the tri-state result of a ghcr.io manifest-existence
// probe (STATBUS-302 architect ruling comment #1): BUILT / NOT BUILT /
// COULD NOT DETERMINE. The third is not a flavour of the second — callers
// MUST NOT treat ghcrIndeterminate as evidence of absence. A failure to
// observe is not evidence about the observed.
type GhcrProbeStatus int

const (
	// ghcrPresent: the registry confirmed the manifest exists (HTTP 200).
	ghcrPresent GhcrProbeStatus = iota
	// ghcrAbsent: the registry confirmed the manifest does NOT exist
	// (HTTP 404) — a real, positive observation, not a guess.
	ghcrAbsent
	// ghcrIndeterminate: the probe itself could not complete (anonymous
	// token fetch failed, network error, an unexpected HTTP status). This
	// is a statement about the PROBE, never about the image.
	ghcrIndeterminate
)

// ghcrAnonymousToken fetches a short-lived pull-scope bearer token for
// owner/image with NO credentials. STATBUS-302: verified empirically
// (2026-08-28) that ghcr.io requires this token dance even for a fully
// public package — a bare unauthenticated manifest HEAD always 401s with
// `www-authenticate: Bearer realm="https://ghcr.io/token",...` — but the
// token endpoint itself needs no GITHUB_TOKEN, no docker login, nothing:
// the same no-credential posture as FetchManifest (github.go), just a
// different registry and a mandatory extra round trip.
func ghcrAnonymousToken(registryBase, owner, image string) (string, error) {
	tokenURL := fmt.Sprintf("%s/token?service=ghcr.io&scope=repository:%s/%s:pull", registryBase, owner, image)
	req, err := http.NewRequest(http.MethodGet, tokenURL, nil)
	if err != nil {
		return "", fmt.Errorf("build ghcr token request: %w", err)
	}
	client := &http.Client{Timeout: 15 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return "", fmt.Errorf("ghcr anonymous token fetch: %w", err)
	}
	defer func() { _ = resp.Body.Close() }()
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("ghcr anonymous token fetch: HTTP %d", resp.StatusCode)
	}
	var body struct {
		Token string `json:"token"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
		return "", fmt.Errorf("ghcr anonymous token decode: %w", err)
	}
	if body.Token == "" {
		return "", fmt.Errorf("ghcr anonymous token: empty token in response")
	}
	return body.Token, nil
}

// ghcrManifestExists reports whether a manifest exists for
// ghcr.io/owner/image:tag using the anonymous two-step: fetch a pull-scope
// token with no credentials, then HEAD the manifest with that bearer.
//
// Returns (ghcrPresent, nil) on HTTP 200, (ghcrAbsent, nil) on HTTP 404
// (confirmed empirically to be a clean 404 with the SAME anonymous token,
// not another 401 — so 404 really does mean "not built", not "probe
// unauthorized"), and (ghcrIndeterminate, err) for anything else. Callers
// must act on ghcrIndeterminate exactly as they would on "no information":
// never as a build failure.
func ghcrManifestExists(registryBase, owner, image, tag string) (GhcrProbeStatus, error) {
	token, err := ghcrAnonymousToken(registryBase, owner, image)
	if err != nil {
		return ghcrIndeterminate, err
	}

	manifestURL := fmt.Sprintf("%s/v2/%s/%s/manifests/%s", registryBase, owner, image, tag)
	req, err := http.NewRequest(http.MethodHead, manifestURL, nil)
	if err != nil {
		return ghcrIndeterminate, fmt.Errorf("build ghcr manifest request: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+token)
	// Accept both OCI and legacy Docker manifest/index media types — our
	// images are multi-arch indexes (confirmed: the live probe returned
	// application/vnd.oci.image.index.v1+json), but a single-platform
	// manifest is equally a valid "present" answer.
	req.Header.Set("Accept", "application/vnd.oci.image.index.v1+json, "+
		"application/vnd.oci.image.manifest.v1+json, "+
		"application/vnd.docker.distribution.manifest.list.v2+json, "+
		"application/vnd.docker.distribution.manifest.v2+json")
	client := &http.Client{Timeout: 15 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return ghcrIndeterminate, fmt.Errorf("ghcr manifest HEAD: %w", err)
	}
	defer func() { _ = resp.Body.Close() }()

	switch resp.StatusCode {
	case http.StatusOK:
		return ghcrPresent, nil
	case http.StatusNotFound:
		return ghcrAbsent, nil
	default:
		return ghcrIndeterminate, fmt.Errorf("ghcr manifest HEAD: unexpected HTTP %d", resp.StatusCode)
	}
}

// probeAllImagesGhcr checks every service's image manifest for tag and
// collapses the per-service results to one verdict:
//
//   - ghcrAbsent, nil        — at least one image is confirmed absent, and
//     no probe in the set was indeterminate (checked in order; an absent
//     result short-circuits immediately, matching "not all present" needing
//     only one counterexample).
//   - ghcrIndeterminate, err — a probe could not complete before a
//     conclusive absent was found; err names which image and why.
//   - ghcrPresent, nil       — every service's image is confirmed present.
//
// STATBUS-302: used only where the caller already knows (via some other
// check) that not every image is present yet — this function's job is
// narrowly to tell an ALREADY-established "not ready" apart from a probe
// that simply couldn't run, never to re-decide readiness on its own.
func probeAllImagesGhcr(registryBase, owner string, services []string, tag string) (GhcrProbeStatus, error) {
	for _, svc := range services {
		image := "statbus-" + svc
		status, err := ghcrManifestExists(registryBase, owner, image, tag)
		switch status {
		case ghcrIndeterminate:
			return ghcrIndeterminate, fmt.Errorf("%s: %w", image, err)
		case ghcrAbsent:
			return ghcrAbsent, nil
		}
	}
	return ghcrPresent, nil
}

package release

import (
	"encoding/json"
	"net"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// ---- helpers ----------------------------------------------------------------

func allOK(results []CheckResult) bool {
	for _, r := range results {
		if !r.OK {
			return false
		}
	}
	return true
}

func countFailed(results []CheckResult) int {
	n := 0
	for _, r := range results {
		if !r.OK {
			n++
		}
	}
	return n
}

// releaseJSON builds a minimal GitHub release API response with the given asset names.
func releaseJSON(assets []string) []byte {
	type asset struct {
		Name string `json:"name"`
	}
	type release struct {
		TagName string  `json:"tag_name"`
		Assets  []asset `json:"assets"`
	}
	a := make([]asset, len(assets))
	for i, name := range assets {
		a[i] = asset{Name: name}
	}
	b, _ := json.Marshal(release{TagName: "v2026.04.0-rc.9", Assets: a})
	return b
}

// ghcrServer builds a test server that mimics the ghcr.io token + manifest endpoints.
// presentImages: set of image names (e.g. "statisticsnorway/statbus-app") whose
// manifests should return 200; all others return 404.
func ghcrServer(t *testing.T, presentImages map[string]bool) *httptest.Server {
	t.Helper()
	return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Token endpoint: always issue a dummy token.
		if r.URL.Path == "/token" {
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`{"token":"test-token"}`))
			return
		}
		// Manifest endpoint: /v2/<org>/<image>/manifests/<tag>
		// Extract the image name from the path.
		// Path looks like /v2/statisticsnorway/statbus-app/manifests/vX
		// We consider everything between /v2/ and /manifests/ as the image.
		path := r.URL.Path
		const v2 = "/v2/"
		const mfst = "/manifests/"
		if len(path) > len(v2) {
			after := path[len(v2):]
			if idx := lastIndex(after, mfst); idx >= 0 {
				image := after[:idx]
				if presentImages[image] {
					w.WriteHeader(http.StatusOK)
				} else {
					w.WriteHeader(http.StatusNotFound)
				}
				return
			}
		}
		w.WriteHeader(http.StatusNotFound)
	}))
}

func lastIndex(s, sep string) int {
	idx := -1
	for i := 0; i <= len(s)-len(sep); i++ {
		if s[i:i+len(sep)] == sep {
			idx = i
		}
	}
	return idx
}

// ---- CheckAssets tests ------------------------------------------------------

func TestCheckAssets_HappyPath(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Write(releaseJSON(requiredAssets))
	}))
	defer srv.Close()

	results := checkAssetsAt(srv.URL, "v2026.04.0-rc.9")
	if !allOK(results) {
		t.Fatalf("expected all assets OK, got: %+v", results)
	}
	if len(results) != len(requiredAssets) {
		t.Fatalf("expected %d results, got %d", len(requiredAssets), len(results))
	}
}

func TestCheckAssets_MissingTag(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNotFound)
	}))
	defer srv.Close()

	results := checkAssetsAt(srv.URL, "v2026.04.0-rc.99")
	if countFailed(results) != len(requiredAssets) {
		t.Fatalf("expected all %d results to fail on 404, got %d failed",
			len(requiredAssets), countFailed(results))
	}
	// All error messages should mention "not found"
	for _, r := range results {
		if r.OK {
			t.Errorf("expected %q to be failed", r.Name)
		}
	}
}

func TestCheckAssets_MissingOneAsset(t *testing.T) {
	// All assets except "sb-darwin-arm64"
	present := make([]string, 0, len(requiredAssets)-1)
	for _, a := range requiredAssets {
		if a != "sb-darwin-arm64" {
			present = append(present, a)
		}
	}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Write(releaseJSON(present))
	}))
	defer srv.Close()

	results := checkAssetsAt(srv.URL, "v2026.04.0-rc.9")
	if countFailed(results) != 1 {
		t.Fatalf("expected exactly 1 failure, got %d: %+v", countFailed(results), results)
	}
	for _, r := range results {
		if !r.OK && r.Name != "asset: sb-darwin-arm64" {
			t.Errorf("unexpected failure on %q", r.Name)
		}
	}
}

func TestCheckAssets_NetworkError(t *testing.T) {
	// Use a port with no listener — connection refused.
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	addr := "http://" + ln.Addr().String()
	ln.Close() // close immediately so connections are refused

	results := checkAssetsAt(addr, "v2026.04.0-rc.9")
	if countFailed(results) != len(requiredAssets) {
		t.Fatalf("expected all results to fail on network error, got %d failed",
			countFailed(results))
	}
}

// ---- CheckManifests tests ---------------------------------------------------

func allImages(present bool) map[string]bool {
	m := make(map[string]bool, len(dockerServices))
	for _, svc := range dockerServices {
		m[githubOrg+"/statbus-"+svc] = present
	}
	return m
}

// ghcrServerWithTags extends ghcrServer to accept a per-image map of
// ALLOWED TAGS. A manifest lookup returns 200 only when the image is
// present AND the tag is in its allowed-tags set; otherwise 404. Used
// to simulate rc.63's commit_short-only images vs. rc.61's CalVer-only.
func ghcrServerWithTags(t *testing.T, allowed map[string]map[string]bool) *httptest.Server {
	t.Helper()
	return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/token" {
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`{"token":"test-token"}`))
			return
		}
		path := r.URL.Path
		const v2 = "/v2/"
		const mfst = "/manifests/"
		if len(path) > len(v2) {
			after := path[len(v2):]
			if idx := lastIndex(after, mfst); idx >= 0 {
				image := after[:idx]
				tag := after[idx+len(mfst):]
				if tags, ok := allowed[image]; ok && tags[tag] {
					w.WriteHeader(http.StatusOK)
					return
				}
				w.WriteHeader(http.StatusNotFound)
				return
			}
		}
		w.WriteHeader(http.StatusNotFound)
	}))
}

// apiServer mocks the GitHub /repos/*/commits/{tag} endpoint. tagToSHA
// maps CalVer tag → full 40-char commit SHA; unknown tags return 404.
func apiServer(t *testing.T, tagToSHA map[string]string) *httptest.Server {
	t.Helper()
	return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		const prefix = "/repos/statisticsnorway/statbus/commits/"
		if !strings.HasPrefix(r.URL.Path, prefix) {
			w.WriteHeader(http.StatusNotFound)
			return
		}
		tag := r.URL.Path[len(prefix):]
		sha, ok := tagToSHA[tag]
		if !ok {
			w.WriteHeader(http.StatusNotFound)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"sha":"` + sha + `"}`))
	}))
}

// TestCheckManifests_NewStyleCommitShort covers the rc.63+ canonical
// path: GitHub API resolves the CalVer tag to a commit_sha; images are
// tagged by commit_short (first 8 chars) only; the CalVer-tagged lookup
// returns 404 (because rc.63+ release.yaml doesn't push that variant).
func TestCheckManifests_NewStyleCommitShort(t *testing.T) {
	api := apiServer(t, map[string]string{
		"v2026.04.0-rc.63": "e2355634abcdef0123456789abcdef0123456789",
	})
	defer api.Close()

	allowed := map[string]map[string]bool{}
	for _, svc := range dockerServices {
		allowed[githubOrg+"/statbus-"+svc] = map[string]bool{"e2355634": true}
	}
	registry := ghcrServerWithTags(t, allowed)
	defer registry.Close()

	results := checkManifestsAt(api.URL, registry.URL, "v2026.04.0-rc.63")
	if !allOK(results) {
		t.Fatalf("expected all manifests OK via commit_short, got: %+v", results)
	}
	// Display names must expose both the logical tag and the physical
	// commit_short so the operator sees what was actually checked.
	for _, r := range results {
		if !strings.Contains(r.Name, "v2026.04.0-rc.63") || !strings.Contains(r.Name, "e2355634") {
			t.Errorf("expected display to include both CalVer and commit_short; got %q", r.Name)
		}
	}
}

// TestCheckManifests_OldStyleCalverFallback covers backward compat for
// rc.61 and earlier: commit_short lookup 404s (rc.61's release.yaml
// didn't push commit_short variants for every image, or the image was
// never pushed to ghcr); CalVer lookup succeeds. The fallback kicks in.
func TestCheckManifests_OldStyleCalverFallback(t *testing.T) {
	api := apiServer(t, map[string]string{
		"v2026.04.0-rc.61": "a1b2c3d4deadbeefcafebabe0000000000000000",
	})
	defer api.Close()

	allowed := map[string]map[string]bool{}
	for _, svc := range dockerServices {
		// Only CalVer tag present, not commit_short.
		allowed[githubOrg+"/statbus-"+svc] = map[string]bool{"v2026.04.0-rc.61": true}
	}
	registry := ghcrServerWithTags(t, allowed)
	defer registry.Close()

	results := checkManifestsAt(api.URL, registry.URL, "v2026.04.0-rc.61")
	if !allOK(results) {
		t.Fatalf("expected CalVer fallback to succeed, got: %+v", results)
	}
	// Display should explicitly mark "legacy CalVer tag" so operators
	// know the backward-compat path was taken.
	for _, r := range results {
		if !strings.Contains(r.Name, "legacy CalVer tag") {
			t.Errorf("expected 'legacy CalVer tag' marker in display; got %q", r.Name)
		}
	}
}

// TestCheckManifests_AllMissing_BothProbesFail covers the hard-error
// case: commit_short and CalVer both 404. Error message should name
// both attempts.
func TestCheckManifests_AllMissing_BothProbesFail(t *testing.T) {
	api := apiServer(t, map[string]string{
		"v9999.99.0-rc.1": "ffffffffffffffffffffffffffffffffffffffff",
	})
	defer api.Close()

	registry := ghcrServerWithTags(t, map[string]map[string]bool{})
	defer registry.Close()

	results := checkManifestsAt(api.URL, registry.URL, "v9999.99.0-rc.1")
	if countFailed(results) != len(dockerServices) {
		t.Fatalf("expected all %d manifests to fail, got %d: %+v",
			len(dockerServices), countFailed(results), results)
	}
	for _, r := range results {
		if r.OK {
			continue
		}
		if !strings.Contains(r.Err, "commit_short or CalVer") {
			t.Errorf("expected error to name both probe attempts; got %q", r.Err)
		}
	}
}

// TestCheckManifests_GithubApiUnreachable covers the degraded-mode
// path where the GitHub API is unreachable (tag→commit_short resolution
// fails). Probe falls through to pure-CalVer lookup.
func TestCheckManifests_GithubApiUnreachable(t *testing.T) {
	// Grab a port, then release it — any API call to this address fails.
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	deadAPI := "http://" + ln.Addr().String()
	ln.Close()

	allowed := map[string]map[string]bool{}
	for _, svc := range dockerServices {
		allowed[githubOrg+"/statbus-"+svc] = map[string]bool{"v2026.04.0-rc.61": true}
	}
	registry := ghcrServerWithTags(t, allowed)
	defer registry.Close()

	results := checkManifestsAt(deadAPI, registry.URL, "v2026.04.0-rc.61")
	if !allOK(results) {
		t.Fatalf("expected CalVer-only fallback to succeed with unreachable API, got: %+v", results)
	}
}

// TestCheckManifests_GithubApi404OnTag covers the case where the tag
// doesn't exist on GitHub at all. Same fallback as unreachable: skip
// commit_short probe, try CalVer only. Probe fails (correct: tag
// genuinely doesn't exist).
func TestCheckManifests_GithubApi404OnTag(t *testing.T) {
	api := apiServer(t, map[string]string{}) // nothing
	defer api.Close()

	registry := ghcrServerWithTags(t, map[string]map[string]bool{})
	defer registry.Close()

	results := checkManifestsAt(api.URL, registry.URL, "v2099.99.0-fake")
	if countFailed(results) != len(dockerServices) {
		t.Fatalf("expected all %d to fail, got %d", len(dockerServices), countFailed(results))
	}
	for _, r := range results {
		if r.OK {
			continue
		}
		if !strings.Contains(r.Err, "commit_short unresolved") {
			t.Errorf("expected 'commit_short unresolved' in err when API returns 404; got %q", r.Err)
		}
	}
}

// TestCheckManifests_MissingOneManifest_NewStyle covers the rc.63+
// version of the "one image failed" scenario: three images tagged at
// commit_short, one missing both commit_short and CalVer.
func TestCheckManifests_MissingOneManifest_NewStyle(t *testing.T) {
	api := apiServer(t, map[string]string{
		"v2026.04.0-rc.63": "e2355634abcdef0123456789abcdef0123456789",
	})
	defer api.Close()

	allowed := map[string]map[string]bool{}
	for _, svc := range dockerServices {
		image := githubOrg + "/statbus-" + svc
		if svc == "proxy" {
			allowed[image] = map[string]bool{} // no tags present — hard fail
		} else {
			allowed[image] = map[string]bool{"e2355634": true}
		}
	}
	registry := ghcrServerWithTags(t, allowed)
	defer registry.Close()

	results := checkManifestsAt(api.URL, registry.URL, "v2026.04.0-rc.63")
	if countFailed(results) != 1 {
		t.Fatalf("expected exactly 1 failure (statbus-proxy), got %d: %+v",
			countFailed(results), results)
	}
	for _, r := range results {
		if !r.OK && !contains(r.Name, "statbus-proxy") {
			t.Errorf("expected failure only on statbus-proxy; got %q", r.Name)
		}
	}
}

func contains(s, sub string) bool {
	return strings.Contains(s, sub)
}

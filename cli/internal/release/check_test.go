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

func TestCheckManifests_HappyPath(t *testing.T) {
	srv := ghcrServer(t, allImages(true))
	defer srv.Close()

	results := checkManifestsAt(srv.URL, "v2026.04.0-rc.9")
	if !allOK(results) {
		t.Fatalf("expected all manifests OK, got: %+v", results)
	}
	if len(results) != len(dockerServices) {
		t.Fatalf("expected %d results, got %d", len(dockerServices), len(results))
	}
}

func TestCheckManifests_MissingOneManifest(t *testing.T) {
	// All images present except statbus-proxy
	present := allImages(true)
	present[githubOrg+"/statbus-proxy"] = false
	srv := ghcrServer(t, present)
	defer srv.Close()

	results := checkManifestsAt(srv.URL, "v2026.04.0-rc.9")
	if countFailed(results) != 1 {
		t.Fatalf("expected exactly 1 failure, got %d: %+v", countFailed(results), results)
	}
	for _, r := range results {
		if !r.OK && !contains(r.Name, "statbus-proxy") {
			t.Errorf("expected failure on statbus-proxy, got %q", r.Name)
		}
	}
}

func TestCheckManifests_AllMissing(t *testing.T) {
	srv := ghcrServer(t, allImages(false))
	defer srv.Close()

	results := checkManifestsAt(srv.URL, "v9999.99.0-rc.1")
	if countFailed(results) != len(dockerServices) {
		t.Fatalf("expected all %d manifests to fail, got %d: %+v",
			len(dockerServices), countFailed(results), results)
	}
}

func TestCheckManifests_NetworkError(t *testing.T) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	addr := "http://" + ln.Addr().String()
	ln.Close()

	results := checkManifestsAt(addr, "v2026.04.0-rc.9")
	if countFailed(results) != len(dockerServices) {
		t.Fatalf("expected all results to fail on network error, got %d failed",
			countFailed(results))
	}
}

func contains(s, sub string) bool {
	return strings.Contains(s, sub)
}

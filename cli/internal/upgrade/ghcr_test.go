package upgrade

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// ghcrFixtureServer serves the two-step anonymous-token dance
// (/token then /v2/.../manifests/...) so tests exercise the exact HTTP
// shape STATBUS-302's live curl transcript proved, not a mocked-away
// abstraction. manifestStatus maps an image name (e.g. "statbus-db") to
// the HTTP status the manifest endpoint returns for it; an image absent
// from the map 404s by default (matches ghcrManifestExists's "confirmed
// absent" case).
func ghcrFixtureServer(t *testing.T, manifestStatus map[string]int, tokenFails bool) *httptest.Server {
	t.Helper()
	mux := http.NewServeMux()
	mux.HandleFunc("/token", func(w http.ResponseWriter, r *http.Request) {
		if tokenFails {
			w.WriteHeader(http.StatusInternalServerError)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]string{"token": "fixture-anonymous-token"})
	})
	mux.HandleFunc("/v2/", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodHead {
			t.Errorf("expected HEAD on the manifest endpoint, got %s", r.Method)
		}
		if got := r.Header.Get("Authorization"); got != "Bearer fixture-anonymous-token" {
			t.Errorf("manifest request missing/wrong bearer token: %q", got)
		}
		// Path shape: /v2/{owner}/{image}/manifests/{tag}
		parts := strings.Split(strings.TrimPrefix(r.URL.Path, "/v2/"), "/")
		if len(parts) < 4 {
			t.Fatalf("unexpected manifest path shape: %s", r.URL.Path)
		}
		image := parts[1]
		status, ok := manifestStatus[image]
		if !ok {
			status = http.StatusNotFound
		}
		w.WriteHeader(status)
	})
	srv := httptest.NewServer(mux)
	t.Cleanup(srv.Close)
	return srv
}

func TestGhcrManifestExists_Present(t *testing.T) {
	srv := ghcrFixtureServer(t, map[string]int{"statbus-sb": http.StatusOK}, false)
	status, err := ghcrManifestExists(srv.URL, "statisticsnorway", "statbus-sb", "700ac971")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != ghcrPresent {
		t.Errorf("got status %v, want ghcrPresent", status)
	}
}

func TestGhcrManifestExists_Absent(t *testing.T) {
	// No entry for "statbus-sb" in the map — the fixture server 404s by
	// default, matching the live probe's confirmed clean-404 behavior with
	// the SAME anonymous token (2026-08-28 curl transcript).
	srv := ghcrFixtureServer(t, map[string]int{}, false)
	status, err := ghcrManifestExists(srv.URL, "statisticsnorway", "statbus-sb", "deadbeef")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != ghcrAbsent {
		t.Errorf("got status %v, want ghcrAbsent", status)
	}
}

func TestGhcrManifestExists_TokenFetchFails_Indeterminate(t *testing.T) {
	srv := ghcrFixtureServer(t, map[string]int{"statbus-sb": http.StatusOK}, true /* tokenFails */)
	status, err := ghcrManifestExists(srv.URL, "statisticsnorway", "statbus-sb", "700ac971")
	if status != ghcrIndeterminate {
		t.Errorf("got status %v, want ghcrIndeterminate", status)
	}
	if err == nil {
		t.Error("expected a non-nil error naming the token-fetch failure")
	}
}

func TestGhcrManifestExists_UnexpectedStatus_Indeterminate(t *testing.T) {
	// THE LOAD-BEARING CASE (architect ruling): a probe that returns
	// neither 200 nor 404 (e.g. a transient 500, or a rate-limit 429) must
	// NEVER be folded into "absent" — that would be exactly the "failure to
	// observe rendered as evidence about the observed" defect this ticket
	// fixes. It must come back indeterminate so the caller acts on NEITHER
	// a build-failed nor a build-succeeded verdict.
	srv := ghcrFixtureServer(t, map[string]int{"statbus-sb": http.StatusInternalServerError}, false)
	status, err := ghcrManifestExists(srv.URL, "statisticsnorway", "statbus-sb", "700ac971")
	if status != ghcrIndeterminate {
		t.Errorf("got status %v, want ghcrIndeterminate", status)
	}
	if err == nil {
		t.Error("expected a non-nil error naming the unexpected status")
	}
}

func TestGhcrManifestExists_NetworkError_Indeterminate(t *testing.T) {
	// Point at a closed port — no server at all. Confirms transport-level
	// failures (not just HTTP-status ones) also land on indeterminate,
	// never on a build verdict.
	status, err := ghcrManifestExists("http://127.0.0.1:1", "statisticsnorway", "statbus-sb", "700ac971")
	if status != ghcrIndeterminate {
		t.Errorf("got status %v, want ghcrIndeterminate", status)
	}
	if err == nil {
		t.Error("expected a non-nil error for the unreachable registry")
	}
}

func TestProbeAllImagesGhcr_AllPresent(t *testing.T) {
	srv := ghcrFixtureServer(t, map[string]int{
		"statbus-db": http.StatusOK, "statbus-app": http.StatusOK,
		"statbus-worker": http.StatusOK, "statbus-proxy": http.StatusOK,
	}, false)
	status, err := probeAllImagesGhcr(srv.URL, "statisticsnorway", []string{"db", "app", "worker", "proxy"}, "700ac971")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != ghcrPresent {
		t.Errorf("got status %v, want ghcrPresent", status)
	}
}

func TestProbeAllImagesGhcr_OneAbsent(t *testing.T) {
	// db and app present, worker absent — the aggregate must report absent
	// (this is the "not built yet" case verifyArtifacts's caller acts on),
	// and must not even need to probe "proxy" (short-circuits on the first
	// conclusive absence — cheaper, and irrelevant to the verdict).
	var proxyProbed bool
	srv := ghcrFixtureServer(t, map[string]int{"statbus-db": http.StatusOK, "statbus-app": http.StatusOK}, false)
	orig := srv.Config.Handler
	srv.Config.Handler = http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.Contains(r.URL.Path, "statbus-proxy") {
			proxyProbed = true
		}
		orig.ServeHTTP(w, r)
	})
	status, err := probeAllImagesGhcr(srv.URL, "statisticsnorway", []string{"db", "app", "worker", "proxy"}, "700ac971")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != ghcrAbsent {
		t.Errorf("got status %v, want ghcrAbsent", status)
	}
	if proxyProbed {
		t.Error("expected probeAllImagesGhcr to short-circuit at the first confirmed absence, but it probed proxy too")
	}
}

func TestProbeAllImagesGhcr_IndeterminateBeforeAbsent(t *testing.T) {
	// db present, app's probe itself fails (token endpoint down) BEFORE any
	// image is confirmed absent — the aggregate must report indeterminate,
	// not silently skip ahead to a conclusion about worker/proxy.
	srv := ghcrFixtureServer(t, map[string]int{"statbus-db": http.StatusOK}, false)
	orig := srv.Config.Handler
	srv.Config.Handler = http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/token" && strings.Contains(r.URL.RawQuery, "statbus-app") {
			w.WriteHeader(http.StatusInternalServerError)
			return
		}
		orig.ServeHTTP(w, r)
	})
	status, err := probeAllImagesGhcr(srv.URL, "statisticsnorway", []string{"db", "app", "worker", "proxy"}, "700ac971")
	if status != ghcrIndeterminate {
		t.Errorf("got status %v, want ghcrIndeterminate", status)
	}
	if err == nil || !strings.Contains(err.Error(), "statbus-app") {
		t.Errorf("expected the error to name statbus-app, got: %v", err)
	}
}

// TestGhcrManifestExists_RealLiveShape is a documentation-as-test pin of
// the exact live evidence STATBUS-302's ruling rests on (comment #1's curl
// transcript, 2026-08-28): a bare unauthenticated HEAD 401s with a
// www-authenticate challenge naming the anonymous token endpoint, and the
// SAME anonymous token then gets 200 for a real tag and a clean 404 for a
// fake one. This test does not hit the network (CI/production boxes must
// stay offline-safe) — it re-asserts the fixture server matches that
// observed shape so a future refactor of the fixture can't silently drift
// from the real registry's behavior without a comment update here too.
func TestGhcrManifestExists_RealLiveShape(t *testing.T) {
	srv := ghcrFixtureServer(t, map[string]int{"statbus-sb": http.StatusOK}, false)

	// Step 1 shape: bare HEAD with no Authorization header still gets
	// SOME response from our fixture (unlike the real registry's 401) —
	// what we're pinning here is only that ghcrManifestExists ITSELF always
	// goes through the token step first, never a bare HEAD.
	var sawBareHead bool
	orig := srv.Config.Handler
	srv.Config.Handler = http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.HasPrefix(r.URL.Path, "/v2/") && r.Header.Get("Authorization") == "" {
			sawBareHead = true
		}
		orig.ServeHTTP(w, r)
	})

	status, err := ghcrManifestExists(srv.URL, "statisticsnorway", "statbus-sb", "700ac971")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != ghcrPresent {
		t.Errorf("got status %v, want ghcrPresent", status)
	}
	if sawBareHead {
		t.Error("ghcrManifestExists issued a manifest HEAD with no Authorization header — must always fetch the anonymous token first")
	}
}

// TestGhcrRegistryBase_MatchesRealHost pins the production constant against
// a typo — nothing else in the package would catch ghcrRegistryBase
// silently drifting from the real registry host.
func TestGhcrRegistryBase_MatchesRealHost(t *testing.T) {
	if ghcrRegistryBase != "https://ghcr.io" {
		t.Errorf("ghcrRegistryBase = %q, want %q", ghcrRegistryBase, "https://ghcr.io")
	}
}

// TestGhcrManifestExists_TokenURLShape pins the exact query-string shape
// the live curl transcript proved works: service=ghcr.io and a
// repository:{owner}/{image}:pull scope, no other params, no auth header.
func TestGhcrManifestExists_TokenURLShape(t *testing.T) {
	var gotQuery string
	mux := http.NewServeMux()
	mux.HandleFunc("/token", func(w http.ResponseWriter, r *http.Request) {
		gotQuery = r.URL.RawQuery
		if got := r.Header.Get("Authorization"); got != "" {
			t.Errorf("token request must be unauthenticated, got Authorization: %q", got)
		}
		_ = json.NewEncoder(w).Encode(map[string]string{"token": "t"})
	})
	mux.HandleFunc("/v2/", func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(http.StatusNotFound) })
	srv := httptest.NewServer(mux)
	t.Cleanup(srv.Close)

	_, _ = ghcrManifestExists(srv.URL, "statisticsnorway", "statbus-sb", "700ac971")

	want := "service=ghcr.io&scope=" + fmt.Sprintf("repository:%s:pull", "statisticsnorway/statbus-sb")
	if gotQuery != want {
		t.Errorf("token query = %q, want %q", gotQuery, want)
	}
}

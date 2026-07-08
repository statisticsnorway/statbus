package upgrade

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

// TestHealthCheckStatusOK pins STATBUS-148's fixed predicate: 2xx ONLY. The
// FIXED DEFECT, named explicitly: this used to be `resp.StatusCode < 500`,
// which let every 4xx through the gate.
func TestHealthCheckStatusOK(t *testing.T) {
	cases := []struct {
		status int
		want   bool
	}{
		{http.StatusOK, true},                   // 200 pass
		{http.StatusCreated, true},              // 201 pass (2xx boundary)
		{http.StatusNoContent, true},            // 204 pass
		{299, true},                             // top of the 2xx range, pass
		{http.StatusMultipleChoices, false},     // 300 fail (3xx, just past the range)
		{http.StatusBadRequest, false},          // 400 fail — THE fixed defect: this used to pass
		{http.StatusUnauthorized, false},        // 401 fail
		{http.StatusNotFound, false},            // 404 fail
		{http.StatusServiceUnavailable, false},  // 503 fail (unchanged — was already >= 500)
		{http.StatusInternalServerError, false}, // 500 fail (unchanged)
	}
	for _, c := range cases {
		if got := healthCheckStatusOK(c.status); got != c.want {
			t.Errorf("healthCheckStatusOK(%d) = %v, want %v", c.status, got, c.want)
		}
	}
}

// TestHealthCheck_400FailsEvenThoughUnder500 is the STATBUS-148 regression
// pin: a functional RPC that RAISEs (PostgREST maps PL/pgSQL RAISE EXCEPTION
// to HTTP 400) must fail the health check — pre-fix, 400 < 500 passed the old
// predicate and the upgrade completed with auth broken for every real user.
func TestHealthCheck_400FailsEvenThoughUnder500(t *testing.T) {
	var rpcHits int
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/ready" {
			w.WriteHeader(http.StatusOK)
			return
		}
		rpcHits++
		w.WriteHeader(http.StatusBadRequest)
		_, _ = w.Write([]byte(`{"message":"upgrade-arc healthpark fixture: auth_status intentionally broken"}`))
	}))
	defer srv.Close()

	d := &Service{
		cachedURL:      srv.URL + "/rpc/auth_status",
		cachedReadyURL: srv.URL + "/ready",
	}

	err := d.healthCheck(nil, 3, time.Millisecond)
	if err == nil {
		t.Fatal("expected healthCheck to fail on a persistent 400 — the fixed defect would have let this pass")
	}
	if rpcHits < 3 {
		t.Errorf("expected all 3 retries to hit the RPC (each 400), got %d", rpcHits)
	}
}

// TestHealthCheck_500StillFails confirms the >=500 failure path is unchanged
// by the tightened predicate (it already failed before this fix).
func TestHealthCheck_500StillFails(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/ready" {
			w.WriteHeader(http.StatusOK)
			return
		}
		w.WriteHeader(http.StatusInternalServerError)
	}))
	defer srv.Close()

	d := &Service{
		cachedURL:      srv.URL + "/rpc/auth_status",
		cachedReadyURL: srv.URL + "/ready",
	}

	if err := d.healthCheck(nil, 2, time.Millisecond); err == nil {
		t.Fatal("expected healthCheck to fail on a persistent 500")
	}
}

// TestHealthCheck_200Passes is the positive control: a healthy auth_status
// (200 on every call) passes immediately, no retries consumed.
func TestHealthCheck_200Passes(t *testing.T) {
	var rpcHits int
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/ready" {
			w.WriteHeader(http.StatusOK)
			return
		}
		rpcHits++
		w.WriteHeader(http.StatusOK)
	}))
	defer srv.Close()

	d := &Service{
		cachedURL:      srv.URL + "/rpc/auth_status",
		cachedReadyURL: srv.URL + "/ready",
	}

	if err := d.healthCheck(nil, 5, time.Millisecond); err != nil {
		t.Fatalf("expected healthCheck to pass on 200, got: %v", err)
	}
	if rpcHits != 1 {
		t.Errorf("expected exactly 1 RPC attempt on an immediate 200, got %d", rpcHits)
	}
}

// TestHealthCheck_TransportErrorFails: an unreachable RPC URL (connection
// refused) must fail the check like any other non-2xx outcome, never pass.
func TestHealthCheck_TransportErrorFails(t *testing.T) {
	readySrv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))
	defer readySrv.Close()

	d := &Service{
		cachedURL:      "http://127.0.0.1:1/rpc/auth_status", // nothing listens on port 1
		cachedReadyURL: readySrv.URL + "/ready",
	}

	if err := d.healthCheck(nil, 2, time.Millisecond); err == nil {
		t.Fatal("expected healthCheck to fail on a transport error (connection refused)")
	}
}

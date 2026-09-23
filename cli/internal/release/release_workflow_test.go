package release

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
)

const (
	testTagCommit = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
	oldTagCommit  = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
)

func serveTagCommit(w http.ResponseWriter) {
	_ = json.NewEncoder(w).Encode(map[string]any{"sha": testTagCommit})
}

func TestCheckReleaseWorkflowRetriesEmptyPage(t *testing.T) {
	var calls atomic.Int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.Contains(r.URL.Path, "/commits/") {
			serveTagCommit(w)
			return
		}
		call := calls.Add(1)
		if call < 3 {
			_ = json.NewEncoder(w).Encode(map[string]any{"workflow_runs": []any{}})
			return
		}
		_ = json.NewEncoder(w).Encode(map[string]any{"workflow_runs": []map[string]any{{
			"id": 501, "html_url": "https://example/run/501", "status": "queued", "head_sha": testTagCommit,
		}}})
	}))
	defer server.Close()
	result := checkReleaseWorkflowAt(server.URL, "v2026.09.1-rc.1")
	if result.Status != ReleaseWorkflowPending || calls.Load() != 3 {
		t.Fatalf("result=%#v calls=%d", result, calls.Load())
	}
}

func TestCheckReleaseWorkflowPermanentlyEmptyStaysMissingAfterThreeCalls(t *testing.T) {
	var calls atomic.Int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.Contains(r.URL.Path, "/commits/") {
			serveTagCommit(w)
			return
		}
		calls.Add(1)
		_ = json.NewEncoder(w).Encode(map[string]any{"workflow_runs": []any{}})
	}))
	defer server.Close()

	result := checkReleaseWorkflowAt(server.URL, "v2026.09.1-rc.99")
	if result.Status != ReleaseWorkflowMissing {
		t.Fatalf("result=%#v, want status %q", result, ReleaseWorkflowMissing)
	}
	if got := calls.Load(); got != 3 {
		t.Fatalf("calls=%d, want exactly 3", got)
	}
}

func TestCheckReleaseWorkflowAtTag(t *testing.T) {
	cases := []struct {
		name       string
		runs       []map[string]any
		wantStatus ReleaseWorkflowStatus
		wantURL    string
		wantID     int64
		wantDetail string
	}{
		{
			name: "green",
			runs: []map[string]any{{
				"id":         101,
				"html_url":   "https://github.com/o/r/actions/runs/101",
				"status":     "completed",
				"conclusion": "success",
				"created_at": "2026-05-19T10:00:00Z",
				"head_sha":   testTagCommit,
			}},
			wantStatus: ReleaseWorkflowGreen,
			wantURL:    "https://github.com/o/r/actions/runs/101",
			wantID:     101,
		},
		{
			name: "pending in_progress",
			runs: []map[string]any{{
				"id":         102,
				"html_url":   "https://github.com/o/r/actions/runs/102",
				"status":     "in_progress",
				"conclusion": nil,
				"created_at": "2026-05-19T10:00:00Z",
				"head_sha":   testTagCommit,
			}},
			wantStatus: ReleaseWorkflowPending,
			wantURL:    "https://github.com/o/r/actions/runs/102",
			wantID:     102,
		},
		{
			name: "failed",
			runs: []map[string]any{{
				"id":         103,
				"html_url":   "https://github.com/o/r/actions/runs/103",
				"status":     "completed",
				"conclusion": "failure",
				"created_at": "2026-05-19T10:00:00Z",
				"head_sha":   testTagCommit,
			}},
			wantStatus: ReleaseWorkflowFailed,
			wantURL:    "https://github.com/o/r/actions/runs/103",
			wantID:     103,
			wantDetail: "failure",
		},
		{
			name:       "missing",
			runs:       []map[string]any{},
			wantStatus: ReleaseWorkflowMissing,
		},
		{
			// Separate IDs are separate workflow runs, not attempts of one
			// rerun. Duplicate tag-push delivery can create two such runs;
			// once one published the immutable tag, the other commonly loses
			// the gh release create race with "tag already exists".
			name: "duplicate push: successful publisher wins over newer failed duplicate",
			runs: []map[string]any{
				{
					"id":         105,
					"html_url":   "https://github.com/o/r/actions/runs/105",
					"status":     "completed",
					"conclusion": "failure",
					"created_at": "2026-05-19T11:00:00Z",
					"head_sha":   testTagCommit,
				},
				{
					"id":         104,
					"html_url":   "https://github.com/o/r/actions/runs/104",
					"status":     "completed",
					"conclusion": "success",
					"created_at": "2026-05-19T10:00:00Z",
					"head_sha":   testTagCommit,
				},
			},
			wantStatus: ReleaseWorkflowGreen,
			wantURL:    "https://github.com/o/r/actions/runs/104",
			wantID:     104,
		},
		{
			name: "newer successful publisher wins over older failure",
			runs: []map[string]any{
				{
					"id":         107,
					"html_url":   "https://github.com/o/r/actions/runs/107",
					"status":     "completed",
					"conclusion": "success",
					"created_at": "2026-05-19T12:00:00Z",
					"head_sha":   testTagCommit,
				},
				{
					"id":         106,
					"html_url":   "https://github.com/o/r/actions/runs/106",
					"status":     "completed",
					"conclusion": "failure",
					"created_at": "2026-05-19T11:00:00Z",
					"head_sha":   testTagCommit,
				},
			},
			wantStatus: ReleaseWorkflowGreen,
			wantURL:    "https://github.com/o/r/actions/runs/107",
			wantID:     107,
		},
		{
			name: "sha mismatch rejected",
			runs: []map[string]any{
				{"id": 109, "html_url": "https://github.com/o/r/actions/runs/109", "status": "completed", "conclusion": "failure", "head_sha": testTagCommit},
				{"id": 108, "html_url": "https://github.com/o/r/actions/runs/108", "status": "completed", "conclusion": "success", "head_sha": oldTagCommit},
			},
			wantStatus: ReleaseWorkflowFailed,
			wantURL:    "https://github.com/o/r/actions/runs/109",
			wantID:     109,
			wantDetail: "failure",
		},
		{
			name: "all duplicates failed rejected",
			runs: []map[string]any{
				{"id": 111, "html_url": "https://github.com/o/r/actions/runs/111", "status": "completed", "conclusion": "failure", "head_sha": testTagCommit},
				{"id": 110, "html_url": "https://github.com/o/r/actions/runs/110", "status": "completed", "conclusion": "failure", "head_sha": testTagCommit},
			},
			wantStatus: ReleaseWorkflowFailed,
			wantURL:    "https://github.com/o/r/actions/runs/111",
			wantID:     111,
			wantDetail: "failure",
		},
		{
			name: "rerun of the same ID is its latest attempt",
			runs: []map[string]any{{
				"id": 112, "html_url": "https://github.com/o/r/actions/runs/112", "status": "completed", "conclusion": "failure",
				"head_sha": testTagCommit, "run_attempt": 2, "previous_attempt_url": "https://api.github.com/repos/o/r/actions/runs/112/attempts/1",
			}},
			wantStatus: ReleaseWorkflowFailed,
			wantURL:    "https://github.com/o/r/actions/runs/112",
			wantID:     112,
			wantDetail: "failure",
		},
		{
			name: "older success plus newer pending duplicate",
			runs: []map[string]any{
				{"id": 113, "html_url": "https://github.com/o/r/actions/runs/113", "status": "in_progress", "head_sha": testTagCommit},
				{"id": 112, "html_url": "https://github.com/o/r/actions/runs/112", "status": "completed", "conclusion": "success", "head_sha": testTagCommit},
			},
			wantStatus: ReleaseWorkflowGreen,
			wantURL:    "https://github.com/o/r/actions/runs/112",
			wantID:     112,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if strings.Contains(r.URL.Path, "/commits/") {
					serveTagCommit(w)
					return
				}
				wantPath := "/repos/statisticsnorway/statbus/actions/workflows/release.yaml/runs"
				if r.URL.Path != wantPath {
					http.Error(w, "unexpected path "+r.URL.Path, http.StatusNotFound)
					return
				}
				// `branch=` is the correct GitHub Actions filter param;
				// the old `head_branch=` was silently ignored (it's a
				// response-only field name, not a query parameter), which
				// is why probing rc.05 returned unfiltered runs that
				// included rc.02's stale success.
				if !strings.Contains(r.URL.RawQuery, "branch=v2026.05.0-rc.15") {
					http.Error(w, "missing branch query", http.StatusBadRequest)
					return
				}
				_ = json.NewEncoder(w).Encode(map[string]any{"workflow_runs": tc.runs})
			}))
			defer server.Close()

			result := checkReleaseWorkflowAt(server.URL, "v2026.05.0-rc.15")
			if result.Status != tc.wantStatus {
				t.Errorf("Status: got %q, want %q", result.Status, tc.wantStatus)
			}
			if result.RunURL != tc.wantURL {
				t.Errorf("RunURL: got %q, want %q", result.RunURL, tc.wantURL)
			}
			if tc.wantID != 0 && result.RunID != tc.wantID {
				t.Errorf("RunID: got %d, want %d", result.RunID, tc.wantID)
			}
			if tc.wantDetail != "" && result.Detail != tc.wantDetail {
				t.Errorf("Detail: got %q, want %q", result.Detail, tc.wantDetail)
			}
		})
	}
}

func TestCheckReleaseWorkflowAtTag_APIError(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
	}))
	defer server.Close()

	result := checkReleaseWorkflowAt(server.URL, "v2026.05.0-rc.15")
	if result.Status != ReleaseWorkflowUnknown {
		t.Errorf("Status: got %q, want %q", result.Status, ReleaseWorkflowUnknown)
	}
	if !strings.Contains(result.Detail, "HTTP 500") {
		t.Errorf("Detail should mention HTTP 500, got %q", result.Detail)
	}
}

func TestReleaseWorkflowURL(t *testing.T) {
	got := ReleaseWorkflowURL()
	want := "https://github.com/statisticsnorway/statbus/actions/workflows/release.yaml"
	if got != want {
		t.Errorf("got %q, want %q", got, want)
	}
}

package release

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

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
			// Exact-most-recent semantics: the newer failure SUPERSEDES
			// the older success. This is the case the old any-green-wins
			// shape got wrong — a rerun (or, for tag-keyed workflows, a
			// completely different run for the same tag) is the current
			// truth, not the "best ever" historical run.
			name: "rerun-supersedes-success: newer failure replaces older success",
			runs: []map[string]any{
				{
					"id":         105,
					"html_url":   "https://github.com/o/r/actions/runs/105",
					"status":     "completed",
					"conclusion": "failure",
					"created_at": "2026-05-19T11:00:00Z",
				},
				{
					"id":         104,
					"html_url":   "https://github.com/o/r/actions/runs/104",
					"status":     "completed",
					"conclusion": "success",
					"created_at": "2026-05-19T10:00:00Z",
				},
			},
			wantStatus: ReleaseWorkflowFailed,
			wantURL:    "https://github.com/o/r/actions/runs/105",
			wantID:     105,
			wantDetail: "failure",
		},
		{
			// The inverse: a successful rerun supersedes a prior failure.
			// Operator retried the failed jobs (gh run rerun --failed)
			// and the latest run is now green — that's authoritative.
			name: "rerun-supersedes-failure: newer success replaces older failure",
			runs: []map[string]any{
				{
					"id":         107,
					"html_url":   "https://github.com/o/r/actions/runs/107",
					"status":     "completed",
					"conclusion": "success",
					"created_at": "2026-05-19T12:00:00Z",
				},
				{
					"id":         106,
					"html_url":   "https://github.com/o/r/actions/runs/106",
					"status":     "completed",
					"conclusion": "failure",
					"created_at": "2026-05-19T11:00:00Z",
				},
			},
			wantStatus: ReleaseWorkflowGreen,
			wantURL:    "https://github.com/o/r/actions/runs/107",
			wantID:     107,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
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

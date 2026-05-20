package release

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestCheckWorkflowAtCommit(t *testing.T) {
	cases := []struct {
		name       string
		runs       []map[string]any
		wantStatus WorkflowCheckStatus
		wantURL    string
		wantID     int64
		wantDetail string
	}{
		{
			name: "green",
			runs: []map[string]any{{
				"id":         1,
				"html_url":   "https://github.com/o/r/actions/runs/1",
				"status":     "completed",
				"conclusion": "success",
				"created_at": "2026-05-19T10:00:00Z",
			}},
			wantStatus: WorkflowCheckGreen,
			wantURL:    "https://github.com/o/r/actions/runs/1",
			wantID:     1,
		},
		{
			name: "pending in_progress",
			runs: []map[string]any{{
				"id":         2,
				"html_url":   "https://github.com/o/r/actions/runs/2",
				"status":     "in_progress",
				"conclusion": nil,
				"created_at": "2026-05-19T10:00:00Z",
			}},
			wantStatus: WorkflowCheckPending,
			wantURL:    "https://github.com/o/r/actions/runs/2",
		},
		{
			name: "pending queued",
			runs: []map[string]any{{
				"id":         3,
				"html_url":   "https://github.com/o/r/actions/runs/3",
				"status":     "queued",
				"conclusion": nil,
				"created_at": "2026-05-19T10:00:00Z",
			}},
			wantStatus: WorkflowCheckPending,
			wantURL:    "https://github.com/o/r/actions/runs/3",
		},
		{
			name: "failed",
			runs: []map[string]any{{
				"id":         4,
				"html_url":   "https://github.com/o/r/actions/runs/4",
				"status":     "completed",
				"conclusion": "failure",
				"created_at": "2026-05-19T10:00:00Z",
			}},
			wantStatus: WorkflowCheckFailed,
			wantURL:    "https://github.com/o/r/actions/runs/4",
			wantID:     4,
			wantDetail: "failure",
		},
		{
			name: "failed-cancelled",
			runs: []map[string]any{{
				"id":         5,
				"html_url":   "https://github.com/o/r/actions/runs/5",
				"status":     "completed",
				"conclusion": "cancelled",
				"created_at": "2026-05-19T10:00:00Z",
			}},
			wantStatus: WorkflowCheckFailed,
			wantURL:    "https://github.com/o/r/actions/runs/5",
			wantDetail: "cancelled",
		},
		{
			name:       "missing",
			runs:       []map[string]any{},
			wantStatus: WorkflowCheckMissing,
		},
		{
			name: "any-green-wins: an earlier success counts even if a later retry is pending",
			// A commit's verdict is immutable per workflow — once ANY run
			// completed successfully, the artifact / test result stands.
			// A later retry hitting transient infra and queuing or
			// failing doesn't unbuild or unrun it.
			runs: []map[string]any{
				{
					"id":         7,
					"html_url":   "https://github.com/o/r/actions/runs/7",
					"status":     "in_progress",
					"conclusion": nil,
					"created_at": "2026-05-19T11:00:00Z",
				},
				{
					"id":         6,
					"html_url":   "https://github.com/o/r/actions/runs/6",
					"status":     "completed",
					"conclusion": "success",
					"created_at": "2026-05-19T10:00:00Z",
				},
			},
			wantStatus: WorkflowCheckGreen,
			wantURL:    "https://github.com/o/r/actions/runs/6",
			wantID:     6,
		},
		{
			name: "any-green-wins: an earlier success counts even if a later retry failed",
			runs: []map[string]any{
				{
					"id":         9,
					"html_url":   "https://github.com/o/r/actions/runs/9",
					"status":     "completed",
					"conclusion": "failure",
					"created_at": "2026-05-19T11:00:00Z",
				},
				{
					"id":         8,
					"html_url":   "https://github.com/o/r/actions/runs/8",
					"status":     "completed",
					"conclusion": "success",
					"created_at": "2026-05-19T10:00:00Z",
				},
			},
			wantStatus: WorkflowCheckGreen,
			wantURL:    "https://github.com/o/r/actions/runs/8",
			wantID:     8,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				wantPath := "/repos/statisticsnorway/statbus/actions/workflows/images.yaml/runs"
				if r.URL.Path != wantPath {
					http.Error(w, "unexpected path "+r.URL.Path, http.StatusNotFound)
					return
				}
				if !strings.Contains(r.URL.RawQuery, "head_sha=abc123def4561234567890abcdef1234567890ab") {
					http.Error(w, "missing head_sha query", http.StatusBadRequest)
					return
				}
				_ = json.NewEncoder(w).Encode(map[string]any{"workflow_runs": tc.runs})
			}))
			defer server.Close()

			result := checkWorkflowAt(server.URL, WorkflowImages, "abc123def4561234567890abcdef1234567890ab")
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

func TestCheckWorkflowAtCommit_APIError(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
	}))
	defer server.Close()

	result := checkWorkflowAt(server.URL, WorkflowImages, "abc123def4561234567890abcdef1234567890ab")
	if result.Status != WorkflowCheckUnknown {
		t.Errorf("Status: got %q, want %q", result.Status, WorkflowCheckUnknown)
	}
	if !strings.Contains(result.Detail, "HTTP 500") {
		t.Errorf("Detail should mention HTTP 500, got %q", result.Detail)
	}
}

func TestCheckWorkflowAtCommit_WorkflowParameterized(t *testing.T) {
	// Same helper, different workflow file → path reflects the param.
	cases := []struct {
		workflow string
		wantPath string
	}{
		{WorkflowImages, "/repos/statisticsnorway/statbus/actions/workflows/images.yaml/runs"},
		{WorkflowTestHardening, "/repos/statisticsnorway/statbus/actions/workflows/test-hardening.yaml/runs"},
		{WorkflowTestInstall, "/repos/statisticsnorway/statbus/actions/workflows/test-install.yaml/runs"},
	}
	for _, tc := range cases {
		t.Run(tc.workflow, func(t *testing.T) {
			var seenPath string
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				seenPath = r.URL.Path
				_ = json.NewEncoder(w).Encode(map[string]any{"workflow_runs": []map[string]any{}})
			}))
			defer server.Close()
			_ = checkWorkflowAt(server.URL, tc.workflow, "abc123def4561234567890abcdef1234567890ab")
			if seenPath != tc.wantPath {
				t.Errorf("path: got %q, want %q", seenPath, tc.wantPath)
			}
		})
	}
}

func TestWorkflowTriggerCommand(t *testing.T) {
	got := WorkflowTriggerCommand(WorkflowImages, "c4e850933fd3406a8cdaaef505d7d3de43f2c692")
	want := "gh workflow run images.yaml --ref c4e850933fd3406a8cdaaef505d7d3de43f2c692"
	if got != want {
		t.Errorf("got %q, want %q", got, want)
	}
}

func TestWorkflowURL(t *testing.T) {
	got := WorkflowURL(WorkflowImages)
	want := "https://github.com/statisticsnorway/statbus/actions/workflows/images.yaml"
	if got != want {
		t.Errorf("got %q, want %q", got, want)
	}
}

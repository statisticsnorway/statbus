package release

import (
	"encoding/json"
	"fmt"
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
		{WorkflowGoTest, "/repos/statisticsnorway/statbus/actions/workflows/go-test.yaml/runs"},
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
	// ref is a branch or tag name (workflow_dispatch rejects bare SHAs).
	for _, tc := range []struct {
		ref  string
		want string
	}{
		{"master", "gh workflow run images.yaml --ref master"},
		{"v2026.05.6-rc.01", "gh workflow run images.yaml --ref v2026.05.6-rc.01"},
	} {
		if got := WorkflowTriggerCommand(WorkflowImages, tc.ref); got != tc.want {
			t.Errorf("ref %q: got %q, want %q", tc.ref, got, tc.want)
		}
	}
}

func TestWorkflowURL(t *testing.T) {
	got := WorkflowURL(WorkflowImages)
	want := "https://github.com/statisticsnorway/statbus/actions/workflows/images.yaml"
	if got != want {
		t.Errorf("got %q, want %q", got, want)
	}
}

// TestWorkflowJobsCompleteAtCommit pins STATBUS-199 comment #4's
// completeness primitive: "the gate verifies what ran, not what the run
// claims." Three arms match the architect's ruling directly:
//   - complete: every required job name is present → complete=true,
//     no missing jobs.
//   - missing-jobs: a subset dispatch (or a decide-only ride/skip run)
//     has fewer jobs than required → complete=false, missingJobs names
//     exactly what's absent — this is the case that makes a self-reported
//     "FULL SUITE" label untrustworthy and the whole reason this
//     function exists instead of trusting run-name.
//   - pagination-overflow: total_count exceeds the single page returned
//     (per_page=100) → the check must refuse to silently truncate and
//     return an error, never a false "complete".
func TestWorkflowJobsCompleteAtCommit(t *testing.T) {
	cases := []struct {
		name         string
		totalCount   int
		jobNames     []string
		required     []string
		wantComplete bool
		wantMissing  []string
		wantErr      bool
		wantErrSub   string
	}{
		{
			name:         "complete",
			totalCount:   3,
			jobNames:     []string{"working", "failing", "postswap-migration-oom"},
			required:     []string{"working", "failing", "postswap-migration-oom"},
			wantComplete: true,
			wantMissing:  nil,
		},
		{
			name:         "missing-jobs: subset dispatch has fewer jobs than required",
			totalCount:   2,
			jobNames:     []string{"working", "failing"},
			required:     []string{"working", "failing", "postswap-migration-oom", "c-rollback-resurrection"},
			wantComplete: false,
			wantMissing:  []string{"postswap-migration-oom", "c-rollback-resurrection"},
		},
		{
			name:       "pagination-overflow: total_count exceeds the returned page",
			totalCount: 150,
			// Only 100 returned even though total_count says 150 — a
			// truncated first page (per_page=100 caps the response).
			jobNames:     namesN(100),
			required:     []string{"working"},
			wantComplete: false,
			wantErr:      true,
			wantErrSub:   "only 100 returned on one page",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				wantPath := "/repos/statisticsnorway/statbus/actions/runs/42/jobs"
				if r.URL.Path != wantPath {
					http.Error(w, "unexpected path "+r.URL.Path, http.StatusNotFound)
					return
				}
				jobs := make([]map[string]any, len(tc.jobNames))
				for i, n := range tc.jobNames {
					jobs[i] = map[string]any{"name": n}
				}
				_ = json.NewEncoder(w).Encode(map[string]any{
					"total_count": tc.totalCount,
					"jobs":        jobs,
				})
			}))
			defer server.Close()

			complete, missing, err := workflowJobsCompleteAtCommit(server.URL, 42, tc.required)
			if tc.wantErr {
				if err == nil {
					t.Fatal("want error, got nil")
				}
				if !strings.Contains(err.Error(), tc.wantErrSub) {
					t.Errorf("error %q does not contain %q", err.Error(), tc.wantErrSub)
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if complete != tc.wantComplete {
				t.Errorf("complete: got %v, want %v", complete, tc.wantComplete)
			}
			if !equalStringSlices(missing, tc.wantMissing) {
				t.Errorf("missingJobs: got %v, want %v", missing, tc.wantMissing)
			}
		})
	}
}

func namesN(n int) []string {
	names := make([]string, n)
	for i := range names {
		names[i] = fmt.Sprintf("job-%d", i)
	}
	return names
}

func equalStringSlices(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

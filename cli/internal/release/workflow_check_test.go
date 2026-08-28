package release

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"runtime"
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
// claims", plus STATBUS-217's strengthening (a required job counts only
// if it CONCLUDED SUCCESS) and STATBUS-216's empty-domain refusal:
//   - complete: every required job is present and successful →
//     Complete=true, both refusal buckets empty.
//   - missing-jobs: a subset dispatch (or a decide-only ride/skip run)
//     has fewer jobs than required → Complete=false, Missing names
//     exactly what's absent — this is the case that makes a self-reported
//     "FULL SUITE" label untrustworthy and the whole reason this
//     function exists instead of trusting run-name.
//   - skipped-required-job (STATBUS-217): the required job IS present but
//     concluded `skipped`. A skipped job does NOT redden its run, so the
//     run is green and, under name-only matching, the gate would have
//     accepted a scenario that never executed. It must land in
//     Unsuccessful — reported apart from Missing, since the remedy differs.
//   - cancelled-required-job: same class, the second non-red conclusion.
//   - null-conclusion: a job that never ran to completion is not proof.
//   - rerun-any-success: one name with a failure AND a success counts as
//     proof — the any-green reading CheckWorkflowAtCommit already applies
//     at run level.
//   - empty-required (STATBUS-216): an empty required list is an ERROR,
//     never a trivially-complete pass. Backstop under the domain-derivation
//     fix in cli/cmd/release.go.
//   - pagination-overflow: total_count exceeds the single page returned
//     (per_page=100) → the check must refuse to silently truncate and
//     return an error, never a false "complete".
func TestWorkflowJobsCompleteAtCommit(t *testing.T) {
	cases := []struct {
		name             string
		totalCount       int
		jobs             []testJob
		required         []string
		wantComplete     bool
		wantMissing      []string
		wantUnsuccessful []UnsuccessfulJob
		wantErr          bool
		wantErrSub       string
	}{
		{
			name:         "complete",
			totalCount:   3,
			jobs:         successfulJobs("working", "failing", "postswap-migration-oom"),
			required:     []string{"working", "failing", "postswap-migration-oom"},
			wantComplete: true,
			wantMissing:  nil,
		},
		{
			name:         "missing-jobs: subset dispatch has fewer jobs than required",
			totalCount:   2,
			jobs:         successfulJobs("working", "failing"),
			required:     []string{"working", "failing", "postswap-migration-oom", "c-rollback-resurrection"},
			wantComplete: false,
			wantMissing:  []string{"postswap-migration-oom", "c-rollback-resurrection"},
		},
		{
			name:       "skipped-required-job: present but never executed (run stays green)",
			totalCount: 2,
			jobs: []testJob{
				{name: "working", conclusion: "success"},
				{name: "postswap-migration-oom", conclusion: "skipped"},
			},
			required:         []string{"working", "postswap-migration-oom"},
			wantComplete:     false,
			wantMissing:      nil,
			wantUnsuccessful: []UnsuccessfulJob{{Name: "postswap-migration-oom", Conclusion: "skipped"}},
		},
		{
			name:       "cancelled-required-job",
			totalCount: 2,
			jobs: []testJob{
				{name: "working", conclusion: "success"},
				{name: "failing", conclusion: "cancelled"},
			},
			required:         []string{"working", "failing"},
			wantComplete:     false,
			wantUnsuccessful: []UnsuccessfulJob{{Name: "failing", Conclusion: "cancelled"}},
		},
		{
			name:       "null-conclusion: the job never ran to completion",
			totalCount: 1,
			jobs: []testJob{
				{name: "working", conclusion: ""},
			},
			required:         []string{"working"},
			wantComplete:     false,
			wantUnsuccessful: []UnsuccessfulJob{{Name: "working", Conclusion: ""}},
		},
		{
			name:       "rerun-any-success: a successful attempt of the same job name counts",
			totalCount: 2,
			jobs: []testJob{
				{name: "working", conclusion: "failure"},
				{name: "working", conclusion: "success"},
			},
			required:     []string{"working"},
			wantComplete: true,
		},
		{
			name:         "empty-required: refuse, never a trivial 0/0 pass",
			totalCount:   1,
			jobs:         successfulJobs("working"),
			required:     nil,
			wantComplete: false,
			wantErr:      true,
			wantErrSub:   "required-job list is empty",
		},
		{
			name:       "pagination-overflow: total_count exceeds the returned page",
			totalCount: 150,
			// Only 100 returned even though total_count says 150 — a
			// truncated first page (per_page=100 caps the response).
			jobs:         successfulJobs(namesN(100)...),
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
				jobs := make([]map[string]any, len(tc.jobs))
				for i, j := range tc.jobs {
					entry := map[string]any{"name": j.name}
					if j.conclusion == "" {
						// GitHub sends conclusion: null for a job that
						// never reached one — exercise the real decode
						// path, not a pre-emptied string.
						entry["conclusion"] = nil
					} else {
						entry["conclusion"] = j.conclusion
					}
					jobs[i] = entry
				}
				_ = json.NewEncoder(w).Encode(map[string]any{
					"total_count": tc.totalCount,
					"jobs":        jobs,
				})
			}))
			defer server.Close()

			verdict, err := workflowJobsCompleteAtCommit(server.URL, 42, tc.required)
			if tc.wantErr {
				if err == nil {
					t.Fatal("want error, got nil")
				}
				if !strings.Contains(err.Error(), tc.wantErrSub) {
					t.Errorf("error %q does not contain %q", err.Error(), tc.wantErrSub)
				}
				if verdict.Complete {
					t.Error("Complete must be false whenever an error is returned — an errored check must never read as proof")
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if verdict.Complete != tc.wantComplete {
				t.Errorf("Complete: got %v, want %v", verdict.Complete, tc.wantComplete)
			}
			if !equalStringSlices(verdict.Missing, tc.wantMissing) {
				t.Errorf("Missing: got %v, want %v", verdict.Missing, tc.wantMissing)
			}
			if !equalUnsuccessfulJobs(verdict.Unsuccessful, tc.wantUnsuccessful) {
				t.Errorf("Unsuccessful: got %v, want %v", verdict.Unsuccessful, tc.wantUnsuccessful)
			}
		})
	}
}

// TestUnsuccessfulJobString pins the operator-facing rendering: the raw
// conclusion is named (so "skipped" vs "cancelled" is visible), and a null
// conclusion is explained rather than printing an empty parenthesis.
func TestUnsuccessfulJobString(t *testing.T) {
	if got := (UnsuccessfulJob{Name: "working", Conclusion: "skipped"}).String(); got != "working (conclusion: skipped)" {
		t.Errorf("got %q", got)
	}
	if got := (UnsuccessfulJob{Name: "working"}).String(); !strings.Contains(got, "never ran to completion") {
		t.Errorf("a null conclusion must be explained, got %q", got)
	}
}

// testJob is one entry of the API's jobs array: the job's name and how it
// ended. Both fields matter — STATBUS-217: presence alone is not proof.
type testJob struct {
	name       string
	conclusion string
}

// successfulJobs builds the ordinary case — every named job ran green.
func successfulJobs(names ...string) []testJob {
	jobs := make([]testJob, len(names))
	for i, n := range names {
		jobs[i] = testJob{name: n, conclusion: "success"}
	}
	return jobs
}

func equalUnsuccessfulJobs(a, b []UnsuccessfulJob) bool {
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

// ─── STATBUS-285: the consumer half — key on what a run EXERCISED ───────────
//
// The publisher stamps `exercised-sha=<40hex>` into each marked run's name;
// the API returns it as display_title. These pin that the gate reads THAT and
// never the head_sha a workflow_run run is filed under.

func TestExercisedSHAOf_StrictParsing_STATBUS285(t *testing.T) {
	const good = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
	cases := []struct {
		name  string
		title string
		want  string
		ok    bool
	}{
		{"plain", "Fast Tests @ exercised-sha=" + good, good, true},
		{"trailing space is a boundary", "pg_regress @ exercised-sha=" + good + " ", good, true},
		{"trailing non-hex word", "x @ exercised-sha=" + good + " (rerun)", good, true},

		// Every one of these must be REFUSED. At a release gate an
		// almost-right identifier is worse than none: it silently credits
		// evidence to the wrong commit.
		{"no marker at all (legacy run)", "Fast Tests", "", false},
		{"short sha", "x @ exercised-sha=abc123", "", false},
		{"39 hex", "x @ exercised-sha=" + good[:39], "", false},
		{"41 hex — must not match the first 40", "x @ exercised-sha=" + good + "a", "", false},
		{"uppercase hex", "x @ exercised-sha=" + strings.ToUpper(good), "", false},
		{"non-hex in range", "x @ exercised-sha=zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz", "", false},
		{"marker with empty value", "x @ exercised-sha=", "", false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got, ok := exercisedSHAOf(c.title)
			if ok != c.ok || got != c.want {
				t.Errorf("exercisedSHAOf(%q) = (%q, %v), want (%q, %v)", c.title, got, ok, c.want, c.ok)
			}
		})
	}
}

func TestCheckWorkflowByMarker_STATBUS285(t *testing.T) {
	const target = "1111111111111111111111111111111111111111"
	const other = "2222222222222222222222222222222222222222"

	cases := []struct {
		name string
		runs string
		want WorkflowCheckStatus
	}{
		{
			// THE BUG THIS TICKET IS ABOUT. The run that tested `target` is
			// filed under `other` (workflow_run files runs under the default
			// branch tip at trigger). head_sha would miss it entirely; the
			// marker finds it.
			name: "green run filed under a DIFFERENT head_sha is still found",
			runs: `{"id":1,"html_url":"u1","status":"completed","conclusion":"success",
			         "head_sha":"` + other + `","display_title":"pg_regress @ exercised-sha=` + target + `"}`,
			want: WorkflowCheckGreen,
		},
		{
			// The other direction, and the dangerous one: a run FILED under
			// target that exercised something else must NOT count for target.
			name: "green run filed under target but exercising another commit does NOT count",
			runs: `{"id":2,"html_url":"u2","status":"completed","conclusion":"success",
			         "head_sha":"` + target + `","display_title":"pg_regress @ exercised-sha=` + other + `"}`,
			want: WorkflowCheckMissing,
		},
		{
			// Legacy runs still inside the lookback window. Graceful: they
			// cannot say what they tested, so they are not evidence — Missing,
			// which every consumer already handles. Never a crash, never green.
			name: "unmarked legacy runs yield Missing, not a crash or a false green",
			runs: `{"id":3,"html_url":"u3","status":"completed","conclusion":"success",
			         "head_sha":"` + target + `","display_title":"pg_regress"}`,
			want: WorkflowCheckMissing,
		},
		{
			name: "pending marked run reports Pending",
			runs: `{"id":4,"html_url":"u4","status":"in_progress","conclusion":null,
			         "head_sha":"` + other + `","display_title":"pg_regress @ exercised-sha=` + target + `"}`,
			want: WorkflowCheckPending,
		},
		{
			name: "failed marked run reports Failed",
			runs: `{"id":5,"html_url":"u5","status":"completed","conclusion":"failure",
			         "head_sha":"` + other + `","display_title":"pg_regress @ exercised-sha=` + target + `"}`,
			want: WorkflowCheckFailed,
		},
		{
			name: "no runs at all",
			runs: ``,
			want: WorkflowCheckMissing,
		},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				// The query must NOT filter on head_sha: doing so would hand
				// back exactly the wrong set for workflow_run runs.
				if r.URL.Query().Get("head_sha") != "" {
					t.Errorf("marker lookup must not filter on head_sha; query was %q", r.URL.RawQuery)
				}
				_, _ = w.Write([]byte(`{"workflow_runs":[` + c.runs + `]}`))
			}))
			defer server.Close()

			got := checkWorkflowByMarkerAt(server.URL, WorkflowPgRegress, target)
			if got.Status != c.want {
				t.Errorf("status = %q, want %q (detail=%q)", got.Status, c.want, got.Detail)
			}
		})
	}
}

// TestOnlyMarkerCarryingWorkflowsUseMarkerLookup_STATBUS285 pins the SCOPE.
//
// images.yaml carries no marker. If it were routed through the marker lookup it
// would go instantly Missing and the release gate would refuse every cut — a
// gate broken by its own rollout. This is the guard on that.
func TestOnlyMarkerCarryingWorkflowsUseMarkerLookup_STATBUS285(t *testing.T) {
	marked := []string{WorkflowFastTests, WorkflowPgRegress}
	unmarked := []string{WorkflowImages, WorkflowGoTest, WorkflowTestHardening,
		WorkflowTestInstall, WorkflowInstallRecoveryHarness, WorkflowAppBuildLint,
		WorkflowUpgradeArcHarness, WorkflowTestUpgrade}

	for _, w := range marked {
		if !workflowCarriesExercisedMarker(w) {
			t.Errorf("%s emits an exercised-sha marker but is not read via the marker lookup", w)
		}
	}
	for _, w := range unmarked {
		if workflowCarriesExercisedMarker(w) {
			t.Errorf("%s does NOT emit an exercised-sha marker, so reading it via the marker "+
				"lookup would make it permanently Missing and refuse every release", w)
		}
	}
}

// TestMarkerScopeMatchesTheWorkflowFiles_STATBUS285 derives the truth from the
// WORKFLOW FILES rather than trusting the Go list beside it.
//
// workflowCarriesExercisedMarker is a hand-kept set, and a hand-kept set rots:
// the day someone adds `exercised-sha=` to another workflow's run-name, or
// removes it from one of these two, the Go side would keep answering from
// memory. Both directions of that drift are silent and bad — a workflow that
// gained the marker keeps being read by the head_sha lie, and one that lost it
// goes permanently Missing and refuses every cut.
//
// So this reads .github/workflows/*.yaml and requires the two sets to agree.
func TestMarkerScopeMatchesTheWorkflowFiles_STATBUS285(t *testing.T) {
	_, thisFile, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("runtime.Caller failed")
	}
	wfDir := filepath.Join(filepath.Dir(thisFile), "..", "..", "..", ".github", "workflows")
	entries, err := os.ReadDir(wfDir)
	if err != nil {
		t.Fatalf("read %s: %v", wfDir, err)
	}

	emitsMarker := map[string]bool{}
	scanned := 0
	for _, e := range entries {
		if e.IsDir() || !strings.HasSuffix(e.Name(), ".yaml") {
			continue
		}
		b, err := os.ReadFile(filepath.Join(wfDir, e.Name()))
		if err != nil {
			t.Fatalf("read %s: %v", e.Name(), err)
		}
		scanned++
		// The marker counts only where it is EMITTED — in a run-name — not
		// where a comment happens to mention it.
		for _, line := range strings.Split(string(b), "\n") {
			trimmed := strings.TrimSpace(line)
			if strings.HasPrefix(trimmed, "#") {
				continue
			}
			if strings.Contains(trimmed, exercisedSHAMarker) {
				emitsMarker[e.Name()] = true
				break
			}
		}
	}

	// Zero-scope guard: a scan that read nothing must fail, not pass.
	if scanned == 0 {
		t.Fatalf("scanned 0 workflow files under %s — the scan is broken, so this test asserts nothing", wfDir)
	}

	for name := range emitsMarker {
		if !workflowCarriesExercisedMarker(name) {
			t.Errorf("%s EMITS an exercised-sha marker but workflowCarriesExercisedMarker says otherwise — "+
				"the release gate is still reading it via the head_sha it is filed under, which is the "+
				"STATBUS-285 lie this ticket removes", name)
		}
	}
	for _, name := range []string{WorkflowFastTests, WorkflowPgRegress} {
		if workflowCarriesExercisedMarker(name) && !emitsMarker[name] {
			t.Errorf("%s is read via the marker lookup but its workflow file no longer emits "+
				"exercised-sha — every commit will now read Missing and the release gate will refuse "+
				"every cut", name)
		}
	}
}

// TestRoutingReachesTheMarkerLookup_STATBUS285 pins that the marker lookup is
// actually REACHED for marker-carrying workflows.
//
// ADDED BECAUSE THIS TICKET'S OWN RED VERIFICATION FOUND IT MISSING: deleting
// the routing — the exact edit that reverts the gate to the head_sha lie — left
// every other test here green, because they called the lookup directly. They
// proved the lookup works; none proved anything reached it.
//
// The discriminator is the QUERY the server receives. The marker path asks
// without a head_sha filter; the legacy path asks with one. Reading which
// arrives tells us which path ran, without needing either to succeed.
func TestRoutingReachesTheMarkerLookup_STATBUS285(t *testing.T) {
	const sha = "3333333333333333333333333333333333333333"

	for _, c := range []struct {
		workflow       string
		wantHeadSHAArg bool
	}{
		{WorkflowPgRegress, false}, // marked → marker lookup → no head_sha filter
		{WorkflowFastTests, false},
		{WorkflowImages, true}, // unmarked → legacy path → head_sha filter
		{WorkflowGoTest, true},
	} {
		t.Run(c.workflow, func(t *testing.T) {
			var sawHeadSHA bool
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				sawHeadSHA = r.URL.Query().Get("head_sha") != ""
				_, _ = w.Write([]byte(`{"workflow_runs":[]}`))
			}))
			defer server.Close()

			_ = checkWorkflowRoutedAt(server.URL, c.workflow, sha)

			if sawHeadSHA != c.wantHeadSHAArg {
				which := map[bool]string{true: "the legacy head_sha path", false: "the marker path"}
				t.Errorf("%s was routed through %s; want %s.\n"+
					"For a marker-carrying workflow the head_sha path is the STATBUS-285 lie: it credits a run "+
					"to the commit it is FILED under rather than the one it EXERCISED.",
					c.workflow, which[sawHeadSHA], which[c.wantHeadSHAArg])
			}
		})
	}
}

package release

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

// STATBUS-249 evidence marks. The correction the architect required is pinned
// first, because it is a live defect rather than a hypothetical: checkWorkflowAt
// returns the FIRST GREEN run at a head_sha, and for a per-scenario question
// that can select a run which does not contain the scenario at all — reporting
// "not covered" while the proof sits in another run at the same commit.

// markServer stands up the two endpoints the union lookup uses: the runs list
// for a workflow at a head_sha, and the jobs list for a run.
func markServer(t *testing.T, runs []map[string]any, jobsByRun map[int64][]map[string]any) *httptest.Server {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case strings.Contains(r.URL.Path, "/actions/workflows/"):
			_ = json.NewEncoder(w).Encode(map[string]any{"workflow_runs": runs})
		case strings.Contains(r.URL.Path, "/actions/runs/"):
			seg := strings.Split(strings.TrimPrefix(r.URL.Path, "/"), "/")
			var runID int64
			for i, s := range seg {
				if s == "runs" && i+1 < len(seg) {
					for _, ch := range seg[i+1] {
						runID = runID*10 + int64(ch-'0')
					}
				}
			}
			jobs := jobsByRun[runID]
			_ = json.NewEncoder(w).Encode(map[string]any{"total_count": len(jobs), "jobs": jobs})
		default:
			http.Error(w, "unexpected path "+r.URL.Path, http.StatusNotFound)
		}
	}))
	t.Cleanup(srv.Close)
	return srv
}

// TestScenarioEvidence_UnionAcrossRuns_STATBUS249 is the architect's required
// correction. Two completed runs exist at one commit: a SMOKE run (green, but it
// contains only the smoke job) and the FULL run containing the scenario. A
// first-green-wins lookup selects the smoke run, does not find the scenario, and
// answers "not proven" — while the proof is right there in the other run.
func TestScenarioEvidence_UnionAcrossRuns_STATBUS249(t *testing.T) {
	srv := markServer(t,
		[]map[string]any{
			// Newest first, exactly as GitHub returns them: the smoke run is
			// the one a first-green-wins lookup would pick.
			{"id": 111, "status": "completed", "conclusion": "success", "html_url": "http://smoke"},
			{"id": 222, "status": "completed", "conclusion": "success", "html_url": "http://full"},
		},
		map[int64][]map[string]any{
			111: {{"name": "0-happy-upgrade", "conclusion": "success"}},
			222: {{"name": "rollback-pair-terminal", "conclusion": "success"}},
		})

	found, detail, err := scenarioProvenInCIAt(srv.URL, WorkflowUpgradeArcHarness, "rollback-pair-terminal", "c07")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !found {
		t.Fatal("UNION REQUIRED: the scenario succeeded in run 222, but the lookup answered 'not proven' — first-green-wins selected the smoke run (111) and stopped. A per-scenario question must consider EVERY completed run at the commit")
	}
	if !strings.Contains(detail, "222") {
		t.Errorf("the detail must name the run that actually carries the proof; got %q", detail)
	}
	// The run URL must survive JSON decoding. Go matches fields
	// case-insensitively but NOT across underscores, so `HTMLURL` silently
	// receives nothing from `html_url` without a tag — the evidence line then
	// prints "in run 222 ()" and still looks fine. Found by running the real
	// command, not by reading the struct.
	if !strings.Contains(detail, "http://full") {
		t.Errorf("the evidence detail must carry the run URL so an operator can open it; got %q", detail)
	}
}

// TestScenarioEvidence_UnsuccessfulJobIsNotAMark_STATBUS249 is AC#6 at the
// store level: rc.06's arcs were CANCELLED. A cancelled or skipped job does not
// redden its run, so a green run can contain one — and it must not count.
func TestScenarioEvidence_UnsuccessfulJobIsNotAMark_STATBUS249(t *testing.T) {
	for _, conclusion := range []string{"cancelled", "skipped", "failure", ""} {
		srv := markServer(t,
			[]map[string]any{{"id": 1, "status": "completed", "conclusion": "success", "html_url": "http://run"}},
			map[int64][]map[string]any{
				1: {{"name": "rollback-pair-terminal", "conclusion": conclusion}},
			})
		found, _, err := scenarioProvenInCIAt(srv.URL, WorkflowUpgradeArcHarness, "rollback-pair-terminal", "c06")
		if err != nil {
			t.Fatalf("conclusion %q: unexpected error: %v", conclusion, err)
		}
		if found {
			t.Errorf("a job concluding %q is NOT a mark — this is the rc.06 specimen: cancelled work must never be inheritable", conclusion)
		}
	}
}

// TestScenarioEvidence_IncompleteRunIsNotConsulted_STATBUS249: a run still in
// progress has concluded nothing. Treating its jobs as evidence would let a
// candidate inherit from work that has not finished.
func TestScenarioEvidence_IncompleteRunIsNotConsulted_STATBUS249(t *testing.T) {
	srv := markServer(t,
		[]map[string]any{{"id": 9, "status": "in_progress", "conclusion": "", "html_url": "http://running"}},
		map[int64][]map[string]any{
			9: {{"name": "rollback-pair-terminal", "conclusion": "success"}},
		})
	found, _, err := scenarioProvenInCIAt(srv.URL, WorkflowUpgradeArcHarness, "rollback-pair-terminal", "c08")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if found {
		t.Error("an in-progress run is not proof — 'still running' must never read as 'passed'")
	}
}

// TestLocalMark_RoundTripAndComposition_STATBUS249 is AC#8: a mark is a mark
// whether it came from a local run or from CI, and ONE lookup consults both.
func TestLocalMark_RoundTripAndComposition_STATBUS249(t *testing.T) {
	dir := t.TempDir()

	got, err := LocalMarkExists(dir, "rollback-kill", "c07")
	if err != nil {
		t.Fatalf("a missing mark file must be a clean no, not an error: %v", err)
	}
	if got {
		t.Fatal("no mark was written, yet one was found")
	}

	if err := WriteLocalMark(dir, "rollback-kill", "c07"); err != nil {
		t.Fatal(err)
	}
	// Idempotent: re-running a scenario must not duplicate its mark.
	if err := WriteLocalMark(dir, "rollback-kill", "c07"); err != nil {
		t.Fatal(err)
	}
	if got, err := LocalMarkExists(dir, "rollback-kill", "c07"); err != nil || !got {
		t.Fatalf("the mark just written was not found (found=%v err=%v)", got, err)
	}
	// A mark is per scenario AND per code-state: neither axis may leak.
	if got, _ := LocalMarkExists(dir, "rollback-kill", "OTHER-COMMIT"); got {
		t.Error("a mark at one commit must not answer for another code-state")
	}
	if got, _ := LocalMarkExists(dir, "other-scenario", "c07"); got {
		t.Error("a mark for one scenario must not answer for another")
	}

	// Composition: the local mark alone satisfies the lookup, with no CI call.
	// (The API base is unreachable here on purpose — if the lookup contacted CI
	// despite a local mark, this would fail rather than silently pass.)
	found, detail, err := ScenarioEvidence(dir, WorkflowUpgradeArcHarness, "rollback-kill")("c07")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !found {
		t.Fatal("a locally recorded pass must satisfy the composed lookup (AC#8)")
	}
	if !strings.Contains(detail, "local mark") {
		t.Errorf("the detail must say the evidence came from a local mark; got %q", detail)
	}
}

// TestWriteLocalMark_RefusesAnIdentitylessMark_STATBUS249: a mark that names no
// scenario or no code-state proves nothing and would be indistinguishable from
// noise at lookup time.
func TestWriteLocalMark_RefusesAnIdentitylessMark_STATBUS249(t *testing.T) {
	dir := t.TempDir()
	if err := WriteLocalMark(dir, "", "c07"); err == nil {
		t.Error("a mark with no scenario must be refused")
	}
	if err := WriteLocalMark(dir, "s", ""); err == nil {
		t.Error("a mark with no commit must be refused")
	}
}

// TestScenarioEvidence_UnreadableRunsAreReported_STATBUS249: if a run's jobs
// cannot be read, the answer is an ERROR, not a confident "not proven". The
// walk above turns that into a recorded EvidenceError rather than silently
// treating the candidate as unproven.
func TestScenarioEvidence_UnreadableRunsAreReported_STATBUS249(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.Contains(r.URL.Path, "/actions/workflows/") {
			_ = json.NewEncoder(w).Encode(map[string]any{"workflow_runs": []map[string]any{
				{"id": 5, "status": "completed", "conclusion": "success", "html_url": "http://r"},
			}})
			return
		}
		http.Error(w, "boom", http.StatusInternalServerError)
	}))
	defer srv.Close()

	found, _, err := scenarioProvenInCIAt(srv.URL, WorkflowUpgradeArcHarness, "rollback-kill", "c07")
	if found {
		t.Fatal("nothing was readable, so nothing can be proven")
	}
	if err == nil {
		t.Fatal("a run whose jobs could not be read must ERROR — answering 'not proven' would claim an examination that did not happen")
	}
}

// TestWorkflowsRunningScenario_UnionsAcrossIdentities_STATBUS249C1 is the Wave C
// seam (249 comment #6). A scenario that legitimately runs under two workflow
// identities must be looked for under both — a mark left by the smoke workflow
// is invisible to a query against the harness, and vice versa.
func TestWorkflowsRunningScenario_UnionsAcrossIdentities_STATBUS249C1(t *testing.T) {
	has := func(list []string, want string) bool {
		for _, w := range list {
			if w == want {
				return true
			}
		}
		return false
	}

	up := WorkflowsRunningScenario(WorkflowInstallRecoveryHarness, "0-happy-upgrade")
	if !has(up, WorkflowTestUpgrade) || !has(up, WorkflowInstallRecoveryHarness) {
		t.Errorf("0-happy-upgrade runs in BOTH the smoke workflow and the harness matrix; got %v", up)
	}
	in := WorkflowsRunningScenario(WorkflowInstallRecoveryHarness, "0-happy-install")
	if !has(in, WorkflowTestInstall) || !has(in, WorkflowInstallRecoveryHarness) {
		t.Errorf("0-happy-install runs in BOTH test-install and the harness matrix; got %v", in)
	}

	// No duplicates: the home workflow must not appear twice when it is also a
	// listed identity, or the lookup pays for the same query twice.
	seen := map[string]int{}
	for _, w := range up {
		seen[w]++
	}
	for w, n := range seen {
		if n > 1 {
			t.Errorf("workflow %s listed %d times — the union must not repeat an identity", w, n)
		}
	}

	// An ordinary arc scenario has exactly one home and must NOT gain
	// identities it never runs under.
	arc := WorkflowsRunningScenario(WorkflowUpgradeArcHarness, "rollback-pair-terminal")
	if len(arc) != 1 || arc[0] != WorkflowUpgradeArcHarness {
		t.Errorf("a scenario with one home must union to just that home; got %v", arc)
	}
}

// TestScenarioEvidence_FindsAMarkUnderTheOtherIdentity_STATBUS249C1: the seam
// end to end. The mark exists ONLY under the smoke identity; a harness-scoped
// lookup must still find it, or the chain re-runs work already proven.
func TestScenarioEvidence_FindsAMarkUnderTheOtherIdentity_STATBUS249C1(t *testing.T) {
	var askedFor []string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case strings.Contains(r.URL.Path, "/actions/workflows/"):
			// Record which identity was queried, and answer only for the smoke one.
			seg := strings.Split(r.URL.Path, "/")
			wf := seg[len(seg)-2]
			askedFor = append(askedFor, wf)
			if wf == WorkflowTestUpgrade {
				_ = json.NewEncoder(w).Encode(map[string]any{"workflow_runs": []map[string]any{
					{"id": 77, "status": "completed", "conclusion": "success", "html_url": "http://smoke"},
				}})
				return
			}
			_ = json.NewEncoder(w).Encode(map[string]any{"workflow_runs": []map[string]any{}})
		case strings.Contains(r.URL.Path, "/actions/runs/"):
			_ = json.NewEncoder(w).Encode(map[string]any{"total_count": 1, "jobs": []map[string]any{
				{"name": "0-happy-upgrade", "conclusion": "success"},
			}})
		default:
			http.Error(w, "unexpected "+r.URL.Path, http.StatusNotFound)
		}
	}))
	defer srv.Close()

	// Exercise the union directly against the test server.
	var found bool
	var detail string
	for _, wf := range WorkflowsRunningScenario(WorkflowInstallRecoveryHarness, "0-happy-upgrade") {
		f, d, err := scenarioProvenInCIAt(srv.URL, wf, "0-happy-upgrade", "c09")
		if err != nil {
			t.Fatalf("%s: %v", wf, err)
		}
		if f {
			found, detail = true, d
			break
		}
	}
	if !found {
		t.Fatalf("the mark exists under %s only; a harness-scoped union must still find it (identities asked: %v)", WorkflowTestUpgrade, askedFor)
	}
	if !strings.Contains(detail, "77") {
		t.Errorf("the detail must name the run holding the mark; got %q", detail)
	}
}

// TestSmokeJobNamesMatchTheirScenarios_STATBUS249C1: the job NAME is the mark.
// A smoke workflow whose job is called anything other than its scenario leaves a
// mark nothing can find, so the scenario is re-run on every candidate while
// appearing — to a reader of the workflow — to be covered.
//
// This caught a live misalignment: test-install.yaml's job was named
// "Provision Hetzner VM + run scenario 0-happy-install", so `covered
// 0-happy-install <commit>` could never see the smoke proof.
func TestSmokeJobNamesMatchTheirScenarios_STATBUS249C1(t *testing.T) {
	for _, tc := range []struct{ file, scenario string }{
		{"test-install.yaml", "0-happy-install"},
		{"test-upgrade.yaml", "0-happy-upgrade"},
	} {
		b, err := os.ReadFile(filepath.Join(repoRootForRelease(t), ".github", "workflows", tc.file))
		if err != nil {
			t.Fatalf("%s: %v", tc.file, err)
		}
		if !strings.Contains(string(b), "name: "+tc.scenario+"\n") {
			t.Errorf("%s must declare `name: %s` — the job name IS the evidence mark, and a mismatch makes the smoke run's proof unfindable", tc.file, tc.scenario)
		}
	}
}

func repoRootForRelease(t *testing.T) string {
	t.Helper()
	_, thisFile, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("runtime.Caller failed")
	}
	// cli/internal/release/evidence_test.go → up three = repo root.
	return filepath.Dir(filepath.Dir(filepath.Dir(filepath.Dir(thisFile))))
}

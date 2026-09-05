package release

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"
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

// TestEvidenceReadRetry_STATBUS351 pins the King's "retry before undecidable"
// ruling at the real HTTP boundary. Only named intermittent classes retry;
// deterministic authentication failures stop immediately; exhaustion names the
// last class so the caller's exit-2 diagnosis is actionable.
func TestEvidenceReadRetry_STATBUS351(t *testing.T) {
	policy := githubReadRetryPolicy{
		maxAttempts: 3,
		budget:      time.Second,
		backoffs:    []time.Duration{0, 0},
	}

	t.Run("5xx then 200 recovers with a visible attempt line", func(t *testing.T) {
		var attempts int
		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
			attempts++
			if attempts == 1 {
				http.Error(w, "temporary outage", http.StatusBadGateway)
				return
			}
			_ = json.NewEncoder(w).Encode(map[string]any{"workflow_runs": []map[string]any{}})
		}))
		defer srv.Close()

		var log bytes.Buffer
		if _, err := listRunsAtCommitWithRetry(srv.URL, WorkflowUpgradeArcHarness, "abc", policy, &log); err != nil {
			t.Fatalf("5xx then 200 must recover: %v", err)
		}
		if attempts != 2 {
			t.Fatalf("attempts = %d, want 2", attempts)
		}
		if got := log.String(); !strings.Contains(got, "attempt 1/3") || !strings.Contains(got, "class=http-5xx") || !strings.Contains(got, "HTTP 502") {
			t.Fatalf("retry line must name attempt, class, and error; got %q", got)
		}
	})

	t.Run("401 is deterministic and never retries", func(t *testing.T) {
		var attempts int
		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
			attempts++
			http.Error(w, "bad token", http.StatusUnauthorized)
		}))
		defer srv.Close()

		var log bytes.Buffer
		_, err := listRunsAtCommitWithRetry(srv.URL, WorkflowUpgradeArcHarness, "abc", policy, &log)
		if err == nil {
			t.Fatal("401 must fail")
		}
		if attempts != 1 {
			t.Fatalf("401 attempts = %d, want 1", attempts)
		}
		if log.Len() != 0 {
			t.Fatalf("deterministic failure must not print retry lines; got %q", log.String())
		}
		if !strings.Contains(err.Error(), "class=unauthorized") {
			t.Fatalf("401 error must name its class; got %v", err)
		}
	})

	t.Run("intermittent exhaustion names the last class", func(t *testing.T) {
		var attempts int
		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
			attempts++
			http.Error(w, "still down", http.StatusServiceUnavailable)
		}))
		defer srv.Close()

		var log bytes.Buffer
		_, err := listRunsAtCommitWithRetry(srv.URL, WorkflowUpgradeArcHarness, "abc", policy, &log)
		if err == nil {
			t.Fatal("exhausted 5xx must fail")
		}
		if attempts != 3 {
			t.Fatalf("attempts = %d, want 3", attempts)
		}
		if got := strings.Count(log.String(), "class=http-5xx"); got != 3 {
			t.Fatalf("retry log has %d classified attempts, want 3: %q", got, log.String())
		}
		if !strings.Contains(err.Error(), "last class=http-5xx") {
			t.Fatalf("exhaustion must name the last class; got %v", err)
		}
	})
}

func TestEvidenceReadRetry_AppliesToRunJobs_STATBUS351(t *testing.T) {
	policy := githubReadRetryPolicy{maxAttempts: 3, budget: time.Second, backoffs: []time.Duration{0, 0}}
	var attempts int
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		attempts++
		if attempts == 1 {
			http.Error(w, "temporary jobs outage", http.StatusInternalServerError)
			return
		}
		_ = json.NewEncoder(w).Encode(map[string]any{
			"total_count": 1,
			"jobs":        []map[string]any{{"name": "working", "conclusion": "success"}},
		})
	}))
	defer srv.Close()

	var log bytes.Buffer
	jobs, err := fetchRunJobsWithRetry(srv.URL, 42, policy, &log)
	if err != nil {
		t.Fatalf("jobs 5xx then 200 must recover: %v", err)
	}
	if attempts != 2 || len(jobs) != 1 || jobs[0].Name != "working" {
		t.Fatalf("attempts=%d jobs=%v, want two attempts and the decoded job", attempts, jobs)
	}
	if !strings.Contains(log.String(), "class=http-5xx") {
		t.Fatalf("jobs retry must be visible and classified; got %q", log.String())
	}
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
	scenario := arc("rollback-kill")

	got, err := LocalMarkExists(dir, scenario, "c07")
	if err != nil {
		t.Fatalf("a missing mark file must be a clean no, not an error: %v", err)
	}
	if got {
		t.Fatal("no mark was written, yet one was found")
	}

	if err := WriteLocalMark(dir, scenario, "c07"); err != nil {
		t.Fatal(err)
	}
	// Idempotent: re-running a scenario must not duplicate its mark.
	if err := WriteLocalMark(dir, scenario, "c07"); err != nil {
		t.Fatal(err)
	}
	if got, err := LocalMarkExists(dir, scenario, "c07"); err != nil || !got {
		t.Fatalf("the mark just written was not found (found=%v err=%v)", got, err)
	}
	// A mark is per scenario AND per code-state: neither axis may leak.
	if got, _ := LocalMarkExists(dir, scenario, "OTHER-COMMIT"); got {
		t.Error("a mark at one commit must not answer for another code-state")
	}
	if got, _ := LocalMarkExists(dir, arc("other-scenario"), "c07"); got {
		t.Error("a mark for one scenario must not answer for another")
	}
	if got, _ := LocalMarkExists(dir, Scenario{Name: scenario.Name, Home: WorkflowFleet}, "c07"); got {
		t.Error("a mark for one workflow home must not answer for a same-name scenario in another home")
	}

	// Composition: the local mark alone satisfies the lookup, with no CI call.
	// (The API base is unreachable here on purpose — if the lookup contacted CI
	// despite a local mark, this would fail rather than silently pass.)
	found, detail, err := ScenarioEvidence(dir, arc("rollback-kill"))("c07")
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
	if err := WriteLocalMark(dir, Scenario{}, "c07"); err == nil {
		t.Error("a mark with no scenario must be refused")
	}
	if err := WriteLocalMark(dir, arc("s"), ""); err == nil {
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

// TestWorkflowsRunningScenario_UnionsProducers_STATBUS350 pins the STATBUS-350
// contract that STATBUS-352's first cut regressed: historical marks under the
// DELETED legacy smoke workflows, the current smoke workflow, and the
// install-recovery harness must all remain discoverable for the two happy-path
// slugs, whichever home asks. Ordinary scenarios have exactly one identity.
// The union is sound only because sensitivity keys those slugs on every
// producer and consumer wrapper (TestHappyPathCompatibility in sensitivity).
func TestWorkflowsRunningScenario_UnionsProducers_STATBUS350(t *testing.T) {
	has := func(list []string, want string) bool {
		for _, w := range list {
			if w == want {
				return true
			}
		}
		return false
	}
	for _, scenario := range []Scenario{fleet("0-happy-install"), {Name: "0-happy-install", Home: WorkflowSmoke}} {
		got := WorkflowsRunningScenario(scenario)
		if got[0] != scenario.Home.String() {
			t.Errorf("%v: home must be asked first; got %v", scenario, got)
		}
		for _, want := range []string{WorkflowTestSmoke, WorkflowTestInstallLegacy, WorkflowInstallRecoveryHarness} {
			if !has(got, want) {
				t.Errorf("%v: STATBUS-350 requires %s marks to remain discoverable; got %v", scenario, want, got)
			}
		}
		if has(got, WorkflowTestUpgradeLegacy) {
			t.Errorf("%v must not ask the upgrade legacy identity; got %v", scenario, got)
		}
		seen := map[string]int{}
		for _, w := range got {
			seen[w]++
		}
		for w, n := range seen {
			if n > 1 {
				t.Errorf("%v lists %s %d times", scenario, w, n)
			}
		}
	}
	up := WorkflowsRunningScenario(fleet("0-happy-upgrade"))
	if !has(up, WorkflowTestUpgradeLegacy) || has(up, WorkflowTestInstallLegacy) {
		t.Errorf("0-happy-upgrade must ask the upgrade legacy identity only; got %v", up)
	}
	if got := WorkflowsRunningScenario(arc("rollback-pair-terminal")); len(got) != 1 || got[0] != WorkflowUpgradeArcHarness {
		t.Errorf("a one-home scenario must have exactly its home; got %v", got)
	}
}

// TestScenarioEvidence_FindsAMarkUnderALegacyIdentity_STATBUS350 is the seam end
// to end: the mark exists ONLY under the deleted legacy identity, and the
// union must still find it.
func TestScenarioEvidence_FindsAMarkUnderALegacyIdentity_STATBUS350(t *testing.T) {
	var askedFor []string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case strings.Contains(r.URL.Path, "/actions/workflows/"):
			seg := strings.Split(r.URL.Path, "/")
			wf := seg[len(seg)-2]
			askedFor = append(askedFor, wf)
			if wf == WorkflowTestUpgradeLegacy {
				_ = json.NewEncoder(w).Encode(map[string]any{"workflow_runs": []map[string]any{
					{"id": 77, "status": "completed", "conclusion": "success", "html_url": "http://legacy"},
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

	var found bool
	var detail string
	for _, wf := range WorkflowsRunningScenario(Scenario{Name: "0-happy-upgrade", Home: WorkflowSmoke}) {
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
		t.Fatalf("the mark exists under %s only; the union must find it (asked: %v)", WorkflowTestUpgradeLegacy, askedFor)
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
	b, err := os.ReadFile(filepath.Join(repoRootForRelease(t), ".github", "workflows", WorkflowTestSmoke))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(b), "name: ${{ matrix.scenario }}\n") {
		t.Errorf("%s must name each matrix job from the bare scenario selector — the resolved job name IS the evidence mark", WorkflowTestSmoke)
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

// TestEvidenceMemo_RepeatQueryMakesNoSecondCall_STATBUS252 pins the fix for a
// RESOURCE defect the shadow's "returns nothing" guarantee does not cover.
//
// The per-scenario path asks about ~31 scenarios × up to 20 candidates × up to
// 3 identities per gate run — hundreds of calls against the SAME small set of
// (workflow, commit) pairs, where the authority makes tens. `./sb release
// stable` runs its gates in sequence in ONE process, so an un-memoized shadow
// at the first gate can exhaust the API budget and make a LATER gate's
// AUTHORITY calls fail. An advisory computation must never be able to starve
// the binding one — and this is not theoretical: a live run already saw 7 of 20
// candidates come back HTTP 403.
func TestEvidenceMemo_RepeatQueryMakesNoSecondCall_STATBUS252(t *testing.T) {
	ResetEvidenceMemo()
	t.Cleanup(ResetEvidenceMemo)

	var runsCalls, jobsCalls int
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case strings.Contains(r.URL.Path, "/actions/workflows/"):
			runsCalls++
			_ = json.NewEncoder(w).Encode(map[string]any{"workflow_runs": []map[string]any{
				{"id": 42, "status": "completed", "conclusion": "success", "html_url": "http://run"},
			}})
		case strings.Contains(r.URL.Path, "/actions/runs/"):
			jobsCalls++
			_ = json.NewEncoder(w).Encode(map[string]any{"total_count": 2, "jobs": []map[string]any{
				{"name": "scenario-a", "conclusion": "success"},
				{"name": "scenario-b", "conclusion": "failure"},
			}})
		default:
			http.Error(w, "unexpected "+r.URL.Path, http.StatusNotFound)
		}
	}))
	defer srv.Close()

	// Ask about MANY scenarios at the SAME (workflow, commit) — the real shape
	// of a gate run, where the domain is dozens of scenarios and the commit set
	// is tiny.
	for i := 0; i < 25; i++ {
		if _, _, err := scenarioProvenInCIAt(srv.URL, WorkflowUpgradeArcHarness, "scenario-a", "c42"); err != nil {
			t.Fatalf("iteration %d: %v", i, err)
		}
		if _, _, err := scenarioProvenInCIAt(srv.URL, WorkflowUpgradeArcHarness, "scenario-b", "c42"); err != nil {
			t.Fatalf("iteration %d: %v", i, err)
		}
	}

	if runsCalls != 1 {
		t.Errorf("the run listing for one (workflow, commit) must be fetched ONCE per process; got %d calls across 50 scenario queries. Un-memoized, a gate run's shadow makes hundreds of these and can exhaust the API budget the AUTHORITY needs at a later gate", runsCalls)
	}
	if jobsCalls != 1 {
		t.Errorf("a run's job list must be fetched ONCE per process; got %d calls. The job list is the same bytes for every scenario asked about that run", jobsCalls)
	}

	// The memo must not change the ANSWERS — a cache that alters a verdict is
	// worse than no cache.
	found, _, err := scenarioProvenInCIAt(srv.URL, WorkflowUpgradeArcHarness, "scenario-a", "c42")
	if err != nil || !found {
		t.Errorf("memoized lookup lost a real mark (found=%v err=%v)", found, err)
	}
	found, _, err = scenarioProvenInCIAt(srv.URL, WorkflowUpgradeArcHarness, "scenario-b", "c42")
	if err != nil || found {
		t.Errorf("memoized lookup invented a mark for a FAILED job (found=%v err=%v)", found, err)
	}
}

// TestEvidenceMemo_DoesNotCacheErrors_STATBUS252: a transient failure must not
// become a permanent "no runs" answer for the rest of the process. Caching an
// error would turn one API hiccup into a fleet re-run — and, in the shadow,
// into a FABRICATED disagreement, which is the output the switch decision is
// read from.
func TestEvidenceMemo_DoesNotCacheErrors_STATBUS252(t *testing.T) {
	ResetEvidenceMemo()
	t.Cleanup(ResetEvidenceMemo)

	var attempts int
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.Contains(r.URL.Path, "/actions/workflows/") {
			attempts++
			if attempts == 1 {
				http.Error(w, "rate limited", http.StatusForbidden)
				return
			}
			_ = json.NewEncoder(w).Encode(map[string]any{"workflow_runs": []map[string]any{
				{"id": 7, "status": "completed", "conclusion": "success", "html_url": "http://run"},
			}})
			return
		}
		_ = json.NewEncoder(w).Encode(map[string]any{"total_count": 1, "jobs": []map[string]any{
			{"name": "scenario-a", "conclusion": "success"},
		}})
	}))
	defer srv.Close()

	if _, _, err := scenarioProvenInCIAt(srv.URL, WorkflowUpgradeArcHarness, "scenario-a", "c7"); err == nil {
		t.Fatal("the first call must surface the API failure")
	}
	found, _, err := scenarioProvenInCIAt(srv.URL, WorkflowUpgradeArcHarness, "scenario-a", "c7")
	if err != nil {
		t.Fatalf("the retry must reach the API again, not a cached error: %v", err)
	}
	if !found {
		t.Error("the retry found nothing — a cached failure would have made this scenario permanently 'unproven' for the rest of the process")
	}
}

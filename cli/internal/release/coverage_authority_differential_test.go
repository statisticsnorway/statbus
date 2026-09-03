package release

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// STATBUS-252, the architect's corrected AC#2 (2026-08-31): the six persisted
// shadow records are all the DEGENERATE case — one complete run covering the
// whole domain, where whole-suite and per-scenario cannot disagree. This test
// builds the case they CAN: a synthetic evidence set where NO SINGLE RUN is
// complete, but EVERY scenario is covered somewhere across runs. It asserts
// three things, per the architect's unblocking instruction:
//   - whole-suite refuses (no run anywhere is complete against the domain);
//   - per-scenario passes each individually-covered scenario;
//   - per-scenario's verdict is CORRECT — the anchor it names for each
//     scenario is cross-checked against the raw synthetic job data, not
//     merely trusted.
//
// It also covers the corrected-criterion edge in the SAME fixture: one
// scenario ("scenario-d") has evidence NOWHERE across any run — per-scenario
// must refuse it too, proving the algorithm can say no rather than defaulting
// to yes whenever *something* was found for *something*.
//
// BOTH real algorithms are exercised, not reimplemented:
//   - the whole-suite side calls workflowJobsCompleteAtCommit (the exact
//     function the promotion gate's authority uses per run), against a fake
//     GitHub API serving the SAME synthetic job data as the per-scenario side;
//   - the per-scenario side calls DecideCoverage (STATBUS-249's shared
//     algorithm) with an Evidence function backed by scenarioProvenInCIAt
//     (the exact function ScenarioEvidence composes in production) against
//     the identical fake server.
//
// One synthetic world, two real production algorithms asked the same
// question — so a genuine divergence in this test is a genuine divergence in
// production, not an artifact of two different toy models.
func TestCoverageAuthorityDifferential_PartialCoverageAcrossRuns_STATBUS252(t *testing.T) {
	ResetEvidenceMemo()
	t.Cleanup(ResetEvidenceMemo)

	// The synthetic world:
	//   c1 (oldest, tag v-rc.01): run 101 covers scenario-a ONLY.
	//   c2 (newer,  tag v-rc.02): run 201 covers scenario-b AND scenario-c.
	//   c3 (target, the RC being gated): NO run at all — nothing ran here;
	//     the gate must decide purely from what c1/c2 can inherit.
	// scenario-d appears in NEITHER run — the "covered nowhere" edge case.
	const (
		c1, c2, c3 = "c1", "c2", "c3"
		tag1, tag2 = "v-rc.01", "v-rc.02"
		run101     = int64(101)
		run201     = int64(201)
	)
	domain := []string{"scenario-a", "scenario-b", "scenario-c", "scenario-d"}

	runsByCommit := map[string][]map[string]any{
		c1: {{"id": run101, "status": "completed", "conclusion": "success", "html_url": "http://run101"}},
		c2: {{"id": run201, "status": "completed", "conclusion": "success", "html_url": "http://run201"}},
		c3: {}, // genuinely nothing ran at the target
	}
	jobsByRun := map[int64][]map[string]any{
		run101: {{"name": "scenario-a", "conclusion": "success"}},
		run201: {
			{"name": "scenario-b", "conclusion": "success"},
			{"name": "scenario-c", "conclusion": "success"},
		},
	}
	server := multiCommitRunServer(t, runsByCommit, jobsByRun)

	// ── ASSERTION 1: WHOLE-SUITE REFUSES ────────────────────────────────
	// The real per-run completeness check (workflowJobsCompleteAtCommit) —
	// the same function the promotion gate's authority calls — must find
	// NEITHER run complete against the domain. That is what "whole-suite
	// refuses" cashes out to structurally: the gate's walk asks exactly this
	// question at every candidate and never gets a yes.
	verdict101, err := workflowJobsCompleteAtCommit(server.URL, run101, domain)
	if err != nil {
		t.Fatalf("unexpected error checking run101: %v", err)
	}
	if verdict101.Complete {
		t.Fatal("run101 must NOT be complete against the full domain — it only covers scenario-a")
	}
	verdict201, err := workflowJobsCompleteAtCommit(server.URL, run201, domain)
	if err != nil {
		t.Fatalf("unexpected error checking run201: %v", err)
	}
	if verdict201.Complete {
		t.Fatal("run201 must NOT be complete against the full domain — it only covers scenario-b and scenario-c")
	}
	// Target c3 has no run at all — the missing-status branch in the real
	// gate, an even more decisive non-completion than run101/run201's
	// partial coverage. Confirmed by construction (runsByCommit[c3] is
	// empty) rather than asserted redundantly here.
	if len(runsByCommit[c3]) != 0 {
		t.Fatal("test fixture error: the target commit must have no runs")
	}
	// No run anywhere in this evidence set is complete: whole-suite refuses.

	// ── ASSERTION 2 & 3: PER-SCENARIO PASSES EACH, CORRECTLY ────────────
	// DecideCoverage — the same shared algorithm the gate's shadow (and,
	// after the switch, the gate itself) calls — walking back from the
	// target c3 through [tag2, tag1] (newest first, matching
	// PriorCandidatesNewestFirst's documented contract).
	depsFor := func(scenario string) CoverageDeps {
		return CoverageDeps{
			PriorCandidatesNewestFirst: func() ([]string, error) { return []string{tag2, tag1}, nil },
			TagCommit: func(tag string) (string, error) {
				switch tag {
				case tag1:
					return c1, nil
				case tag2:
					return c2, nil
				}
				return "", fmt.Errorf("no such tag %q", tag)
			},
			Evidence: func(commit string) (bool, string, error) {
				// The exact function ScenarioEvidence composes in
				// production for the CI half — exercised for real against
				// the fake server, not stubbed.
				return scenarioProvenInCIAt(server.URL, WorkflowUpgradeArcHarness, scenario, commit)
			},
			// Nothing sensitive changed anywhere in this synthetic history
			// — isolates the test to the coverage/completeness divergence
			// this ticket is about, not the separate path-sensitivity
			// question STATBUS-199 already covers elsewhere.
			DiffTouches: func(from, to string) (bool, []string, error) { return false, nil, nil },
		}
	}

	wantAnchor := map[string]struct{ tag, commit string }{
		"scenario-a": {tag1, c1},
		"scenario-b": {tag2, c2},
		"scenario-c": {tag2, c2},
	}
	for scenario, want := range wantAnchor {
		v, err := DecideCoverage(arc(scenario), c3, depsFor(scenario))
		if err != nil {
			t.Fatalf("%s: unexpected error: %v", scenario, err)
		}
		if !v.Covered() {
			t.Errorf("%s: per-scenario must find it COVERED (it has evidence at %s) — the divergence this test exists to prove would be lost if this failed", scenario, want.commit)
			continue
		}
		if v.Kind != CoverageCoveredBy {
			t.Errorf("%s: expected covered-by (evidence is at a prior anchor, not the target), got %q", scenario, v.Kind)
		}
		// CORRECTNESS, not just a verdict: the anchor named must be the one
		// that ACTUALLY carries the scenario in the raw synthetic job data
		// — cross-checked independently of DecideCoverage's own bookkeeping.
		if v.Anchor != want.tag || v.AnchorCommit != want.commit {
			t.Errorf("%s: anchor = (%s, %s), want (%s, %s)", scenario, v.Anchor, v.AnchorCommit, want.tag, want.commit)
		}
		runID := commitToRun(want.commit, c1, run101, c2, run201)
		if !jobListHasSuccessfulJob(jobsByRun[runID], scenario) {
			t.Errorf("%s: BUG IN THE TEST FIXTURE ITSELF — the named anchor's run does not actually contain a successful job for this scenario, so the verdict's claim is not grounded in the evidence", scenario)
		}
	}

	// ── THE CORRECTED-CRITERION EDGE: covered nowhere → per-scenario refuses too ──
	vd, err := DecideCoverage(arc("scenario-d"), c3, depsFor("scenario-d"))
	if err != nil {
		t.Fatalf("scenario-d: unexpected error: %v", err)
	}
	if vd.Covered() {
		t.Fatal("scenario-d has evidence in NEITHER run — per-scenario must refuse it. A per-scenario path that cannot say no here proves nothing about the yes cases either")
	}
	if vd.Kind != CoverageNotCovered {
		t.Errorf("scenario-d: expected not-covered, got %q", vd.Kind)
	}
	if vd.CandidatesSeen != 2 {
		t.Errorf("scenario-d: the walk must have examined both candidates before giving up, got %d", vd.CandidatesSeen)
	}
}

// multiCommitRunServer stands up the two endpoints the per-scenario evidence
// lookup uses (list runs at a head_sha; list jobs for a run id) — the SAME
// shape evidence_test.go's markServer serves, extended to route the runs
// list by head_sha too (markServer only ever serves one commit; this
// differential test needs the target and two distinct anchor commits to
// answer differently, which is the whole point of the fixture).
func multiCommitRunServer(t *testing.T, runsByCommit map[string][]map[string]any, jobsByRun map[int64][]map[string]any) *httptest.Server {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case strings.Contains(r.URL.Path, "/actions/workflows/"):
			sha := r.URL.Query().Get("head_sha")
			_ = json.NewEncoder(w).Encode(map[string]any{"workflow_runs": runsByCommit[sha]})
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

// jobListHasSuccessfulJob reports whether jobs contains a job named
// scenario that concluded success — the ground-truth check the differential
// test uses to verify an anchor's claim independently of DecideCoverage.
func jobListHasSuccessfulJob(jobs []map[string]any, scenario string) bool {
	for _, j := range jobs {
		if j["name"] == scenario && j["conclusion"] == "success" {
			return true
		}
	}
	return false
}

// commitToRun is a tiny two-entry lookup local to this test — deliberately
// not a map literal at the call site, so each anchor assertion above reads
// as "the run at this commit" rather than requiring the reader to hold a
// separate commit->run table in their head.
func commitToRun(commit, c1 string, run1 int64, c2 string, run2 int64) int64 {
	if commit == c1 {
		return run1
	}
	if commit == c2 {
		return run2
	}
	return 0
}

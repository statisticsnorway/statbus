package release

import (
	"bufio"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"strings"
)

// Evidence marks (STATBUS-249). THERE IS NO NEW STORE — the architect's ruling,
// and the reason it is the right answer: a mark for scenario X at code-state Y
// already exists as "a job named X, with conclusion success, in a run at
// head_sha Y", which is exactly what WorkflowJobsCompleteAtCommit already reads.
//
// Why not a git ref namespace, which was the obvious shape: nothing is pushed
// here, so STATBUS-236's measured rule (T) — a ref whose .github/workflows/ tree
// differs from the default branch is refused — cannot apply. The hazard is not
// managed, it is absent. No new permission, no token story, and no NEW platform
// dependency: the release gate already bets on this same API and this same
// retention in checkWorkflowAt and in the path-sensitivity walk.
//
// Why not artifacts: their retention here is 14 days (upgrade-arc-harness.yaml,
// install-recovery-harness.yaml) and 30 (test-install.yaml). Run and JOB records
// outlive that by months — the oldest install-recovery run still answering is
// twelve weeks old. A store that forgets would turn an inherited proof back into
// a bare success on a timer, which is the defect this ticket removes.
//
// AC#6 (nothing rides incomplete work) needs no new mechanism either: a
// cancelled or skipped job carries a non-success conclusion, so it is not a
// mark. rc.06's cancelled arcs cannot be mistaken for proof by this store —
// which is precisely why the Go gate was immune to the specimen while the
// tag-comparing chain was not.

// scenarioMarksDir is the LOCAL half (AC#8), keeping the ratified stamp pattern:
// a locally-run scenario records itself here, CI-run scenarios are covered by
// the job record, and ONE lookup consults both. Same shape as today's
// tmp/*-passed-sha stamps — only the granularity changes, from per-suite to
// per-scenario.
const scenarioMarksDir = "tmp/scenario-marks"

// LocalMarkPath is the file recording local passes of one scenario: one 40-hex
// commit per line, append-only.
func LocalMarkPath(projDir, scenario string) string {
	return filepath.Join(projDir, scenarioMarksDir, scenario)
}

// WriteLocalMark records that scenario passed locally at commit. Append-only and
// idempotent: re-running a scenario does not duplicate its mark.
//
// It deliberately records ONLY on the caller's assertion of success — the caller
// must not call it for a scenario that did not complete, which is AC#6 on the
// local side.
func WriteLocalMark(projDir, scenario, commit string) error {
	if scenario == "" || commit == "" {
		return fmt.Errorf("a mark needs both a scenario and a commit (got scenario=%q commit=%q) — a mark that identifies neither proves nothing", scenario, commit)
	}
	already, err := LocalMarkExists(projDir, scenario, commit)
	if err != nil {
		return err
	}
	if already {
		return nil
	}
	path := LocalMarkPath(projDir, scenario)
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return fmt.Errorf("create mark directory: %w", err)
	}
	f, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644)
	if err != nil {
		return fmt.Errorf("open mark file: %w", err)
	}
	defer func() { _ = f.Close() }()
	if _, err := fmt.Fprintln(f, commit); err != nil {
		return fmt.Errorf("write mark: %w", err)
	}
	return nil
}

// LocalMarkExists reports whether this machine recorded a pass of scenario at
// commit. A missing file is a clean "no", never an error — not having run it
// locally is the normal case.
func LocalMarkExists(projDir, scenario, commit string) (bool, error) {
	if scenario == "" || commit == "" {
		return false, fmt.Errorf("mark lookup needs both a scenario and a commit")
	}
	f, err := os.Open(LocalMarkPath(projDir, scenario))
	if err != nil {
		if os.IsNotExist(err) {
			return false, nil
		}
		return false, fmt.Errorf("read mark file: %w", err)
	}
	defer func() { _ = f.Close() }()
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		if strings.TrimSpace(sc.Text()) == commit {
			return true, nil
		}
	}
	if err := sc.Err(); err != nil {
		return false, fmt.Errorf("scan mark file: %w", err)
	}
	return false, nil
}

// runAtCommit is the minimal run record the union lookup needs.
//
// The json tags are load-bearing, not decoration: Go's default field matching is
// case-insensitive but NOT underscore-insensitive, so `HTMLURL` silently fails
// to receive `html_url` without one. Caught by running the command for real —
// the evidence line printed "in run 32187511838 ()" with an empty URL, which is
// exactly the kind of quietly-degraded operator message that reads as fine.
type runAtCommit struct {
	ID         int64  `json:"id"`
	HTMLURL    string `json:"html_url"`
	Status     string `json:"status"`
	Conclusion string `json:"conclusion"`
}

// listRunsAtCommit returns EVERY run of a workflow at a commit, newest first.
//
// This exists because checkWorkflowAt answers a different question: it returns
// the FIRST GREEN run (workflow_check.go:152-157). For a per-scenario question
// that is wrong — a smoke run and a full run can both exist at one commit, and
// first-run-wins can select the one that happens not to contain the scenario
// being asked about, reporting "not covered" while the proof sits in the other
// run at the very same commit.
func listRunsAtCommit(apiBase, workflow, commitSHA string) ([]runAtCommit, error) {
	url := fmt.Sprintf("%s/repos/%s/%s/actions/workflows/%s/runs?head_sha=%s&per_page=100",
		apiBase, githubOrg, githubRepo, workflow, commitSHA)
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return nil, fmt.Errorf("build request: %w", err)
	}
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("User-Agent", "statbus-release-check")
	if auth := githubAuthHeader(); auth != "" {
		req.Header.Set("Authorization", auth)
	}
	resp, err := httpClient().Do(req)
	if err != nil {
		return nil, fmt.Errorf("request failed: %w", err)
	}
	defer func() { _ = resp.Body.Close() }()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("GitHub API returned HTTP %d", resp.StatusCode)
	}
	var body struct {
		WorkflowRuns []runAtCommit `json:"workflow_runs"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
		return nil, fmt.Errorf("decode response: %w", err)
	}
	return body.WorkflowRuns, nil
}

// ScenarioProvenInCI reports whether ANY completed run of workflow at commitSHA
// contains a successful job named scenario — UNION across runs, never
// first-run-wins.
//
// Incomplete runs are skipped rather than consulted: a job in a still-running
// run has not concluded, and "in progress" is not proof.
func ScenarioProvenInCI(workflow, scenario, commitSHA string) (bool, string, error) {
	return scenarioProvenInCIAt("https://api.github.com", workflow, scenario, commitSHA)
}

func scenarioProvenInCIAt(apiBase, workflow, scenario, commitSHA string) (bool, string, error) {
	if scenario == "" || commitSHA == "" {
		return false, "", fmt.Errorf("evidence lookup needs both a scenario and a commit")
	}
	runs, err := listRunsAtCommit(apiBase, workflow, commitSHA)
	if err != nil {
		return false, "", err
	}
	var readErrs []string
	for _, run := range runs {
		if run.Status != "completed" {
			continue
		}
		// One required name: Complete is then exactly "this job was present AND
		// concluded success" — the per-scenario question, answered by the same
		// tested code the gate uses for whole suites.
		jobs, jerr := workflowJobsCompleteAtCommit(apiBase, run.ID, []string{scenario})
		if jerr != nil {
			readErrs = append(readErrs, fmt.Sprintf("run %d: %v", run.ID, jerr))
			continue
		}
		if jobs.Complete {
			return true, fmt.Sprintf("job %q succeeded in run %d (%s)", scenario, run.ID, run.HTMLURL), nil
		}
	}
	if len(readErrs) > 0 {
		// Some runs could not be read. Reporting a bare "not proven" here would
		// claim an examination that did not happen, so the caller is told.
		return false, "", fmt.Errorf("could not read %d run(s) at %s: %s", len(readErrs), shortSHA(commitSHA), strings.Join(readErrs, "; "))
	}
	return false, "", nil
}

// WorkflowsRunningScenario lists EVERY workflow identity that legitimately runs
// a scenario (STATBUS-249 comment #6, the Wave C seam).
//
// A scenario can leave marks under more than one identity: the smoke pair runs
// 0-happy-install and 0-happy-upgrade in their OWN dedicated workflows, and the
// install-recovery harness runs the same two scenarios in its matrix. A query
// against one identity cannot see a mark left under the other, so the
// per-scenario question must union across identities — the same union principle
// already ruled one level down for runs.
//
// WHOLE-SUITE COMPLETENESS DELIBERATELY DOES NOT UNION: "did every required job
// run?" genuinely needs one workflow's full job list, and unioning there would
// let jobs from two different runs add up to a completeness nobody achieved.
// Only the per-scenario question unions.
//
// Failure direction is safe by construction: a MISSED identity re-runs a
// scenario (costly, correct), while a wrongly-included one could only find a
// successful job of that exact name — which is a real mark.
func WorkflowsRunningScenario(homeWorkflow, scenario string) []string {
	workflows := []string{homeWorkflow}
	add := func(w string) {
		if w != homeWorkflow {
			workflows = append(workflows, w)
		}
	}
	switch scenario {
	case "0-happy-install":
		add(WorkflowTestInstall)
		add(WorkflowInstallRecoveryHarness)
	case "0-happy-upgrade":
		add(WorkflowTestUpgrade)
		add(WorkflowInstallRecoveryHarness)
	}
	return workflows
}

// ScenarioEvidence composes the halves into the ONE lookup DecideCoverage
// consumes: the local stamp first (cheap, offline, and the machine's own
// knowledge), then CI's job records across every identity that legitimately
// runs this scenario.
//
// Order matters only for cost, not for truth — a mark from any half is a mark,
// which is what "composable from a local run or from CI" (AC#8) means.
func ScenarioEvidence(projDir, workflow, scenario string) EvidenceAt {
	identities := WorkflowsRunningScenario(workflow, scenario)
	return func(commit string) (bool, string, error) {
		local, err := LocalMarkExists(projDir, scenario, commit)
		if err != nil {
			return false, "", err
		}
		if local {
			return true, fmt.Sprintf("local mark (%s)", LocalMarkPath(projDir, scenario)), nil
		}
		// Union across identities. An error from one identity is REMEMBERED but
		// does not end the search: another identity may hold a real mark, and
		// giving up on the first API hiccup would re-run work that is provably
		// covered. Only if NOTHING is found does the error surface, so the
		// caller can tell "not found" from "could not look".
		var firstErr error
		for _, wf := range identities {
			found, detail, cerr := ScenarioProvenInCI(wf, scenario, commit)
			if cerr != nil {
				if firstErr == nil {
					firstErr = fmt.Errorf("%s: %w", wf, cerr)
				}
				continue
			}
			if found {
				return true, fmt.Sprintf("%s [%s]", detail, wf), nil
			}
		}
		if firstErr != nil {
			return false, "", firstErr
		}
		return false, "", nil
	}
}

package release

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"strings"
)

// Workflow filename constants. The filename in .github/workflows/ is the
// canonical identity of each workflow — these constants MUST match it
// exactly. See doc/release-workflow-gates.md for the chain (filename →
// constant → SKIP_* env var) and rationale.
const (
	WorkflowImages                 = "images.yaml"
	WorkflowFastTests              = "fast-tests.yaml"
	WorkflowGoTest                 = "go-test.yaml"
	WorkflowTestHardening          = "test-hardening.yaml"
	WorkflowTestInstall            = "test-install.yaml"
	WorkflowInstallRecoveryHarness = "install-recovery-harness.yaml"
	WorkflowPgRegress              = "pg_regress.yaml"
	// WorkflowAppBuildLint (STATBUS-199): app/ build + lint. Never gated
	// anywhere before this — gains its first release-gate consumer at the
	// prerelease preflight (D1 layer re-map).
	WorkflowAppBuildLint = "app_build_and_lint-workflow.yaml"
	// WorkflowUpgradeArcHarness (STATBUS-199): the 31 real-dispatch upgrade
	// arcs (STATBUS-071). Gated at STABLE (needs the RC tag to exist), not
	// prerelease — same reasoning as WorkflowInstallRecoveryHarness. A
	// green run only satisfies the gate when its job list is COMPLETE
	// against the arcs present in the tree at its commit (see
	// WorkflowJobsCompleteAtCommit) — STATBUS-199 comment #4: the gate
	// verifies what ran, not what the run claims via a self-reported label.
	WorkflowUpgradeArcHarness = "upgrade-arc-harness.yaml"
	// WorkflowTestUpgrade (STATBUS-247 smoke pair, second half): the
	// install-then-upgrade happy path on an ephemeral box. Its own workflow
	// identity ON PURPOSE — a smoke run and a full harness run at the same
	// commit must never be conflated by a first-green-run query (doc-034
	// finding B).
	WorkflowTestUpgrade = "test-upgrade.yaml"
)

// WorkflowCheckStatus describes the state of a workflow at a commit.
type WorkflowCheckStatus string

const (
	WorkflowCheckGreen   WorkflowCheckStatus = "green"   // latest run: completed/success
	WorkflowCheckPending WorkflowCheckStatus = "pending" // latest run: queued or in_progress
	WorkflowCheckFailed  WorkflowCheckStatus = "failed"  // latest run: completed/<non-success>
	WorkflowCheckMissing WorkflowCheckStatus = "missing" // no runs for this commit
	WorkflowCheckUnknown WorkflowCheckStatus = "unknown" // API unreachable, auth, decode error
)

// WorkflowCheckResult is the full outcome of one CheckWorkflowAtCommit call.
type WorkflowCheckResult struct {
	Status WorkflowCheckStatus
	// RunURL is the html_url of the run cited as authoritative for this
	// status (empty for missing or unknown).
	RunURL string
	// RunID is the numeric workflow_run.id of the cited run (zero for
	// missing or unknown). Used to construct the exact
	// `gh run rerun --failed <id>` command for transient retries.
	RunID int64
	// Detail carries the conclusion string when Status=failed, and the
	// error message when Status=unknown. Empty for green/pending/missing.
	Detail string
	// BypassReason is non-empty when Status=green was returned via an
	// operator SKIP_* env-var bypass instead of a real GitHub Actions
	// run. Consumers SHOULD surface this prominently — a bypass means
	// the workflow's invariant has NOT been verified for the SHA, and
	// downstream consumers (deployment, install) may fail on missing
	// artifacts / regressed schema. Empty for normal (verified-green)
	// results.
	//
	// Currently populated only by SKIP_IMAGES=1 (since the images
	// workflow's bypass is the most dangerous — Docker artifacts may
	// not exist for the SHA). SKIP_TEST_HARDENING and SKIP_TEST_INSTALL
	// are still handled at the consumer call sites in release.go
	// because each carries its own tailored guidance text.
	BypassReason string
}

// CheckWorkflowAtCommit queries GitHub Actions for the latest run of
// `workflow` at the given commit. commitSHA must be the full 40-char SHA —
// the GitHub API returns zero matches for short SHAs. `workflow` is a
// filename like "images.yaml"; use the Workflow* constants in this file.
//
// Any-green semantics: a commit's verdict for this workflow is immutable
// once any run completed/success'd. A later retry of the same workflow
// (transient flake, tag-push duplicate, manual dispatch) can queue or
// fail without invalidating the artifact / test result. Treat any
// completed/success run for the commit as authoritative regardless of
// recency.
//
// Priority order:
//  1. Any completed/success → Green (use that run's URL/ID).
//  2. Else any not-completed → Pending (the in-flight run is the
//     operator's signal: wait for it).
//  3. Else all completed without success → Failed (use latest's
//     conclusion as the diagnostic).
func CheckWorkflowAtCommit(workflow, commitSHA string) WorkflowCheckResult {
	// SKIP_IMAGES=1 operator bypass. Effective at every consumer site —
	// pre-push hook (`./sb release verify-images`), prerelease pre-flight
	// (preflightChecks), stable pre-flight (releaseStableCmd). Use ONLY
	// when GitHub Actions or ghcr.io is genuinely unavailable; the
	// returned synthetic green result carries a BypassReason that
	// consumers MUST surface as a prominent warning. Downstream
	// deployments may fail if the SHA's Docker images don't actually
	// exist in ghcr.io.
	if workflow == WorkflowImages && os.Getenv("SKIP_IMAGES") == "1" {
		return WorkflowCheckResult{
			Status:       WorkflowCheckGreen,
			BypassReason: "SKIP_IMAGES=1 operator bypass — Docker artifacts NOT verified for this SHA. Deployments may FAIL on stale ghcr.io manifest. Use only when GitHub Actions or ghcr.io is unavailable.",
		}
	}
	return checkWorkflowRoutedAt("https://api.github.com", workflow, commitSHA)
}

// checkWorkflowRoutedAt is THE ROUTING DECISION, extracted so it can be tested.
//
// It exists because of a hole this ticket's own RED verification exposed: with
// the routing inlined above, deleting it — the single change that reverts the
// gate to the head_sha lie — left every test in this file green. The tests
// called the marker lookup directly, so they proved the lookup worked and
// nothing proved it was ever REACHED. A fix nothing routes to is not a fix.
func checkWorkflowRoutedAt(apiBase, workflow, commitSHA string) WorkflowCheckResult {
	if workflowCarriesExercisedMarker(workflow) {
		return checkWorkflowByMarkerAt(apiBase, workflow, commitSHA)
	}
	return checkWorkflowAt(apiBase, workflow, commitSHA)
}

// ─── STATBUS-285: which commit a run actually EXERCISED ─────────────────────
//
// THE LIE THIS REPLACES. `?head_sha=` asks GitHub which commit a run is filed
// under, and for a workflow_run-triggered run that is NOT the commit the run
// tested: GitHub files it under the default branch's tip AT TRIGGER TIME. So a
// green run could be credited to a commit it never touched, and the commit it
// did test could look like it had no run at all. Both directions are wrong, and
// the false-green direction is the dangerous one — it is a release gate.
//
// THE FIX IS TO ASK THE RUN ITSELF. The publisher half stamps the exercised
// commit into each run's name, which the API returns as display_title. That
// string is written by the workflow at run-creation from its own event context,
// so it says what was tested rather than what the run is filed under.
//
// SCOPED DELIBERATELY. Only the workflows that actually carry the marker are
// read this way. Applying it everywhere would turn every unmarked workflow —
// images.yaml above all — instantly Missing, which at a release gate means
// refusing a cut for a marker its workflow was never taught to emit. A gate
// that fails closed on its own rollout is still a broken gate.
const exercisedSHAMarker = "exercised-sha="

func workflowCarriesExercisedMarker(workflow string) bool {
	switch workflow {
	case WorkflowFastTests, WorkflowPgRegress:
		return true
	}
	return false
}

// exercisedSHAOf extracts the commit a run reports having exercised.
//
// STRICT, AND THE STRICTNESS IS THE POINT: the marker must be followed by
// EXACTLY 40 lowercase hex characters. A short sha, a truncated title, a
// trailing word, or a marker someone wrote by hand into a run name all return
// false rather than a partial match — because the only thing worse than no
// evidence at a release gate is evidence that is nearly right. Callers treat
// "no usable marker" as no match, never as a reason to fall back to head_sha.
func exercisedSHAOf(displayTitle string) (string, bool) {
	i := strings.Index(displayTitle, exercisedSHAMarker)
	if i < 0 {
		return "", false
	}
	rest := displayTitle[i+len(exercisedSHAMarker):]
	if len(rest) < 40 {
		return "", false
	}
	sha := rest[:40]
	// Anything directly after the 40 characters must be a boundary, not more
	// hex — otherwise a 41-character string would match on its first 40.
	if len(rest) > 40 && isHexDigit(rest[40]) {
		return "", false
	}
	for i := 0; i < 40; i++ {
		if !isHexDigit(sha[i]) {
			return "", false
		}
	}
	return sha, true
}

func isHexDigit(c byte) bool {
	return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')
}

// checkWorkflowByMarkerAt finds the run that EXERCISED commitSHA by reading
// each run's self-reported marker, rather than trusting the head_sha the run is
// filed under. Same green/pending/failed precedence as checkWorkflowAt — only
// the selection of which runs count differs.
//
// NO head_sha FILTER ON THE QUERY, deliberately. Filtering server-side would
// hand back exactly the set that is wrong for workflow_run runs: the run that
// tested this commit is filed under a different sha and would be excluded,
// while runs that never touched it would be included. So the lookback is over
// recent runs of the workflow and the marker does the selecting.
//
// A LEGACY RUN WITH NO MARKER SIMPLY DOES NOT MATCH. It is not an error and not
// a fallback — it is a run that cannot say what it tested, so it cannot be
// evidence about this commit. With no marked run in the window the result is
// Missing, which every existing consumer already handles as "no evidence".
func checkWorkflowByMarkerAt(apiBase, workflow, commitSHA string) WorkflowCheckResult {
	url := fmt.Sprintf("%s/repos/%s/%s/actions/workflows/%s/runs?per_page=100",
		apiBase, githubOrg, githubRepo, workflow)
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return WorkflowCheckResult{Status: WorkflowCheckUnknown, Detail: fmt.Sprintf("build request: %v", err)}
	}
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("User-Agent", "statbus-release-check")
	if auth := githubAuthHeader(); auth != "" {
		req.Header.Set("Authorization", auth)
	}

	resp, err := httpClient().Do(req)
	if err != nil {
		return WorkflowCheckResult{Status: WorkflowCheckUnknown, Detail: fmt.Sprintf("request failed: %v", err)}
	}
	defer func() { _ = resp.Body.Close() }()
	if resp.StatusCode != http.StatusOK {
		return WorkflowCheckResult{Status: WorkflowCheckUnknown, Detail: fmt.Sprintf("GitHub API returned HTTP %d", resp.StatusCode)}
	}

	var body struct {
		WorkflowRuns []struct {
			ID           int64  `json:"id"`
			HTMLURL      string `json:"html_url"`
			Status       string `json:"status"`
			Conclusion   string `json:"conclusion"`
			CreatedAt    string `json:"created_at"`
			DisplayTitle string `json:"display_title"`
		} `json:"workflow_runs"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
		return WorkflowCheckResult{Status: WorkflowCheckUnknown, Detail: fmt.Sprintf("decode response: %v", err)}
	}

	type run struct {
		ID         int64
		HTMLURL    string
		Status     string
		Conclusion string
	}
	var matched []run
	for _, r := range body.WorkflowRuns {
		sha, ok := exercisedSHAOf(r.DisplayTitle)
		if !ok || sha != commitSHA {
			continue
		}
		matched = append(matched, run{ID: r.ID, HTMLURL: r.HTMLURL, Status: r.Status, Conclusion: r.Conclusion})
	}
	if len(matched) == 0 {
		return WorkflowCheckResult{Status: WorkflowCheckMissing}
	}

	for _, r := range matched {
		if r.Status == "completed" && r.Conclusion == "success" {
			return WorkflowCheckResult{Status: WorkflowCheckGreen, RunURL: r.HTMLURL, RunID: r.ID}
		}
	}
	for _, r := range matched {
		if r.Status != "completed" {
			return WorkflowCheckResult{Status: WorkflowCheckPending, RunURL: r.HTMLURL, RunID: r.ID}
		}
	}
	latest := matched[0]
	return WorkflowCheckResult{Status: WorkflowCheckFailed, RunURL: latest.HTMLURL, RunID: latest.ID, Detail: latest.Conclusion}
}

// checkWorkflowAt is the testable inner variant — apiBase is the GitHub
// API root so tests can stand up an httptest server.
func checkWorkflowAt(apiBase, workflow, commitSHA string) WorkflowCheckResult {
	url := fmt.Sprintf("%s/repos/%s/%s/actions/workflows/%s/runs?head_sha=%s&per_page=10",
		apiBase, githubOrg, githubRepo, workflow, commitSHA)
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return WorkflowCheckResult{Status: WorkflowCheckUnknown, Detail: fmt.Sprintf("build request: %v", err)}
	}
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("User-Agent", "statbus-release-check")
	if auth := githubAuthHeader(); auth != "" {
		req.Header.Set("Authorization", auth)
	}

	resp, err := httpClient().Do(req)
	if err != nil {
		return WorkflowCheckResult{Status: WorkflowCheckUnknown, Detail: fmt.Sprintf("request failed: %v", err)}
	}
	defer func() { _ = resp.Body.Close() }()
	if resp.StatusCode != http.StatusOK {
		return WorkflowCheckResult{Status: WorkflowCheckUnknown, Detail: fmt.Sprintf("GitHub API returned HTTP %d", resp.StatusCode)}
	}

	var body struct {
		WorkflowRuns []struct {
			ID         int64  `json:"id"`
			HTMLURL    string `json:"html_url"`
			Status     string `json:"status"`
			Conclusion string `json:"conclusion"`
			CreatedAt  string `json:"created_at"`
		} `json:"workflow_runs"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
		return WorkflowCheckResult{Status: WorkflowCheckUnknown, Detail: fmt.Sprintf("decode response: %v", err)}
	}
	if len(body.WorkflowRuns) == 0 {
		return WorkflowCheckResult{Status: WorkflowCheckMissing}
	}

	for _, run := range body.WorkflowRuns {
		if run.Status == "completed" && run.Conclusion == "success" {
			return WorkflowCheckResult{Status: WorkflowCheckGreen, RunURL: run.HTMLURL, RunID: run.ID}
		}
	}
	for _, run := range body.WorkflowRuns {
		if run.Status != "completed" {
			return WorkflowCheckResult{Status: WorkflowCheckPending, RunURL: run.HTMLURL, RunID: run.ID}
		}
	}
	latest := body.WorkflowRuns[0]
	return WorkflowCheckResult{Status: WorkflowCheckFailed, RunURL: latest.HTMLURL, RunID: latest.ID, Detail: latest.Conclusion}
}

// UnsuccessfulJob is a required job that WAS present in the run but did
// not conclude success — the STATBUS-217 case. Conclusion is the raw
// GitHub conclusion string ("skipped", "cancelled", "failure", …), empty
// when the job carried no conclusion at all (null: queued/in-progress).
type UnsuccessfulJob struct {
	Name       string
	Conclusion string
}

// String renders one operator-facing line: the job name plus why it does
// not count as proof.
func (u UnsuccessfulJob) String() string {
	conclusion := u.Conclusion
	if conclusion == "" {
		conclusion = "none — the job never ran to completion"
	}
	return fmt.Sprintf("%s (conclusion: %s)", u.Name, conclusion)
}

// JobsCompleteness is the verdict of WorkflowJobsCompleteAtCommit. The two
// refusal buckets are kept apart on purpose (STATBUS-217 AC#2): they have
// different operator remedies. Missing means the run never contained the
// job — a subset dispatch, or a matrix that did not expand; Unsuccessful
// means the job existed and did NOT execute to a green end — a skipped or
// cancelled job, which does NOT redden its run and would otherwise pass
// unnoticed.
type JobsCompleteness struct {
	// Complete is the gate-facing verdict: every required job was present
	// AND concluded success. True only when both buckets are empty.
	Complete bool
	// Missing lists required job names absent from the run entirely.
	Missing []string
	// Unsuccessful lists required jobs present in the run that did not
	// conclude success.
	Unsuccessful []UnsuccessfulJob
}

// WorkflowJobsCompleteAtCommit is the STATBUS-199 comment #4 completeness
// check: "the gate verifies what ran, not what the run claims." A run's
// job list is ground truth the GitHub API already exposes — unlike a
// self-reported run-name label, a subset dispatch or a decide-only skip
// run cannot fake having every required job. requiredJobNames must be the
// exact job `name:` values (both upgrade-arc-harness's `run-arc` and
// install-recovery-harness's `run-scenario` matrix jobs declare
// `name: ${{ matrix.scenario }}` — the bare scenario string, no prefix).
//
// Presence is NOT proof (STATBUS-217): each required job must also have
// concluded success. Failures already redden the whole run, so the cases
// this actually closes are `skipped` and `cancelled` — neither turns a run
// red, so a green run could otherwise satisfy the gate while a required
// scenario never executed. The moment individual matrix jobs become
// skippable (a per-scenario condition, a selector mechanism, the
// STATBUS-214 orchestrator rework) that is a live hole, not a theoretical
// one.
//
// An EMPTY requiredJobNames is an error, never a pass (STATBUS-216): "is
// every required job present?" asked of an empty domain is trivially yes,
// which is how a renamed scenario directory would silently disarm the
// gate. The callers derive their domain from the tree at the commit; an
// empty derivation means the derivation itself broke.
//
// Pagination: per_page=100 covers every known matrix (31 arcs, ~15
// scenarios) plus the harness's own non-matrix jobs in one page. This
// asserts total_count <= len(returned jobs) rather than silently trusting
// a truncated first page — a growing matrix must fail loud, not pass on
// an incomplete read.
func WorkflowJobsCompleteAtCommit(runID int64, requiredJobNames []string) (JobsCompleteness, error) {
	return workflowJobsCompleteAtCommit("https://api.github.com", runID, requiredJobNames)
}

func workflowJobsCompleteAtCommit(apiBase string, runID int64, requiredJobNames []string) (JobsCompleteness, error) {
	if len(requiredJobNames) == 0 {
		return JobsCompleteness{}, fmt.Errorf("required-job list is empty — refusing to report completeness of run %d against an empty domain: every job is trivially present in an empty set, so a 0/0 pass proves nothing (STATBUS-216). The caller's scenario domain derivation is broken (moved/renamed directory, or a path typo)", runID)
	}
	url := fmt.Sprintf("%s/repos/%s/%s/actions/runs/%d/jobs?per_page=100", apiBase, githubOrg, githubRepo, runID)
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return JobsCompleteness{}, fmt.Errorf("build request: %w", err)
	}
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("User-Agent", "statbus-release-check")
	if auth := githubAuthHeader(); auth != "" {
		req.Header.Set("Authorization", auth)
	}

	resp, err := httpClient().Do(req)
	if err != nil {
		return JobsCompleteness{}, fmt.Errorf("request failed: %w", err)
	}
	defer func() { _ = resp.Body.Close() }()
	if resp.StatusCode != http.StatusOK {
		return JobsCompleteness{}, fmt.Errorf("GitHub API returned HTTP %d", resp.StatusCode)
	}

	var body struct {
		TotalCount int `json:"total_count"`
		Jobs       []struct {
			Name       string `json:"name"`
			Conclusion string `json:"conclusion"`
		} `json:"jobs"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
		return JobsCompleteness{}, fmt.Errorf("decode response: %w", err)
	}
	if body.TotalCount > len(body.Jobs) {
		return JobsCompleteness{}, fmt.Errorf("run %d has %d jobs but only %d returned on one page (per_page=100) — refusing to silently truncate the completeness check", runID, body.TotalCount, len(body.Jobs))
	}

	// A name can appear more than once (a re-run attempt returned by the
	// API, or a matrix that legitimately repeats a name). Any success for
	// the name counts — same any-green reading as CheckWorkflowAtCommit;
	// the first conclusion is what gets reported when none succeeded.
	conclusionsByName := make(map[string][]string, len(body.Jobs))
	for _, j := range body.Jobs {
		conclusionsByName[j.Name] = append(conclusionsByName[j.Name], j.Conclusion)
	}

	var verdict JobsCompleteness
	for _, name := range requiredJobNames {
		conclusions, present := conclusionsByName[name]
		if !present {
			verdict.Missing = append(verdict.Missing, name)
			continue
		}
		succeeded := false
		for _, c := range conclusions {
			if c == "success" {
				succeeded = true
				break
			}
		}
		if !succeeded {
			verdict.Unsuccessful = append(verdict.Unsuccessful, UnsuccessfulJob{Name: name, Conclusion: conclusions[0]})
		}
	}
	verdict.Complete = len(verdict.Missing) == 0 && len(verdict.Unsuccessful) == 0
	return verdict, nil
}

// WorkflowTriggerCommand returns the gh CLI invocation an operator runs to
// start `workflow`. Used in operator-facing error messages when
// CheckWorkflowAtCommit returns WorkflowCheckMissing.
//
// `ref` MUST be a branch or tag name — NOT a commit SHA. GitHub's
// workflow_dispatch API rejects raw SHAs with HTTP 422 "No ref found"; it
// only resolves branch/tag refs and builds that ref's tip. Callers must
// therefore translate the target commit into the branch/tag whose tip is
// that commit (e.g. "master" for a master-tip commit, or the RC tag for an
// RC commit) before calling this.
func WorkflowTriggerCommand(workflow, ref string) string {
	return fmt.Sprintf("gh workflow run %s --ref %s", workflow, ref)
}

// WorkflowURL returns the GitHub UI URL where `workflow`'s runs are
// listed. Used in operator-facing error messages when no specific run
// URL exists yet (WorkflowCheckMissing case).
func WorkflowURL(workflow string) string {
	return fmt.Sprintf("https://github.com/%s/%s/actions/workflows/%s",
		githubOrg, githubRepo, workflow)
}

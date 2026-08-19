package release

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
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
	return checkWorkflowAt("https://api.github.com", workflow, commitSHA)
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

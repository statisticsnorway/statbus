package release

import (
	"encoding/json"
	"fmt"
	"net/http"
)

// Workflow filename constants. The filename in .github/workflows/ is the
// canonical identity of each workflow — these constants MUST match it
// exactly. See doc/release-workflow-gates.md for the chain (filename →
// constant → SKIP_* env var) and rationale.
const (
	WorkflowImages        = "images.yaml"
	WorkflowTestHardening = "test-hardening.yaml"
	WorkflowTestInstall   = "test-install.yaml"
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
	defer resp.Body.Close()
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

// WorkflowTriggerCommand returns the gh CLI invocation an operator runs to
// start `workflow` at the given commit. Used in operator-facing error
// messages when CheckWorkflowAtCommit returns WorkflowCheckMissing.
func WorkflowTriggerCommand(workflow, commitSHA string) string {
	return fmt.Sprintf("gh workflow run %s --ref %s", workflow, commitSHA)
}

// WorkflowURL returns the GitHub UI URL where `workflow`'s runs are
// listed. Used in operator-facing error messages when no specific run
// URL exists yet (WorkflowCheckMissing case).
func WorkflowURL(workflow string) string {
	return fmt.Sprintf("https://github.com/%s/%s/actions/workflows/%s",
		githubOrg, githubRepo, workflow)
}

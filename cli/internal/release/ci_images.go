package release

import (
	"encoding/json"
	"fmt"
	"net/http"
)

// ciImagesWorkflow is the GitHub Actions workflow file that builds the four
// service Docker images on every master push and tag push. Its green/red state
// at a given commit IS the canonical "are the Docker artifacts buildable"
// signal — both prerelease pre-flight and the pre-push tag gate consult it.
//
// The slow local docker-build replay that used to live in .githooks/pre-push
// was a redundant duplicate of this same workflow.
const ciImagesWorkflow = "ci-images.yaml"

// CIImagesStatus describes the state of the ci-images.yaml workflow at a commit.
type CIImagesStatus string

const (
	CIImagesGreen   CIImagesStatus = "green"   // latest run: completed/success
	CIImagesPending CIImagesStatus = "pending" // latest run: queued or in_progress
	CIImagesFailed  CIImagesStatus = "failed"  // latest run: completed/<non-success>
	CIImagesMissing CIImagesStatus = "missing" // no runs for this commit
	CIImagesUnknown CIImagesStatus = "unknown" // API unreachable, auth, decode error
)

// CIImagesResult is the full outcome of one CheckCIImagesAtCommit call.
type CIImagesResult struct {
	Status CIImagesStatus
	// RunURL is the html_url of the latest run for this commit (empty for
	// missing or unknown).
	RunURL string
	// RunID is the numeric workflow_run.id of the latest run for this
	// commit (zero for missing or unknown). Used to construct the exact
	// `gh run rerun --failed <id>` command the operator can copy-paste
	// for transient retries.
	RunID int64
	// Detail carries the conclusion string when Status=failed, and the error
	// message when Status=unknown. Empty for green/pending/missing.
	Detail string
}

// CheckCIImagesAtCommit queries GitHub Actions for the latest ci-images.yaml run
// at the given commit. commitSHA must be the full 40-char SHA — the GitHub API
// returns zero matches for short SHAs.
func CheckCIImagesAtCommit(commitSHA string) CIImagesResult {
	return checkCIImagesAt("https://api.github.com", commitSHA)
}

// checkCIImagesAt is the testable inner variant — apiBase is the GitHub API
// root so tests can stand up an httptest server.
func checkCIImagesAt(apiBase, commitSHA string) CIImagesResult {
	url := fmt.Sprintf("%s/repos/%s/%s/actions/workflows/%s/runs?head_sha=%s&per_page=10",
		apiBase, githubOrg, githubRepo, ciImagesWorkflow, commitSHA)
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return CIImagesResult{Status: CIImagesUnknown, Detail: fmt.Sprintf("build request: %v", err)}
	}
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("User-Agent", "statbus-release-check")
	if auth := githubAuthHeader(); auth != "" {
		req.Header.Set("Authorization", auth)
	}

	resp, err := httpClient().Do(req)
	if err != nil {
		return CIImagesResult{Status: CIImagesUnknown, Detail: fmt.Sprintf("request failed: %v", err)}
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return CIImagesResult{Status: CIImagesUnknown, Detail: fmt.Sprintf("GitHub API returned HTTP %d", resp.StatusCode)}
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
		return CIImagesResult{Status: CIImagesUnknown, Detail: fmt.Sprintf("decode response: %v", err)}
	}
	if len(body.WorkflowRuns) == 0 {
		return CIImagesResult{Status: CIImagesMissing}
	}

	// Any-green semantics: a commit's Docker artifact is immutable once
	// ci-images.yaml's master-push run has built and pushed it to ghcr.io.
	// A later retry of the same workflow (e.g. tag-push duplicate, manual
	// dispatch, transient infra flake retry) can fail without unbuilding
	// the artifact. Treat any completed/success run for the commit as
	// authoritative — older or newer, doesn't matter.
	//
	// Priority order:
	//   1. Any completed/success → Green (use that run's URL/ID).
	//   2. Else any not-completed → Pending (the in-flight run is the
	//      operator's signal: wait for it).
	//   3. Else all completed without success → Failed (use latest's
	//      conclusion as the diagnostic).
	for _, run := range body.WorkflowRuns {
		if run.Status == "completed" && run.Conclusion == "success" {
			return CIImagesResult{Status: CIImagesGreen, RunURL: run.HTMLURL, RunID: run.ID}
		}
	}
	for _, run := range body.WorkflowRuns {
		if run.Status != "completed" {
			return CIImagesResult{Status: CIImagesPending, RunURL: run.HTMLURL, RunID: run.ID}
		}
	}
	latest := body.WorkflowRuns[0]
	return CIImagesResult{Status: CIImagesFailed, RunURL: latest.HTMLURL, RunID: latest.ID, Detail: latest.Conclusion}
}

// CIImagesTriggerCommand returns the gh CLI invocation an operator runs to
// start ci-images.yaml at the given commit. Used in operator-facing error
// messages when CheckCIImagesAtCommit returns CIImagesMissing.
func CIImagesTriggerCommand(commitSHA string) string {
	return fmt.Sprintf("gh workflow run %s --ref %s", ciImagesWorkflow, commitSHA)
}

// CIImagesWorkflowURL returns the GitHub UI URL where ci-images runs are
// listed. Used in operator-facing error messages when no specific run URL
// exists yet (CIImagesMissing case).
func CIImagesWorkflowURL() string {
	return fmt.Sprintf("https://github.com/%s/%s/actions/workflows/%s",
		githubOrg, githubRepo, ciImagesWorkflow)
}

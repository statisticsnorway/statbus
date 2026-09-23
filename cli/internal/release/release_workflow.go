package release

import (
	"encoding/json"
	"fmt"
	"net/http"
	"time"
)

// releaseWorkflow is the GitHub Actions workflow file that publishes the
// `gh release` assets (binaries, checksums, manifest, seed) on every tag
// push. Its green/red state for a given tag IS the "are the release
// artifacts published" signal that `./sb release verify-artifacts` reports against.
//
// Distinct from images.yaml: that workflow's tag-push trigger was
// dropped (master-push runs are authoritative for Docker artifacts).
// release.yaml's tag-push trigger MUST stay — it's the only way the
// GitHub Release gets created.
const releaseWorkflow = "release.yaml"

// ReleaseWorkflowStatus describes the state of the release.yaml workflow
// for a given tag.
type ReleaseWorkflowStatus string

const (
	ReleaseWorkflowGreen   ReleaseWorkflowStatus = "green"   // latest run completed/success
	ReleaseWorkflowPending ReleaseWorkflowStatus = "pending" // latest run queued/in_progress
	ReleaseWorkflowFailed  ReleaseWorkflowStatus = "failed"  // latest run completed/<non-success>
	ReleaseWorkflowMissing ReleaseWorkflowStatus = "missing" // no runs for this tag
	ReleaseWorkflowUnknown ReleaseWorkflowStatus = "unknown" // API unreachable / decode error
)

// ReleaseWorkflowResult is the full outcome of one CheckReleaseWorkflowAtTag call.
type ReleaseWorkflowResult struct {
	Status ReleaseWorkflowStatus
	RunURL string
	RunID  int64
	// Detail carries the conclusion string when Status=failed and the
	// error message when Status=unknown. Empty otherwise.
	Detail string
}

// CheckReleaseWorkflowAtTag queries GitHub Actions for the release.yaml
// runs triggered by the push of the given tag and reports whether any run
// successfully published that tag's artifacts. A tag push should normally
// produce one run, but GitHub can admit duplicate push deliveries as separate
// run IDs. Once one of those runs succeeds, the immutable tag's artifacts are
// published; a parallel duplicate can then fail with "Release.tag_name already
// exists" without invalidating that success.
//
// A GitHub rerun keeps the same run ID and updates that run's attempt/status,
// so scanning distinct run IDs for a success does not let an older attempt of
// one run override its newer failed attempt.
func CheckReleaseWorkflowAtTag(tag string) ReleaseWorkflowResult {
	return checkReleaseWorkflowAt("https://api.github.com", tag)
}

// checkReleaseWorkflowAt is the testable inner variant.
//
// Uses `branch=<tag>` as the filter. GitHub Actions' REST API has no
// `head_branch` query parameter (that name is a response-only field on
// each workflow run); a `head_branch=` query string is silently ignored
// and the unfiltered first page of runs comes back. The correct filter
// is `branch=`, which for a tag-trigger run matches the tag name.
func checkReleaseWorkflowAt(apiBase, tag string) ReleaseWorkflowResult {
	for attempt := 1; attempt <= 3; attempt++ {
		result := checkReleaseWorkflowOnceAt(apiBase, tag)
		if result.Status != ReleaseWorkflowMissing || attempt == 3 {
			return result
		}
		time.Sleep(250 * time.Millisecond)
	}
	panic("unreachable")
}

func checkReleaseWorkflowOnceAt(apiBase, tag string) ReleaseWorkflowResult {
	url := fmt.Sprintf("%s/repos/%s/%s/actions/workflows/%s/runs?branch=%s&event=push&per_page=10",
		apiBase, githubOrg, githubRepo, releaseWorkflow, tag)
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return ReleaseWorkflowResult{Status: ReleaseWorkflowUnknown, Detail: fmt.Sprintf("build request: %v", err)}
	}
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("User-Agent", "statbus-release-check")
	if auth := githubAuthHeader(); auth != "" {
		req.Header.Set("Authorization", auth)
	}

	resp, err := httpClient().Do(req)
	if err != nil {
		return ReleaseWorkflowResult{Status: ReleaseWorkflowUnknown, Detail: fmt.Sprintf("request failed: %v", err)}
	}
	defer func() { _ = resp.Body.Close() }()
	if resp.StatusCode != http.StatusOK {
		return ReleaseWorkflowResult{Status: ReleaseWorkflowUnknown, Detail: fmt.Sprintf("GitHub API returned HTTP %d", resp.StatusCode)}
	}

	var body struct {
		WorkflowRuns []struct {
			ID         int64  `json:"id"`
			HTMLURL    string `json:"html_url"`
			Status     string `json:"status"`
			Conclusion string `json:"conclusion"`
		} `json:"workflow_runs"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
		return ReleaseWorkflowResult{Status: ReleaseWorkflowUnknown, Detail: fmt.Sprintf("decode response: %v", err)}
	}
	if len(body.WorkflowRuns) == 0 {
		return ReleaseWorkflowResult{Status: ReleaseWorkflowMissing}
	}

	// GitHub returns newest first. Prefer any successful distinct run because
	// release publication is an idempotent fact for this immutable tag. Keep
	// the newest run as the diagnostic when no run succeeded.
	for _, run := range body.WorkflowRuns {
		if run.Status == "completed" && run.Conclusion == "success" {
			return ReleaseWorkflowResult{Status: ReleaseWorkflowGreen, RunURL: run.HTMLURL, RunID: run.ID}
		}
	}
	latest := body.WorkflowRuns[0]
	switch {
	case latest.Status != "completed":
		return ReleaseWorkflowResult{Status: ReleaseWorkflowPending, RunURL: latest.HTMLURL, RunID: latest.ID}
	default:
		return ReleaseWorkflowResult{Status: ReleaseWorkflowFailed, RunURL: latest.HTMLURL, RunID: latest.ID, Detail: latest.Conclusion}
	}
}

// ReleaseWorkflowURL returns the GitHub UI URL where release.yaml runs
// are listed — used in operator-facing error messages when no specific
// run exists yet (the missing case).
func ReleaseWorkflowURL() string {
	return fmt.Sprintf("https://github.com/%s/%s/actions/workflows/%s",
		githubOrg, githubRepo, releaseWorkflow)
}

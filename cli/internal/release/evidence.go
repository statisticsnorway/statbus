package release

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
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

// githubReadRetryPolicy is deliberately small and typed: only the classes
// githubReadAttempt marks intermittent may enter this loop. Everything else is
// deterministic and returns on its first attempt. Tests pass a zero-backoff
// policy through the same HTTP functions production uses.
type githubReadRetryPolicy struct {
	maxAttempts int
	budget      time.Duration
	backoffs    []time.Duration
}

var defaultGitHubReadRetryPolicy = githubReadRetryPolicy{
	maxAttempts: 3,
	budget:      30 * time.Second,
	backoffs:    []time.Duration{2 * time.Second, 5 * time.Second},
}

type githubReadFailure struct {
	class     string
	err       error
	retryable bool
}

func (f githubReadFailure) Error() string { return f.err.Error() }

// githubRead retries only named intermittent failures. Every intermittent
// attempt is visible on stderr, including the final exhausted attempt, so a
// recovered transient and an exit-2 exhaustion both explain themselves.
func githubRead(url string, policy githubReadRetryPolicy, retryLog io.Writer) ([]byte, error) {
	if policy.maxAttempts < 1 {
		policy.maxAttempts = 1
	}
	if policy.budget <= 0 {
		policy.budget = defaultGitHubReadRetryPolicy.budget
	}
	if retryLog == nil {
		retryLog = io.Discard
	}

	ctx, cancel := context.WithTimeout(context.Background(), policy.budget)
	defer cancel()

	var last githubReadFailure
	for attempt := 1; attempt <= policy.maxAttempts; attempt++ {
		body, failure := githubReadAttempt(ctx, url)
		if failure == nil {
			return body, nil
		}
		last = *failure
		if !failure.retryable {
			return nil, fmt.Errorf("GitHub evidence read failed (class=%s): %w", failure.class, failure.err)
		}

		fmt.Fprintf(retryLog, "GitHub evidence read attempt %d/%d failed: class=%s error=%v\n",
			attempt, policy.maxAttempts, failure.class, failure.err)
		if attempt == policy.maxAttempts {
			break
		}

		delay := time.Duration(0)
		if i := attempt - 1; i < len(policy.backoffs) {
			delay = policy.backoffs[i]
		}
		if delay > 0 {
			timer := time.NewTimer(delay)
			select {
			case <-timer.C:
			case <-ctx.Done():
				if !timer.Stop() {
					select {
					case <-timer.C:
					default:
					}
				}
				return nil, fmt.Errorf("GitHub evidence read retry budget exhausted after %d attempt(s) (last class=%s): %w", attempt, last.class, last.err)
			}
		}
	}

	return nil, fmt.Errorf("GitHub evidence read retry exhausted after %d attempt(s) (last class=%s): %w",
		policy.maxAttempts, last.class, last.err)
}

func githubReadAttempt(ctx context.Context, url string) ([]byte, *githubReadFailure) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, &githubReadFailure{class: "request", err: fmt.Errorf("build request: %w", err)}
	}
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("User-Agent", "statbus-release-check")
	if auth := githubAuthHeader(); auth != "" {
		req.Header.Set("Authorization", auth)
	}

	resp, err := httpClient().Do(req)
	if err != nil {
		class := "network"
		var netErr net.Error
		if errors.Is(err, context.DeadlineExceeded) || errors.As(err, &netErr) && netErr.Timeout() {
			class = "timeout"
		}
		return nil, &githubReadFailure{class: class, err: fmt.Errorf("request failed: %w", err), retryable: true}
	}
	defer func() { _ = resp.Body.Close() }()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		class := "network"
		var netErr net.Error
		if errors.Is(err, context.DeadlineExceeded) || errors.As(err, &netErr) && netErr.Timeout() {
			class = "timeout"
		}
		return nil, &githubReadFailure{class: class, err: fmt.Errorf("read response: %w", err), retryable: true}
	}
	if resp.StatusCode == http.StatusOK {
		return body, nil
	}

	failure := githubReadFailure{err: fmt.Errorf("GitHub API returned HTTP %d", resp.StatusCode)}
	switch {
	case resp.StatusCode >= 500 && resp.StatusCode <= 599:
		failure.class, failure.retryable = "http-5xx", true
	case resp.StatusCode == http.StatusTooManyRequests:
		failure.class, failure.retryable = "rate-limit", true
	case resp.StatusCode == http.StatusForbidden && hasRateLimitHeaders(resp.Header):
		failure.class, failure.retryable = "rate-limit", true
	case resp.StatusCode == http.StatusUnauthorized:
		failure.class = "unauthorized"
	case resp.StatusCode == http.StatusForbidden:
		failure.class = "forbidden"
	case resp.StatusCode == http.StatusNotFound:
		failure.class = "not-found"
	default:
		failure.class = "http-status"
	}
	return nil, &failure
}

func hasRateLimitHeaders(header http.Header) bool {
	for _, name := range []string{"Retry-After", "X-RateLimit-Limit", "X-RateLimit-Remaining", "X-RateLimit-Reset", "X-RateLimit-Resource"} {
		if header.Get(name) != "" {
			return true
		}
	}
	return false
}

func decodeGitHubEvidence(body []byte, target any) error {
	if err := json.Unmarshal(body, target); err != nil {
		return fmt.Errorf("GitHub evidence read failed (class=decode): decode response: %w", err)
	}
	return nil
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
	return listRunsAtCommitWithRetry(apiBase, workflow, commitSHA, defaultGitHubReadRetryPolicy, os.Stderr)
}

func listRunsAtCommitWithRetry(apiBase, workflow, commitSHA string, policy githubReadRetryPolicy, retryLog io.Writer) ([]runAtCommit, error) {
	url := fmt.Sprintf("%s/repos/%s/%s/actions/workflows/%s/runs?head_sha=%s&per_page=100",
		apiBase, githubOrg, githubRepo, workflow, commitSHA)
	bodyBytes, err := githubRead(url, policy, retryLog)
	if err != nil {
		return nil, err
	}
	var body struct {
		WorkflowRuns []runAtCommit `json:"workflow_runs"`
	}
	if err := decodeGitHubEvidence(bodyBytes, &body); err != nil {
		return nil, err
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
	runs, err := runsAtCommitMemoized(apiBase, workflow, commitSHA)
	if err != nil {
		return false, "", err
	}
	var readErrs []string
	for _, run := range runs {
		if run.Status != "completed" {
			continue
		}
		jobs, jerr := jobsForRunMemoized(apiBase, run.ID)
		if jerr != nil {
			readErrs = append(readErrs, fmt.Sprintf("run %d: %v", run.ID, jerr))
			continue
		}
		// A mark is a job of this name that CONCLUDED SUCCESS. A name can repeat
		// (a re-run attempt, or a matrix that legitimately reuses it) — any
		// success counts, the same any-green reading the whole-suite check uses.
		for _, j := range jobs {
			if j.Name == scenario && j.Conclusion == "success" {
				return true, fmt.Sprintf("job %q succeeded in run %d (%s)", scenario, run.ID, run.HTMLURL), nil
			}
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
func WorkflowsRunningScenario(scenario Scenario) []string {
	home := scenario.Home.String()
	workflows := []string{home}
	add := func(w string) {
		if w != home {
			workflows = append(workflows, w)
		}
	}
	switch scenario.Name {
	case "0-happy-install":
		add(WorkflowTestSmoke)
		add(WorkflowTestInstallLegacy)
		add(WorkflowInstallRecoveryHarness)
	case "0-happy-upgrade":
		add(WorkflowTestSmoke)
		add(WorkflowTestUpgradeLegacy)
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
func ScenarioEvidence(projDir string, scenario Scenario) EvidenceAt {
	identities := WorkflowsRunningScenario(scenario)
	return func(commit string) (bool, string, error) {
		local, err := LocalMarkExists(projDir, scenario.Name, commit)
		if err != nil {
			return false, "", err
		}
		if local {
			return true, fmt.Sprintf("local mark (%s)", LocalMarkPath(projDir, scenario.Name)), nil
		}
		// Union across identities. An error from one identity is REMEMBERED but
		// does not end the search: another identity may hold a real mark, and
		// giving up on the first API hiccup would re-run work that is provably
		// covered. Only if NOTHING is found does the error surface, so the
		// caller can tell "not found" from "could not look".
		var firstErr error
		for _, wf := range identities {
			found, detail, cerr := ScenarioProvenInCI(wf, scenario.Name, commit)
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

// ─────────────────────────────────────────────────────────────────────────
// PROCESS-LIFETIME MEMO (STATBUS-252 precondition).
//
// THE DEFECT THIS CLOSES is a resource channel, not a logic one, which is why
// the shadow's "returns nothing" guarantee does not cover it. Per gate run the
// per-scenario path asks about ~31 scenarios × up to 20 candidate commits × up
// to 3 workflow identities — hundreds of API calls against the SAME small set
// of (workflow, commit) pairs, where the authority makes tens. `./sb release
// stable` runs its gates in sequence in ONE process, so a shadow at the first
// gate can exhaust the API budget and make a LATER gate's AUTHORITY calls fail.
// An advisory computation must never be able to starve the binding one.
//
// Not theoretical: a live run of this library already saw 7 of 20 candidates
// come back unreadable (HTTP 403) on an unauthenticated budget.
//
// The memo keys on (workflow, commit) for run listings and on run id for job
// listings — the two things asked repeatedly with identical arguments — which
// collapses the repeat work to roughly the authority's own call count.
//
// LIFETIME IS THE PROCESS, DELIBERATELY. A gate run is a single decision about
// a single moment; caching across it is what makes the numbers add up. A
// long-lived daemon would need invalidation, and this is not one.
// ─────────────────────────────────────────────────────────────────────────

type evidenceMemo struct {
	mu   sync.Mutex
	runs map[string][]runAtCommit
	jobs map[string][]jobRecord
}

// jobRecord is one job's name and conclusion — the raw material both the
// per-scenario question and the whole-suite question are computed from.
type jobRecord struct {
	Name       string `json:"name"`
	Conclusion string `json:"conclusion"`
}

var memo = &evidenceMemo{
	runs: map[string][]runAtCommit{},
	jobs: map[string][]jobRecord{},
}

// ResetEvidenceMemo clears the memo. Tests use it to prove the memo is doing
// the work; production never calls it, because the process IS the lifetime.
func ResetEvidenceMemo() {
	memo.mu.Lock()
	defer memo.mu.Unlock()
	memo.runs = map[string][]runAtCommit{}
	memo.jobs = map[string][]jobRecord{}
}

// runsAtCommitMemoized returns every run of a workflow at a commit, asking the
// API at most once per (workflow, commit) per process.
//
// Errors are NOT cached: a transient failure must not become a permanent
// "no runs" answer for the rest of the process, which would turn one API
// hiccup into a fleet re-run and — worse — into a fabricated disagreement in
// the shadow's own output.
func runsAtCommitMemoized(apiBase, workflow, commitSHA string) ([]runAtCommit, error) {
	// apiBase is PART OF THE KEY. Without it two different API roots collide —
	// benign in production, where there is one, but wrong in principle and it
	// silently crossed answers between two test servers the moment the memo
	// landed. A cache keyed on less than its inputs is a cache that can return
	// another question's answer.
	key := apiBase + "\x00" + workflow + "\x00" + commitSHA
	memo.mu.Lock()
	if cached, ok := memo.runs[key]; ok {
		memo.mu.Unlock()
		return cached, nil
	}
	memo.mu.Unlock()

	runs, err := listRunsAtCommit(apiBase, workflow, commitSHA)
	if err != nil {
		return nil, err
	}
	memo.mu.Lock()
	memo.runs[key] = runs
	memo.mu.Unlock()
	return runs, nil
}

// jobsForRunMemoized returns a run's job records, asking the API at most once
// per run id per process. Same no-caching-of-errors rule as above.
func jobsForRunMemoized(apiBase string, runID int64) ([]jobRecord, error) {
	key := fmt.Sprintf("%s\x00%d", apiBase, runID)
	memo.mu.Lock()
	if cached, ok := memo.jobs[key]; ok {
		memo.mu.Unlock()
		return cached, nil
	}
	memo.mu.Unlock()

	jobs, err := fetchRunJobs(apiBase, runID)
	if err != nil {
		return nil, err
	}
	memo.mu.Lock()
	memo.jobs[key] = jobs
	memo.mu.Unlock()
	return jobs, nil
}

// fetchRunJobs reads one run's job list. Kept separate from
// WorkflowJobsCompleteAtCommit's verdict logic so the raw records can be cached
// and reused for BOTH questions — the per-scenario one asked here and the
// whole-suite one asked by the authority.
func fetchRunJobs(apiBase string, runID int64) ([]jobRecord, error) {
	return fetchRunJobsWithRetry(apiBase, runID, defaultGitHubReadRetryPolicy, os.Stderr)
}

func fetchRunJobsWithRetry(apiBase string, runID int64, policy githubReadRetryPolicy, retryLog io.Writer) ([]jobRecord, error) {
	url := fmt.Sprintf("%s/repos/%s/%s/actions/runs/%d/jobs?per_page=100", apiBase, githubOrg, githubRepo, runID)
	bodyBytes, err := githubRead(url, policy, retryLog)
	if err != nil {
		return nil, err
	}
	var body struct {
		TotalCount int         `json:"total_count"`
		Jobs       []jobRecord `json:"jobs"`
	}
	if err := decodeGitHubEvidence(bodyBytes, &body); err != nil {
		return nil, err
	}
	if body.TotalCount > len(body.Jobs) {
		// Same refusal as the whole-suite reader: a truncated page would make a
		// present job look missing, and here that reads as "not covered".
		return nil, fmt.Errorf("run %d has %d jobs but only %d returned on one page (per_page=100) — refusing to answer from a truncated read", runID, body.TotalCount, len(body.Jobs))
	}
	return body.Jobs, nil
}

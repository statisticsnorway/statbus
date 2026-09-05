package cmd

// STATBUS-224: workflow trigger facts are asserted by PARSING the YAML, never by
// matching the file's text.
//
// The old pin used `strings.Contains(wfText, "v*-rc.*")`, so any occurrence
// satisfied it — including one inside a comment. Observed 2026-08-18: after the
// tag trigger was REMOVED from test-install.yaml, the pin still passed, because
// the comment left behind explaining the move contained the literal trigger
// text. The test asserted a fact that had just stopped being true, which is
// worse than having no test: it reports a guarantee nobody is checking.
//
// Comments do not survive parsing. That is the whole fix.

import (
	"fmt"
	"os"
	"regexp"
	"sort"
	"strings"
	"testing"

	"gopkg.in/yaml.v3"
)

// workflowPushTriggers returns the `on.push` block of a workflow, parsed.
//
// THE `on:` KEY TRAP: in YAML 1.1 the bare word `on` is a BOOLEAN, so a naive
// parse can land the trigger block under the key `true` instead of `"on"`.
// gopkg.in/yaml.v3 follows the YAML 1.2 core schema (only true/false are
// booleans), so `on` decodes as the string — but this helper checks BOTH keys
// anyway rather than depending on which spec the parser follows. A pin that
// silently found nothing would pass every assertion below by vacuous truth,
// which is precisely the failure mode STATBUS-224 exists to remove.
func workflowPushTriggers(t *testing.T, relPath string) map[string]any {
	t.Helper()
	data, err := os.ReadFile(thisRepoFile(t, relPath))
	if err != nil {
		t.Fatalf("cannot read %s: %v", relPath, err)
	}
	var doc map[any]any
	if err := yaml.Unmarshal(data, &doc); err != nil {
		t.Fatalf("%s is not parseable YAML (%v) — a workflow that does not parse cannot be reasoned about at all", relPath, err)
	}

	onBlock, ok := doc["on"]
	if !ok {
		onBlock, ok = doc[true] // a YAML 1.1 parser lands the block here
	}
	if !ok {
		t.Fatalf("%s has no `on:` block — either the trigger was deleted or this parse is wrong; both must fail loudly rather than vacuously pass", relPath)
	}
	onMap := asStringMap(t, relPath, "on", onBlock)
	push, ok := onMap["push"]
	if !ok {
		return nil // no push trigger at all; callers assert what that means for them
	}
	return asStringMap(t, relPath, "on.push", push)
}

// asStringMap normalises a decoded YAML mapping to string keys, accepting both
// shapes a parser may produce (map[string]any in YAML 1.2, map[any]any where a
// bare key like `on` decoded as a non-string). Anything that is not a mapping
// fails loudly rather than returning an empty map that would satisfy every
// assertion by vacuous truth.
func asStringMap(t *testing.T, relPath, field string, raw any) map[string]any {
	t.Helper()
	switch m := raw.(type) {
	case map[string]any:
		return m
	case map[any]any:
		out := make(map[string]any, len(m))
		for k, v := range m {
			out[fmt.Sprintf("%v", k)] = v
		}
		return out
	default:
		t.Fatalf("%s: `%s` is %T, not a mapping — cannot inspect triggers structurally", relPath, field, raw)
		return nil
	}
}

// yamlStringList reads a YAML sequence-of-strings field, tolerating both the
// flow form (`tags: ['v*']`) and the block form (`tags:\n  - 'v*'`) — they parse
// identically, which is exactly why parsing beats text matching.
func yamlStringList(t *testing.T, relPath, field string, block map[string]any) []string {
	t.Helper()
	raw, ok := block[field]
	if !ok {
		return nil
	}
	items, ok := raw.([]any)
	if !ok {
		t.Fatalf("%s: `on.push.%s` is %T, not a list", relPath, field, raw)
	}
	out := make([]string, 0, len(items))
	for _, it := range items {
		s, ok := it.(string)
		if !ok {
			t.Fatalf("%s: `on.push.%s` contains a %T, not a string", relPath, field, it)
		}
		out = append(out, s)
	}
	return out
}

// TestTagFiredWorkflows_TriggersParsedNotGrepped_STATBUS224 re-asserts the
// STATBUS-205 layering fact structurally, for EVERY row of the pinned table
// (AC#3): each workflow's `on.push.tags` really declares the RC-tag pattern, and
// `on.push.branches` really is absent. A comment mentioning either can no longer
// satisfy anything.
func TestTagFiredWorkflows_TriggersParsedNotGrepped_STATBUS224(t *testing.T) {
	const rcTagPattern = "v*-rc.*"
	for _, wf := range tagFiredWorkflows {
		t.Run(wf.yaml, func(t *testing.T) {
			push := workflowPushTriggers(t, wf.yaml)
			if push == nil {
				t.Fatalf("%s has no `on.push` trigger at all — the STATBUS-205 stable-layer gating of %s rests on it firing at the RC tag", wf.yaml, wf.workflow)
			}

			tags := yamlStringList(t, wf.yaml, "tags", push)
			found := false
			for _, tag := range tags {
				if tag == rcTagPattern {
					found = true
					break
				}
			}
			if !found {
				t.Errorf("%s no longer declares the %s tag-push trigger in on.push.tags (parsed: %v) — the STATBUS-205 stable-layer gating of %s rests on that trigger fact; re-decide the gate layer together with this trigger change",
					wf.yaml, rcTagPattern, tags, wf.workflow)
			}

			// A branch-push trigger would dissolve the deadlock argument that
			// justifies gating these at stable rather than at prerelease.
			if branches := yamlStringList(t, wf.yaml, "branches", push); len(branches) > 0 {
				t.Errorf("%s now has a branch-push trigger (on.push.branches = %v) — it is no longer purely tag-fired, so the STATBUS-205 deadlock argument for gating it at stable rather than prerelease no longer holds and the layer must be re-decided",
					wf.yaml, branches)
			}
		})
	}
}

// exemptPathsIgnoreWorkflows are the workflows whose `on.push.paths-ignore` is a
// STANDING COPY of ops/release/ci-exempt-paths.txt.
//
// Three copies exist by STRUCTURAL NECESSITY, not by neglect: GitHub evaluates
// path filters server-side, before any job or checkout runs, so a trigger filter
// cannot read the checked-in list — and images.yaml's bash port cannot either,
// for the same reason. Collapsing them was ruled AGAINST for that reason. What
// CAN be enforced is that they agree.
var exemptPathsIgnoreWorkflows = []string{
	".github/workflows/go-test.yaml",
	".github/workflows/app_build_and_lint-workflow.yaml",
}

// TestPathsIgnoreMatchesExemptList_STATBUS224 pins the copies equal, so adding an
// exempt path in one place fails until all of them agree.
//
// FAIL-TOWARD-FULL-BUILD, the same direction as everywhere else in this system:
// a paths-ignore that ignores MORE than the preflight exempts is not a wait, it
// is a HARD STOP — the workflow never runs, so no run exists at the tip, and the
// preflight's ancestor-ride cannot rescue a commit it does not consider exempt.
// A paths-ignore that ignores LESS merely costs a redundant run. The equality
// assertion is what keeps the dangerous direction unreachable.
func TestPathsIgnoreMatchesExemptList_STATBUS224(t *testing.T) {
	exempt, err := loadCIExemptPaths(thisRepoFile(t, "."))
	if err != nil {
		t.Fatalf("loadCIExemptPaths: %v", err)
	}
	if len(exempt) == 0 {
		t.Fatal("the exempt list is empty — if that is deliberate, these paths-ignore filters must be emptied too")
	}

	// MAPPING, stated explicitly because the two dialects differ: the Go
	// matcher's entry is an anchored path PREFIX (`.backlog/` matches every file
	// beneath it), while GitHub's filter is a GLOB (`.backlog/**`). A directory
	// entry `X/` therefore corresponds to exactly `X/**`; a non-directory entry
	// corresponds to itself.
	want := make([]string, 0, len(exempt))
	for _, entry := range exempt {
		if strings.HasSuffix(entry, "/") {
			want = append(want, entry+"**")
			continue
		}
		want = append(want, entry)
	}
	sort.Strings(want)

	for _, wfPath := range exemptPathsIgnoreWorkflows {
		t.Run(wfPath, func(t *testing.T) {
			push := workflowPushTriggers(t, wfPath)
			if push == nil {
				t.Fatalf("%s has no `on.push` trigger — it can no longer carry a paths-ignore copy of the exempt list", wfPath)
			}
			got := yamlStringList(t, wfPath, "paths-ignore", push)
			sort.Strings(got)

			if !equalStringSlicesLocal(got, want) {
				t.Errorf("%s's on.push.paths-ignore does not match ops/release/ci-exempt-paths.txt.\n  paths-ignore: %v\n  expected:     %v (from the exempt list, with `X/` mapped to `X/**`)\n\n"+
					"The exempt list necessarily exists in THREE copies — this file's trigger filter, images.yaml's bash port, and the Go matcher — because GitHub evaluates path filters server-side before any code exists to read the checked-in list. Adding an exempt path means updating all three. Ignoring MORE here than the preflight exempts is a HARD STOP, not a wait: the workflow never runs, no run exists at the tip, and the ancestor-ride cannot rescue a commit it does not consider exempt.",
					wfPath, got, want)
			}
		})
	}
}

func equalStringSlicesLocal(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

// STATBUS-237 — the two halves of the Go-test-cache safety story (STATBUS-234's
// `-count=1` and STATBUS-235's live CI cache) were held together by PROSE:
// test workflows carry a comment explaining `-count=1` must stay, and
// build-only workflows carry a comment stating they never run tests. Both are
// true today; neither is enforced. A future editor adding a `go test` step to
// a build-only workflow, or trimming `-count=1` from a test one, re-opens the
// staleness with nothing to notice — same class as STATBUS-197 and STATBUS-224:
// a comment stating a condition-dependent fact that a later change quietly
// falsifies.
//
// goTestInvocationRe / countEqualsOneRe operate on ONE LINE of a `run:` block
// at a time (a block can be multi-line — STATBUS-118-style scripts with
// `set -euo pipefail` followed by several commands), so `-count=1` is required
// on the SAME line that invokes `go test`, not merely anywhere in the step —
// a step that runs `go test ./foo` on one line and `go test ./bar -count=1`
// on another must fail on the first line specifically.
var (
	goTestInvocationRe = regexp.MustCompile(`(?:^|[\s;&|(])go\s+test(?:[\s;&|)]|$)`)
	countEqualsOneRe   = regexp.MustCompile(`(?:^|\s)-count=1(?:\s|$)`)
)

// allWorkflowYAMLFiles enumerates every file under .github/workflows/ (AC#3 —
// no maintained list of which workflows run tests; the check reads what each
// one actually does, so a NEW workflow is covered automatically).
func allWorkflowYAMLFiles(t *testing.T) []string {
	t.Helper()
	dir := thisRepoFile(t, ".github/workflows")
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatalf("cannot list .github/workflows: %v", err)
	}
	out := make([]string, 0, len(entries))
	for _, e := range entries {
		if e.IsDir() {
			continue
		}
		name := e.Name()
		if strings.HasSuffix(name, ".yaml") || strings.HasSuffix(name, ".yml") {
			out = append(out, ".github/workflows/"+name)
		}
	}
	sort.Strings(out)
	return out
}

// TestGoTestStepsCarryCountEqualsOne_STATBUS237 pins the STATBUS-234/235
// invariant as a mechanism instead of prose: any workflow step whose `run`
// command invokes `go test` must also carry `-count=1` on that same command
// line. STATBUS-234 established why — several of our most important tests are
// PINS that read files outside the Go module, and Go's test cache does not
// track them, so a cached "ok" can vouch for outside-module content that has
// since changed. STATBUS-235 then turned the CI build cache on, which is the
// state that makes a missed `-count=1` bite instead of merely being slow.
//
// AC#3: walks EVERY file in .github/workflows/ (allWorkflowYAMLFiles) — no
// maintained list of which ones run tests.
// AC#4: inspects the PARSED `run:` string from the YAML document, never the
// raw file text. YAML-level comments (anything above a `run:` key) never
// reach the decoded value at all — that is STATBUS-224's whole point, and it
// falls out of using yaml.v3 rather than text search. A shell `#` comment
// LINE *inside* a run: block's own script text is additionally skipped
// explicitly below (it IS part of the parsed string, since YAML does not
// understand shell syntax), so prose like `# remember: go test needs
// -count=1` cannot satisfy or trip the check either way.
//
// BOUNDARY (architect, STATBUS-237 review): a check must report what it
// examined, including in its own documentation — "is our test cache safe?"
// must never be answered by someone who did not check what this pin actually
// looks at. This pin walks .github/workflows/*.y{a,}ml and matches literal
// `go test` in each step's PARSED `run:` text. It does NOT see: a `go test`
// invocation hidden inside a script a workflow merely CALLS (`./dev.sh test`
// is the live example — dev.sh's own internals are unexamined here); a
// composite action under .github/actions/ (none currently run `go test`,
// verified by inspection at STATBUS-237 review time); or a `go test`
// embedded inside a quoted `sh -c '...'` string (the regexes match the
// OUTER line's tokens, not a nested shell parse).
// None of these exist in this repo today. This sentence exists so that fact
// is stated, not assumed.
//
// STRICT BY DESIGN — line continuations are a KNOWN, ACCEPTED false
// positive, not a bug to fix: `run: go test ./... \` with `-count=1` on the
// following line FAILS this pin, because the two lines are checked
// independently and neither one alone carries both the invocation and the
// flag. The "obvious" fix — join `\`-continued lines before matching — must
// NOT be made: it would trade one harmless false alarm (an operator adds a
// parenthesis and reruns) for a REAL false negative (a `-count=1` sitting on
// a physically different, unrelated command line could then satisfy a `go
// test` invocation on another line entirely, which is exactly the
// same-command-line requirement this pin exists to enforce). A false RED
// that is loud and cheap to fix beats a false GREEN that vouches for the
// wrong command. Strict, per-line matching is the safe direction; keep it.
func TestGoTestStepsCarryCountEqualsOne_STATBUS237(t *testing.T) {
	for _, wfPath := range allWorkflowYAMLFiles(t) {
		wfPath := wfPath
		t.Run(wfPath, func(t *testing.T) {
			data, err := os.ReadFile(thisRepoFile(t, wfPath))
			if err != nil {
				t.Fatalf("cannot read %s: %v", wfPath, err)
			}
			var doc map[string]any
			if err := yaml.Unmarshal(data, &doc); err != nil {
				t.Fatalf("%s is not parseable YAML (%v) — a workflow that does not parse cannot be reasoned about at all", wfPath, err)
			}

			jobsRaw, ok := doc["jobs"]
			if !ok {
				return // no jobs at all — nothing to walk (e.g. a workflow that only reads inputs)
			}
			jobs := asStringMap(t, wfPath, "jobs", jobsRaw)

			jobNames := make([]string, 0, len(jobs))
			for name := range jobs {
				jobNames = append(jobNames, name)
			}
			sort.Strings(jobNames) // deterministic order — stable failure output across runs

			for _, jobName := range jobNames {
				job := asStringMap(t, wfPath, "jobs."+jobName, jobs[jobName])
				stepsRaw, ok := job["steps"]
				if !ok {
					continue // e.g. a job that only calls a reusable workflow via `uses:` at job level
				}
				steps, ok := stepsRaw.([]any)
				if !ok {
					t.Fatalf("%s: jobs.%s.steps is %T, not a list", wfPath, jobName, stepsRaw)
				}

				for i, stepRaw := range steps {
					step := asStringMap(t, wfPath, fmt.Sprintf("jobs.%s.steps[%d]", jobName, i), stepRaw)
					runRaw, ok := step["run"]
					if !ok {
						continue // a `uses:` step (composite action / marketplace action) — nothing to inspect
					}
					runText, ok := runRaw.(string)
					if !ok {
						t.Fatalf("%s: jobs.%s.steps[%d].run is %T, not a string", wfPath, jobName, i, runRaw)
					}

					stepLabel, _ := step["name"].(string)
					if stepLabel == "" {
						stepLabel = fmt.Sprintf("steps[%d]", i)
					}

					for lineNo, line := range strings.Split(runText, "\n") {
						trimmed := strings.TrimSpace(line)
						if trimmed == "" || strings.HasPrefix(trimmed, "#") {
							continue // blank, or a shell comment LINE — prose, not a command (AC#4)
						}
						if !goTestInvocationRe.MatchString(line) {
							continue
						}
						if !countEqualsOneRe.MatchString(line) {
							t.Errorf("%s job %q step %q line %d invokes `go test` without `-count=1` on the same command line: %q\n\n"+
								"STATBUS-234: `-count=1` disables Go's test cache, which does not track the outside-module files our pin tests assert facts about (workflow YAML, checked-in lists, shell scripts). STATBUS-235 turned the CI build/test cache ON, which is the state that makes a missing `-count=1` silently replay a stale verdict instead of merely being slow. Add `-count=1` to this exact command line.",
								wfPath, jobName, stepLabel, lineNo+1, trimmed)
						}
					}
				}
			}
		})
	}
}

// TestSupersededVerdictRunsLastAndAsksForItself_STATBUS246 pins the fix for a
// real defect in the orchestrator's first version, and it was the COMMON path
// rather than an edge case.
//
// THE DEFECT: the `superseded` verdict job keyed on the UPFRONT decide-obsolete
// answer alone. A chain runs for hours; a newer candidate is cut mid-chain;
// every later joint's own inline check correctly declines to start anything —
// and each of those jobs then SUCCEEDS having done nothing, while the verdict
// never fires because the upfront answer was 'false'. The run concludes SUCCESS
// with no fleet having run and nothing saying why: the rc.07 defect reborn
// inside the mechanism built to prevent it.
//
// The two properties that fix it are structural, so they are pinned structurally:
// the verdict must run LAST (needs every joint) and must ask the obsolete
// question ITSELF rather than trusting five predecessors to have reported.
func TestSupersededVerdictRunsLastAndAsksForItself_STATBUS246(t *testing.T) {
	rel := ".github/workflows/release-fleet-orchestrator.yaml"
	data, err := os.ReadFile(thisRepoFile(t, rel))
	if err != nil {
		t.Fatalf("read %s: %v", rel, err)
	}
	var doc struct {
		Jobs map[string]struct {
			Needs []string `yaml:"needs"`
			If    string   `yaml:"if"`
			Steps []struct {
				Name string `yaml:"name"`
				Run  string `yaml:"run"`
			} `yaml:"steps"`
		} `yaml:"jobs"`
	}
	if err := yaml.Unmarshal(data, &doc); err != nil {
		t.Fatalf("parse %s: %v", rel, err)
	}

	verdict, ok := doc.Jobs["superseded"]
	if !ok {
		t.Fatal("the orchestrator must carry a `superseded` job — the third verdict is named, not approximated (STATBUS-246 AC#4)")
	}

	// 1. RUNS LAST: every other job that can precede it must be in needs, or a
	//    supersession detected after that job would conclude before the verdict.
	needed := map[string]bool{}
	for _, n := range verdict.Needs {
		needed[n] = true
	}
	for name := range doc.Jobs {
		if name == "superseded" || name == "coverage-question-health" {
			continue
		}
		if !needed[name] {
			t.Errorf("the superseded verdict must need %q so it runs LAST — otherwise a supersession detected at that joint concludes the run before the verdict speaks, and the chain reports a bare success over work that never ran", name)
		}
	}

	// 2. ASKS FOR ITSELF: it must not gate on another job's obsolete output.
	if strings.Contains(verdict.If, "decide-obsolete") && strings.Contains(verdict.If, "obsolete") {
		t.Errorf("the verdict must not key on the UPFRONT obsolete answer — that answer is hours stale by the time the chain ends, and a mid-chain supersession would never fire it. Got if: %q", verdict.If)
	}
	var checks int
	for _, st := range verdict.Steps {
		if strings.Contains(st.Run, "git tag --sort=-version:refname") {
			checks++
		}
	}
	if checks == 0 {
		t.Error("the superseded verdict must perform the obsolete check as its OWN first act — the arriving job checks for itself rather than trusting predecessors to have reported (STATBUS-246 AC#1 applied to the job that states the verdict)")
	}

	// 3. It must still be able to speak when every upstream was SKIPPED, which
	//    is exactly what a superseded chain looks like.
	if !strings.Contains(verdict.If, "!cancelled()") {
		t.Errorf("the verdict's if: must use !cancelled() — on a superseded chain every upstream is skipped, and an implicit success() gate would silence the one job whose whole purpose is to speak then. Got: %q", verdict.If)
	}
}

func TestFleetStagesUseCoveredSubsetAndHealthIsIndependent_STATBUS351(t *testing.T) {
	rel := ".github/workflows/release-fleet-orchestrator.yaml"
	data, err := os.ReadFile(thisRepoFile(t, rel))
	if err != nil {
		t.Fatal(err)
	}
	var doc struct {
		Jobs map[string]struct {
			Needs   []string          `yaml:"needs"`
			If      string            `yaml:"if"`
			Outputs map[string]string `yaml:"outputs"`
			Steps   []struct {
				Name string            `yaml:"name"`
				ID   string            `yaml:"id"`
				If   string            `yaml:"if"`
				Run  string            `yaml:"run"`
				With map[string]string `yaml:"with"`
			} `yaml:"steps"`
		} `yaml:"jobs"`
	}
	if err := yaml.Unmarshal(data, &doc); err != nil {
		t.Fatal(err)
	}
	if _, exists := doc.Jobs["decide-upgrade-sensitivity"]; exists {
		t.Fatal("the one-hop bash sensitivity job must be deleted; every fleet scenario uses DecideCoverage")
	}

	for _, tc := range []struct {
		job      string
		workflow string
	}{
		{"smoke", "test-smoke.yaml"},
		{"install-recovery-harness", "install-recovery-harness.yaml"},
		{"upgrade-arc-harness", "upgrade-arc-harness.yaml"},
	} {
		job, ok := doc.Jobs[tc.job]
		if !ok {
			t.Fatalf("missing %s job", tc.job)
		}
		if strings.Contains(job.If, "sensitive") {
			t.Errorf("%s if: still references the deleted sensitivity verdict: %q", tc.job, job.If)
		}
		if job.Outputs["undecidable"] == "" || job.Outputs["coverage_error"] == "" {
			t.Errorf("%s must expose undecidable + exact stderr to coverage-question-health", tc.job)
		}
		var decision, dispatch bool
		for _, step := range job.Steps {
			if step.Name == "Decision point: which scenarios are uncovered?" {
				decision = strings.Contains(step.Run, "release covered-subset") && strings.Contains(step.Run, tc.workflow) && strings.Contains(step.Run, "undecidable=true") && strings.Contains(step.Run, "scenarios=")
			}
			if step.With["workflow-file"] == tc.workflow {
				dispatch = strings.Contains(step.If, "coverage.outputs.dispatch") && strings.Contains(step.With["dispatch-inputs"], "scenarios=")
			}
		}
		if !decision {
			t.Errorf("%s must ask covered-subset and carry an exit-2 full-suite arm", tc.job)
		}
		if !dispatch {
			t.Errorf("%s must dispatch only when requested and pass the uncovered scenario selectors", tc.job)
		}
	}

	health, ok := doc.Jobs["coverage-question-health"]
	if !ok {
		t.Fatal("coverage-question-health job is required")
	}
	if !strings.Contains(health.If, "always()") {
		t.Errorf("coverage-question-health must run with always(); got %q", health.If)
	}
	needed := strings.Join(health.Needs, " ")
	if !strings.Contains(needed, "smoke") || !strings.Contains(needed, "install-recovery-harness") || !strings.Contains(needed, "upgrade-arc-harness") {
		t.Errorf("coverage-question-health must run after all three dispatch stages; needs=%v", health.Needs)
	}
	for _, stage := range []string{"smoke", "install-recovery-harness", "upgrade-arc-harness"} {
		if strings.Contains(strings.Join(doc.Jobs[stage].Needs, " "), "coverage-question-health") {
			t.Errorf("coverage-question-health must not enter the %s dispatch chain", stage)
		}
	}
	var diagnosis bool
	for _, step := range health.Steps {
		if strings.Contains(step.Run, "the full suite was dispatched instead of guessing; fix the evidence path (token/API), the sensitivity policy, the install-recovery structural validation, or the repository read that failed") {
			diagnosis = true
		}
	}
	if !diagnosis {
		t.Fatal("coverage-question-health must carry the King-approved actionable diagnosis")
	}
}

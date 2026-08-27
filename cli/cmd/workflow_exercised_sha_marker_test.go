package cmd

import (
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

// STATBUS-285. For workflow_run-triggered workflows GitHub files a run's API
// head_sha under the DEFAULT BRANCH'S TIP AT TRIGGER TIME, not under the commit
// the run tested. Execution is pinned correctly; ATTRIBUTION is structurally
// wrong at the API, and no yaml can change what head_sha a run is filed under.
//
// So these workflows PUBLISH the commit they exercised in run-name, which the
// API exposes as display_title. The release gate will key evidence on that
// instead of head_sha.
//
// THIS TEST IS WHAT SEPARATES THAT MARKER FROM THE SELF-REPORT STATBUS-199 §5
// REJECTED. There, a run-name claimed WHAT RAN (full suite vs subset) — a claim
// a dispatch input could falsify, which is why that gate moved to the job list.
// Here the label must be a RESTATEMENT OF THE SAME TRIGGER CONTEXT VALUE THAT
// DRIVES THE CHECKOUT. If the marker expression and the ref expression are the
// same expression, the label cannot lie without the checkout lying identically —
// and then the tests ran where the label says they ran.
//
// That equivalence is not self-enforcing, which is why it is asserted here: a
// future edit could change one and not the other, and nothing at runtime would
// notice. The gate's soundness would degrade silently, which is the exact class
// of failure this whole ticket is about.
const exercisedSHAMarker = "exercised-sha="

// workflowRunTriggeredOracles are the workflows whose green the release gate
// consumes as evidence about a named commit. Both are workflow_run-triggered by
// design (they must run after Images), which is precisely why they need the
// marker: the trigger type that makes them useful is the trigger type that
// breaks their attribution.
var workflowRunTriggeredOracles = []string{
	"fast-tests.yaml",
	"pg_regress.yaml",
}

func readWorkflowFile(t *testing.T, name string) string {
	t.Helper()
	path := filepath.Join("..", "..", ".github", "workflows", name)
	b, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read %s: %v", path, err)
	}
	return string(b)
}

func TestWorkflowRunMarkerMatchesCheckoutRef_STATBUS285(t *testing.T) {
	// The one expression both sites must use. Written once here so the test
	// cannot drift from itself.
	const contextExpr = "github.event.workflow_run.head_sha"

	for _, wf := range workflowRunTriggeredOracles {
		t.Run(wf, func(t *testing.T) {
			body := readWorkflowFile(t, wf)

			// 1. The workflow must still be workflow_run-triggered. If that ever
			//    changes the marker's justification changes with it, and this
			//    test should be re-decided rather than silently kept passing.
			if !strings.Contains(body, "workflow_run:") {
				t.Fatalf("%s is no longer workflow_run-triggered — the STATBUS-285 attribution hazard and this marker's justification both rest on that trigger; re-decide the marker together with the trigger change", wf)
			}

			// 2. There must be a run-name carrying the machine-read marker.
			runName := workflowRunNameBlock(t, wf, body)
			if !strings.Contains(runName, exercisedSHAMarker) {
				t.Fatalf("%s run-name no longer carries the %q marker — the release gate reads the exercised commit from display_title; without it every run of this workflow becomes unattributable and the gate refuses (run-name found: %q)", wf, exercisedSHAMarker, runName)
			}

			// 3. THE LOAD-BEARING ASSERTION: the marker must publish the SAME
			//    context expression the code is checked out at. A marker computed
			//    any other way is a self-report, and STATBUS-199 §5 already ruled
			//    that a self-reported label is not gate evidence.
			if !strings.Contains(runName, contextExpr) {
				t.Fatalf("%s run-name publishes something other than %s — a marker that does not restate the checkout's own context value is a SELF-REPORT, which STATBUS-199 §5 rejected as gate evidence (run-name: %q)", wf, contextExpr, runName)
			}
			if !strings.Contains(body, contextExpr+" }}") {
				t.Fatalf("%s no longer resolves the checkout ref from %s — the marker would then name a commit the run did not check out, which is the STATBUS-285 hazard with extra confidence", wf, contextExpr)
			}

			// 4. The marker must be evaluable at RUN CREATION. run-name is
			//    evaluated before any job exists, so a step output there would
			//    render empty — and, worse, a marker that depended on a job would
			//    be absent from FAILED runs, degrading every red to Missing and
			//    re-opening STATBUS-256's do-not-just-re-run defect.
			if strings.Contains(runName, "steps.") || strings.Contains(runName, "needs.") {
				t.Fatalf("%s run-name references a job/step context (%q) — run-name is evaluated at run creation, before any job runs, so this renders empty AND disappears from failed runs, which would make every red run read as Missing", wf, runName)
			}
		})
	}
}

// workflowRunNameBlock returns the run-name value, including a folded
// (`>-`) continuation line.
func workflowRunNameBlock(t *testing.T, wf, body string) string {
	t.Helper()
	re := regexp.MustCompile(`(?m)^run-name:[ \t]*(.*)$`)
	loc := re.FindStringSubmatchIndex(body)
	if loc == nil {
		t.Fatalf("%s has no top-level run-name — STATBUS-285 requires it to publish the exercised commit", wf)
	}
	value := strings.TrimSpace(body[loc[2]:loc[3]])
	rest := body[loc[1]:]
	if value == ">-" || value == ">" || value == "|" || value == "|-" {
		value = ""
		for _, line := range strings.Split(rest, "\n") {
			if strings.TrimSpace(line) == "" {
				continue
			}
			if !strings.HasPrefix(line, " ") && !strings.HasPrefix(line, "\t") {
				break
			}
			value += " " + strings.TrimSpace(line)
		}
	}
	return strings.TrimSpace(value)
}

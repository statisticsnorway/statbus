package cmd

// STATBUS-260: the chain's transport to dev must NAME the candidate.
//
// The old transport pushed the candidate's commit to a deploy branch and relied
// on that push to trigger deploy-to-dev. The premise was false — a push made
// with the default GITHUB_TOKEN does not trigger `on: push` workflows — so the
// branch moved, the deploy never ran, and the orchestrator waited out its full
// budget for a run that could not exist.
//
// These follow this package's STATBUS-224 rule: PARSE the YAML, never grep the
// text. A text pin here would be satisfied by the very comments that explain the
// change, which is how a pin once kept passing after the fact it asserted had
// stopped being true. Shell comments inside `run:` blocks are stripped for the
// same reason — a comment must neither satisfy nor defeat an assertion.

import (
	"os"
	"strings"
	"testing"

	"gopkg.in/yaml.v3"
)

func workflowDoc(t *testing.T, relPath string) map[string]any {
	t.Helper()
	data, err := os.ReadFile(thisRepoFile(t, relPath))
	if err != nil {
		t.Fatalf("cannot read %s: %v", relPath, err)
	}
	var doc map[string]any
	if err := yaml.Unmarshal(data, &doc); err != nil {
		t.Fatalf("%s is not parseable YAML (%v) — a workflow that does not parse cannot be reasoned about at all", relPath, err)
	}
	return doc
}

// jobSteps returns one job's steps, failing loudly if the job is missing — a
// vacuous pass here would report a guarantee nobody is checking.
func jobSteps(t *testing.T, relPath, job string) []map[string]any {
	t.Helper()
	doc := workflowDoc(t, relPath)
	jobs, ok := doc["jobs"].(map[string]any)
	if !ok {
		t.Fatalf("%s has no jobs block", relPath)
	}
	raw, ok := jobs[job]
	if !ok {
		t.Fatalf("%s has no job %q — the scan lost its subject", relPath, job)
	}
	jm, ok := raw.(map[string]any)
	if !ok {
		t.Fatalf("%s job %q is not a mapping", relPath, job)
	}
	rawSteps, ok := jm["steps"].([]any)
	if !ok {
		t.Fatalf("%s job %q has no steps", relPath, job)
	}
	var out []map[string]any
	for _, s := range rawSteps {
		if m, ok := s.(map[string]any); ok {
			out = append(out, m)
		}
	}
	if len(out) == 0 {
		t.Fatalf("%s job %q parsed to zero steps", relPath, job)
	}
	return out
}

// runScriptsWithoutComments concatenates a job's shell scripts with `#` comment
// lines removed, so an assertion about what the job DOES cannot be satisfied or
// defeated by prose explaining what it used to do.
func runScriptsWithoutComments(steps []map[string]any) string {
	var b strings.Builder
	for _, st := range steps {
		script, _ := st["run"].(string)
		for _, line := range strings.Split(script, "\n") {
			if strings.HasPrefix(strings.TrimSpace(line), "#") {
				continue
			}
			b.WriteString(line)
			b.WriteString("\n")
		}
	}
	return b.String()
}

// TestChainDispatchesDevExplicitly_STATBUS260 is the transport fix itself.
func TestChainDispatchesDevExplicitly_STATBUS260(t *testing.T) {
	steps := jobSteps(t, ".github/workflows/release-fleet-orchestrator.yaml", "dev-canary")

	var dispatch map[string]any
	for _, st := range steps {
		if uses, _ := st["uses"].(string); strings.Contains(uses, "dispatch-fleet-and-wait") {
			dispatch = st
		}
	}
	if dispatch == nil {
		t.Fatal(`the dev-canary job never dispatches deploy-to-dev.

It relied on a branch push to trigger it, and that trigger does not fire for a
default-token push — so the deploy never ran and the chain waited out its budget
on a run that could not exist.`)
	}

	with, ok := dispatch["with"].(map[string]any)
	if !ok {
		t.Fatal("the dispatch step has no `with:` block")
	}
	if wf, _ := with["workflow-file"].(string); wf != "deploy-to-dev.yaml" {
		t.Errorf("the dev-canary leg dispatches %q, want deploy-to-dev.yaml", wf)
	}
	inputs, _ := with["dispatch-inputs"].(string)
	if !strings.Contains(inputs, "sha=") {
		t.Errorf(`the dispatch does not NAME the candidate (dispatch-inputs: %q).

Naming it is the point: the transport becomes candidate-addressed, so the chain
says which commit it is testing instead of leaving a branch position to imply
it.`, inputs)
	}

	// And the branch push must no longer BE the transport.
	if scripts := runScriptsWithoutComments(steps); strings.Contains(scripts, "refs/heads/ops/cloud/deploy/dev") {
		t.Error(`the dev-canary job still pushes the deploy branch as its transport.

The push is not the trigger — that premise is what failed. Pushing it again
alongside an explicit dispatch would restore the ambiguity the dispatch removes,
and could start a second deploy for the same candidate.`)
	}
}

// TestDeployToDevAcceptsTheCandidate_STATBUS260: the receiving end must take the
// commit as an input, while keeping the push trigger STATBUS-244's transitional
// button still uses.
func TestDeployToDevAcceptsTheCandidate_STATBUS260(t *testing.T) {
	doc := workflowDoc(t, ".github/workflows/deploy-to-dev.yaml")
	onBlock, ok := doc["on"]
	if !ok {
		t.Fatal("deploy-to-dev has no `on:` block")
	}
	onMap, ok := onBlock.(map[string]any)
	if !ok {
		t.Fatal("deploy-to-dev's `on:` block is not a mapping")
	}

	wd, ok := onMap["workflow_dispatch"].(map[string]any)
	if !ok {
		t.Fatal("deploy-to-dev's workflow_dispatch declares no inputs — the chain cannot name the candidate")
	}
	inputs, ok := wd["inputs"].(map[string]any)
	if !ok {
		t.Fatal("deploy-to-dev's workflow_dispatch has no inputs block")
	}
	if _, ok := inputs["sha"]; !ok {
		t.Error("deploy-to-dev accepts no `sha` input — the dispatch has nowhere to put the candidate's commit")
	}

	if _, ok := onMap["push"]; !ok {
		t.Error(`deploy-to-dev's push trigger was removed.

STATBUS-244's transitional master-to-dev button still writes that branch. The
push stopped being the CHAIN's transport, which is not the same as being unused
— switching it off breaks a caller that is still live.`)
	}
}

// TestDevDeployVerifiesTheRequestedCommit_STATBUS260 is the guard, and the
// deepest part of the fix.
//
// The poll used to take its subject from the box's OWN emit, so it asked "did
// the box converge on whatever the box decided to install?" — very nearly
// self-referential. It could not hang and could not fail for the reason that
// matters: a box installing a NEWER candidate would converge, the poll would
// confirm it, and the workflow would report SUCCESS while the chain believed dev
// took the candidate under test.
func TestDevDeployVerifiesTheRequestedCommit_STATBUS260(t *testing.T) {
	relPath := ".github/workflows/deploy-to-dev.yaml"
	doc := workflowDoc(t, relPath)

	// The single resolved commit every consumer reads.
	env, ok := doc["env"].(map[string]any)
	if !ok {
		t.Fatal("deploy-to-dev declares no workflow-level env — there is no single answer to which commit this run is about")
	}
	if _, ok := env["REQUESTED_SHA"]; !ok {
		t.Error("deploy-to-dev does not resolve a REQUESTED_SHA — each step would then answer 'which commit' for itself")
	}

	scripts := runScriptsWithoutComments(jobSteps(t, relPath, "deploy"))

	if !strings.Contains(scripts, `SHA="$REQUESTED_SHA"`) {
		t.Error(`the convergence poll does not read the REQUESTED commit.

Polling the commit the BOX chose asks whether the box did what it decided, not
whether it did what the chain asked. That check cannot fail for the reason this
ticket exists.`)
	}
	if strings.Contains(scripts, `SHA="$DEPLOYED_COMMIT"`) {
		t.Error("the poll still takes its subject from the box's own emit — that is the self-referential check being removed")
	}

	// The equality guard, and that a mismatch STOPS the deploy.
	if !strings.Contains(scripts, `"$DEPLOYED_COMMIT" != "$REQUESTED_SHA"`) {
		t.Error(`nothing compares the requested commit with the one the box installed.

Under a candidate-addressed install they can differ only if something resolved a
target other than the one asked for — the defect itself — so it must be checked
rather than assumed.`)
	}
	// Read the GUARD STEP'S OWN script, not a concatenation of the job's.
	//
	// My first version sliced a window out of the concatenated scripts using the
	// YAML indentation as the end marker — and a block scalar STRIPS that
	// indentation, so the marker never matched, the window ran to the end of the
	// job, and the assertion below was satisfied by an `exit 1` belonging to a
	// different step. It passed while measuring the wrong thing. Selecting the
	// step by name removes the possibility.
	guard := stepScriptByName(t, relPath, "deploy", "Assert the box installed")
	if !strings.Contains(guard, "exit 1") {
		t.Error("a requested-vs-installed mismatch must FAIL the deploy — a warning would let the chain green-light a box running something else")
	}
	if !strings.Contains(guard, "::error") {
		t.Error("the mismatch must be annotated as an error so it surfaces in the run summary, not only in the log")
	}
}

// stepScriptByName returns ONE step's run script, chosen by a substring of its
// name. It fails loudly when the step is absent: a guard test that cannot find
// its subject must fail, never pass by examining nothing.
func stepScriptByName(t *testing.T, relPath, job, nameContains string) string {
	t.Helper()
	for _, st := range jobSteps(t, relPath, job) {
		if name, _ := st["name"].(string); strings.Contains(name, nameContains) {
			script, _ := st["run"].(string)
			if script == "" {
				t.Fatalf("step %q in %s has no run script", name, relPath)
			}
			return script
		}
	}
	t.Fatalf("no step whose name contains %q in %s job %q — the scan lost its subject", nameContains, relPath, job)
	return ""
}

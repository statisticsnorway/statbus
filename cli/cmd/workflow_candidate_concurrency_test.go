package cmd

import (
	"fmt"
	"strings"
	"testing"

	"gopkg.in/yaml.v3"
)

type concurrencyWorkflow struct {
	On struct {
		WorkflowRun struct {
			Workflows []string `yaml:"workflows"`
			Types     []string `yaml:"types"`
			Branches  []string `yaml:"branches"`
		} `yaml:"workflow_run"`
	} `yaml:"on"`
	Concurrency struct {
		Group  string `yaml:"group"`
		Cancel bool   `yaml:"cancel-in-progress"`
	} `yaml:"concurrency"`
	Jobs map[string]struct {
		Needs       string `yaml:"needs"`
		Concurrency struct {
			Group  string `yaml:"group"`
			Cancel bool   `yaml:"cancel-in-progress"`
		} `yaml:"concurrency"`
	} `yaml:"jobs"`
}

func loadConcurrencyWorkflow(t *testing.T, name string) concurrencyWorkflow {
	t.Helper()
	var workflow concurrencyWorkflow
	if err := yaml.Unmarshal([]byte(readWorkflowFile(t, name)), &workflow); err != nil {
		t.Fatal(err)
	}
	return workflow
}

// Evaluate the subset of Actions expressions used in the concurrency key. Fail closed
// when the workflow changes to syntax this contract test cannot model.
func evaluateConcurrencyExpression(expression string, context map[string]string) (string, error) {
	expression = strings.TrimSpace(strings.TrimSuffix(strings.TrimPrefix(expression, "${{"), "}}"))
	expression = strings.TrimSpace(expression)
	if strings.HasPrefix(expression, "(") && strings.HasSuffix(expression, ")") {
		if closing := matchingParen(expression, 0); closing == len(expression)-1 {
			return evaluateConcurrencyExpression(expression[1:len(expression)-1], context)
		}
	}
	for _, operator := range []string{"||", "&&", "=="} {
		if at := topLevelOperator(expression, operator); at >= 0 {
			left, err := evaluateConcurrencyExpression(expression[:at], context)
			if err != nil {
				return "", err
			}
			if operator == "||" && left != "" && left != "false" {
				return left, nil
			}
			if operator == "&&" && (left == "" || left == "false") {
				return "false", nil
			}
			right, err := evaluateConcurrencyExpression(expression[at+len(operator):], context)
			if err != nil {
				return "", err
			}
			switch operator {
			case "||":
				return right, nil
			case "&&":
				return right, nil
			case "==":
				if left == right {
					return "true", nil
				}
				return "false", nil
			}
		}
	}
	if strings.HasPrefix(expression, "format(") && strings.HasSuffix(expression, ")") {
		args := expression[len("format(") : len(expression)-1]
		comma := topLevelOperator(args, ",")
		if comma < 0 {
			return "", fmt.Errorf("invalid format: %s", expression)
		}
		pattern, err := evaluateConcurrencyExpression(args[:comma], context)
		if err != nil {
			return "", err
		}
		value, err := evaluateConcurrencyExpression(args[comma+1:], context)
		if err != nil {
			return "", err
		}
		return strings.ReplaceAll(pattern, "{0}", value), nil
	}
	if len(expression) >= 2 && expression[0] == '\'' && expression[len(expression)-1] == '\'' {
		return expression[1 : len(expression)-1], nil
	}
	if value, ok := context[expression]; ok {
		return value, nil
	}
	return "", fmt.Errorf("unsupported concurrency expression %q", expression)
}

func matchingParen(s string, start int) int {
	depth := 0
	quoted := false
	for i := start; i < len(s); i++ {
		switch s[i] {
		case '\'':
			quoted = !quoted
		case '(':
			if !quoted {
				depth++
			}
		case ')':
			if !quoted {
				depth--
				if depth == 0 {
					return i
				}
			}
		}
	}
	return -1
}

func topLevelOperator(s, operator string) int {
	depth := 0
	quoted := false
	for i := 0; i+len(operator) <= len(s); i++ {
		switch s[i] {
		case '\'':
			quoted = !quoted
		case '(':
			if !quoted {
				depth++
			}
		case ')':
			if !quoted {
				depth--
			}
		}
		if !quoted && depth == 0 && strings.HasPrefix(s[i:], operator) {
			return i
		}
	}
	return -1
}

func TestFastTestsCandidateConcurrency_STATBUS415(t *testing.T) {
	fast := loadConcurrencyWorkflow(t, "fast-tests.yaml")
	if fast.Concurrency.Group != "" {
		t.Fatal("workflow-level concurrency cancels before candidate classification")
	}
	job := fast.Jobs["fast-tests"]
	if job.Needs != "classify" || !job.Concurrency.Cancel {
		t.Fatal("Fast Tests must classify before applying cancellable job concurrency")
	}
	const candidateA = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
	const masterB = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
	const fixtureSHA = "cccccccccccccccccccccccccccccccccccccccc"
	const dispatchSHA = "dddddddddddddddddddddddddddddddddddddddd"
	cases := []struct {
		name, event, ref, sha, candidate, headSHA, headBranch, refName, want string
	}{
		{"master A", "workflow_run", "refs/heads/master", candidateA, "false", candidateA, "master", "", "fast-tests-master"},
		{"master B", "workflow_run", "refs/heads/master", masterB, "false", masterB, "master", "", "fast-tests-master"},
		{"tagged A", "push", "refs/tags/v1.0-rc.1", candidateA, "true", "", "", "v1.0-rc.1", "fast-tests-rc-" + candidateA},
		{"later master B", "workflow_run", "refs/heads/master", masterB, "false", masterB, "master", "", "fast-tests-master"},
		{"PR 1", "pull_request", "refs/pull/1/merge", candidateA, "false", "", "", "", "fast-tests-refs/pull/1/merge"},
		{"PR 2", "pull_request", "refs/pull/2/merge", masterB, "false", "", "", "", "fast-tests-refs/pull/2/merge"},
		// STATBUS-433: a fixture-branch workflow_run (upgrade-arc harness's Images
		// dispatch on a throwaway test/upgrade-arc-* branch) must never share
		// master's group.
		{"fixture workflow_run", "workflow_run", "refs/heads/master", fixtureSHA, "false", fixtureSHA, "test/upgrade-arc-x", "", "fast-tests-test/upgrade-arc-x"},
		// A manual `gh workflow run fast-tests.yaml --ref feature` dispatch on a
		// non-master branch must also get its own group, not master's.
		{"dispatch other branch", "workflow_dispatch", "refs/heads/feature", dispatchSHA, "false", "", "", "feature", "fast-tests-feature"},
	}
	keys := make(map[string]string)
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			context := map[string]string{
				"github.event_name":                     tc.event,
				"github.ref":                            tc.ref,
				"github.ref_name":                       tc.refName,
				"github.sha":                            tc.sha,
				"github.event.workflow_run.head_sha":    tc.headSHA,
				"github.event.workflow_run.head_branch": tc.headBranch,
				"needs.classify.outputs.candidate":      tc.candidate,
			}
			key, err := evaluateConcurrencyExpression(job.Concurrency.Group, context)
			if err != nil {
				t.Fatal(err)
			}
			if key != tc.want {
				t.Errorf("group = %q, want %q", key, tc.want)
			}
			keys[tc.name] = key
		})
	}
	if keys["master A"] != keys["master B"] {
		t.Error("B must cancel superseded ordinary master A")
	}
	if keys["tagged A"] == keys["later master B"] {
		t.Error("B must not cancel candidate A's evidence")
	}
	if keys["PR 1"] == keys["PR 2"] {
		t.Error("unrelated PRs must have separate groups")
	}
	if keys["fixture workflow_run"] == keys["master A"] {
		t.Error("a fixture-branch workflow_run must not share master's cancellable group (STATBUS-433)")
	}
	if keys["dispatch other branch"] == keys["master A"] {
		t.Error("a workflow_dispatch on a non-master branch must not share master's cancellable group (STATBUS-433)")
	}
}

// TestFastTestsExcludesFixtureBranch_STATBUS433 asserts fast-tests.yaml's
// workflow_run trigger carries a `branches: [master]` filter.
//
// Without it, every Images completion on ANY branch — including the
// throwaway test/upgrade-arc-* fixture branches the upgrade-arc harness
// dispatches images.yaml against (`gh workflow run images.yaml --ref
// <fixture-branch>`, test/install-recovery/lib/upgrade-target.sh) — started a
// Fast Tests run. That run classified candidate=false (no RC tag on a
// fixture branch, see TestFastTestsCandidateConcurrency_STATBUS415 above)
// and so landed in the exact same 'fast-tests-master' concurrency group as
// master's own runs, with cancel-in-progress: true silently cancelling
// master's in-flight verdict. The fixture runs also fail by design
// (deliberately-broken migrations), adding unrelated red noise.
//
// `branches` on workflow_run filters on the TRIGGERING run's head_branch —
// per GitHub's on.workflow_run.<branches|branches-ignore> docs — so this does
// not touch the push/pull_request triggers, and ordinary master-push Images
// runs (images.yaml's own push trigger is already branches: [master]) are
// unaffected.
func TestFastTestsExcludesFixtureBranch_STATBUS433(t *testing.T) {
	fast := loadConcurrencyWorkflow(t, "fast-tests.yaml")
	wr := fast.On.WorkflowRun
	if len(wr.Workflows) != 1 || wr.Workflows[0] != "Images" {
		t.Fatalf("workflow_run.workflows = %v, want [Images]", wr.Workflows)
	}
	if len(wr.Branches) != 1 || wr.Branches[0] != "master" {
		t.Fatalf("workflow_run.branches = %v, want [master] — without this, fixture-branch Images runs (upgrade-arc-harness) start Fast Tests runs that share master's cancellable concurrency group (STATBUS-433)", wr.Branches)
	}
}

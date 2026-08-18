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

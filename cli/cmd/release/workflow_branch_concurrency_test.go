package releasecmd

import (
	"fmt"
	"os/exec"
	"testing"
)

// There is no Actions runtime evaluator in the existing dependencies. Pin the
// bounded grouping expression and have actionlint check its real syntax/types.
// The local event/ref prototype is evidence, not a substitute runtime evaluator.
func TestWorkflowBranchConcurrency_STATBUS453(t *testing.T) {
	for _, wf := range []struct{ path, prefix string }{
		{".github/workflows/app_build_and_lint-workflow.yaml", "app-build-lint"},
		{".github/workflows/go-test.yaml", "go-test"},
	} {
		t.Run(wf.prefix, func(t *testing.T) {
			doc := parsedYAMLMap(t, wf.path)
			concurrency := asStringMap(t, wf.path, "concurrency", doc["concurrency"])
			want := fmt.Sprintf("${{ (github.event_name == 'pull_request' || github.ref != 'refs/heads/master') && format('%s-{0}', github.ref) || '%s-master' }}", wf.prefix, wf.prefix)
			if concurrency["group"] != want {
				t.Fatalf("group = %v, want master-only fixed group and otherwise per-ref: %s", concurrency["group"], want)
			}
			if concurrency["cancel-in-progress"] != true {
				t.Fatal("newest run must still cancel the previous run in its group")
			}
			actionlint, err := exec.LookPath("actionlint")
			if err != nil {
				t.Skip("actionlint unavailable: expression syntax/type check requires local actionlint")
			}
			out, err := exec.Command(actionlint, "-shellcheck=", "-pyflakes=", thisRepoFile(t, wf.path)).CombinedOutput()
			if err != nil {
				t.Fatalf("actionlint: %v\n%s", err, out)
			}
		})
	}
}

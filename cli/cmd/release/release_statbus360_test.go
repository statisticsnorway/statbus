package releasecmd

import (
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/release"
)

func TestCheck7FailureMessagesNameFastTestsRunner_STATBUS360(t *testing.T) {
	for _, status := range []release.WorkflowCheckStatus{
		release.WorkflowCheckPending,
		release.WorkflowCheckFailed,
		release.WorkflowCheckMissing,
		release.WorkflowCheckUnknown,
	} {
		t.Run(string(status), func(t *testing.T) {
			result := release.WorkflowCheckResult{
				Status: status,
				RunID:  42,
				RunURL: "https://github.example/Fast-Tests-run/42",
				Detail: "failure",
			}
			out := captureStdout(t, func() {
				printFastSuiteWorkflowFailure(t.TempDir(), result, "0123456789ab", strings.Repeat("0", 40))
			})
			if !strings.Contains(out, "Fast Tests") {
				t.Errorf("check 7 %s message does not name the runner workflow:\n%s", status, out)
			}
		})
	}
}

// TestFastTestsMissingNeverSuggestsDispatchAtRawSHA pins the workflow_dispatch
// contract (WorkflowTriggerCommand: a ref must be a branch or tag, never a SHA;
// GitHub answers 422). When the candidate commit is not origin/master's tip, a
// Missing Fast Tests verdict must tell the operator to push, not print a
// `gh workflow run --ref <sha>` that cannot work (review tmp/review-433.md §2).
func TestFastTestsMissingNeverSuggestsDispatchAtRawSHA(t *testing.T) {
	headFull := strings.Repeat("a", 40)
	out := captureStdout(t, func() {
		printFastSuiteWorkflowFailure(t.TempDir(), release.WorkflowCheckResult{Status: release.WorkflowCheckMissing}, headFull[:12], headFull)
	})
	if strings.Contains(out, "--ref "+headFull) {
		t.Fatalf("Missing verdict suggests dispatching at a raw SHA, which GitHub rejects:\n%s", out)
	}
	if !strings.Contains(out, "is not origin/master's tip") {
		t.Fatalf("Missing verdict off master's tip must say why no trigger command is offered:\n%s", out)
	}
}

func TestPrereleaseHelpMentionsFastSuiteOnce_STATBUS360(t *testing.T) {
	const suite = "fast suite: local stamp, else the Fast Tests runner job at HEAD"
	help := releasePrereleaseCmd.Long
	if got := strings.Count(help, suite); got != 1 {
		t.Fatalf("prerelease help contains the suite description %d times, want exactly once:\n%s", got, help)
	}
	if strings.Contains(help, "\n  - fast-tests") {
		t.Fatalf("prerelease help lists fast-tests as a second oracle for the same suite:\n%s", help)
	}
}

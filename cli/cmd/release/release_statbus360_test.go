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
				printFastSuiteWorkflowFailure(result, "0123456789ab", strings.Repeat("0", 40))
			})
			if !strings.Contains(out, "Fast Tests") {
				t.Errorf("check 7 %s message does not name the runner workflow:\n%s", status, out)
			}
			if strings.Contains(out, release.WorkflowPgRegress) {
				t.Errorf("check 7 %s message points at the self-hosted fallback:\n%s", status, out)
			}
		})
	}
}

func TestPrereleaseHelpMentionsPgRegressFastSuiteOnce_STATBUS360(t *testing.T) {
	const suite = "pg_regress fast suite: local stamp, else the Fast Tests runner job at HEAD"
	help := releasePrereleaseCmd.Long
	if got := strings.Count(help, suite); got != 1 {
		t.Fatalf("prerelease help contains the suite description %d times, want exactly once:\n%s", got, help)
	}
	if strings.Contains(help, "\n  - fast-tests") {
		t.Fatalf("prerelease help lists fast-tests as a second oracle for the same suite:\n%s", help)
	}
}

package releasecmd

import (
	"os"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/cmd"
)

// TestGuardExitNeverCollidesWithCoveredVerdicts pins the exit-code contract
// the orchestrator branches on: the staleness guard's refusal is 69
// (EX_UNAVAILABLE) and `covered`'s three verdicts are 0/1/2. Before this, both
// used 2, and a stale build rendered as "undecidable → must run".
func TestGuardExitNeverCollidesWithCoveredVerdicts(t *testing.T) {
	if cmd.ExitBinaryUnusable == ExitCovered || cmd.ExitBinaryUnusable == ExitMustRun || cmd.ExitBinaryUnusable == ExitUndecided {
		t.Fatalf("ExitBinaryUnusable=%d collides with a covered verdict code", cmd.ExitBinaryUnusable)
	}
	if cmd.ExitBinaryUnusable != 69 {
		t.Fatalf("ExitBinaryUnusable = %d, want 69 (EX_UNAVAILABLE); the orchestrator's case arm is written for 69", cmd.ExitBinaryUnusable)
	}
	src, err := os.ReadFile("../root.go")
	if err != nil {
		t.Fatal(err)
	}
	guard := extractGuardBody(t, string(src))
	if strings.Contains(guard, "os.Exit(2)") {
		t.Fatal("stalenessGuard still exits 2 somewhere; that is a covered verdict code")
	}
}

func extractGuardBody(t *testing.T, src string) string {
	t.Helper()
	start := strings.Index(src, "func stalenessGuard(")
	if start < 0 {
		t.Fatal("stalenessGuard not found")
	}
	end := strings.Index(src[start:], "\n}\n")
	return src[start : start+end]
}

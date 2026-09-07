package releasecmd

// STATBUS-364: check 7 (Fast Tests) gets the same diff-since-green exempt-path
// coverage as go-test / app-build-lint. A green run at an older SHA covers HEAD
// when every file changed since is in ops/release/ci-exempt-paths.txt, and the
// ride must NAME the covering run (its URL, not just the commit) so the operator
// can audit exactly what passed.

import (
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/release"
)

// TestCheck7CoveragePath_NamesTheCoveringRun_STATBUS364 drives check 7's
// coverage path through findExemptRide (the shared helper check 7 already calls
// for WorkflowFastTests) and printExemptRide. It pins the two facts the gate
// relies on: a board-only diff over a green ancestor rides AND names the
// covering run URL, while a single non-exempt file forbids the ride and names
// the offender.
func TestCheck7CoveragePath_NamesTheCoveringRun_STATBUS364(t *testing.T) {
	t.Run("green at older SHA + board-only diff passes and names the covering run", func(t *testing.T) {
		dir, tip, code := rideFixture(t, 2)
		stubWorkflowSeams(t, greenAt(code), trivialComplete)

		ride, whyNot, _ := findExemptRide(dir, release.WorkflowFastTests, tip)
		if ride == nil {
			t.Fatalf("check 7 must ride a board-only diff over a green ancestor; refused with: %s", whyNot)
		}
		if ride.Commit != code {
			t.Errorf("covering commit = %s, want %s", ride.Commit, code)
		}
		if ride.Result.RunURL == "" {
			t.Fatal("the ride must carry the covering run's URL so check 7 can name it")
		}

		out := captureStdout(t, func() { printExemptRide("Fast Tests", ride) })
		if !strings.Contains(out, ride.Result.RunURL) {
			t.Errorf("check 7's ride must NAME the covering run URL (%s); output:\n%s", ride.Result.RunURL, out)
		}
		if !strings.Contains(out, "Fast Tests") {
			t.Errorf("the ride must be attributed to the Fast Tests gate; output:\n%s", out)
		}
		if !strings.Contains(out, "also covers this commit") {
			t.Errorf("the ride must say plainly it covers this commit; output:\n%s", out)
		}
	})

	t.Run("one non-exempt file fails and names the offender", func(t *testing.T) {
		dir, _, code := rideFixture(t, 1)
		writeAndCommit(t, dir, "code change", "cli/internal/upgrade/service.go")
		tip := runGitInCmd(t, dir, "rev-parse", "HEAD")
		stubWorkflowSeams(t, greenAt(code), trivialComplete)

		ride, whyNot, _ := findExemptRide(dir, release.WorkflowFastTests, tip)
		if ride != nil {
			t.Fatalf("check 7 rode a tip containing a non-exempt change (target %s) — untested code would enter a release", ride.Commit)
		}
		if !strings.Contains(whyNot, "service.go") {
			t.Errorf("the refusal must name the offending file so the operator knows this code state is untested; got %q", whyNot)
		}
	})
}

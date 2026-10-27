//go:build release_live

package releasecmd

import (
	"os"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/config"
	"github.com/statisticsnorway/statbus/cli/internal/release"
	"github.com/statisticsnorway/statbus/cli/internal/upgrade"
)

// TestReleaseStablePreflightGates runs the EXACT gate functions `./sb release stable`
// calls, against the real repo, the real GitHub Actions API and the real canary
// boxes, and stops where the command would tag+push. It is the read-only twin
// of the promotion: same code, same inputs, no side effects (the RunE's own
// git-fetch is the only thing not repeated here).
//
// Opt-in, because it needs network, `gh` credentials and SSH to the canaries:
//
//	STATBUS_LIVE_RELEASE_GATES=<rc-tag> GITHUB_TOKEN=$(gh auth token) \
//	  go test -count=1 -run TestReleaseStablePreflightGates -v ./cmd
func TestReleaseStablePreflightGates(t *testing.T) {
	rcTag := os.Getenv("STATBUS_LIVE_RELEASE_GATES")
	if rcTag == "" {
		t.Skip("set STATBUS_LIVE_RELEASE_GATES=<rc-tag> to exercise the real promotion gates")
	}
	projDir := config.ProjectDir()
	rcCommit, err := resolveCommitish(projDir, rcTag)
	if err != nil {
		t.Fatalf("resolve %s: %v", rcTag, err)
	}
	rcShort := upgrade.ShortForDisplay(rcCommit)
	t.Logf("gates for %s at %s", rcTag, rcShort)

	type gate struct {
		name string
		run  func() gateVerdict
	}
	gates := []gate{
		{"test-hardening", func() gateVerdict {
			return checkStableWorkflowGate(release.WorkflowTestHardening, "test-hardening", "SKIP_TEST_HARDENING", rcTag, rcCommit, rcShort)
		}},
		{"test-smoke", func() gateVerdict { return checkSmokeGate(projDir, rcTag, rcCommit, rcShort) }},
		{"install-recovery-harness", func() gateVerdict { return checkInstallRecoveryHarnessGate(projDir, rcTag, rcCommit, rcShort) }},
		{"upgrade-arc-harness", func() gateVerdict { return checkUpgradeArcHarnessGate(projDir, rcTag, rcCommit, rcShort) }},
		{"rc-artifacts", func() gateVerdict { return checkRCArtifactGate(rcTag) }},
		{"canaries", func() gateVerdict { return checkCanaryGates(rcTag, rcCommit) }},
	}
	for _, g := range gates {
		var verdict gateVerdict
		out := captureStdout(t, func() { verdict = g.run() })
		t.Logf("--- %s: verdict=%v\n%s", g.name, verdict, out)
		if verdict != gatePassed {
			t.Errorf("gate %s did not pass for %s", g.name, rcTag)
		}
	}
}

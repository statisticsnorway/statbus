package releasecmd

// STATBUS-532: the stable preflight must report what is actually happening —
// running, not started, passed, failed — with ⏳ for pending work and ✗ only
// for an observed failure. These tests were written against the 2026-10-26
// alarmist output and failed there (red evidence: tmp/test-532-red.log); the
// wording they pin is the plain replacement.

import (
	"strings"
	"testing"
	"time"

	"github.com/statisticsnorway/statbus/cli/internal/release"
)

// Pending tag-fired workflow: an in-flight run is work in progress, not a
// failure. The old output printed "✗ test-hardening is still pending".
func TestStableGate_PendingRendersAsRunning_STATBUS532(t *testing.T) {
	const commit = "1234567890123456789012345678901234567890"
	stubWorkflowSeams(t, func(workflow, sha string) release.WorkflowCheckResult {
		return release.WorkflowCheckResult{
			Status: release.WorkflowCheckPending,
			RunID:  99,
			RunURL: "https://github.com/statisticsnorway/statbus/actions/runs/99",
		}
	}, trivialComplete)

	var verdict gateVerdict
	out := captureStdout(t, func() {
		verdict = checkStableWorkflowGate(release.WorkflowTestHardening, "test-hardening", "SKIP_TEST_HARDENING", "v2026.08.0-rc.01", commit, commit[:12])
	})
	if verdict == gatePassed {
		t.Fatalf("a run still in progress must not pass the gate; output:\n%s", out)
	}
	if verdict != gatePending {
		t.Errorf("a running workflow is pending work, not an observed failure; output:\n%s", out)
	}
	if !strings.Contains(out, "  ⏳ test-hardening is still running at "+commit[:12]) {
		t.Errorf("pending work must carry the hourglass and the word 'running'; output:\n%s", out)
	}
	if strings.Contains(out, "✗") {
		t.Errorf("pending work must not wear the failure icon; output:\n%s", out)
	}
	if !strings.Contains(out, "gh run watch 99") {
		t.Errorf("the pending state must point at the in-flight run; output:\n%s", out)
	}
}

// A missing tag-fired run is work that has not started: hourglass, plain
// words, and the trigger to start it.
func TestStableGate_MissingRendersAsNotStarted_STATBUS532(t *testing.T) {
	const commit = "1234567890123456789012345678901234567890"
	stubWorkflowSeams(t, func(workflow, sha string) release.WorkflowCheckResult {
		return release.WorkflowCheckResult{Status: release.WorkflowCheckMissing}
	}, trivialComplete)

	var verdict gateVerdict
	out := captureStdout(t, func() {
		verdict = checkStableWorkflowGate(release.WorkflowTestHardening, "test-hardening", "SKIP_TEST_HARDENING", "v2026.08.0-rc.01", commit, commit[:12])
	})
	if verdict == gatePassed {
		t.Fatalf("a workflow that never ran must not pass; output:\n%s", out)
	}
	if verdict != gatePending {
		t.Errorf("a workflow that has not run is pending work, not an observed failure; output:\n%s", out)
	}
	if !strings.Contains(out, "  ⏳ test-hardening has not run for "+commit[:12]) {
		t.Errorf("not-started work must carry the hourglass; output:\n%s", out)
	}
	if !strings.Contains(out, "gh workflow run test-hardening.yaml --ref v2026.08.0-rc.01") {
		t.Errorf("not-started work must offer its trigger; output:\n%s", out)
	}
}

// A concluded non-success run is the one case that earns ✗.
func TestStableGate_FailedRendersAsObservedFailure_STATBUS532(t *testing.T) {
	const commit = "1234567890123456789012345678901234567890"
	stubWorkflowSeams(t, func(workflow, sha string) release.WorkflowCheckResult {
		return release.WorkflowCheckResult{
			Status: release.WorkflowCheckFailed,
			Detail: "failure",
			RunID:  42,
			RunURL: "https://github.com/statisticsnorway/statbus/actions/runs/42",
		}
	}, trivialComplete)

	var verdict gateVerdict
	out := captureStdout(t, func() {
		verdict = checkStableWorkflowGate(release.WorkflowTestHardening, "test-hardening", "SKIP_TEST_HARDENING", "v2026.08.0-rc.01", commit, commit[:12])
	})
	if verdict == gatePassed {
		t.Fatalf("a failed run must not pass; output:\n%s", out)
	}
	if verdict != gateFailed {
		t.Errorf("a concluded non-success run is an observed failure; output:\n%s", out)
	}
	if !strings.Contains(out, "  ✗ test-hardening failed at "+commit[:12]) {
		t.Errorf("an observed failure must carry the error icon and the word 'failed'; output:\n%s", out)
	}
}

// The orchestrator starts lxd-fleet only after its dev-canary step. While the
// orchestrator is still running, a missing lxd-fleet run means that step has
// not been reached — name the blocked step and DO NOT offer a manual trigger
// that would race the orchestrator. The old output offered the trigger
// immediately.
func TestLXDFleetMissing_OrchestratorRunningNamesItsBlockedStep_STATBUS532(t *testing.T) {
	const commit = "1234567890123456789012345678901234567890"
	stubWorkflowSeams(t, func(workflow, sha string) release.WorkflowCheckResult {
		if workflow == "release-fleet-orchestrator.yaml" {
			return release.WorkflowCheckResult{
				Status: release.WorkflowCheckPending,
				RunID:  77,
				RunURL: "https://github.com/statisticsnorway/statbus/actions/runs/77",
			}
		}
		return release.WorkflowCheckResult{Status: release.WorkflowCheckMissing}
	}, trivialComplete)

	var verdict gateVerdict
	out := captureStdout(t, func() {
		verdict = checkInstallRecoveryHarnessGate("", "v2026.08.0-rc.01", commit, commit[:12])
	})
	if verdict == gatePassed {
		t.Fatalf("a missing LXD suite must not pass; output:\n%s", out)
	}
	if !strings.Contains(out, "  ⏳ lxd-fleet has not run for "+commit[:12]) {
		t.Errorf("the missing suite is pending work; output:\n%s", out)
	}
	if !strings.Contains(out, "dev-canary") {
		t.Errorf("the output must name the orchestrator step the fleet is waiting on; output:\n%s", out)
	}
	if !strings.Contains(out, "gh run watch 77") {
		t.Errorf("the output must point at the orchestrator run itself; output:\n%s", out)
	}
	if strings.Contains(out, "gh workflow run lxd-fleet.yaml") {
		t.Errorf("a manual trigger must NOT be offered while the orchestrator is still working — it would race the chain; output:\n%s", out)
	}
}

// The same missing suite, but the orchestrator has FINISHED without scheduling
// it: now the manual trigger is the right next move.
func TestLXDFleetMissing_OrchestratorFinishedOffersTrigger_STATBUS532(t *testing.T) {
	const commit = "1234567890123456789012345678901234567890"
	stubWorkflowSeams(t, func(workflow, sha string) release.WorkflowCheckResult {
		if workflow == "release-fleet-orchestrator.yaml" {
			return release.WorkflowCheckResult{Status: release.WorkflowCheckGreen}
		}
		return release.WorkflowCheckResult{Status: release.WorkflowCheckMissing}
	}, trivialComplete)

	var verdict gateVerdict
	out := captureStdout(t, func() {
		verdict = checkInstallRecoveryHarnessGate("", "v2026.08.0-rc.01", commit, commit[:12])
	})
	if verdict == gatePassed {
		t.Fatalf("a missing LXD suite must not pass; output:\n%s", out)
	}
	if !strings.Contains(out, "finished without scheduling") {
		t.Errorf("the output must say the orchestrator finished without scheduling the fleet; output:\n%s", out)
	}
	if !strings.Contains(out, "gh workflow run lxd-fleet.yaml --ref v2026.08.0-rc.01") {
		t.Errorf("once the orchestrator is done, the manual trigger IS the next move; output:\n%s", out)
	}
}

// arcBlockedFixture builds the STATBUS-252 blocked state: every arc has
// evidence at rc.01, a sensitive file changed on the way to rc.02, and no run
// exists at rc.02 yet. Returns (dir, anchorTag, target, targetShort).
func arcBlockedFixture(t *testing.T, arcs ...string) (string, string, string, string) {
	t.Helper()
	paths := []string{"doc/readme.md"}
	for _, arc := range arcs {
		paths = append(paths, upgradeArcDir+arc+upgradeArcSuffix)
	}
	dir, _ := arcFixture(t, paths...)
	writeSensitivePathsFile(t, dir, "cli/internal/upgrade/")

	anchor := runGitInCmd(t, dir, "rev-parse", "HEAD")
	runGitInCmd(t, dir, "tag", "-a", "v2026.08.0-rc.01", "-m", "Pre-release v2026.08.0-rc.01")

	writeAndCommit(t, dir, "sensitive change", "cli/internal/upgrade/service.go")
	target := runGitInCmd(t, dir, "rev-parse", "HEAD")
	runGitInCmd(t, dir, "tag", "-a", "v2026.08.0-rc.02", "-m", "Pre-release v2026.08.0-rc.02")

	addOriginRemote(t, dir)
	pushTags(t, dir)

	evidence := map[string]map[string]bool{}
	for _, arc := range arcs {
		evidence[arc] = map[string]bool{anchor: true}
	}
	stubScenarioEvidence(t, evidence)
	return dir, "v2026.08.0-rc.01", target, target[:7]
}

// The 2026-10-26 preflight printed all 33 arc names with a ✗ each and repeated
// the same changed-file count 33 times. The collapse must instead say how many
// scenarios have passed, why the old results cannot be reused, and how to
// inspect the actual changes — with the SAME paths the check itself watches.
func TestArcGate_BlockedOutputCollapsesNamesAndCounts_STATBUS532(t *testing.T) {
	dir, anchorTag, target, targetShort := arcBlockedFixture(t, "alpha", "beta", "gamma", "delta", "epsilon")
	stubWorkflowSeams(t, func(workflow, sha string) release.WorkflowCheckResult {
		if workflow == "release-fleet-orchestrator.yaml" {
			return release.WorkflowCheckResult{Status: release.WorkflowCheckPending, RunID: 77,
				RunURL: "https://github.com/statisticsnorway/statbus/actions/runs/77"}
		}
		return release.WorkflowCheckResult{Status: release.WorkflowCheckMissing}
	}, trivialComplete)

	var verdict gateVerdict
	out := captureStdout(t, func() {
		verdict = checkUpgradeArcHarnessGate(dir, "v2026.08.0-rc.02", target, target[:7])
	})
	if verdict == gatePassed {
		t.Fatalf("blocked scenarios must not pass; output:\n%s", out)
	}

	wantSummary := "  ⏳ upgrade-arc-harness.yaml: 0/5 scenarios have passed at " + target[:7] +
		". Results from " + anchorTag + " cannot be reused because 1 file used by these scenarios changed."
	if !strings.Contains(out, wantSummary) {
		t.Errorf("summary mismatch; want %q; output:\n%s", wantSummary, out)
	}
	for _, arc := range []string{"alpha", "beta", "gamma", "delta", "epsilon"} {
		if strings.Contains(out, "✗ "+arc) {
			t.Errorf("pending arc %q must not wear the failure icon; output:\n%s", arc, out)
		}
	}
	if strings.Contains(out, "changed files — re-run with --verbose") {
		t.Errorf("the repeated changed-file count pointer must be gone — the git commands replace it; output:\n%s", out)
	}

	// The git commands must name the SAME hard-coded paths the scenario check
	// watches: the fixture policy above plus the arc home's own rules.
	wantCmd := "git log --oneline " + anchorTag + ".." + targetShort + " -- " +
		".github/workflows/upgrade-arc-harness.yaml " +
		"cli/internal/release cli/internal/upgrade " +
		"ops/ci-deploy-status.sh ops/niue/sshdo ops/niue/sshdoers " +
		"ops/release/upgrade-sensitive-paths.txt " +
		"test/install-recovery/arcs test/install-recovery/run.sh"
	if !strings.Contains(out, wantCmd) {
		t.Errorf("the review command must carry the exact pathspec the check watches;\nwant: %s\noutput:\n%s", wantCmd, out)
	}
	if !strings.Contains(out, "git diff "+anchorTag+".."+targetShort+" -- ") {
		t.Errorf("a diff command over the same range must be offered; output:\n%s", out)
	}
	if !strings.Contains(out, "git log -p "+anchorTag+".."+targetShort+" -- ") {
		t.Errorf("a commit-by-commit patch command over the same range must be offered; output:\n%s", out)
	}

	// The orchestrator is still working: it starts the arcs after dev-canary,
	// so no manual trigger may be offered.
	if strings.Contains(out, "gh workflow run upgrade-arc-harness.yaml") {
		t.Errorf("no manual trigger while the orchestrator is mid-run; output:\n%s", out)
	}
	if !strings.Contains(out, "dev-canary") {
		t.Errorf("the orchestrator's blocked step must be named; output:\n%s", out)
	}
}

// When the orchestrator has finished without scheduling the arcs, the manual
// trigger becomes the next move.
func TestArcGate_BlockedOrchestratorFinishedOffersTrigger_STATBUS532(t *testing.T) {
	dir, _, target, _ := arcBlockedFixture(t, "alpha")
	stubWorkflowSeams(t, func(workflow, sha string) release.WorkflowCheckResult {
		if workflow == "release-fleet-orchestrator.yaml" {
			return release.WorkflowCheckResult{Status: release.WorkflowCheckGreen}
		}
		return release.WorkflowCheckResult{Status: release.WorkflowCheckMissing}
	}, trivialComplete)

	var verdict gateVerdict
	out := captureStdout(t, func() {
		verdict = checkUpgradeArcHarnessGate(dir, "v2026.08.0-rc.02", target, target[:7])
	})
	if verdict == gatePassed {
		t.Fatalf("blocked scenarios must not pass; output:\n%s", out)
	}
	if !strings.Contains(out, "finished without scheduling") {
		t.Errorf("the output must say the orchestrator finished without scheduling; output:\n%s", out)
	}
	if !strings.Contains(out, "gh workflow run upgrade-arc-harness.yaml --ref v2026.08.0-rc.02") {
		t.Errorf("the manual trigger is the next move once the orchestrator is done; output:\n%s", out)
	}
}

// A concluded FAILURE at the target commit is an observed error: ✗, plain
// 'failed', and the failed run named.
func TestArcGate_FailedRunAtTargetIsAnObservedError_STATBUS532(t *testing.T) {
	dir, _, target, _ := arcBlockedFixture(t, "alpha")
	stubWorkflowSeams(t, func(workflow, sha string) release.WorkflowCheckResult {
		if workflow == release.WorkflowUpgradeArcHarness {
			return release.WorkflowCheckResult{
				Status: release.WorkflowCheckFailed, Detail: "failure", RunID: 55,
				RunURL: "https://github.com/statisticsnorway/statbus/actions/runs/55"}
		}
		return release.WorkflowCheckResult{Status: release.WorkflowCheckMissing}
	}, trivialComplete)

	var verdict gateVerdict
	out := captureStdout(t, func() {
		verdict = checkUpgradeArcHarnessGate(dir, "v2026.08.0-rc.02", target, target[:7])
	})
	if verdict == gatePassed {
		t.Fatalf("a failed run at the target must not pass; output:\n%s", out)
	}
	if verdict != gateFailed {
		t.Errorf("a concluded failure at the target is an observed failure, not pending work; output:\n%s", out)
	}
	if !strings.Contains(out, "✗") || !strings.Contains(out, "failed") {
		t.Errorf("an observed failure must say so with the error icon; output:\n%s", out)
	}
	if !strings.Contains(out, "gh run view 55 --log-failed") {
		t.Errorf("the failed run must be named for inspection; output:\n%s", out)
	}
}

// Dev within its automatic-deploy window is NOT a fault: the chain installs
// dev, and a two-minute-old offer is normal operation. The old output called
// any wait "THIS IS A FAULT ON THIS SLOT".
func TestCanaryDev_ShortWaitIsNotYetAFault_STATBUS532(t *testing.T) {
	discovered := time.Now().Add(-2 * time.Minute).UTC().Format("2006-01-02 15:04:05+00")
	probe := canaryProbe{found: true, state: "available", discoveredAt: discovered}

	out := captureStdout(t, func() {
		printCanaryExplanation(canarySlots[0], canaryAwaitingOperator, probe, "v2026.08.0-rc.09")
	})
	if strings.Contains(out, "FAULT") {
		t.Errorf("a two-minute wait on the automatic canary is not a fault; output:\n%s", out)
	}
	if !strings.Contains(out, "not yet a fault") {
		t.Errorf("the short wait must be named as normal automatic-deploy behaviour; output:\n%s", out)
	}
	if !strings.Contains(out, "Release Fleet Orchestrator") {
		t.Errorf("the next move must be inspecting the orchestrator, not manual register/schedule; output:\n%s", out)
	}
	if !strings.Contains(out, "Your next move") {
		t.Errorf("every outcome must hand the reader a next move; output:\n%s", out)
	}
}

// The same row after the automatic-deploy window IS a fault: the chain had
// its chance and did not deliver.
func TestCanaryDev_LongWaitIsAFault_STATBUS532(t *testing.T) {
	discovered := time.Now().Add(-11 * time.Hour).UTC().Format("2006-01-02 15:04:05+00")
	probe := canaryProbe{found: true, state: "available", discoveredAt: discovered}

	out := captureStdout(t, func() {
		printCanaryExplanation(canarySlots[0], canaryAwaitingOperator, probe, "v2026.08.0-rc.09")
	})
	if !strings.Contains(out, "FAULT") {
		t.Errorf("an offer unclaimed for 11h on the automatic canary is a chain fault; output:\n%s", out)
	}
	if strings.Contains(out, "not yet a fault") {
		t.Errorf("the long wait must not be rendered as normal; output:\n%s", out)
	}
}

// Norway has not discovered the RC: its 6h check interval makes waiting the
// expected state, said plainly, and the diagnostic command must not carry the
// duplicated '(Upgrader|Upgrader)' alternation the old output printed.
func TestCanaryNorway_NotOfferedWaitsForItsNextCheck_STATBUS532(t *testing.T) {
	probe := canaryProbe{checkInterval: "6h", lastDiscoveryAt: "2026-08-18 09:00:00+00"}

	out := captureStdout(t, func() {
		printCanaryExplanation(canarySlots[1], canaryNotOffered, probe, "v2026.08.0-rc.09")
	})
	if !strings.Contains(out, "every 6h") {
		t.Errorf("the box's check interval must be reported; output:\n%s", out)
	}
	if !strings.Contains(out, "not a fault") {
		t.Errorf("waiting for the next 6h check is expected, and the output must say so; output:\n%s", out)
	}
	if strings.Contains(out, "(Upgrader|Upgrader)") {
		t.Errorf("the diagnostic grep must not duplicate the Upgrader alternative; output:\n%s", out)
	}
	if !strings.Contains(out, "(Upgrader|upgrade service) started") {
		t.Errorf("the diagnostic grep must match the upgrader's actual start lines; output:\n%s", out)
	}
	if !strings.Contains(out, "./sb upgrade check") {
		t.Errorf("the make-it-check-now command must be offered; output:\n%s", out)
	}
}

// stubCanaryProbe swaps the ssh probe seam (release_canary.go's probeCanary)
// for the duration of a test, so checkOneCanary's full rendering — header
// icon, slot name, verdict — is exercisable without a box.
func stubCanaryProbe(t *testing.T, probe canaryProbe, err error) {
	t.Helper()
	old := probeCanary
	probeCanary = func(canarySlot, string) (canaryProbe, error) { return probe, err }
	t.Cleanup(func() { probeCanary = old })
}

// The full canary rendering: pending states wear the hourglass and the
// operator slot is named "Canary Norway", while an observed install failure
// wears ✗. Gating is unchanged: only completed passes.
func TestCanaryHeader_IconAndNamePerState_STATBUS532(t *testing.T) {
	const commit = "1234567890123456789012345678901234567890"
	cases := []struct {
		name     string
		slot     canarySlot
		probe    canaryProbe
		wantMark string
		wantHead string
	}{
		{"norway not offered", canarySlots[1], canaryProbe{checkInterval: "6h"}, "⏳", "Canary Norway — has not discovered this RC"},
		{"norway completed", canarySlots[1], canaryProbe{found: true, state: "completed", completedAt: "2026-08-19 09:00:00+00"}, "✓", "Canary Norway — passed"},
		{"norway failed", canarySlots[1], canaryProbe{found: true, state: "failed", errorText: "boom"}, "✗", "Canary Norway"},
		{"dev short wait", canarySlots[0], canaryProbe{found: true, state: "available", discoveredAt: time.Now().Add(-2 * time.Minute).UTC().Format("2006-01-02 15:04:05+00")}, "⏳", "Canary dev"},
		{"dev long wait", canarySlots[0], canaryProbe{found: true, state: "available", discoveredAt: time.Now().Add(-11 * time.Hour).UTC().Format("2006-01-02 15:04:05+00")}, "✗", "Canary dev"},
		{"dev install running", canarySlots[0], canaryProbe{found: true, state: "in_progress", startedAt: "2026-08-19 09:00:00+00"}, "⏳", "Canary dev"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			stubCanaryProbe(t, tc.probe, nil)
			var verdict gateVerdict
			out := captureStdout(t, func() {
				verdict = checkOneCanary(tc.slot, "v2026.08.0-rc.09", commit)
			})
			head := ""
			for _, line := range strings.Split(out, "\n") {
				if strings.Contains(line, "Canary ") {
					head = line
					break
				}
			}
			if head == "" {
				t.Fatalf("no canary header line; output:\n%s", out)
			}
			if !strings.HasPrefix(head, "  "+tc.wantMark+" ") {
				t.Errorf("header must start with %q; got %q; output:\n%s", tc.wantMark, head, out)
			}
			if !strings.Contains(head, tc.wantHead) {
				t.Errorf("header must contain %q; got %q", tc.wantHead, head)
			}
			if strings.Contains(out, "Canary no ") || strings.Contains(out, "Canary no\n") || strings.Contains(out, "Canary no —") {
				t.Errorf("the operator slot must be named Norway, not 'no'; output:\n%s", out)
			}
			want := gatePending
			switch tc.wantMark {
			case "✓":
				want = gatePassed
			case "✗":
				want = gateFailed
			}
			if verdict != want {
				t.Errorf("verdict = %v, want %v; output:\n%s", verdict, want, out)
			}
		})
	}
}

// Only pending work remains → the run ends waiting, not alarmed. Any observed
// failure → the refusal is named as such. Both still block promotion.
func TestConcludeStablePreflight_WaitingVsFailed_STATBUS532(t *testing.T) {
	out := captureStdout(t, func() {
		if err := concludeStablePreflight(nil, gatePassed, gatePending); err == nil {
			t.Error("pending work must still block promotion")
		}
	})
	if !strings.Contains(out, "Stable promotion is waiting for the checks above to complete.") {
		t.Errorf("pending-only must end with the waiting message; output:\n%s", out)
	}

	var failedErr error
	out = captureStdout(t, func() {
		failedErr = concludeStablePreflight(nil, gatePassed, gatePending, gateFailed)
	})
	if failedErr == nil {
		t.Error("an observed failure must block promotion")
	}
	if strings.Contains(out, "waiting for the checks") {
		t.Errorf("a real failure must not be softened into the waiting message; output:\n%s", out)
	}

	if err := concludeStablePreflight(nil, gatePassed, gatePassed); err != nil {
		t.Errorf("all green must proceed: %v", err)
	}
}

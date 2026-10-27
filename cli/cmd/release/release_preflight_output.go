package releasecmd

// STATBUS-532: the stable preflight's operator-facing states. The gate
// DECISIONS are unchanged — only completed/verified work passes — but a
// refusal now distinguishes "an observed failure needs action" from "work is
// running or has legitimately not started yet", so the closing message and
// each line's icon can tell the truth.

import (
	"errors"
	"fmt"
	"sort"
	"strings"

	"github.com/spf13/cobra"

	"github.com/statisticsnorway/statbus/cli/internal/release"
)

// gateVerdict is a stable pre-flight gate's three-way answer. gatePending and
// gateFailed both refuse promotion exactly as the old boolean false did; the
// distinction exists so the output can say "waiting" instead of "failed" when
// no observed failure remains.
type gateVerdict int

const (
	// gatePassed — the gate's invariant is verified for this RC.
	gatePassed gateVerdict = iota
	// gatePending — work is running or legitimately not started yet. Waiting
	// (or starting the work, when the chain has finished without scheduling
	// it) is the next move. Rendered with ⏳.
	gatePending
	// gateFailed — an observed failure: a concluded non-success run, a failed
	// install attempt, a probe that could not read the box. Needs action, not
	// time. Rendered with ✗.
	gateFailed
)

// errStablePromotionWaiting is the non-zero exit for "only pending work
// remains". The message is printed by concludeStablePreflight itself with
// cobra's "Error:" prefix silenced: a waiting state is not an alarm, but the
// promotion must still not proceed.
var errStablePromotionWaiting = errors.New("stable promotion is waiting for the checks above to complete")

// concludeStablePreflight turns the gates' verdicts into the command's
// closing state. Any observed failure keeps the historic refusal; pending
// work alone ends with a concrete waiting message. Gating semantics are
// unchanged: anything short of all-green returns a non-nil error.
func concludeStablePreflight(cmd *cobra.Command, verdicts ...gateVerdict) error {
	failed, pending := false, false
	for _, v := range verdicts {
		switch v {
		case gateFailed:
			failed = true
		case gatePending:
			pending = true
		}
	}
	switch {
	case failed:
		return fmt.Errorf("pre-flight checks failed")
	case pending:
		fmt.Println("Stable promotion is waiting for the checks above to complete.")
		if cmd != nil {
			cmd.SilenceErrors = true
		}
		return errStablePromotionWaiting
	}
	return nil
}

// pluralFiles renders "1 file" / "N files" for the blocked-summary sentence.
func pluralFiles(n int) string {
	if n == 1 {
		return "1 file"
	}
	return fmt.Sprintf("%d files", n)
}

// sortedAnchors sorts the blocked-anchor set for deterministic output.
func sortedAnchors(anchors map[string]struct{}) []string {
	out := make([]string, 0, len(anchors))
	for anchor := range anchors {
		out = append(out, anchor)
	}
	sort.Strings(out)
	return out
}

// printReviewCommands offers the operator git commands that inspect exactly
// the changes a scenario home's check is sensitive to, over anchor→target.
// The pathspec comes from release.DisplayPathspec — the same hard-coded rules
// the check itself consults, never a list invented for display.
func printReviewCommands(projDir string, home release.Workflow, anchor, rcShort string) {
	pathspec, err := release.DisplayPathspec(projDir, home)
	if err != nil {
		fmt.Printf("    (could not compute the review path list: %v)\n", err)
		return
	}
	paths := strings.Join(pathspec, " ")
	fmt.Println("    Review the commits with:")
	fmt.Printf("      git log --oneline %s..%s -- %s\n", anchor, rcShort, paths)
	fmt.Println("    See the actual changes with:")
	fmt.Printf("      git diff %s..%s -- %s\n", anchor, rcShort, paths)
	fmt.Println("    Or review them commit by commit with patches:")
	fmt.Printf("      git log -p %s..%s -- %s\n", anchor, rcShort, paths)
	fmt.Println("    These are the same paths this check watches for changes — not a list made up for display.")
}

// printOrchestratorGuidance explains an orchestrator-scheduled workflow that
// has not started. predecessor names the orchestrator step that must finish
// first ("its dev-canary step" for lxd-fleet and the upgrade arcs, which the
// orchestrator's job graph places after dev; "its smoke step" for smoke).
//
// The manual trigger is offered ONLY when the orchestrator has finished (or
// never ran) without scheduling the workflow. While the orchestrator is still
// working, the blocked step is named instead, and a hand trigger would race
// the chain (STATBUS-532).
func printOrchestratorGuidance(workflow, rcTag, rcCommit, predecessor string) {
	orch := checkWorkflowAtCommit(release.WorkflowFleetOrchestrator, rcCommit)
	switch orch.Status {
	case release.WorkflowCheckPending:
		fmt.Printf("    The release orchestrator is still working on this RC. It starts %s after %s, which has not finished — later steps are skipped until it does, so nothing here has started yet.\n", workflow, predecessor)
		fmt.Printf("    Watch: gh run watch %d\n", orch.RunID)
		fmt.Printf("    URL:   %s\n", orch.RunURL)
		fmt.Println("    Next: wait for the orchestrator to finish, then re-run stable")
	case release.WorkflowCheckGreen:
		fmt.Printf("    The release orchestrator has finished without scheduling %s. Trigger it by hand:\n", workflow)
		fmt.Printf("      %s\n", release.WorkflowTriggerCommand(workflow, rcTag))
		fmt.Printf("    Watch: %s\n", release.WorkflowURL(workflow))
		fmt.Println("    Next: wait for green, then re-run stable")
	case release.WorkflowCheckFailed:
		fmt.Printf("    The release orchestrator run for this RC failed (conclusion: %s) before scheduling %s — its later steps were skipped.\n", orch.Detail, workflow)
		fmt.Printf("    See: gh run view %d --log-failed\n", orch.RunID)
		fmt.Printf("    URL: %s\n", orch.RunURL)
		fmt.Printf("    Once the cause is understood, trigger by hand: %s\n", release.WorkflowTriggerCommand(workflow, rcTag))
		fmt.Println("    Next: wait for green, then re-run stable")
	default:
		// Missing or unknown: nothing is going to schedule this workflow, so
		// the manual trigger is the next move.
		fmt.Printf("    No release orchestrator run is managing this RC, so nothing will schedule %s on its own. Trigger it:\n", workflow)
		fmt.Printf("      %s\n", release.WorkflowTriggerCommand(workflow, rcTag))
		fmt.Printf("    Watch: %s\n", release.WorkflowURL(workflow))
		fmt.Println("    Next: wait for green, then re-run stable")
	}
}

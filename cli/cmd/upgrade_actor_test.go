package cmd

import (
	"os"
	"strings"
	"testing"
)

// STATBUS-317 TRAP #1, verbatim from the architect: "a naive prompt would
// wedge the deploy path. The CI door is ./sb upgrade apply <sha> over
// sshdo, entirely non-interactive. A prompt that blocks there hangs the
// automatic canary forever. The TTY test is not politeness; it is what
// keeps this from breaking the chain."
//
// These pin the shape that makes that true: resolveOperator is the ONLY
// place a prompt may originate, it checks isTerminal() before printing
// anything, and every state-transition verb reaches it — none of them
// prompt directly or skip the check.

func readUpgradeCmdSource(t *testing.T) string {
	t.Helper()
	b, err := os.ReadFile(thisRepoFile(t, "cli/cmd/upgrade.go"))
	if err != nil {
		t.Fatalf("read upgrade.go: %v", err)
	}
	return string(b)
}

// TestResolveOperatorChecksTerminalBeforePrompting_STATBUS317: the ordering
// inside resolveOperator itself — isTerminal() must gate the prompt, not
// follow it.
func TestResolveOperatorChecksTerminalBeforePrompting_STATBUS317(t *testing.T) {
	src := readUpgradeCmdSource(t)
	start := strings.Index(src, "func resolveOperator(")
	if start < 0 {
		t.Fatal("resolveOperator not found — test is stale or the STATBUS-317 TTY gate regressed")
	}
	end := strings.Index(src[start:], "\n}\n")
	if end < 0 {
		t.Fatal("closing brace for resolveOperator not found")
	}
	body := src[start : start+end]

	ttyIdx := strings.Index(body, "isTerminal()")
	promptIdx := strings.Index(body, "fmt.Print(")
	if ttyIdx < 0 || promptIdx < 0 {
		t.Fatalf("resolveOperator is missing the isTerminal() check or the prompt itself — test is stale (tty=%d prompt=%d)", ttyIdx, promptIdx)
	}
	if ttyIdx > promptIdx {
		t.Error(`resolveOperator checks isTerminal() AFTER already printing the prompt.

That is the exact wedge the architect named: a non-interactive caller
(CI's ./sb upgrade apply <sha> over sshdo) would already be blocked on
stdin by the time this function realizes there is no terminal to answer
from. The check must gate the prompt, not follow it.`)
	}
	// And it must be a real return-early guard, not merely present somewhere
	// in the body — !isTerminal() must return before the prompt code runs.
	if !strings.Contains(body[:promptIdx], "if !isTerminal()") {
		t.Error(`resolveOperator must return early on "if !isTerminal()" before reaching the prompt — a differently-shaped check (e.g. only warning, or checking a different condition) is not the guard this trap requires`)
	}
}

// TestStateTransitionVerbsRouteThroughResolveOperator_STATBUS317: every verb
// that can transition an upgrade row (schedule, dismiss, apply, apply-latest)
// must call resolveOperator — never prompt directly (which would bypass the
// TTY gate) and never silently skip actor resolution.
func TestStateTransitionVerbsRouteThroughResolveOperator_STATBUS317(t *testing.T) {
	src := readUpgradeCmdSource(t)

	// resolveOperator must be the ONLY operator-prompt path: its own body
	// (not the whole file — trustKeyAddCmd has its own, unrelated,
	// already-gated interactive prompt for a different feature entirely)
	// must contain exactly one bufio.NewReader(os.Stdin).
	start := strings.Index(src, "func resolveOperator(")
	if start < 0 {
		t.Fatal("resolveOperator not found — test is stale")
	}
	end := strings.Index(src[start:], "\n}\n")
	if end < 0 {
		t.Fatal("closing brace for resolveOperator not found")
	}
	resolveOperatorBody := src[start : start+end]
	if n := strings.Count(resolveOperatorBody, "bufio.NewReader(os.Stdin)"); n != 1 {
		t.Errorf("expected exactly 1 use of bufio.NewReader(os.Stdin) inside resolveOperator, found %d", n)
	}

	for _, call := range []struct{ verb, want string }{
		{"RunSchedule", "RunSchedule(context.Background(), args[0], recreateFlag, resolveOperator(operatorFlag))"},
		{"RunDismiss", "RunDismiss(context.Background(), args[0], resolveOperator(operatorFlag))"},
		{"RunApply", "RunApply(ctx, args[0], recreate, resolveOperator(\"\"))"},
	} {
		if !strings.Contains(src, call.want) {
			t.Errorf("%s call site not found in the expected shape %q — a state-transition verb must resolve its operator through resolveOperator, never bypass it", call.verb, call.want)
		}
	}
	// apply-latest: less rigid literal match (it is nested inside a larger
	// call), so check the two pieces are adjacent instead.
	if !strings.Contains(src, "RunSchedule(context.Background(), latestVersion, recreateFlag, resolveOperator(\"\"))") {
		t.Error("apply-latest's RunSchedule call must resolve its operator through resolveOperator(\"\") — it is the deploy-workflow CI door and must never prompt without going through the TTY gate")
	}
}

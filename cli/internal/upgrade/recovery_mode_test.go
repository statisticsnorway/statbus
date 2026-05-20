package upgrade

import (
	"os"
	"strings"
	"testing"
)

// TestParseRecoveryMode covers the operator-facing --recovery flag
// parser. Wrong values must fail fast before any DB or filesystem
// state is touched.
func TestParseRecoveryMode(t *testing.T) {
	cases := []struct {
		in   string
		want RecoveryMode
		ok   bool
	}{
		{"", RecoveryAuto, true},
		{"auto", RecoveryAuto, true},
		{"forward", RecoveryForward, true},
		{"restore", RecoveryRestore, true},
		{"AUTO", "", false},   // case-sensitive on purpose
		{"reset", "", false},  // adjacent typo
		{"force", "", false},  // adjacent typo
		{" auto", "", false},  // no whitespace tolerance
		{"auto ", "", false},  // no whitespace tolerance
		{"forward,restore", "", false},
	}
	for _, tc := range cases {
		got, err := ParseRecoveryMode(tc.in)
		if tc.ok {
			if err != nil {
				t.Errorf("ParseRecoveryMode(%q) = err %v; want %v, nil", tc.in, err, tc.want)
				continue
			}
			if got != tc.want {
				t.Errorf("ParseRecoveryMode(%q) = %v; want %v", tc.in, got, tc.want)
			}
			continue
		}
		if err == nil {
			t.Errorf("ParseRecoveryMode(%q) = %v, nil; want error", tc.in, got)
		}
	}
}

// readServiceGo returns the contents of service.go, used by structural
// tests below to assert the runtime-strategy shape of Layer 2 stays in
// place across refactors. Pattern borrowed from postswap_test.go.
func readServiceGo(t *testing.T) string {
	t.Helper()
	data, err := os.ReadFile("service.go")
	if err != nil {
		t.Fatalf("read service.go: %v", err)
	}
	return string(data)
}

// extractFuncBody returns the body of a top-level Go function declaration
// starting at `signature`. Reads until matching closing brace at column 0.
// Used to scope assertions to a specific function so refactors that move
// the relevant code into a different function are caught.
func extractFuncBody(t *testing.T, source, signature string) string {
	t.Helper()
	start := strings.Index(source, signature)
	if start < 0 {
		t.Fatalf("function signature not found: %q", signature)
	}
	// Walk forward from `start` to find the matching "\n}\n" that closes
	// the top-level function. Naive but adequate for non-nested top-level
	// funcs; the project style avoids nested funcs with their own
	// top-level closing braces.
	tail := source[start:]
	end := strings.Index(tail, "\n}\n")
	if end < 0 {
		t.Fatalf("function closing brace not found for %q", signature)
	}
	return tail[:end+3]
}

// TestResumePostSwap_RestoreShortCircuitPresent guards the
// --recovery=restore short-circuit in resumePostSwap: when the operator
// requests restore explicitly, the function MUST skip applyPostSwap and
// route directly to recoveryRollback. Without this branch
// --recovery=restore would still run the forward pipeline before
// falling through to rollback on failure — defeats the operator's
// intent.
func TestResumePostSwap_RestoreShortCircuitPresent(t *testing.T) {
	body := extractFuncBody(t, readServiceGo(t),
		"func (d *Service) resumePostSwap(ctx context.Context, flag UpgradeFlag, mode RecoveryMode) error {")

	if !strings.Contains(body, "mode == RecoveryRestore") {
		t.Errorf("resumePostSwap missing `mode == RecoveryRestore` branch — " +
			"operator's --recovery=restore would not short-circuit applyPostSwap")
	}
	if !strings.Contains(body, "d.recoveryRollback(") {
		t.Errorf("resumePostSwap missing call to d.recoveryRollback — " +
			"restore short-circuit cannot complete without it")
	}
}

// TestApplyPostSwap_ModeGatedRollback guards that applyPostSwap's
// failure paths route through postSwapFailure (which honors --recovery=
// forward by skipping the rollback) rather than calling d.rollback()
// directly. A regression here would make --recovery=forward useless
// for operators trying to inspect a wedged partial state.
func TestApplyPostSwap_ModeGatedRollback(t *testing.T) {
	body := extractFuncBody(t, readServiceGo(t),
		"func (d *Service) applyPostSwap(ctx context.Context, id int, commitSHA, displayName, previousVersion, backupPath string, recreate bool, progress *ProgressLog, mode RecoveryMode) error {")

	// applyPostSwap must NOT call d.rollback() directly — all failure
	// paths go through postSwapFailure so the mode gating applies.
	if strings.Contains(body, "d.rollback(") {
		t.Errorf("applyPostSwap calls d.rollback() directly — " +
			"failure path bypasses --recovery=forward gating. " +
			"Route the failure through postSwapFailure instead.")
	}
	if !strings.Contains(body, "d.postSwapFailure(") {
		t.Errorf("applyPostSwap missing calls to d.postSwapFailure — " +
			"failure paths are not mode-gated")
	}
}

// TestPostSwapFailure_ForwardModeSkipsRollback guards that
// postSwapFailure's RecoveryForward branch deliberately does NOT call
// d.rollback(). This is the operator-debug property: --recovery=forward
// preserves partial state for inspection.
func TestPostSwapFailure_ForwardModeSkipsRollback(t *testing.T) {
	body := extractFuncBody(t, readServiceGo(t),
		"func (d *Service) postSwapFailure(ctx context.Context, id int, displayName, previousVersion, reason string, progress *ProgressLog, mode RecoveryMode) error {")

	// The function must contain a RecoveryForward branch.
	if !strings.Contains(body, "mode == RecoveryForward") {
		t.Errorf("postSwapFailure missing `mode == RecoveryForward` branch")
	}

	// Within the RecoveryForward branch the function must NOT call
	// d.rollback() — the whole point of forward mode is to skip rollback.
	// Verify by checking that d.rollback() appears only AFTER the
	// RecoveryForward branch's `return` statement.
	forwardIdx := strings.Index(body, "mode == RecoveryForward")
	rollbackIdx := strings.Index(body, "d.rollback(")
	forwardReturnIdx := strings.Index(body[forwardIdx:], "return ")
	if rollbackIdx < 0 {
		t.Errorf("postSwapFailure missing d.rollback() call for auto path")
		return
	}
	if forwardReturnIdx < 0 {
		t.Errorf("postSwapFailure RecoveryForward branch missing return statement")
		return
	}
	// The auto rollback() call must be AFTER the forward branch's return,
	// meaning forward-mode flow exits before reaching it.
	if rollbackIdx < forwardIdx+forwardReturnIdx {
		t.Errorf("postSwapFailure: d.rollback() appears before RecoveryForward's return — " +
			"forward mode would still trigger rollback")
	}
}

// TestRecoverFromFlag_ForwardFailureAutoRestore guards that the
// PreSwap-HEAD-matches branch in recoverFromFlag implements the
// runtime forward-then-restore strategy: on forward failure under
// RecoveryAuto (or any non-Forward mode) and with a usable backup,
// fall through to recoveryRollback with an "auto-restored" error
// message.
func TestRecoverFromFlag_ForwardFailureAutoRestore(t *testing.T) {
	body := extractFuncBody(t, readServiceGo(t),
		"func (d *Service) recoverFromFlag(ctx context.Context, mode RecoveryMode) (err error) {")

	// Must NOT reference the removed autoChooseRecovery helper.
	if strings.Contains(body, "autoChooseRecovery") {
		t.Errorf("recoverFromFlag still references autoChooseRecovery — " +
			"the runtime-strategy redesign removed that helper")
	}

	// Must contain a RecoveryForward gate around the forward-failure
	// path so --recovery=forward propagates the error without restoring.
	if !strings.Contains(body, "mode == RecoveryForward") {
		t.Errorf("recoverFromFlag missing `mode == RecoveryForward` gate — " +
			"--recovery=forward would still trigger auto-restore")
	}

	// Must contain the auto-restore log signature so operators reading
	// the upgrade-progress log can search for it.
	if !strings.Contains(body, "auto-restored from") {
		t.Errorf("recoverFromFlag missing 'auto-restored from' log signature " +
			"for the forward-then-restore strategy")
	}

	// Must use flag.BackupPath to gate the fallback (without a usable
	// backup, auto-restore would have nothing to restore from).
	if !strings.Contains(body, "flag.BackupPath") {
		t.Errorf("recoverFromFlag forward-failure path does not consult flag.BackupPath")
	}
}

// TestRecoveryMode_AutoIsTheDefault guards that ParseRecoveryMode treats
// the empty string AND the literal "auto" as RecoveryAuto. The install
// CLI relies on this to make `--recovery` optional with the right
// default; an empty default-on-unset would silently produce
// RecoveryMode("") and break downstream switches.
func TestRecoveryMode_AutoIsTheDefault(t *testing.T) {
	got, err := ParseRecoveryMode("")
	if err != nil {
		t.Fatalf("empty string: unexpected error %v", err)
	}
	if got != RecoveryAuto {
		t.Errorf("empty string: got %v, want RecoveryAuto", got)
	}
}


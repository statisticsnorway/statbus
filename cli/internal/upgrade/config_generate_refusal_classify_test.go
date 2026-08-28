package upgrade

import (
	"errors"
	"fmt"
	"os"
	"strings"
	"testing"
)

// STATBUS-298 — the recovery boot's `./sb config generate` pre-flight must
// distinguish a PRINCIPLED, non-retriable configuration refusal (exit 78,
// EX_CONFIG) from every other failure (timeout, permissions, disk full,
// an unclassified exit 1) that a retry might actually clear. Before this
// fix, EVERY exit here was treated identically: return a generic error,
// systemd restarts into the identical refusal every ~30s, five restarts
// later the rate limiter kills the unit — with the db left down, because
// every attempt failed before ever reaching EnsureDBUp.

func TestConfigGenerateIsPrincipledRefusal(t *testing.T) {
	// AC#1 — exit 78 (a principled config.ErrPrincipledRefusal, selected by
	// configGenerateCmd.RunE) IS the refusal class → write the marker, exit
	// 78 directly, never retry.
	if !configGenerateIsPrincipledRefusal(exitErrWithCode(t, exitPrincipledConfigRefusal)) {
		t.Errorf("exit %d must classify as a principled refusal", exitPrincipledConfigRefusal)
	}

	// AC#2 — every non-78 failure is NOT the refusal class → keep the
	// existing exit-and-let-systemd-retry behavior (a re-run might help).
	for _, tc := range []struct {
		name string
		err  error
	}{
		{"unclassified exit 1 (a genuinely transient config.Generate error)", exitErrWithCode(t, 1)},
		{"exit 2 (unrelated failure shape)", exitErrWithCode(t, 2)},
		{"config generate timeout (a plain error, not an *exec.ExitError)",
			fmt.Errorf("command timed out after 2m0s: %s config generate", "sb")},
		{"non-ExitError (e.g. the subprocess could not even start)",
			errors.New("fork/exec ./sb: no such file or directory")},
		{"nil (defensive — the handler only calls this on a non-nil err)", nil},
	} {
		if configGenerateIsPrincipledRefusal(tc.err) {
			t.Errorf("%s must NOT classify as a principled refusal (keep exit-and-retry)", tc.name)
		}
	}
}

// TestRecoveryBootRefusalBranchWritesMarkerAndExits is the structural guard
// (same genre as TestFlaglessDeterministicBootMigrateStaysAlive) that Run()'s
// config-generate pre-flight actually wires configGenerateIsPrincipledRefusal
// to the marker write + os.Exit(78) — and that the transient/generic-error
// branch (return, no exit) still exists for everything else, in that order.
func TestRecoveryBootRefusalBranchWritesMarkerAndExits(t *testing.T) {
	src, err := os.ReadFile(thisRepoFile(t, "cli/internal/upgrade/service.go"))
	if err != nil {
		t.Fatalf("read service.go: %v", err)
	}
	run := extractFuncBody(t, string(src), "func (d *Service) Run(")

	refusalIdx := strings.Index(run, "if configGenerateIsPrincipledRefusal(err) {")
	if refusalIdx < 0 {
		t.Fatal("Run() must branch on configGenerateIsPrincipledRefusal(err) — test is stale or the fix regressed")
	}
	genericIdx := strings.Index(run, `return fmt.Errorf("pre-flight: regenerate config before db up:`)
	if genericIdx < 0 {
		t.Fatal("Run() must still return the generic pre-flight error for the transient/non-refusal case")
	}
	if refusalIdx > genericIdx {
		t.Errorf("the refusal branch must be checked BEFORE the generic return; refusalIdx=%d genericIdx=%d", refusalIdx, genericIdx)
	}

	branch := run[refusalIdx:genericIdx]
	if !strings.Contains(branch, "writeConfigRefusalMarker(") {
		t.Error("the refusal branch must write the config-refusal marker (./sb install's lever) before exiting")
	}
	if !strings.Contains(branch, fmt.Sprintf("os.Exit(%s)", "exitPrincipledConfigRefusal")) {
		t.Error("the refusal branch must os.Exit(exitPrincipledConfigRefusal) directly — returning a generic error here would let systemd retry the identical refusal")
	}
	if strings.Contains(branch, "return fmt.Errorf") {
		t.Error("the refusal branch must not ALSO return an error — os.Exit already terminates the process; a stray return would be dead code")
	}
}

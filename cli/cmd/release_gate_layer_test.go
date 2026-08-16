package cmd

// STATBUS-205 — the two fixes to the release gate lane, pinned.
//
// Fix 1 (layer correction): test-hardening.yaml and test-install.yaml
// trigger ONLY on v*-rc.* tag push (+ manual dispatch), so no run can
// exist before the RC tag. Gating them at prerelease preflight was a
// deadlock — the preflight demanded runs that only the tag it refused to
// cut could start (the King hit this live at his cut). They gate at
// stable promotion instead. TestReleaseGateLayer_TagFiredWorkflows pins
// BOTH sides: the gate layer in release.go AND the trigger fact in the
// workflow files that justifies it — if either side changes, the pin
// fails and the layering must be re-decided deliberately.
//
// Fix 2 (hedge before, not after): the stable-shipped coordination
// warning used to print AFTER the bless declaration — hedging a decision
// already made. It now lives in the REFUSAL text, where the operator
// reads it BEFORE declaring; a declared pass prints only the neutral ⟳
// receipt. TestMigrationImmutability_StableCoordination* pin both sides.

import (
	"bytes"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/release"
)

// tagFiredWorkflows are the workflows whose ONLY automatic trigger is the
// RC tag push itself — the King's exception clause ("...except where we
// need the pre-release to actually test the gate").
var tagFiredWorkflows = []struct {
	yaml     string
	workflow string // the release.Workflow* constant value
}{
	{".github/workflows/test-hardening.yaml", release.WorkflowTestHardening},
	{".github/workflows/test-install.yaml", release.WorkflowTestInstall},
}

func TestReleaseGateLayer_TagFiredWorkflows(t *testing.T) {
	src, err := os.ReadFile(thisRepoFile(t, "cli/cmd/release.go"))
	if err != nil {
		t.Fatalf("cannot read release.go: %v", err)
	}
	code := string(src)

	for _, wf := range tagFiredWorkflows {
		constName := workflowConstName(t, wf.workflow)

		// Side 1a: NOT gated at prerelease preflight.
		if strings.Contains(code, "checkPrereleaseWorkflowGate(projDir, release."+constName) {
			t.Errorf("release.go gates %s at prerelease preflight — that is the STATBUS-205 "+
				"deadlock: %s fires only on the v*-rc.* tag push, so preflight demands a run "+
				"that only the tag it refuses to cut can start. Gate it at stable "+
				"(checkStableWorkflowGate) instead.", wf.workflow, wf.yaml)
		}
		// Side 1b: gated at stable.
		if !strings.Contains(code, "checkStableWorkflowGate(release."+constName) {
			t.Errorf("release.go no longer gates %s at stable promotion "+
				"(checkStableWorkflowGate) — a tag-fired workflow with no gate anywhere is "+
				"an unverified release oracle. See STATBUS-205.", wf.workflow)
		}

		// Side 2: the trigger fact the layering rests on. If someone later
		// adds a commit-scope trigger (push: branches) to these workflows,
		// the deadlock argument dissolves and the layer choice must be
		// re-decided — fail here to force that.
		wfData, err := os.ReadFile(thisRepoFile(t, wf.yaml))
		if err != nil {
			t.Fatalf("cannot read %s: %v", wf.yaml, err)
		}
		wfText := string(wfData)
		if !strings.Contains(wfText, "v*-rc.*") {
			t.Errorf("%s no longer declares the v*-rc.* tag-push trigger — the STATBUS-205 "+
				"stable-layer gating of %s rests on that trigger fact; re-decide the gate "+
				"layer together with this trigger change.", wf.yaml, wf.workflow)
		}
		if strings.Contains(wfText, "branches:") {
			t.Errorf("%s now has a branch-push trigger — it is no longer purely tag-fired, "+
				"so the STATBUS-205 deadlock argument for gating it at stable (not prerelease "+
				"preflight) no longer holds. Re-decide the gate layer deliberately.", wf.yaml)
		}
	}
}

// workflowConstName maps a workflow yaml basename back to its release
// package constant name, so the source pin above greps for the constant
// reference (release.WorkflowTestInstall) rather than a string literal.
func workflowConstName(t *testing.T, workflow string) string {
	t.Helper()
	switch workflow {
	case release.WorkflowTestHardening:
		return "WorkflowTestHardening"
	case release.WorkflowTestInstall:
		return "WorkflowTestInstall"
	}
	t.Fatalf("no constant-name mapping for workflow %q", workflow)
	return ""
}

// captureStdout runs fn with os.Stdout redirected to a pipe and returns
// everything fn printed.
func captureStdout(t *testing.T, fn func()) string {
	t.Helper()
	old := os.Stdout
	r, w, err := os.Pipe()
	if err != nil {
		t.Fatalf("os.Pipe: %v", err)
	}
	os.Stdout = w
	done := make(chan string)
	go func() {
		var buf bytes.Buffer
		_, _ = io.Copy(&buf, r)
		done <- buf.String()
	}()
	defer func() {
		os.Stdout = old
	}()
	fn()
	_ = w.Close()
	os.Stdout = old
	return <-done
}

// immutabilityFixture builds a repo with one released migration, tags it
// with prevTag, then modifies the migration on top — the exact state the
// immutability gate exists to catch.
func immutabilityFixture(t *testing.T, prevTag string) string {
	t.Helper()
	dir := makeRepo(t)
	tagAnnotated(t, dir, prevTag, "release "+prevTag)
	migPath := filepath.Join(dir, "migrations", "20260101000000_init.up.sql")
	if err := os.WriteFile(migPath, []byte("-- init\n-- edited after release\n"), 0644); err != nil {
		t.Fatal(err)
	}
	for _, args := range [][]string{
		{"add", "migrations"},
		{"commit", "-q", "-m", "edit released migration"},
	} {
		cmd := exec.Command("git", args...)
		cmd.Dir = dir
		if out, err := cmd.CombinedOutput(); err != nil {
			t.Fatalf("git %v: %v\n%s", args, err, out)
		}
	}
	return dir
}

const stableCoordinationPhrase = "coordinated with downstream rollouts"

func TestMigrationImmutability_StableCoordination_InRefusal(t *testing.T) {
	dir := immutabilityFixture(t, "v2026.01.0")
	t.Setenv(release.IntentionallyFixBrokenImmutableMigrationEnvVar, "")

	var gateErr error
	out := captureStdout(t, func() {
		gateErr = checkMigrationImmutability(dir, "v2026.01.0", "test")
	})
	if gateErr == nil {
		t.Fatal("expected the immutability gate to refuse a modified released migration")
	}
	if !strings.Contains(out, "STABLE tag") || !strings.Contains(out, stableCoordinationPhrase) {
		t.Fatalf("refusal against a stable predecessor must carry the coordination line "+
			"(STATBUS-205 Fix 2: the operator reads it BEFORE declaring the bless); output:\n%s", out)
	}
	// The coordination line must come BEFORE the declaration paragraph —
	// that ordering is the whole point of Fix 2.
	coordIdx := strings.Index(out, stableCoordinationPhrase)
	declIdx := strings.Index(out, "ONLY if you have inspected")
	if declIdx < 0 {
		t.Fatalf("refusal lost its declaration paragraph; output:\n%s", out)
	}
	if coordIdx > declIdx {
		t.Fatalf("the coordination line prints AFTER the declaration paragraph — it must "+
			"come before, so the operator reads it before declaring; output:\n%s", out)
	}
}

func TestMigrationImmutability_StableCoordination_AbsentForRCPredecessor(t *testing.T) {
	dir := immutabilityFixture(t, "v2026.01.0-rc.01")
	t.Setenv(release.IntentionallyFixBrokenImmutableMigrationEnvVar, "")

	var gateErr error
	out := captureStdout(t, func() {
		gateErr = checkMigrationImmutability(dir, "v2026.01.0-rc.01", "test")
	})
	if gateErr == nil {
		t.Fatal("expected the immutability gate to refuse a modified released migration")
	}
	if strings.Contains(out, stableCoordinationPhrase) {
		t.Fatalf("an RC predecessor is not stable-shipped — the coordination line must not "+
			"print for it; output:\n%s", out)
	}
}

func TestMigrationImmutability_DeclaredPass_NeutralReceiptOnly(t *testing.T) {
	dir := immutabilityFixture(t, "v2026.01.0")
	t.Setenv(release.IntentionallyFixBrokenImmutableMigrationEnvVar, "20260101000000")

	var gateErr error
	out := captureStdout(t, func() {
		gateErr = checkMigrationImmutability(dir, "v2026.01.0", "test")
	})
	if gateErr != nil {
		t.Fatalf("declared bless must pass the gate, got: %v\noutput:\n%s", gateErr, out)
	}
	if !strings.Contains(out, "⟳ Intentionally fixing broken (immutable) migration 20260101000000") {
		t.Fatalf("declared pass lost its neutral ⟳ receipt; output:\n%s", out)
	}
	if strings.Contains(out, "⚠") || strings.Contains(out, stableCoordinationPhrase) {
		t.Fatalf("declared pass must print ONLY the neutral receipt — the coordination "+
			"warning after the declaration hedged a decision already made (STATBUS-205 "+
			"Fix 2); output:\n%s", out)
	}
}

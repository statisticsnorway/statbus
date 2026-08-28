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
}

// TestRecoveryBootParksOnRefusalWithExistingConfig — STATBUS-307. A policy
// refusal (which release CHANNEL to follow) must not decide whether the
// DATABASE comes back: those are different criticalities STATBUS-298's
// single all-or-nothing branch used to conflate. This pins the fork added on
// top of 298's exit-78 path: a box with a PRIOR generated .env (proof it has
// served before) must PARK (marker written, no exit, fall through to
// EnsureDBUp) rather than hard-refuse; only a box with NO prior .env (nothing
// to fall back to) keeps the STATBUS-298 hard refusal.
func TestRecoveryBootParksOnRefusalWithExistingConfig(t *testing.T) {
	src, err := os.ReadFile(thisRepoFile(t, "cli/internal/upgrade/service.go"))
	if err != nil {
		t.Fatalf("read service.go: %v", err)
	}
	run := extractFuncBody(t, string(src), "func (d *Service) Run(")

	refusalIdx := strings.Index(run, "if configGenerateIsPrincipledRefusal(err) {")
	if refusalIdx < 0 {
		t.Fatal("Run() must branch on configGenerateIsPrincipledRefusal(err) — test is stale or STATBUS-298 regressed")
	}

	// The fork must check for a pre-existing generated config BEFORE deciding
	// hard-refuse vs park.
	noEnvIdx := strings.Index(run, `os.Stat(envPath); statErr != nil {`)
	if noEnvIdx < 0 || noEnvIdx < refusalIdx {
		t.Fatal("the refusal branch must check os.Stat(envPath) for a pre-existing generated config, AFTER classifying the refusal — test is stale or the fork is missing")
	}

	// NO-CONFIG (fresh box): exactly one os.Exit(exitPrincipledConfigRefusal)
	// site must remain, and it must be inside the no-env branch — the hard
	// refusal is UNCHANGED for a box with nothing to fall back to.
	exitCount := strings.Count(run, "os.Exit(exitPrincipledConfigRefusal)")
	if exitCount != 1 {
		t.Errorf("expected exactly 1 os.Exit(exitPrincipledConfigRefusal) site (the no-prior-config hard refusal), found %d — STATBUS-307's has-config path must fall through instead of also exiting", exitCount)
	}
	noEnvExitIdx := strings.Index(run, "os.Exit(exitPrincipledConfigRefusal)")
	if noEnvExitIdx < noEnvIdx {
		t.Error("os.Exit(exitPrincipledConfigRefusal) must be INSIDE the os.Stat(envPath) failure branch (the no-prior-config case)")
	}

	// HAS-CONFIG (prior .env exists): must PARK — write is already covered by
	// the marker-write assertion above (shared statement) — and must fall
	// through with NEITHER an exit NOR a return between the park's own log
	// line and the branch's closing `else` (the STATBUS-298 transient-error
	// return, which must stay reachable only for the non-refusal case).
	parkLogIdx := strings.Index(run, "PARKING the upgrade")
	if parkLogIdx < 0 {
		t.Fatal("the has-config path must log that it is PARKING the upgrade (STATBUS-307) — test is stale or the log line changed")
	}
	if parkLogIdx < noEnvExitIdx {
		t.Error("the PARKING log line must come AFTER the no-config hard-refusal branch (has-config is the fallback path, checked second)")
	}
	genericReturnIdx := strings.Index(run, `return fmt.Errorf("pre-flight: regenerate config before db up:`)
	if genericReturnIdx < 0 {
		t.Fatal("Run() must still return the generic pre-flight error for the transient/non-refusal case — test is stale or the fix regressed")
	}
	if genericReturnIdx < parkLogIdx {
		t.Fatal("the generic transient-error return must come AFTER the park log line in source order — test's fall-through window would be inverted")
	}
	fallThroughWindow := run[parkLogIdx:genericReturnIdx]
	if strings.Contains(fallThroughWindow, "os.Exit") {
		t.Error("the has-config PARK path must NOT os.Exit — it must fall through to EnsureDBUp so the database returns (STATBUS-307's whole point)")
	}
	if strings.Contains(fallThroughWindow, "return ") {
		t.Error("the has-config PARK path must NOT return — a return here would skip EnsureDBUp exactly like the old all-or-nothing behavior STATBUS-307 fixes")
	}
}

package upgrade

import (
	"errors"
	"fmt"
	"os/exec"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/migrate"
)

// STATBUS-046 (doc-021/D3) — the crash-resume escalation core is the bound that
// replaces the rune loop-forever. These lock the two terminal triggers (budget
// exhaustion + same-step-twice), the death-count boundary (deaths == attempts-1;
// RecoveryDeathBudget deaths exhaust it, so the resume at attempts==budget+1 is
// terminal), and the safety routing (terminal → park at-target / rollback when
// data-safe). Direction is 039's; this only bounds how-long/how-loud.

func TestResumeEscalation_ContinuesWithinBudgetDifferentSteps(t *testing.T) {
	// Deaths at DIFFERENT steps, under budget → keep trying forward.
	for attempts := 1; attempts <= RecoveryDeathBudget; attempts++ {
		action, reason := resumeEscalation(attempts, StepMigrateUp, StepImagePull, false)
		if action != recoveryContinue {
			t.Errorf("attempts=%d different steps under budget must continue; got %s (%q)", attempts, action, reason)
		}
		if reason != "" {
			t.Errorf("continue must carry no reason; got %q", reason)
		}
	}
}

// The budget boundary: budget 3 DEATHS ⇒ three forward attempts run and die
// (attempts 1,2,3 → deaths 0,1,2), the 4th resume (attempts==4, deaths==3) is
// terminal. The counter is incremented at attempt START, so `attempts` already
// includes the current resume and deaths == attempts-1.
func TestResumeEscalation_BudgetBoundaryAtTarget(t *testing.T) {
	// attempts == budget (deaths == budget-1) → still under the budget → continue.
	if a, _ := resumeEscalation(RecoveryDeathBudget, StepHealthCheck, StepMigrateUp, false); a != recoveryContinue {
		t.Fatalf("attempt %d (deaths %d < budget %d) must still run; got %s", RecoveryDeathBudget, RecoveryDeathBudget-1, RecoveryDeathBudget, a)
	}
	// attempts == budget+1 (deaths == budget) → exhausted → park (at-target).
	a, reason := resumeEscalation(RecoveryDeathBudget+1, StepHealthCheck, StepMigrateUp, false)
	if a != recoveryPark {
		t.Fatalf("budget+1 at-target must PARK; got %s", a)
	}
	if !strings.Contains(reason, "budget exhausted") {
		t.Errorf("park reason must name budget exhaustion; got %q", reason)
	}
}

// Budget exhaustion when a rollback is data-safe (pre-swap / positively-Behind)
// routes to ROLLBACK, not park.
func TestResumeEscalation_BudgetExhaustDataSafeRollsBack(t *testing.T) {
	a, reason := resumeEscalation(RecoveryDeathBudget+1, StepImagePull, StepConfigGenerate, true)
	if a != recoveryRollback {
		t.Fatalf("budget exhausted + data-safe must ROLL BACK; got %s", a)
	}
	if !strings.Contains(reason, "budget exhausted") {
		t.Errorf("rollback reason must name budget exhaustion; got %q", reason)
	}
}

// Same-step-twice is terminal IMMEDIATELY, even with budget remaining.
func TestResumeEscalation_SameStepTwiceParksEarly(t *testing.T) {
	// attempts=2 (well under budget) but died at migrate-up twice in a row.
	a, reason := resumeEscalation(2, StepMigrateUp, StepMigrateUp, false)
	if a != recoveryPark {
		t.Fatalf("same-step-twice at-target must PARK early; got %s", a)
	}
	if !strings.Contains(reason, "same-step-twice") || !strings.Contains(reason, StepMigrateUp) {
		t.Errorf("reason must name the deterministic-hang + the step; got %q", reason)
	}
	// data-safe variant → rollback early.
	if a2, _ := resumeEscalation(2, StepMigrateUp, StepMigrateUp, true); a2 != recoveryRollback {
		t.Errorf("same-step-twice + data-safe must ROLL BACK early; got %s", a2)
	}
}

// An empty dying step (unknown — first attempt, or crash before any step
// recorded) must NOT trigger same-step-twice even if priorDeathStep is also
// empty. Two "unknowns" are not evidence of a deterministic hang.
func TestResumeEscalation_EmptyStepsNeverSameStepTwice(t *testing.T) {
	if a, _ := resumeEscalation(2, "", "", false); a != recoveryContinue {
		t.Errorf("empty dying steps under budget must continue (unknown != same-step); got %s", a)
	}
	// still bounded by the budget though:
	if a, _ := resumeEscalation(RecoveryDeathBudget+1, "", "", false); a != recoveryPark {
		t.Errorf("empty steps still hit the budget → park; got %s", a)
	}
}

// ── slice 2: B/C failure classification ──────────────────────────────────────

// STATBUS-046 slice 2 — the structured classifier. config-generate is the one
// cleanly exit-code-classifiable site now: a non-timeout failure is deterministic
// (B, park on first); a timeout is unknown (budget-bounded, no false park); the
// migrate/docker sites stay unknown until Q5/Q2. classUnknown parks on nothing.
func TestClassifyStepFailure_ConfigGenerateDeterministic(t *testing.T) {
	if got := classifyStepFailure(StepConfigGenerate, errors.New("template render failed")); got != classDeterministic {
		t.Errorf("config-generate non-timeout failure must be B/deterministic; got %s", got)
	}
	if !classDeterministic.parksOnFirst() {
		t.Error("classDeterministic must park on first")
	}
}

func TestClassifyStepFailure_TimeoutIsUnknownNotDeterministic(t *testing.T) {
	// A hung config-generate (ErrCommandTimeout) must NOT park on first — the
	// death budget + same-step-twice bound a repeated hang instead.
	timeoutErr := fmt.Errorf("config-generate hung: %w", ErrCommandTimeout)
	if got := classifyStepFailure(StepConfigGenerate, timeoutErr); got != classUnknown {
		t.Errorf("a config-generate TIMEOUT must be classUnknown (budget-bounded), not B; got %s", got)
	}
	if classUnknown.parksOnFirst() {
		t.Error("classUnknown must NOT park on first")
	}
}

func TestClassifyStepFailure_UnclassifiedSitesAreUnknown(t *testing.T) {
	// Until Q5 (migrate exit-code encoding) and Q2 (docker structured signal),
	// these sites must return classUnknown — NEVER text-matched, NEVER a false B.
	for _, step := range []string{StepMigrateUp, StepImagePull, StepDBUp, StepStartServices, StepHealthCheck, StepReconnect} {
		if got := classifyStepFailure(step, errors.New("some failure")); got != classUnknown {
			t.Errorf("step %s must be classUnknown pending Q2/Q5; got %s", step, got)
		}
	}
}

func TestClassifyStepFailure_NilErr(t *testing.T) {
	if got := classifyStepFailure(StepConfigGenerate, nil); got != classUnknown {
		t.Errorf("nil error must be classUnknown; got %s", got)
	}
}

// STATBUS-046 slice 2 (Q5) — the migrate exit-code contract, read STRUCTURALLY.
// A real subprocess produces a genuine *exec.ExitError so exitCodeOf + the
// StepMigrateUp mapping are exercised end-to-end (not a hand-built fake).
func migrateExitErr(t *testing.T, code int) error {
	t.Helper()
	err := exec.Command("sh", "-c", fmt.Sprintf("exit %d", code)).Run()
	if err == nil {
		t.Fatalf("sh -c 'exit %d' unexpectedly succeeded", code)
	}
	return err
}

func TestClassifyStepFailure_MigrateExitCodeContract(t *testing.T) {
	if got := classifyStepFailure(StepMigrateUp, migrateExitErr(t, migrate.ExitDeterministic)); got != classDeterministic {
		t.Errorf("migrate exit %d must be B/deterministic; got %s", migrate.ExitDeterministic, got)
	}
	if got := classifyStepFailure(StepMigrateUp, migrateExitErr(t, migrate.ExitResource)); got != classResource {
		t.Errorf("migrate exit %d must be C/resource; got %s", migrate.ExitResource, got)
	}
	// Unclassified (1) and any other exit → unknown → A (budget-bounded).
	if got := classifyStepFailure(StepMigrateUp, migrateExitErr(t, migrate.ExitUnclassified)); got != classUnknown {
		t.Errorf("migrate exit %d (unclassified) must be classUnknown; got %s", migrate.ExitUnclassified, got)
	}
	if got := classifyStepFailure(StepMigrateUp, migrateExitErr(t, 5)); got != classUnknown {
		t.Errorf("an unmapped migrate exit (5) must be classUnknown; got %s", got)
	}
	// A non-exit error (no structured signal) → unknown.
	if got := classifyStepFailure(StepMigrateUp, errors.New("plain error")); got != classUnknown {
		t.Errorf("a non-exit migrate error must be classUnknown; got %s", got)
	}
}

// STATBUS-046 slice 2 (Q2) — docker marker classification. Only the kernel-stable
// ENOSPC marker promotes (to C); the manifest-404 case is unknown→A (the daemon
// rewraps the OCI string to generic "not found" prose — a live-sample finding).
// Conjunctive (exit + marker), positive-exact-match only; miss / non-exit → A.
func TestClassifyDockerFailure_Markers(t *testing.T) {
	exit := migrateExitErr(t, 1) // docker/compose exits 1 for all these alike

	// disk full → C (verbatim strerror(ENOSPC), kernel-authored, survives rewrap).
	enospc := "failed to register layer: write /var/lib/docker/tmp/x: no space left on device"
	if got := classifyDockerFailure(exit, enospc); got != classResource {
		t.Errorf("ENOSPC stderr + non-zero exit must be C; got %s", got)
	}
	// manifest-404 as the DAEMON actually rewraps it → NOT promoted → unknown → A.
	// (Q1 still parks a persistent 404 in 2 deaths via same-step-twice.)
	daemon404 := `failed to resolve reference "ghcr.io/x/statbus-db:abc123": ghcr.io/x/statbus-db:abc123: not found`
	if got := classifyDockerFailure(exit, daemon404); got != classUnknown {
		t.Errorf("daemon-rewrapped 404 (\"not found\") must be classUnknown→A, not promoted; got %s", got)
	}
	// unrelated docker failure → unknown → A (bounded leniency, never a wrong park).
	if got := classifyDockerFailure(exit, "Error response from daemon: network timeout"); got != classUnknown {
		t.Errorf("an unmatched docker failure must be classUnknown; got %s", got)
	}
	// CONJUNCTIVE: the ENOSPC text WITHOUT a process-exit error must NOT classify.
	if got := classifyDockerFailure(errors.New("timeout: no space left on device"), "no space left on device"); got != classUnknown {
		t.Errorf("marker without a non-zero process exit must be classUnknown (conjunctive); got %s", got)
	}
	// empty stderr → unknown.
	if got := classifyDockerFailure(exit, ""); got != classUnknown {
		t.Errorf("empty stderr must be classUnknown; got %s", got)
	}
}

// STATBUS-046 slice 2 — the bounded stderr capture (docker ENOSPC backstop) must
// keep the TAIL (where kernel error markers appear) and never grow unbounded.
func TestTailBuffer_KeepsBoundedTail(t *testing.T) {
	tb := &tailBuffer{max: 16}
	tb.Write([]byte("0123456789"))
	tb.Write([]byte("abcdef: no space left on device"))
	got := tb.String()
	if len(got) > 16 {
		t.Fatalf("tailBuffer exceeded its cap: %d bytes (%q)", len(got), got)
	}
	// The tail (the end, where ENOSPC lands) must be preserved for the classifier.
	if !strings.HasSuffix("abcdef: no space left on device", got) {
		t.Errorf("tailBuffer must keep the TAIL; got %q", got)
	}
	// And that tail must still let the classifier see the marker when it's within cap.
	tb2 := &tailBuffer{max: 4096}
	tb2.Write([]byte("failed to register layer: write /x: no space left on device"))
	if !strings.Contains(tb2.String(), kernelMarkerENOSPC) {
		t.Errorf("a within-cap ENOSPC line must survive capture; got %q", tb2.String())
	}
}

// STATBUS-046 slice 1B — the rollback regime uses the SIBLING rollbackResumeIsTerminal
// (NOT resumeEscalation, whose exhaust term must not fire for a rollback). Terminal
// IFF the last TWO deaths were BOTH mid-rollback: step==StepRollback AND
// priorStep==StepRollback. It takes TWO consecutive rollback deaths — a single
// transient reboot/OOM mid-restore must re-run, never insta-fail (3 fwd + 2 rb).
func TestRollbackResumeIsTerminal(t *testing.T) {
	// Handoff / first rollback resume: the JUST-crashed death was a FORWARD step,
	// prior is anything → NOT terminal (the rollback gets its designed attempt).
	for _, forward := range []string{StepMigrateUp, StepHealthCheck, StepImagePull, StepConfigGenerate, ""} {
		if rollbackResumeIsTerminal(forward, StepRollback) {
			t.Errorf("first rollback resume (just-crashed death forward=%q) must NOT terminal", forward)
		}
	}
	// DEATH 1 mid-rollback: step==StepRollback but prior is the FORWARD step
	// (rolled from the handoff) → NOT terminal (the free re-run — the off-by-one
	// this fix closes: the box must NOT fail on a single mid-rollback crash).
	if rollbackResumeIsTerminal(StepRollback, StepMigrateUp) {
		t.Error("ONE mid-rollback death (prior still forward) must NOT terminal — the rollback re-runs")
	}
	// DEATH 2 mid-rollback: BOTH step and prior are StepRollback → terminal.
	if !rollbackResumeIsTerminal(StepRollback, StepRollback) {
		t.Error("two consecutive mid-rollback deaths (both StepRollback) must terminal → restore-broke")
	}
}

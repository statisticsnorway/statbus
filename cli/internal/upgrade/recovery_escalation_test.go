package upgrade

import (
	"strings"
	"testing"
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

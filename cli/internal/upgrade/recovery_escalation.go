package upgrade

import "fmt"

// STATBUS-046 (doc-021, King ruling D3) — the crash-resume escalation core: the
// bound that replaces the rune loop-forever (10,229 restarts). systemd
// StartLimit cannot bound a ~160s/cycle crash loop; the real bound is an
// UPGRADE-ATTEMPT budget owned by recovery. This file holds the PURE decision
// (no I/O) + the stable step names; service.go wires the persisted state (the
// recovery_attempts row column + the flag's dying-step field) around it.

// RecoveryDeathBudget bounds how many PROCESS DEATHS a single flag-owned upgrade
// may accrue before recovery stops trying forward (D3's unit is DEATHS, not
// attempts — named that way so nobody later "fixes" the off-by-one that isn't
// one). recovery_attempts is incremented at attempt START, so a dead process
// self-counts with no post-hoc bookkeeping; the number of deaths observed at any
// resume is `attempts - 1` (the first attempt had no preceding death). Budget 3
// deaths ⇒ the 4th resume (attempts==4, deaths==3) is terminal, so exactly three
// forward attempts run and die before park. Class-A in-place waits never consume
// it. Tunable at build/arc (doc-021 §Ratification ask 2).
const RecoveryDeathBudget = 3

// Phase-3 (post-swap forward) step identifiers, recorded on the flag as each
// step BEGINS so a crash freezes the dying step. Two consecutive deaths at the
// SAME step = deterministic-hang evidence → terminal immediately, independent of
// remaining budget (doc-021 D3). These are STABLE machine identifiers (never
// English prose) so the same-step comparison is exact — the doc-022 lesson that
// classification must not ride error text. Mapped to the applyPostSwap steps
// (doc-021 §Step-list 3.1–3.7 + the Phase-4 completion writes).
const (
	StepConfigGenerate = "config-generate" // 3.1
	StepImagePull      = "image-pull"      // 3.2
	StepDBUp           = "db-up"           // 3.3
	StepReconnect      = "reconnect"       // 3.4
	StepMigrateUp      = "migrate-up"      // 3.5
	StepStartServices  = "start-services"  // 3.6
	StepHealthCheck    = "health-check"    // 3.7
	StepMaintenanceOff = "maintenance-off" // 4.1
	StepComplete       = "complete"        // 4.2–4.3 terminal write + flag removal
)

// recoveryAction is what a crash-resume must do BEFORE re-running the forward
// pipeline.
type recoveryAction int

const (
	recoveryContinue recoveryAction = iota // proceed with this forward attempt
	recoveryPark                           // at-target: stop + park (siren once, alive-idle)
	recoveryRollback                       // data-safe: roll back to this upgrade's snapshot
)

func (a recoveryAction) String() string {
	switch a {
	case recoveryContinue:
		return "continue"
	case recoveryPark:
		return "park"
	case recoveryRollback:
		return "rollback"
	default:
		return fmt.Sprintf("recoveryAction(%d)", int(a))
	}
}

// resumeEscalation is the PURE escalation decision (no I/O), evaluated on a
// crash-resume BEFORE the forward pipeline re-runs. Inputs:
//   - attempts: recovery_attempts AFTER the attempt-START increment, so it
//     already includes this resume (each just-crashed attempt self-counted).
//   - deathStep: the step the just-crashed attempt was executing (frozen on the
//     flag); "" when unknown (the very first attempt, or a crash before any
//     step was recorded).
//   - priorDeathStep: the deathStep recorded at the PREVIOUS resume.
//   - canRollBack: ground truth (STATBUS-039) says a rollback is data-safe
//     (pre-swap, or positively-Behind). Direction is NEVER decided here — this
//     only routes a TERMINAL outcome to its safe terminal. Forward-vs-back is
//     039's call; 046 governs only how-long / how-loud forward is tried.
//
// Rules (doc-021 / D3):
//   - same-step-twice (deathStep non-empty AND == priorDeathStep) → terminal
//     now (deterministic-hang evidence), even with budget remaining.
//   - deaths (== attempts-1) >= RecoveryDeathBudget → terminal (budget exhausted).
//   - otherwise → continue.
//
// A terminal outcome routes by canRollBack: true → rollback (data-safe), false
// → park (at-target — can't roll back; the loop-forever regime this ticket
// kills). The park/rollback split is the ONLY place phase matters, and it is a
// safety routing, never a direction decision.
func resumeEscalation(attempts int, deathStep, priorDeathStep string, canRollBack bool) (action recoveryAction, reason string) {
	// deaths observed at this resume: the counter increments at attempt START, so
	// the current attempt hasn't itself died yet — the first attempt (attempts==1)
	// follows zero deaths. 3 deaths (attempts==4) exhausts the budget.
	deaths := attempts - 1
	sameStepTwice := deathStep != "" && deathStep == priorDeathStep
	exhausted := deaths >= RecoveryDeathBudget
	if !sameStepTwice && !exhausted {
		return recoveryContinue, ""
	}
	if sameStepTwice {
		reason = fmt.Sprintf("two consecutive crash-deaths at step %q — deterministic hang (same-step-twice)", deathStep)
	} else {
		reason = fmt.Sprintf("crash-resume budget exhausted: %d process deaths >= budget %d (attempt %d, last death at step %q)",
			deaths, RecoveryDeathBudget, attempts, stepOrUnknown(deathStep))
	}
	if canRollBack {
		return recoveryRollback, reason
	}
	return recoveryPark, reason
}

func stepOrUnknown(s string) string {
	if s == "" {
		return "unknown"
	}
	return s
}

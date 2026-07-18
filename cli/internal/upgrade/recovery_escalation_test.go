package upgrade

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/migrate"
)

// STATBUS-046 (doc-021/D3) — the crash-resume escalation core is the bound that
// replaces the rune loop-forever. These lock the two terminal triggers (budget
// exhaustion + same-step-twice), the death-count boundary (deaths == attempts-1;
// RecoveryDeathBudget deaths exhaust it, so the resume at attempts==budget+1 is
// terminal), and the safety routing (terminal → park already-at-new / rollback when
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
	// attempts == budget+1 (deaths == budget) → exhausted → park (already-at-new).
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

// STATBUS-044 comment #6 — StepBootMigrate is the resume-time schema catch-up
// (Run + install ladder), now counted by RecoveryBudgetGuard at the START of the
// pass so a death IN the boot migrate self-counts. The pure core is step-agnostic:
// same-step-twice must fire for StepBootMigrate exactly as for any Phase-3 step.
// This locks the fabricated boot-migrate scenario's arithmetic at the value level:
// two consecutive boot-migrate deaths (attempts==3, deaths==2) → park early.
func TestResumeEscalation_BootMigrateSameStepTwice(t *testing.T) {
	// The fabricated scenario: kill #1 and kill #2 both land in boot-migrate.
	//   boot1 attempts=1 death="" continue → stamp boot-migrate → KILL
	//   boot2 attempts=2 death=boot-migrate prior="" → continue → KILL
	//   boot3 attempts=3 death=boot-migrate prior=boot-migrate → same-step-twice → PARK
	if a, _ := resumeEscalation(2, StepBootMigrate, "", false); a != recoveryContinue {
		t.Fatalf("boot2: one boot-migrate death (prior empty) under budget must continue; got %s", a)
	}
	a, reason := resumeEscalation(3, StepBootMigrate, StepBootMigrate, false)
	if a != recoveryPark {
		t.Fatalf("boot3: two consecutive boot-migrate deaths must PARK early (same-step-twice); got %s", a)
	}
	if !strings.Contains(reason, "same-step-twice") || !strings.Contains(reason, StepBootMigrate) {
		t.Errorf("park reason must name same-step-twice + the boot-migrate step; got %q", reason)
	}
	// A boot-migrate death followed by a DIFFERENT step (boot migrate then succeeds,
	// dies later at a Phase-3 step) must NOT same-step-twice.
	if a, _ := resumeEscalation(2, StepStartServices, StepBootMigrate, false); a != recoveryContinue {
		t.Errorf("boot-migrate then a different-step death under budget must continue; got %s", a)
	}
}

// StepBootMigrate is a STABLE machine identifier, distinct from the applyNewSbUpgrading
// StepMigrateUp (3.5) — the two migrate windows must never collapse to one string,
// or a boot-migrate death and a (near-impossible) step-3.5 death would falsely read
// as same-step-twice across the two.
func TestStepBootMigrateIdentifier(t *testing.T) {
	if StepBootMigrate != "boot-migrate" {
		t.Errorf("StepBootMigrate must be the stable %q identifier; got %q", "boot-migrate", StepBootMigrate)
	}
	if StepBootMigrate == StepMigrateUp {
		t.Errorf("StepBootMigrate (%q) must be distinct from StepMigrateUp (%q)", StepBootMigrate, StepMigrateUp)
	}
}

// STATBUS-044 comment #6 part 3 — countRecoveryAttemptOnce counts EXACTLY ONCE per
// process lifetime. Once RecoveryBudgetGuard has counted (recoveryPassCounted), a
// later downstream caller (resumeNewSb / recoveryRollback) must reuse the stored
// value WITHOUT touching the DB — the load-bearing "don't double-count the same
// pass" short-circuit. A nil queryConn proves the DB is never dereferenced on this
// path.
func TestCountRecoveryAttemptOnce_ShortCircuitsWhenCounted(t *testing.T) {
	d := &Service{recoveryPassCounted: true, recoveryPassAttempts: 7} // nil queryConn on purpose
	n, err := d.countRecoveryAttemptOnce(context.Background(), 42)
	if err != nil {
		t.Fatalf("counted short-circuit must not error (must not touch the DB); got %v", err)
	}
	if n != 7 {
		t.Errorf("counted short-circuit must reuse the stored attempts (7); got %d", n)
	}
}

// STATBUS-044 comment #6 (architect F1) — a PARKED row must never be automatically
// rolled back. recoveryRollback is the single chokepoint every auto-restore route
// funnels through (positively-Behind, both Unknown-exhaust arms, the flagless
// completeInProgressUpgrade path), so the parked-skip lives there — and MUST precede
// the budget increment + the terminal check, or a row RecoveryBudgetGuard just
// parked (its boot migrate skipped → schema possibly Behind) would be auto-restored.
// Source-order guard (recoveryRollback needs a live DB + flock to exercise
// behaviorally; the ordering is the invariant that matters).
func TestRecoveryRollback_ParkedSkipPrecedesRestore(t *testing.T) {
	src, err := os.ReadFile(thisRepoFile(t, "cli/internal/upgrade/service.go"))
	if err != nil {
		t.Fatalf("read service.go: %v", err)
	}
	body := extractFuncBody(t, string(src), "func (d *Service) recoveryRollback(")
	parkedIdx := strings.Index(body, "d.upgradeParkedReason(ctx, id)")
	incrementIdx := strings.Index(body, "d.countRecoveryAttemptOnce(ctx, id)")
	terminalIdx := strings.Index(body, "rollbackResumeIsTerminal(")
	for name, idx := range map[string]int{
		"d.upgradeParkedReason(ctx, id)":      parkedIdx,
		"d.countRecoveryAttemptOnce(ctx, id)": incrementIdx,
		"rollbackResumeIsTerminal(":           terminalIdx,
	} {
		if idx < 0 {
			t.Fatalf("recoveryRollback missing %s — test is stale (F1 parked-skip removed or renamed?)", name)
		}
	}
	if parkedIdx > incrementIdx || parkedIdx > terminalIdx {
		t.Errorf("F1: the parked-skip (upgradeParkedReason, idx=%d) must PRECEDE the rollback budget increment (idx=%d) and the terminal check (idx=%d) — a parked row must never be auto-rolled-back.",
			parkedIdx, incrementIdx, terminalIdx)
	}
}

// STATBUS-134 — the (rollback, rollback) terminal pair must FORM across
// guard-interleaved passes. RecoveryBudgetGuard runs before recoverFromFlag routes
// to recoveryRollback; pre-134 it stamped Step=boot-migrate on EVERY boot, so
// recordRollbackCommit could never leave two consecutive StepRollback marks on disk
// → rollbackResumeIsTerminal (the 1B restore-broke terminal at TWO rollback deaths)
// was structurally unreachable, and a broken rollback crash-looped to the WRONG
// budget park at attempts==4. The fix: when the frozen step is a rollback death, the
// guard DEFERS (no stamp). This simulation models the two real flag-mutating ops
// (the guard's conditional stamp + recordRollbackCommit) and drives them through the
// REAL rollbackResumeIsTerminal to prove the pair forms at exactly 2 deaths WITH the
// fix, and never forms WITHOUT it.
func TestRollbackPairForms_AcrossGuardInterleavedPasses(t *testing.T) {
	// mirrors RecoveryBudgetGuard's stamp step: defer (no mutation) on a rollback
	// death when the fix is present; otherwise roll PriorDeathStep←Step, Step←boot-migrate.
	guardStamp := func(step, prior string, fix bool) (string, string) {
		if fix && step == StepRollback {
			return step, prior // STATBUS-134 defer — preserve the rollback history
		}
		return StepBootMigrate, step // Step←boot-migrate, Prior←old Step
	}
	// mirrors recordRollbackCommit (service.go): PriorDeathStep←Step, Step←rollback.
	rollbackCommit := func(step string) (string, string) {
		return StepRollback, step // Step←rollback, Prior←old Step
	}
	// Drive the rollback regime from the state right after the FIRST mid-rollback
	// death (recordRollbackCommit ran once on the forward→rollback handoff): frozen
	// flag is (Step=rollback, Prior=boot-migrate). Each pass: guard stamps, then
	// recoveryRollback checks the terminal on the guard-mutated flag; if not terminal
	// it commits + the rollback dies again.
	simulate := func(fix bool) int { // returns the death count at which restore-broke fires, or 0 if never
		step, prior := StepRollback, StepBootMigrate
		deaths := 1 // death #1 already happened
		for pass := 0; pass < 8; pass++ {
			step, prior = guardStamp(step, prior, fix)
			if rollbackResumeIsTerminal(step, prior) {
				return deaths
			}
			step, prior = rollbackCommit(step) // commit → rollback runs → dies again
			deaths++
		}
		return 0 // never terminal within the window
	}
	if got := simulate(true); got != 2 {
		t.Errorf("WITH the STATBUS-134 defer, restore-broke must fire at 2 consecutive rollback deaths; fired at %d", got)
	}
	if got := simulate(false); got != 0 {
		t.Errorf("WITHOUT the defer (pre-134 bug), the (rollback,rollback) pair must NEVER form (guard re-stamps boot-migrate every boot) → restore-broke unreachable; but it fired at %d", got)
	}
}

// STATBUS-134 — structural guard: RecoveryBudgetGuard must DEFER (no consult, no
// stamp) when the frozen step is a rollback death. Pins the wiring: the
// `flag.Step == StepRollback` early return precedes BOTH the resumeEscalation consult
// and the StepBootMigrate stamp.
func TestRecoveryBudgetGuard_DefersOnRollbackStep(t *testing.T) {
	src, err := os.ReadFile(thisRepoFile(t, "cli/internal/upgrade/service.go"))
	if err != nil {
		t.Fatalf("read service.go: %v", err)
	}
	body := extractFuncBody(t, string(src), "func (d *Service) RecoveryBudgetGuard(")
	deferIdx := strings.Index(body, "flag.Step == StepRollback")
	consultIdx := strings.Index(body, "resumeEscalation(attempts, flag.Step, flag.PriorDeathStep, false)")
	stampIdx := strings.Index(body, "f.Step = StepBootMigrate")
	for name, idx := range map[string]int{
		"flag.Step == StepRollback (rollback-defer)": deferIdx,
		"resumeEscalation(...) consult":              consultIdx,
		"f.Step = StepBootMigrate stamp":             stampIdx,
	} {
		if idx < 0 {
			t.Fatalf("RecoveryBudgetGuard missing %s — test is stale (STATBUS-134 defer removed?)", name)
		}
	}
	if deferIdx > consultIdx || deferIdx > stampIdx {
		t.Errorf("STATBUS-134: the rollback-defer (flag.Step==StepRollback, idx=%d) must PRECEDE the consult (idx=%d) and the boot-migrate stamp (idx=%d) — else a rollback pass is consulted/stamped and the (rollback,rollback) pair can't form.",
			deferIdx, consultIdx, stampIdx)
	}
}

// STATBUS-135 — completeInProgressUpgrade (the flagless-row reconciliation belt)
// must PARKED-SKIP before it arms the flag-cleanup defer, or the defer strips the flag
// from a parked row (parked rows are state='in_progress', so the routine's SELECT
// matches them) → next boot is flag-blind → RecoveryBudgetGuard no-op → ungated
// boot-migrate boot-loop; and a parked already-at-new row could be mis-marked
// 'completed'. The load-bearing invariant is the ORDER: the parked-skip must precede
// the defer (its `return` fires before the defer arms). Source-order guard —
// completeInProgressUpgrade needs a live DB to exercise behaviorally.
//
// STATBUS-192: the flag-cleanup defer is now GUARDED (`defer func(){ if !parkedExit
// { d.removeUpgradeFlag() } }()`), so the serve-proof start/health-fail PARK path can
// materialize + KEEP a faithful flag (`./sb install` un-park). This test anchors on
// that guard and still asserts the parked-skip precedes it.
func TestCompleteInProgressUpgrade_ParkedSkipPrecedesFlagStrip(t *testing.T) {
	src, err := os.ReadFile(thisRepoFile(t, "cli/internal/upgrade/service.go"))
	if err != nil {
		t.Fatalf("read service.go: %v", err)
	}
	body := extractFuncBody(t, string(src), "func (d *Service) completeInProgressUpgrade(")
	parkedIdx := strings.Index(body, "d.upgradeParkedReason(ctx, id)")
	// The guarded flag-cleanup defer (STATBUS-192): `if !parkedExit {` is its unique,
	// stable anchor — the conditional strip that replaced the bare defer.
	deferIdx := strings.Index(body, "if !parkedExit {")
	for name, idx := range map[string]int{
		"d.upgradeParkedReason(ctx, id)":                             parkedIdx,
		"if !parkedExit { (guarded flag-cleanup defer, STATBUS-192)": deferIdx,
	} {
		if idx < 0 {
			t.Fatalf("completeInProgressUpgrade missing %s — test is stale (STATBUS-135 parked-skip / STATBUS-192 guarded defer removed?)", name)
		}
	}
	if parkedIdx > deferIdx {
		t.Errorf("STATBUS-135: the parked-skip (upgradeParkedReason, idx=%d) must PRECEDE the guarded flag-cleanup defer (if !parkedExit, idx=%d) — otherwise the defer strips a parked row's flag on the skip's return.",
			parkedIdx, deferIdx)
	}
}

// STATBUS-044 comment #6 (architect F2) — a deliberate ./sb install un-park must
// grant ONE genuinely-fresh attempt. UnparkByID resets the ROW's recovery_attempts,
// but the flag's frozen Step + PriorDeathStep survive on disk; ClearFlagStepHistory
// zeroes them so the next escalation consult does not same-step-twice INSTA-RE-PARK
// at attempts==1. Behavioral filesystem test (no DB needed).
func TestClearFlagStepHistory_ClearsDeathHistoryPreservesRest(t *testing.T) {
	dir := t.TempDir()
	seed := UpgradeFlag{
		ID: 7, CommitSHA: "abc123", Holder: HolderService, Phase: PhaseNewSbUpgrading,
		Step: StepBootMigrate, PriorDeathStep: StepBootMigrate,
	}
	lock, err := acquireFlock(dir, seed)
	if err != nil {
		t.Fatalf("seed flag: %v", err)
	}
	lock.Close()

	d := &Service{projDir: dir}
	if err := d.ClearFlagStepHistory(); err != nil {
		t.Fatalf("ClearFlagStepHistory: %v", err)
	}
	got, err := ReadFlagFile(dir)
	if err != nil || got == nil {
		t.Fatalf("read flag after clear: got=%v err=%v", got, err)
	}
	if got.Step != "" || got.PriorDeathStep != "" {
		t.Errorf("death history not cleared: Step=%q PriorDeathStep=%q (both must be empty so a fresh attempt has no prior death)", got.Step, got.PriorDeathStep)
	}
	// Everything else must be preserved (identity, phase, holder).
	if got.ID != 7 || got.CommitSHA != "abc123" || got.Holder != HolderService || got.Phase != PhaseNewSbUpgrading {
		t.Errorf("ClearFlagStepHistory must preserve non-step fields; got %+v", *got)
	}

	// No flag file → no-op, no error.
	empty := &Service{projDir: t.TempDir()}
	if err := empty.ClearFlagStepHistory(); err != nil {
		t.Errorf("ClearFlagStepHistory with no flag file must be a no-op; got %v", err)
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
	_, _ = tb.Write([]byte("0123456789"))
	_, _ = tb.Write([]byte("abcdef: no space left on device"))
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
	_, _ = tb2.Write([]byte("failed to register layer: write /x: no space left on device"))
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

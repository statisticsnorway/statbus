---
id: STATBUS-134
title: >-
  rollback-pair-terminal-dead: RecoveryBudgetGuard's stamp interleave makes the
  2-death rollback terminal structurally unreachable
status: Done
assignee: []
created_date: '2026-07-04 22:30'
updated_date: '2026-07-07 04:01'
labels:
  - upgrade
  - install-recovery
  - product
dependencies: []
references:
  - cli/internal/upgrade/service.go
  - cli/internal/upgrade/recovery_escalation.go
  - STATBUS-044
  - STATBUS-046
priority: high
ordinal: 135000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
FOUND live in r17 (park-oracle campaign, 2026-07-05): three consecutive deaths mid-rollback never fired rollbackResumeIsTerminal (the STATBUS-046 1B restore-broke terminal, designed to human-stop after TWO consecutive rollback deaths); instead the shared budget parked at attempts==4. Architect-verified root cause: on every boot with a service-held forward flag, RecoveryBudgetGuard rolls PriorDeathStep←Step and stamps Step←'boot-migrate' BEFORE recoverFromFlag routes to recoveryRollback, which then re-stamps Step←'rollback' (Prior←'boot-migrate') via recordRollbackCommit. So the on-disk pair (Step=='rollback' AND PriorDeathStep=='rollback') can never form — the exact stamp-interference class refinement A fixed on the forward side, now on the rollback side. Consequence: a broken rollback crash-loops to the BUDGET park (reason 'budget exhausted… last death at step "rollback"') instead of the designed restore-broke state='failed' human stop — a softer, wrong signal for a box whose restore cannot complete, and it invites futile un-park→rollback→re-park cycles.

FIX SHAPE (architect): in RecoveryBudgetGuard, when the frozen flag.Step == StepRollback (the previous death was mid-rollback), DEFER to the rollback regime: still count the pass (countRecoveryAttemptOnce — 1B's shared never-reset counter), but skip the resumeEscalation consult (1B pin: budget exhaust must never terminal a rollback) AND skip the roll+stamp (preserve the rollback step history). Then death 1: recordRollbackCommit writes (Prior←rollback? no — Prior←current Step, Step←rollback) → after two consecutive mid-rollback deaths the pair (rollback, rollback) forms on disk and rollbackResumeIsTerminal fires at the designed 2 deaths. Accepted nuance (document): a death during BOOT-MIGRATE on a rollback-regime pass reads as a rollback death (Step stays 'rollback' unstamped) — conservative, fires restore-broke slightly early, honest for a pass whose purpose was rollback recovery. Verification: unit test at the escalation level (pair forms across guard-interleaved passes) + the accidental r17 shape (clean-deterministic boot-migrate failure → Behind → rollback crash loop) is the natural VM scenario once this lands — see the r17 journal (tmp/vm-run-park-scenario r17 logs).
<!-- SECTION:DESCRIPTION:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-07-06 07:40
---
CLOSED: shipped 28aa1e920, architect-approved with all three review points verified. The dedicated pair-terminal VM scenario is deliberately NOT this ticket's scope — it needs STATBUS-136 first (the terminal write must survive the abort path before a scenario can assert it).
---

author: foreman
created: 2026-07-07 04:01
---
RUN-PROVEN (2026-07-07, rollback-pair-terminal arc, CI run 28839994287 on b0df2af0d): the pair-terminal bound observed live on a real VM — two consecutive in-process deaths inside the rollback (recordRollbackCommit stamp verified present at each death via the arc's flag reads) drove the restore-broke terminal at EXACTLY 2, never a third rollback attempt. The RecoveryBudgetGuard rollback deferral + pair-terminal semantics this ticket shipped are now oracle-backed, not just unit-tested. Arc lineage: first real run (28838952364) validated the construction but was blinded by a compact-JSON-only flag reader; fixed b0df2af0d; green on the re-run.
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
NORTH STAR: a broken database restore must summon a human after exactly 2 crash deaths — not offer the operator a doomed "fresh attempt". SHIPPED 28aa1e920 (2026-07-04): RecoveryBudgetGuard now defers to the rollback regime when the frozen flag step is rollback (counts the death, skips its own consult and stamp), so two consecutive mid-rollback deaths again form the (rollback, rollback) pair and the restore-broke terminal fires at the designed 2. Found via r17 live evidence (3 rollback deaths never terminaled; the budget-park that fired instead violated the 1B pin). Dual-reviewed; simulation test proves the pair forms WITH the deferral and never forms without it. REMAINING ELSEWHERE: this fix's own VM oracle (the r17 crash-loop shape as a scenario) is future work, sequenced after STATBUS-136 — tracked there, not here.
<!-- SECTION:FINAL_SUMMARY:END -->

---
id: STATBUS-134
title: >-
  rollback-pair-terminal-dead: RecoveryBudgetGuard's stamp interleave makes the
  2-death rollback terminal structurally unreachable
status: To Do
assignee: []
created_date: '2026-07-04 22:30'
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

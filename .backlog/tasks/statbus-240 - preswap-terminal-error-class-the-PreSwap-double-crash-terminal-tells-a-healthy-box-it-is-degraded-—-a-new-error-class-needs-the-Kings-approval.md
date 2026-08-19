---
id: STATBUS-240
title: >-
  preswap-terminal-error-class: the PreSwap double-crash terminal tells a
  healthy box it is degraded — a new error class needs the King's approval
status: To Do
assignee: []
created_date: '2026-08-19 00:15'
labels:
  - upgrade-recovery
  - operator-ux
dependencies: []
references:
  - cli/internal/upgrade/service.go
priority: high
type: bug
ordinal: 233000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
An operator whose upgrade died twice before the swap is told their system is degraded and to contact support — about a database the product's own log says was never modified, when running ./sb install (their one tool) is what actually resolves it. The behaviour is right; the label lies, and for a statistical office that converts a self-serviceable state into a support ticket measured in days.

WHAT THE EVIDENCE SHOWS (engineer, rc.05 arc run 32187511838, ruled at STATBUS-228 comments #13-15): service.go:2966-2968 hard-codes error class ROLLBACK_FAILED_DB_RESTORE for the same-step-twice rollback terminal on BOTH routes. On the post-swap route the label is CORRECT (a restore genuinely failed). On the PreSwap route it lies three times: no restore was ever attempted (nothing to restore — the volume was never touched), "the system is in a degraded state" (the same log shows ./sb install completing and the box healthy), and "contact SSB support and involve your IT staff" (the operator can self-serve).

WHY THIS NEEDS THE KING: no existing error class fits. The engineer walked all fifteen (service.go:1946-1980): ErrRollbackDBRestore names a restore that did not happen; ErrResumeDied is post-swap by definition; GitCorrupt/ServicesUp/ServicesNotStopped/BinaryCorrupt each name a sub-step that never ran; ErrInstallPreconditionFailed is already used for the per-attempt reason lines. A NEW operator-facing error class is a change to the operator surface — the King reviews its name and message text before it ships (architect's ruling: one more cycle of a wrong-but-loud message beats an unreviewed 2am invention).

THE SHAPE OF THE FIX once approved: the :2966 terminal branches on whether the route is PreSwap (nothing moved) vs post-swap (restore failed); the PreSwap arm gets the new class with a message that says the truth — the upgrade never changed anything, the previous version is being restored to service, run ./sb install to retry or wait for the service's next attempt.

WHAT IS ACHIEVED: the African-NSO operator frame holds — the error text an unattended box shows is true, names the self-service remedy, and never sends a healthy system to support.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The King approves the new error class name and its operator-facing message text before implementation
- [ ] #2 The :2966 terminal distinguishes the PreSwap route (nothing moved) from the post-swap route (restore failed); the post-swap label is unchanged
- [ ] #3 The corrected arcs' assertions observe the new class on the PreSwap route at a suite run
<!-- AC:END -->

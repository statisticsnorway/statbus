---
id: STATBUS-135
title: >-
  parked-contract-holes: completeInProgressUpgrade has no parked awareness —
  unconditional defer strips the flag, can mis-complete a parked row
status: Done
assignee: []
created_date: '2026-07-04 22:31'
updated_date: '2026-07-06 07:41'
labels:
  - upgrade
  - install-recovery
  - product
  - silent-loss
dependencies: []
references:
  - cli/internal/upgrade/service.go
  - STATBUS-044
  - STATBUS-046
priority: high
ordinal: 136000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
FOUND live in r17 (2026-07-05, architect-traced to the line): after RecoveryBudgetGuard parked the row (attempt 4) and F1's parked-skip in recoveryRollback correctly refused the auto-rollback, Run proceeded to completeInProgressUpgrade — which SELECTs any in_progress row (parked rows are in_progress by design) and immediately arms `defer d.removeUpgradeFlag()` (service.go:2651) covering EVERY exit path. The parked row's refusal path returned → the defer STRIPPED THE FLAG while the row stayed parked. Three legs of the same gap (the function predates the park concept and has zero parked awareness):
1. FLAG LOSS (observed in r17): violates 'parked rows keep their flag'. Next restart boots with NO flag → RecoveryBudgetGuard is a no-op → boot-migrate runs UNGATED (re-runs the killer migration for that class) and on clean failure hits the no-flag markTerminal(BOOT_MIGRATE_UP_FAILED) refuse → latent boot-loop. r17's box is alive-idle only because no restart has happened since the strip.
2. WRONG COMPLETED (latent): for a parked AT-TARGET row (the applyPostSwap-step-death park class), waitForDBHealth + the binary+migrations ground truth can both pass while app containers are still broken (that's why it parked instead of canary-self-healing) → the function would mark the parked row 'completed' — a silent lie, and an automatic un-park by a non-deliberate path.
3. F1 chokepoint reliance: the Behind path here routes through recoveryRollback where F1 blocks it (observed working twice in r17) — correct, but the function then falls through to its own exits with the defer armed (leg 1).

FIX SHAPE (architect): parked-skip at the TOP of completeInProgressUpgrade — right after the in_progress SELECT and BEFORE the defer arms: read upgradeParkedReason; parked → log the skip + return (flag kept, row untouched); read error → fail-open proceed (the 42703 bootstrap pattern, service.go:5792-5804 rationale verbatim). One check kills all three legs. Keep F1's recoveryRollback check unchanged (chokepoint stands). Test: behavioral — parked row + flag on disk → completeInProgressUpgrade returns with flag STILL present and row still parked/in_progress.
<!-- SECTION:DESCRIPTION:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-07-06 07:41
---
CLOSED: shipped f9bdac46d, proven live by r18/r19's flag-present-after-park assertions across multiple daemon restarts.
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
NORTH STAR: once an upgrade is parked, NOTHING automatic may touch it — not a rollback, not a completion, not the flag file; only a deliberate operator act moves it. SHIPPED f9bdac46d (2026-07-04): parked-skip at the top of completeInProgressUpgrade, before the unconditional flag-removal defer arms. Closed three holes at once: the observed flag strip (next boot went flag-blind → ungated boot-migrate), the latent wrong-completed (a parked at-target row with broken app containers would have been marked completed — an automatic un-park-by-lie), and the defer firing even after the rollback parked-skip correctly refused. PROVEN LIVE in r18/r19: flag present after park across multiple restarts (assert 4 green).
<!-- SECTION:FINAL_SUMMARY:END -->

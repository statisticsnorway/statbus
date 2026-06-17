---
id: STATBUS-077
title: >-
  flag-absent-after-kill: 4 scenarios leave no in-progress flag after the kill
  (RUN-A Cat A unmasked by the quiesce fix) — rc.04 gate residual #3
status: In Progress
assignee:
  - architect
created_date: '2026-06-17 13:07'
labels:
  - install-recovery
  - rc.04
  - gate
  - recovery
  - flag-timing
  - regression-triage
dependencies:
  - STATBUS-075
references:
  - cli/internal/upgrade/service.go
  - cli/cmd/install_upgrade.go
  - test/install-recovery/scenarios/3-postswap-mid-tx-kill.sh
  - test/install-recovery/scenarios/3-postswap-resume-died-rollback.sh
priority: high
ordinal: 77000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
THE genuinely-new 3rd residual class from run 27683157288 (commit 3a0d6e6dd) — surfaced once the SIGKILL-quiesce fix (3a0d6e6dd) removed the quiesce-rollback that previously MASKED it (this was RUN A's "Category A: flag absent after kill"). NOT fixed by e6c85c193 (which fixes only freshness + masked-unit).

THE 4 SCENARIOS (all fail `✗ expected flag file present after kill`): 3-postswap-archivebackup-resume, 3-postswap-mid-tx-kill, 3-postswap-resume-died-rollback, 4-rollback-restore-watchdog. All have a coherent fabricate (HEAD,HEAD) → the install reaches its kill point → after the kill the upgrade-in-progress flag file is ABSENT.

THE QUESTION (architect diagnosing, first principles, product-vs-harness):
(a) PRODUCT bug: executeUpgrade does not write the in-progress flag BEFORE the kill point → a crash there leaves NO recovery marker. If so this is ALBANIA-CRITICAL: a mid-upgrade crash on a no-remote-rescue standalone box would be undetectable by recovery (the operator's re-run couldn't find the interrupted upgrade). This is the exact class the campaign exists to harden.
(b) HARNESS bug: the kill/park misfired or the assertion checks too early. CLUE: mid-tx-kill's log shows `migrate subprocess parked (PID=          )` — park-detection captured an EMPTY PID before pg_terminate_backend, so the kill may not have fired at the intended mid-tx point.

OPEN: do the 4 kill at the same conceptual point or different (mid-tx / mid-applyPostSwap / resume-died / rollback-restore)? One root cause or several? Per-scenario logs in tmp/run288/cls-<scenario>/.

GATING: blocks the rc.04 100%-green gate (STATBUS-075) alongside the (already-fixed) freshness + masked-unit classes. The re-run is HELD until this fix lands so it batches with e6c85c193's 9 fixes into ONE comprehensive re-run. OWNER: architect (diagnose product-vs-harness + fix shape) -> implement -> foreman review/commit -> re-run.
<!-- SECTION:DESCRIPTION:END -->

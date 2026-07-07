---
id: STATBUS-144
title: >-
  flagless-boot-migrate-churn: a concluded box restart-churns on a broken
  pending migration until the upgrade daemon dies silently
status: To Do
assignee: []
created_date: '2026-07-07 02:57'
updated_date: '2026-07-07 03:07'
labels:
  - upgrade
  - recovery
  - product
  - install-recovery
dependencies: []
references:
  - cli/internal/upgrade/service.go
  - cli/internal/migrate/exit_codes.go
  - STATBUS-136
  - STATBUS-046
ordinal: 145000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: a box that has already concluded (upgrade row at a terminal state, no recovery flag) must never restart-churn on a broken pending migration — one loud report, then alive-idle. BENEFIT: the git-corrupt abort's natural aftermath stops silently killing the upgrade daemon (no discovery, no scheduled pickup, no backup ticker) on exactly the boxes that just had their worst day. STAGE: Stage 1 (install/upgrade robustness). COMPLEXITY: engineer-substantial-but-small. DEPENDS ON: nothing.

FOUND live (abort-oracle scenario first pass, 2026-07-07, kept-VM autopsy by the architect — NRestarts observed at 7 and climbing, ~30s cadence): after a terminal (row=failed, flag removed), a FLAGLESS boot whose boot-migrate hits a deterministically failing pending migration EXITS the process — the deferred-recovery path requires a service-held flag, and there is none — so systemd restarts it every RestartSec=30s until StartLimit (10 per 600s; a 30s cadence trips it, unlike the original rune loop's 150s) kills the unit into a silent 'failed' unit state. Terminal outcome: the upgrade DAEMON dead with no siren and no park, while app/db keep serving.

REACHABLE IN REALITY as the natural sequel of every git-corrupt abort: the abort's defining feature is that the git restore FAILED, so the new version's migrations (including whichever broke the upgrade) REMAIN on disk with row=failed and no flag — every subsequent service boot then churns to StartLimit death. Violates the recovery design's own standard for deterministic failures (fail fast + actionable ONCE, stay alive — never loop) in the one window the ratified budget boundary deliberately excluded (flagless, post-terminal).

SEVERITY, honest and modest: the abort itself already sirened and instructed the operator; services keep serving; the loop kills only the upgrade daemon — but "churn 10 times then die silently" is not a designed terminal.

FIX SHAPE (architect): in the service's FLAGLESS boot-migrate failure handling, classify deterministic failures (the migrate exit-code contract's exit 20) → log loud ONCE + CONTINUE to the main loop alive-idle (the daemon has normal duties; the broken migration resurfaces actionably on any deliberate operation). Keep exit-and-restart only for the transient/unclassified case.

ORACLE: the abort-write-lands scenario run WITHOUT its cleanup step reproduces this exactly (its first pass did, by accident — the r-ledger evidence); preserve as a variant assertion once the fix lands.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A flagless boot whose boot-migrate fails DETERMINISTICALLY (exit 20) logs one loud actionable report and continues to the main loop alive-idle — no restart churn, no StartLimit death
- [ ] #2 Transient/unclassified boot-migrate failures keep the exit-and-restart behavior
- [ ] #3 The abort-aftermath state (row=failed, no flag, broken migration on disk) leaves the daemon alive and serving its normal loop, verified by a scenario variant
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-07-07 03:07
---
LIVE SEVERITY EVIDENCE (banked from the kept abort-oracle VM 65.108.158.151 before reaping, systemd 255, operator empirics 2026-07-07): the flagless churn was observed running to its terminal — NRestarts climbed ~+1 per 30s (7 at the architect's read, 9 at the operator's) until the unit sat in state 'failed' — i.e. the StartLimit death is not hypothetical, it is the observed end state of this bug on a real box. Counter arithmetic for the fix's gate/tests, confirmed on the same box: `systemctl reset-failed` zeroes NRestarts in BOTH unit states (failed 9→0, active 1→0), and the counter increments by exactly +1 per restart (0→1→2, timestamped, no skips). The abort-oracle scenario now deletes its synthetic migration promptly and stays a narrow 136 oracle; THIS ticket's future oracle is that same scenario WITHOUT the cleanup step, asserting the StartLimit death (pointer in the scenario header).
---
<!-- COMMENTS:END -->

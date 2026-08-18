---
id: STATBUS-228
title: >-
  rollback-restore-crash: upgrades can no longer roll back — the service
  crash-dies twice during the rollback's database restore, on two scenarios that
  passed before
status: To Do
assignee:
  - engineer
created_date: '2026-08-18 10:27'
labels:
  - upgrade-recovery
  - release
  - regression
dependencies: []
references:
  - cli/internal/upgrade/service.go
  - tmp/operator-arc-fails34-triage-2026-08-18.md
priority: high
type: bug
ordinal: 228000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
When an upgrade fails, the system's promise is that it rolls back: restore the database backup, restart the old version, leave a working box. At rc.03, that promise broke — and a release cannot ship while rollback is broken, because rollback is what makes every other upgrade risk survivable.

WHAT THE EVIDENCE SHOWS: two arc scenarios that exercise rollback (restore-broke-reattempt, jobs 95644094935; rollback-pair-terminal, 95644095093) both got through setup and into their rollback phase, then failed identically: "ROLLBACK_FAILED_DB_RESTORE: rollback could not complete — two consecutive crash-deaths during rollback (recovery attempt 1)", with the database connection dying mid-restore ("failed to receive message: unexpected EOF" on 127.0.0.1:3014). Both scenarios PASSED at the previous full suite (run 30755799405). The two failures are byte-identical in signature, 13-15 minutes into healthy runs — not the VM-starvation class (that one is 227).

THE SUSPECT WINDOW: everything between the last passing suite's commit and the rc.03 tag (bafcb396b) — which includes the recent restore/read-only-window work, the marker-truth rewrite on the restoration success arm, and the restore-identity changes. The crash-death-during-restore shape suggests the service process itself is dying while the restore runs (watchdog kill? panic? the restore's own connection handling?) — "two consecutive crash-deaths" is the budget guard's counting language, meaning the daemon died and its resume died again.

WHAT IS ACHIEVED BY FIXING: the promotion path reopens on a release whose rollback demonstrably works — the one property an unattended statistical-office box cannot live without.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Root cause traced with file:line — what in the suspect window makes the service crash-die during the rollback DB restore
- [ ] #2 Fix designed (architect-reviewed) and landed with a RED-first oracle at the unit level where the mechanism allows
- [ ] #3 Both scenarios green at a suite run carrying the fix — the promotion candidate moves to that release
<!-- AC:END -->

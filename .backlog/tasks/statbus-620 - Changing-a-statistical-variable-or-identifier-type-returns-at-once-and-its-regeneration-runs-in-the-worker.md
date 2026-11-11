---
id: STATBUS-620
title: >-
  Changing a statistical variable or identifier type returns at once and its
  regeneration runs in the worker
status: To Do
assignee: []
created_date: '2026-11-11T12:51:00Z'
labels:
  - db
  - worker
  - admin
dependencies: []
priority: medium
ordinal: 533204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## North Star
An administrator's change to a statistical variable or an identifier type is stored at once; the work it implies on a full register (indices, import columns, default import mappings) runs in the background, with progress shown like other worker work.

## Zoom out
Split from STATBUS-619 (owner 2026-11-11 12:48). On Norway (rune, v2026.11.4-rc.01, 3.1M statistical units) each save of stat_definition or external_ident_type took 8.6 to 13.3 s (db log 12:35:09 to 12:36:28 GMT). The time is the statement trigger lifecycle_callbacks.cleanup_and_generate (AFTER INSERT/UPDATE/DELETE on both tables), which runs every registered callback inside the save: statistical_unit_jsonb_indices, import external ident, link, stat var data columns, default definition mappings. STATBUS-619 made the dialogs show Saving… meanwhile (5fe1d9118); the wait itself remains.

## Zoom in (to design with the owner before building)
- The trigger enqueues one worker task (deduplicated) instead of regenerating inline; the worker runs cleanup_and_generate.
- What a user sees between save and regeneration: the change listed at once, imports and search catching up when the task finishes (navbar progress, as for recalculation).
- Whether only the callbacks a change needs run (an enabled flip on one variable touches that variable's index and columns).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 [Owner] Agrees the design (worker task, what is visible meanwhile) after a walk-through. The answer is recorded in this ticket's notes and becomes the build plan.
- [ ] #2 Disabling one statistical variable on a database with 3M statistical units returns in under 1 s, and the worker finishes the regeneration; the measurement before and after is recorded in this ticket
- [ ] #3 An import started right after the change uses the regenerated columns; a test asserts it
<!-- AC:END -->

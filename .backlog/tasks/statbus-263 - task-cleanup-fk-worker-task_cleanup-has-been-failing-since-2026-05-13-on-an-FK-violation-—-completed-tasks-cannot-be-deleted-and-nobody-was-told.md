---
id: STATBUS-263
title: >-
  task-cleanup-fk: worker task_cleanup has been failing since 2026-05-13 on an
  FK violation — completed tasks cannot be deleted, and nobody was told
status: To Do
assignee: []
created_date: '2026-08-27 12:41'
labels:
  - worker
  - norway
dependencies: []
priority: medium
type: bug
ordinal: 256000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found during the STATBUS-262 sweep on rune (no.statbus.org): worker.tasks row 536277, command task_cleanup, state failed, created 2026-05-13 — "update or delete on table \"tasks\" violates foreign key constraint" on DELETE FROM worker.tasks WHERE state = 'completed'. The box holds 605k completed task rows.

Two defects, not one: (1) the cleanup's DELETE collides with an FK referencing worker.tasks — either the FK lacks the right ON DELETE behaviour or the cleanup must delete dependents first; (2) a maintenance task failing continuously since May was invisible — same silence family as STATBUS-262's week-long read-only refusals (the loud-guard question there covers this case too).

Architect concurred on 2026-08-27 that this is its own root-cause, not foldable into 262. Investigate against the schema the box actually runs; check whether other fleet boxes show the same failed cleanup.

WHAT IS ACHIEVED: completed-task cleanup works again fleet-wide, and a failing maintenance task cannot stay silent for months.
<!-- SECTION:DESCRIPTION:END -->

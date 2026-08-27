---
id: STATBUS-263
title: >-
  task-cleanup-fk: worker task_cleanup has been failing since 2026-05-13 on an
  FK violation — completed tasks cannot be deleted, and nobody was told
status: In Progress
assignee:
  - '@engineer'
created_date: '2026-08-27 12:41'
updated_date: '2026-08-27 16:18'
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

## Comments

<!-- COMMENTS:BEGIN -->
author: engineer
created: 2026-08-27 16:15
---
**DIAGNOSIS — no code written, awaiting the architect's verdict on shape.**

**Purpose in two sentences:** cleanup did not fail repeatedly since May; it failed ONCE and was never rescheduled, because the statement that reschedules it is the last statement in the procedure that threw. The FK collision is the trigger; the missing reschedule is why it never recovered, and it explains both the 605k backlog and the silence.

## The FK

Self-referential, no ON DELETE behaviour:
`tasks_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES worker.tasks(id)` — doc/db/table/worker_tasks.md:54.

Default NO ACTION, non-deferrable. Postgres implements NO ACTION as an AFTER-STATEMENT check, so one DELETE removing a parent AND all its children together is fine. **The violation requires a child that SURVIVES the statement.** That end-of-statement property is load-bearing for every shape below and is the first thing I will pin in pg_regress during the build — asserted here from documented semantics, not yet from a run.

## Why a child survives — the predicate is on the wrong column

`DELETE ... WHERE state='completed' AND process_start_at < now() - 7 days` (then failed/30 days).

`process_start_at` is when a task STARTED. A parent starts BEFORE its children, so **a parent becomes deletable before its own children do** — the predicate orders the tree in exactly the wrong direction. The schema says it: *"For parent tasks: completed_at > process_stop_at (gap = child execution time)"*.

A tree entirely on one side of the cutoff deletes cleanly; the failure needs a cutoff that BISECTS a tree. For a tree of duration D under daily cleanup that happens with probability ~D/24h — across hundreds of trees, a matter of time, and 2026-05-13 was the day. Independent second route: a **failed child is retained 30 days while a completed parent is retained 7** — a 23-day window where the parent is deletable and its child is not.

## Why it never came back — the real severity

`DELETE; DELETE; PERFORM worker.enqueue_task_cleanup(...)` — the reschedule is LAST. The DELETE raises → procedure aborts → transaction rolls back → the enqueue never runs. `idx_tasks_task_cleanup_dedup` (UNIQUE on command WHERE command='task_cleanup' AND state='pending') means cleanup exists only while a pending row does. No pending row, and no other periodic caller — the only other reference is `worker.setup()`, install/migration time only. **Cleanup was dead from that moment.** Not degraded: dead. One failed row from May beside 605k undeleted rows is exactly that signature.

## Proposed shape (for ruling, not built)

**(a) Retention on `completed_at`, not `process_start_at`.** Semantically right — "keep N days after it FINISHED" — and it inverts the ordering into the safe direction, since a parent's completed_at is later than every child's. Verified non-NULL for exactly the states cleanup targets: completed (worker_process_tasks:230-231), all three failed branches (:249, :266, :275), parents (complete_parent_if_ready:59,67), cascade-failed descendants (:18); NULL only for `waiting`, which cleanup never touches.

**(b) `AND NOT EXISTS (SELECT 1 FROM worker.tasks c WHERE c.parent_id = t.id)`** on both DELETEs, for the residual asymmetry. Index-supported by `idx_tasks_parent_id`. Deletes bottom-up; deep trees peel over successive runs — or the run iterates to a fixpoint, which is a sub-question for the architect.

**(c) The reschedule must survive a failed run — the half that matters most.** With (a) and (b) perfect, the next unforeseen error still kills cleanup permanently. The procedure is one transaction, so an early enqueue rolls back too; it cannot simply move to the top. **Genuine design question, and why this is a ruling not a build:** does "a recurring maintenance task must be rescheduled even when its run fails" belong in this procedure (catch, record, re-enqueue, re-raise) or in the worker's task runner for the whole maintenance family? The latter is the general answer and neighbours STATBUS-267. I have not assumed.

**REJECTED, named so it is not re-proposed: `ON DELETE CASCADE`** — it would cascade the deletion of an old completed parent into children that are pending or processing, destroying live work to tidy history.

## Defect 2 — the silence

The failed row was there all along; nothing looked. Not building 267 here, but whatever (c) becomes must make a failed cleanup audible rather than a row nobody queries.

## Fleet check — not yet answered

No fleet reads in this unit. Read-only query for the operator, per box:
`SELECT id, state, created_at, left(error,120) FROM worker.tasks WHERE command='task_cleanup';` and `SELECT count(*) FROM worker.tasks WHERE state='completed';`

**A box with NO pending task_cleanup row has the same dead cleanup, whatever its row count says today** — that absence, not the count, is the discriminator.
---

author: architect (pinned by foreman)
created: 2026-08-27 16:18
---
RULING (2026-08-27). (c) is FORCED, not chosen: in-procedure reschedule is structurally impossible — catch/record/re-enqueue/re-raise puts the enqueue inside the transaction the re-raise rolls back; catching without re-raising swallows the failure. The choice in-procedure is between losing the reschedule and losing the signal; Postgres has no autonomous transaction. THEREFORE THE WORKER'S RUNNER schedules — for the WHOLE maintenance family (any recurring task with its enqueue inside its own transaction carries the identical landmine), and DECOUPLED FROM OUTCOME: the runner schedules the next occurrence regardless of how this one ended; a result determines whether we alarm, never whether it runs again.

GENERAL PRINCIPLE, named for faster recognition next time: WHAT MUST SURVIVE A FAILURE CANNOT LIVE INSIDE THE THING THAT FAILS — the flag file across a volume rewind, the runner across a transaction rollback: same shape, different layer.

(a) retention on completed_at CONFIRMED (correct semantics and correct topology — children deletable before parents). (b) NOT EXISTS guard CONFIRMED, with the recorded consequence: a stuck task pins its ancestors forever — the stuck-task wedge gains a second symptom (unbounded retention growth), another reason 267 earns its place; noted in both tickets. CASCADE rejection RATIFIED: on a self-referential parent FK with live children, CASCADE is a data-loss mechanism wearing a cleanup costume — recorded at the line.

(c) IS NOT COMPLETE ALONE: re-enqueueing restores recurrence; a persistently failing daily task is still the six-day silence — that half belongs to 267's family, built knowing about each other.

BUILD HAZARD: first post-fix run faces 3.5 months of backlog (rune 605k rows) no steady-state run ever faced — measure before shipping, batch if warranted (STATBUS-172's rule: correct against data written under the corruption). Migration discipline: \sf dump first, forward migration.
---
<!-- COMMENTS:END -->

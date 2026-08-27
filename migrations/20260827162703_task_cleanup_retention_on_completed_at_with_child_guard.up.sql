BEGIN;

-- STATBUS-263: task_cleanup deletes coherently, in bounded batches, and no
-- longer schedules itself.
--
-- WHAT WENT WRONG. On 2026-05-13 the bulk DELETE raised
--   update or delete on table "tasks" violates foreign key constraint
--   "tasks_parent_id_fkey"
-- and cleanup has not run since. rune now holds 605k undeleted completed rows.
-- It did not fail repeatedly: it failed ONCE and was never rescheduled, because
-- the re-enqueue was the last statement in the procedure that threw, so the
-- rollback took the reschedule with it. With no pending row (the partial unique
-- index idx_tasks_task_cleanup_dedup means cleanup exists only while one does)
-- and no other periodic caller, cleanup was dead, not degraded.
--
-- Three changes, each argued below.

CREATE OR REPLACE PROCEDURE worker.command_task_cleanup(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_completed_retention_days INT = COALESCE((payload->>'completed_retention_days')::int, 7);
    v_failed_retention_days INT = COALESCE((payload->>'failed_retention_days')::int, 30);
    -- Batch size and pass ceiling. Measured, not guessed: against a synthetic
    -- 600k-row backlog shaped like rune's (200k parents x 2 children), the
    -- unbatched statement ran 12.7s then 7.6s. Twenty seconds of DELETE holding
    -- row locks on the worker's hottest table is not a statement to fire
    -- unbounded on a production box, where the same work will be slower.
    v_batch_size INT = 10000;
    v_max_passes INT = 100;
    v_pass INT = 0;
    v_removed INT;
    v_total_completed INT = 0;
    v_total_failed INT = 0;
BEGIN
    -- ── DELETING TERMINAL TASKS WITHOUT ORPHANING A CHILD ────────────────────
    --
    -- worker.tasks references ITSELF (tasks_parent_id_fkey, parent_id -> id)
    -- with no ON DELETE clause, so NO ACTION applies. NO ACTION is checked
    -- AFTER THE STATEMENT, not per row — verified by a run, not by the manual,
    -- in test/sql/095_worker_task_parent_fk_delete_semantics.sql. So a single
    -- statement MAY remove a parent together with its children; what it must
    -- never do is leave a child behind.
    --
    -- That is why the remedy is the SELECTION, not the ordering. Two changes
    -- make the selection coherent:
    --
    -- 1. RETENTION ON completed_at, NOT process_start_at. The old predicate
    --    filtered when a task STARTED. A parent starts before its children, so
    --    it became deletable BEFORE them — the tree was ordered in exactly the
    --    wrong direction, and any cutoff falling inside a still-retained tree
    --    orphaned a child. completed_at is both the right semantics (retention
    --    means "keep N days after it FINISHED") and the right topology: a
    --    parent completes after every child, so children become deletable
    --    first. completed_at is non-NULL for precisely the states swept here
    --    and NULL only for 'waiting', which is never swept.
    --
    -- 2. THE CHILD GUARD. Retention windows still differ between states — a
    --    failed child is kept 30 days while its completed parent is kept 7 —
    --    so NOT EXISTS refuses to remove any row that still has a child of any
    --    kind. Index-supported by idx_tasks_parent_id.
    --
    --    RECORDED CONSEQUENCE (STATBUS-263 ruling): a task stuck in a
    --    non-terminal state pins its ancestors forever, so the stuck-task wedge
    --    gains a second symptom — unbounded retention growth. That is a reason
    --    to detect stuck tasks (STATBUS-267), NOT a reason to weaken this
    --    guard. Measured: with 1000 stuck children, 500 ancestors stayed.
    --
    -- ON DELETE CASCADE IS NOT AN OPTION AND MUST NOT BE REINTRODUCED AS A
    -- SIMPLIFICATION. On a self-referential parent FK whose children may be
    -- pending or processing, CASCADE is a data-loss mechanism wearing a
    -- cleanup costume: deleting one old completed parent would silently take
    -- live, unfinished work with it.
    --
    -- The guard deletes bottom-up, so one pass frees the next level: a tree of
    -- depth D needs D+1 passes. Looping to a fixpoint HERE matters — without
    -- it a backlog drains one level per DAY. Measured: 600k rows cleared in two
    -- passes; the pass ceiling is a runaway stop, not an expected limit.
    LOOP
        v_pass := v_pass + 1;

        WITH doomed AS (
            SELECT t.id
            FROM worker.tasks AS t
            WHERE t.state = 'completed'::worker.task_state
              AND t.completed_at < (now() - (v_completed_retention_days || ' days')::interval)
              AND NOT EXISTS (SELECT 1 FROM worker.tasks AS c WHERE c.parent_id = t.id)
            LIMIT v_batch_size
        )
        DELETE FROM worker.tasks AS d
        USING doomed
        WHERE d.id = doomed.id;

        GET DIAGNOSTICS v_removed = ROW_COUNT;
        v_total_completed := v_total_completed + v_removed;
        EXIT WHEN v_removed = 0 OR v_pass >= v_max_passes;
    END LOOP;

    v_pass := 0;
    LOOP
        v_pass := v_pass + 1;

        WITH doomed AS (
            SELECT t.id
            FROM worker.tasks AS t
            WHERE t.state = 'failed'::worker.task_state
              AND t.completed_at < (now() - (v_failed_retention_days || ' days')::interval)
              AND NOT EXISTS (SELECT 1 FROM worker.tasks AS c WHERE c.parent_id = t.id)
            LIMIT v_batch_size
        )
        DELETE FROM worker.tasks AS d
        USING doomed
        WHERE d.id = doomed.id;

        GET DIAGNOSTICS v_removed = ROW_COUNT;
        v_total_failed := v_total_failed + v_removed;
        EXIT WHEN v_removed = 0 OR v_pass >= v_max_passes;
    END LOOP;

    -- ── NO SELF-RESCHEDULE HERE ANY MORE ─────────────────────────────────────
    --
    -- This procedure used to end with PERFORM worker.enqueue_task_cleanup(...).
    -- That is the bug that turned one bad day into three silent months: the
    -- enqueue lived inside the transaction that the failure rolled back, so a
    -- failing run erased its own next occurrence.
    --
    -- It cannot be repaired in place. Catching the error and re-enqueueing puts
    -- the INSERT inside the same doomed transaction; catching without
    -- re-raising throws the failure away instead. In-procedure, the only choice
    -- is which to lose — the reschedule or the signal — because PostgreSQL has
    -- no autonomous transaction.
    --
    -- WHAT MUST SURVIVE A FAILURE CANNOT LIVE INSIDE THE THING THAT FAILS.
    -- Recurrence therefore belongs to the worker's runner, which schedules the
    -- next occurrence in its own transaction, decoupled from this one's
    -- outcome: a result decides whether we ALARM, never whether we RUN AGAIN.
    -- See cli/src/worker.cr.
    --
    -- The Info Principle: report what this run did, so a caller and the task
    -- row can see the work rather than infer it from a silent success.
    p_info := COALESCE(p_info, '{}'::jsonb) || jsonb_build_object(
        'completed_tasks_deleted', v_total_completed,
        'failed_tasks_deleted', v_total_failed
    );
END;
$procedure$;

END;

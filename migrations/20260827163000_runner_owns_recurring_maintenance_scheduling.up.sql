BEGIN;

-- STATBUS-263: recurrence becomes a property of the COMMAND, and scheduling
-- becomes the runner's job.
--
-- WHAT MUST SURVIVE A FAILURE CANNOT LIVE INSIDE THE THING THAT FAILS.
--
-- Both maintenance commands used to end by scheduling themselves:
--   command_task_cleanup       -> PERFORM worker.enqueue_task_cleanup(...)
--   command_import_job_cleanup -> PERFORM worker.enqueue_import_job_cleanup()
-- Each enqueue sat inside the transaction its own handler ran in, so a handler
-- that raised rolled back its own next occurrence. task_cleanup hit that on
-- 2026-05-13 and never ran again — three months of silence and 605k undeleted
-- rows on rune. import_job_cleanup carries the identical landmine; it has
-- survived only because its per-job DELETEs are individually wrapped, so the
-- failures it does have are swallowed into warnings instead of raising.
--
-- The repair is structural, not local. Recurrence is declared here as data and
-- executed by the worker's runner in its own transaction, decoupled from the
-- run's outcome: A RESULT DECIDES WHETHER WE ALARM, NEVER WHETHER WE RUN AGAIN.

-- ── Recurrence as data ───────────────────────────────────────────────────────
-- Declared beside handler_procedure/before_procedure/after_procedure, which
-- already establish the pattern that the registry is where a command's
-- behaviour is described rather than hard-coded in a client.
ALTER TABLE worker.command_registry
    ADD COLUMN schedule_interval interval;

COMMENT ON COLUMN worker.command_registry.schedule_interval IS
    'How often this command should recur. NULL = not recurring (event-driven). '
    'Non-NULL makes it a member of the maintenance family: the worker''s runner '
    'schedules the next occurrence after each run REGARDLESS OF OUTCOME, and '
    'seeds a missing one at startup. A handler must never schedule itself — its '
    'enqueue would live inside the transaction its own failure rolls back '
    '(STATBUS-263).';

UPDATE worker.command_registry
SET schedule_interval = interval '24 hours'
WHERE command IN ('task_cleanup', 'import_job_cleanup');

-- ── Ensuring the next occurrence exists ──────────────────────────────────────
CREATE OR REPLACE FUNCTION worker.ensure_recurring_task(p_command text, p_payload jsonb DEFAULT NULL)
RETURNS bigint
LANGUAGE plpgsql
AS $ensure_recurring_task$
DECLARE
    _ensure_recurring_task BIGINT;
    v_interval INTERVAL;
BEGIN
    SELECT cr.schedule_interval INTO v_interval
    FROM worker.command_registry AS cr
    WHERE cr.command = p_command;

    -- Fail fast rather than silently doing nothing: being asked to schedule a
    -- command that is not recurring means the caller's model is wrong, and a
    -- quiet no-op here would present as a maintenance task that never runs.
    IF v_interval IS NULL THEN
        RAISE EXCEPTION 'worker.ensure_recurring_task: command % has no schedule_interval (not a recurring command)', p_command;
    END IF;

    -- ON CONFLICT DO NOTHING with no target: the per-command partial unique
    -- indexes (idx_tasks_*_dedup) permit exactly one PENDING row per recurring
    -- command, so a pending occurrence already in place wins and this is a
    -- no-op. That single property makes one statement serve both callers —
    -- "schedule the next run" and "seed one if absent" are the same request.
    INSERT INTO worker.tasks (command, payload, scheduled_at)
    VALUES (p_command, p_payload, now() + v_interval)
    ON CONFLICT DO NOTHING
    RETURNING id INTO _ensure_recurring_task;

    IF _ensure_recurring_task IS NOT NULL THEN
        PERFORM pg_notify('worker_tasks', 'maintenance');
    END IF;

    RETURN _ensure_recurring_task;  -- NULL when one already existed
END;
$ensure_recurring_task$;

COMMENT ON FUNCTION worker.ensure_recurring_task(text, jsonb) IS
    'Ensure a pending occurrence of a recurring command exists. Returns the new '
    'task id, or NULL if one was already pending. Idempotent by way of the '
    'per-command dedup indexes (STATBUS-263).';

-- ── What the runner calls after each batch ───────────────────────────────────
CREATE OR REPLACE FUNCTION worker.schedule_recurring_after(p_since timestamptz)
RETURNS TABLE (command text, task_id bigint)
LANGUAGE plpgsql
AS $schedule_recurring_after$
BEGIN
    -- Every recurring command whose occurrence reached a TERMINAL state since
    -- p_since gets its next one scheduled. 'completed' and 'failed' are treated
    -- identically and that is the entire point: the outcome decides whether we
    -- alarm, never whether we run again.
    --
    -- The finished task's own payload is carried forward, so a run configured
    -- with non-default retention keeps that configuration.
    RETURN QUERY
    SELECT t.command,
           worker.ensure_recurring_task(t.command, t.payload)
    FROM worker.tasks AS t
    JOIN worker.command_registry AS cr ON cr.command = t.command
    WHERE cr.schedule_interval IS NOT NULL
      AND t.state IN ('completed'::worker.task_state, 'failed'::worker.task_state)
      AND t.completed_at >= p_since;
END;
$schedule_recurring_after$;

COMMENT ON FUNCTION worker.schedule_recurring_after(timestamptz) IS
    'Schedule the next occurrence of every recurring command that finished '
    'since p_since, whether it succeeded or failed. Called by the worker runner '
    'in its own transaction, so a handler''s rollback cannot take the next '
    'occurrence with it (STATBUS-263).';

-- ── What the runner calls at startup ─────────────────────────────────────────
CREATE OR REPLACE FUNCTION worker.seed_recurring_tasks()
RETURNS TABLE (command text, task_id bigint)
LANGUAGE plpgsql
AS $seed_recurring_tasks$
BEGIN
    -- A box whose recurring row was destroyed by the old self-scheduling bug
    -- has nothing pending and therefore nothing to trigger recovery — rune has
    -- been in that state since May. Seeding at startup is what brings such a
    -- box back without an operator knowing to intervene.
    --
    -- Only rows that were actually ABSENT come back (ensure_recurring_task
    -- returns NULL when one was already pending), so the caller can report what
    -- it repaired instead of announcing work it did not do.
    RETURN QUERY
    SELECT cr.command,
           worker.ensure_recurring_task(cr.command, NULL)
    FROM worker.command_registry AS cr
    WHERE cr.schedule_interval IS NOT NULL;
END;
$seed_recurring_tasks$;

COMMENT ON FUNCTION worker.seed_recurring_tasks() IS
    'Ensure every recurring command has a pending occurrence. Called at worker '
    'startup so a box whose maintenance row was lost recovers on its own '
    '(STATBUS-263).';

-- ── The handlers stop scheduling themselves ──────────────────────────────────
-- command_task_cleanup already had its PERFORM removed by the migration that
-- rewrote it. import_job_cleanup keeps its body and loses only that last line.
CREATE OR REPLACE PROCEDURE worker.command_import_job_cleanup(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_job_record RECORD;
    v_deleted_count INTEGER := 0;
BEGIN
    RAISE DEBUG 'Running worker.command_import_job_cleanup';

    FOR v_job_record IN
        SELECT id, slug FROM public.import_job WHERE expires_at <= now()
    LOOP
        RAISE DEBUG '[Job % (Slug: %)] Expired, attempting deletion.', v_job_record.id, v_job_record.slug;
        BEGIN
            DELETE FROM public.import_job WHERE id = v_job_record.id;
            v_deleted_count := v_deleted_count + 1;
            RAISE DEBUG '[Job % (Slug: %)] Successfully deleted.', v_job_record.id, v_job_record.slug;
        EXCEPTION
            WHEN OTHERS THEN
                RAISE WARNING '[Job % (Slug: %)] Failed to delete expired import job: %', v_job_record.id, v_job_record.slug, SQLERRM;
        END;
    END LOOP;

    RAISE DEBUG 'Finished worker.command_import_job_cleanup. Deleted % expired jobs.', v_deleted_count;

    -- No self-reschedule: the runner owns recurrence (STATBUS-263). See the
    -- schedule_interval column comment for why a handler must never schedule
    -- itself.
    p_info := COALESCE(p_info, '{}'::jsonb) || jsonb_build_object('expired_jobs_deleted', v_deleted_count);
END;
$procedure$;

END;

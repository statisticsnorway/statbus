```sql
CREATE OR REPLACE FUNCTION worker.ensure_recurring_task(p_command text, p_payload jsonb DEFAULT NULL::jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
AS $function$
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
$function$
```

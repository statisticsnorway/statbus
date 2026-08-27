```sql
CREATE OR REPLACE FUNCTION worker.schedule_recurring_after(p_since timestamp with time zone)
 RETURNS TABLE(command text, task_id bigint)
 LANGUAGE plpgsql
AS $function$
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
$function$
```

```sql
CREATE OR REPLACE PROCEDURE worker.command_task_cleanup(IN payload jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_completed_retention_days INT = COALESCE((payload->>'completed_retention_days')::int, 7);
    v_failed_retention_days INT = COALESCE((payload->>'failed_retention_days')::int, 30);
BEGIN
    -- Delete completed tasks older than retention period
    DELETE FROM worker.tasks
    WHERE state = 'completed'::worker.task_state
      AND processed_at < (now() - (v_completed_retention_days || ' days')::interval);

    -- Delete failed tasks older than retention period
    DELETE FROM worker.tasks
    WHERE state = 'failed'::worker.task_state
      AND processed_at < (now() - (v_failed_retention_days || ' days')::interval);

    -- Schedule to run again in 24 hours
    PERFORM worker.enqueue_task_cleanup(
      v_completed_retention_days,
      v_failed_retention_days
    );
END;
$procedure$
```

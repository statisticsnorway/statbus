```sql
CREATE OR REPLACE PROCEDURE worker.command_task_cleanup(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_completed_retention_days INT = COALESCE((payload->>'completed_retention_days')::int, 7);
    v_failed_retention_days INT = COALESCE((payload->>'failed_retention_days')::int, 30);
BEGIN
    DELETE FROM worker.tasks
    WHERE state = 'completed'::worker.task_state
      AND process_start_at < (now() - (v_completed_retention_days || ' days')::interval);

    DELETE FROM worker.tasks
    WHERE state = 'failed'::worker.task_state
      AND process_start_at < (now() - (v_failed_retention_days || ' days')::interval);

    PERFORM worker.enqueue_task_cleanup(
      v_completed_retention_days,
      v_failed_retention_days
    );
END;
$procedure$
```

```sql
CREATE OR REPLACE FUNCTION worker.enqueue_task_cleanup(p_completed_retention_days integer DEFAULT 7, p_failed_retention_days integer DEFAULT 30)
 RETURNS bigint
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_task_id BIGINT;
  v_payload JSONB;
BEGIN
  -- Create payload
  v_payload := jsonb_build_object(
    'completed_retention_days', p_completed_retention_days,
    'failed_retention_days', p_failed_retention_days
  );

  -- Insert with ON CONFLICT for this specific command type
  INSERT INTO worker.tasks (
    command,
    payload,
    scheduled_at
  ) VALUES (
    'task_cleanup',
    v_payload,
    now() + interval '24 hours'
  )
  ON CONFLICT (command) WHERE command = 'task_cleanup' AND state = 'pending'::worker.task_state
  DO UPDATE SET
    state = 'pending'::worker.task_state,
    priority = EXCLUDED.priority,  -- Use the new priority to push queue position
    processed_at = NULL,
    error = NULL
  RETURNING id INTO v_task_id;

  -- Notify worker of new task with queue information
  PERFORM pg_notify('worker_tasks', 'maintenance');

  RETURN v_task_id;
END;
$function$
```

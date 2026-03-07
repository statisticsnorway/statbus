```sql
CREATE OR REPLACE FUNCTION worker.enqueue_import_job_cleanup()
 RETURNS bigint
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_task_id BIGINT;
BEGIN
  -- Insert with ON CONFLICT for this specific command type
  INSERT INTO worker.tasks (
    command,
    payload,
    scheduled_at
  ) VALUES (
    'import_job_cleanup',
    '{}'::jsonb, -- No payload needed as expiry is on the job itself
    now() + interval '24 hours'
  )
  ON CONFLICT (command) WHERE command = 'import_job_cleanup' AND state = 'pending'::worker.task_state
  DO UPDATE SET
    payload = EXCLUDED.payload,
    scheduled_at = EXCLUDED.scheduled_at, -- Update to the new scheduled time
    state = 'pending'::worker.task_state,
    priority = EXCLUDED.priority,
    processed_at = NULL,
    error = NULL
  RETURNING id INTO v_task_id;

  -- Notify worker of new task with queue information
  PERFORM pg_notify('worker_tasks', 'maintenance');

  RETURN v_task_id;
END;
$function$
```

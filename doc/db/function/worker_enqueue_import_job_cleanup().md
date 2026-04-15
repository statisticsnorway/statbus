```sql
CREATE OR REPLACE FUNCTION worker.enqueue_import_job_cleanup()
 RETURNS bigint
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_task_id BIGINT;
BEGIN
  INSERT INTO worker.tasks (
    command,
    payload,
    scheduled_at
  ) VALUES (
    'import_job_cleanup',
    '{}'::jsonb,
    now() + interval '24 hours'
  )
  ON CONFLICT (command) WHERE command = 'import_job_cleanup' AND state = 'pending'::worker.task_state
  DO UPDATE SET
    payload = EXCLUDED.payload,
    scheduled_at = EXCLUDED.scheduled_at,
    state = 'pending'::worker.task_state,
    priority = EXCLUDED.priority,
    process_start_at = NULL,
    error = NULL
  RETURNING id INTO v_task_id;

  PERFORM pg_notify('worker_tasks', 'maintenance');

  RETURN v_task_id;
END;
$function$
```

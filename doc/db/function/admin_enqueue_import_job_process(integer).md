```sql
CREATE OR REPLACE FUNCTION admin.enqueue_import_job_process(p_job_id integer)
 RETURNS bigint
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_task_id BIGINT;
  v_payload JSONB;
  v_priority INTEGER;
BEGIN
  -- Validate job exists and get priority
  SELECT priority INTO v_priority
  FROM public.import_job
  WHERE id = p_job_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Import job % not found', p_job_id;
  END IF;

  -- Create payload
  v_payload := jsonb_build_object('job_id', p_job_id);

  -- Insert task with payload and priority
  -- Use job priority if available, otherwise fall back to job ID
  -- This ensures jobs are processed in order of upload timestamp
  INSERT INTO worker.tasks (
    command,
    payload,
    priority
  ) VALUES (
    'import_job_process',
    v_payload,
    COALESCE(v_priority, p_job_id)
  )
  RETURNING id INTO v_task_id;

  -- Notify worker of new task with queue information
  PERFORM pg_notify('worker_tasks', 'import');

  RETURN v_task_id;
END;
$function$
```

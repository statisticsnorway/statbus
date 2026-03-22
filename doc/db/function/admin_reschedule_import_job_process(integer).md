```sql
CREATE OR REPLACE FUNCTION admin.reschedule_import_job_process(p_job_id integer)
 RETURNS bigint
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_task_id BIGINT;
  v_parent_id BIGINT;
  v_payload JSONB;
  v_job public.import_job;
BEGIN
  -- Get the job details to check if it should be rescheduled
  SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;

  -- Only reschedule if the job is in a state that requires further processing
  IF v_job.state IN ('upload_completed', 'preparing_data', 'analysing_data', 'approved', 'processing_data') THEN
    -- Find our own task and its parent (the import_job wrapper)
    SELECT id, parent_id INTO v_task_id, v_parent_id
    FROM worker.tasks
    WHERE state = 'processing' AND worker_pid = pg_backend_pid()
    ORDER BY id DESC LIMIT 1;

    -- Create payload
    v_payload := jsonb_build_object('job_id', p_job_id);

    IF v_parent_id IS NOT NULL THEN
      -- Spawn sibling under the same import_job parent
      v_task_id := worker.spawn(
        p_command => 'import_job_process',
        p_payload => v_payload,
        p_parent_id => v_parent_id
      );
    ELSE
      -- Fallback: no parent (shouldn't happen, but be safe)
      INSERT INTO worker.tasks (
        command,
        payload,
        priority
      ) VALUES (
        'import_job_process',
        v_payload,
        v_job.priority
      )
      RETURNING id INTO v_task_id;

      PERFORM pg_notify('worker_tasks', 'import');
    END IF;

    RAISE DEBUG 'Rescheduled Task ID: %', v_task_id;
    RETURN v_task_id;
  END IF;

  RETURN NULL;
END;
$function$
```

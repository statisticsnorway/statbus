-- Down Migration 20260318134116: restructure_import_queue
--
-- Restores flat import_job_process tasks (no parent wrapper)
BEGIN;

-- ============================================================================
-- 1. Restore original enqueue_import_job_process (creates import_job_process directly)
-- ============================================================================

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
$function$;

-- ============================================================================
-- 2. Restore original reschedule_import_job_process (creates new top-level task)
-- ============================================================================

CREATE OR REPLACE FUNCTION admin.reschedule_import_job_process(p_job_id integer)
 RETURNS bigint
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_task_id BIGINT;
  v_payload JSONB;
  v_job public.import_job;
BEGIN
  -- Get the job details to check if it should be rescheduled
  SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;

  -- Only reschedule if the job is in a state that requires further processing
  IF v_job.state IN ('upload_completed', 'preparing_data', 'analysing_data', 'approved', 'processing_data') THEN
    -- Create payload
    v_payload := jsonb_build_object('job_id', p_job_id);

    -- Insert task with payload and priority
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
    RAISE DEBUG 'Rescheduled Task ID: %', v_task_id;

    -- Notify worker of new task with queue information
    PERFORM pg_notify('worker_tasks', 'import');

    RETURN v_task_id;
  END IF;

  RETURN NULL;
END;
$function$;

-- ============================================================================
-- 3. Restore hooks on import_job_process
-- ============================================================================

UPDATE worker.command_registry
SET before_procedure = 'worker.notify_is_importing_start',
    after_procedure = 'worker.notify_is_importing_stop'
WHERE command = 'import_job_process';

-- ============================================================================
-- 4. Drop the import_job handler and command
-- ============================================================================

DROP PROCEDURE IF EXISTS worker.command_import_job(jsonb);

DELETE FROM worker.command_registry WHERE command = 'import_job';

END;

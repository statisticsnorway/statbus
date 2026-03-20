-- Migration 20260318134116: restructure_import_queue
--
-- Wraps import_job_process in a parent import_job task to create proper
-- structured trees. Each import job gets one top-level import_job parent
-- with serial import_job_process children (one per state transition/batch).
BEGIN;

-- ============================================================================
-- 1. Register the new import_job command
-- ============================================================================

INSERT INTO worker.command_registry
  (queue, command, handler_procedure, before_procedure, after_procedure, description)
VALUES
  ('import', 'import_job', 'worker.command_import_job',
   'worker.notify_is_importing_start', 'worker.notify_is_importing_stop',
   'Parent wrapper for a single import job');

-- ============================================================================
-- 2. Move hooks from import_job_process to import_job (parent owns lifecycle)
-- ============================================================================

UPDATE worker.command_registry
SET before_procedure = NULL, after_procedure = NULL
WHERE command = 'import_job_process';

-- ============================================================================
-- 3. Create the import_job handler procedure
-- ============================================================================

CREATE OR REPLACE PROCEDURE worker.command_import_job(IN p_payload jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'admin', 'pg_temp'
AS $command_import_job$
DECLARE
  v_task_id BIGINT;
BEGIN
  -- Find own task_id (same pattern as command_collect_changes)
  SELECT id INTO v_task_id
  FROM worker.tasks
  WHERE state = 'processing' AND worker_pid = pg_backend_pid()
  ORDER BY id DESC LIMIT 1;

  -- Spawn first child: import_job_process runs under this parent
  PERFORM worker.spawn(
    p_command => 'import_job_process',
    p_payload => p_payload,
    p_parent_id => v_task_id,
    p_child_mode => 'serial'
  );
  -- Returns — parent becomes 'waiting', serial fiber picks up the child
END;
$command_import_job$;

-- ============================================================================
-- 4. Modify enqueue_import_job_process to create import_job parent
-- ============================================================================

CREATE OR REPLACE FUNCTION admin.enqueue_import_job_process(p_job_id integer)
 RETURNS bigint
 LANGUAGE plpgsql
AS $enqueue_import_job_process$
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

  -- Insert import_job parent task (not import_job_process directly)
  -- The handler will spawn import_job_process as a serial child
  INSERT INTO worker.tasks (
    command,
    payload,
    priority
  ) VALUES (
    'import_job',
    v_payload,
    COALESCE(v_priority, p_job_id)
  )
  RETURNING id INTO v_task_id;

  -- Notify worker of new task with queue information
  PERFORM pg_notify('worker_tasks', 'import');

  RETURN v_task_id;
END;
$enqueue_import_job_process$;

-- ============================================================================
-- 5. Modify reschedule_import_job_process to spawn sibling under same parent
-- ============================================================================

CREATE OR REPLACE FUNCTION admin.reschedule_import_job_process(p_job_id integer)
 RETURNS bigint
 LANGUAGE plpgsql
AS $reschedule_import_job_process$
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
$reschedule_import_job_process$;

END;

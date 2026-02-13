BEGIN;

-- Restore the original function (without datname filter)
CREATE OR REPLACE FUNCTION worker.reset_abandoned_processing_tasks()
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_reset_count int := 0;
  v_task RECORD;
  v_stale_pid INT;
BEGIN
  -- Terminate all other lingering worker backends.
  -- The current worker holds the global advisory lock, so any other process with
  -- application_name = 'worker' is a stale remnant from a previous crash.
  FOR v_stale_pid IN
    SELECT pid FROM pg_stat_activity
    WHERE application_name = 'worker' AND pid <> pg_backend_pid()
  LOOP
    RAISE LOG 'Terminating stale worker PID %', v_stale_pid;
    PERFORM pg_terminate_backend(v_stale_pid);
  END LOOP;

  -- Find tasks stuck in 'processing' and reset their status to 'pending'.
  -- The backends have already been terminated above.
  FOR v_task IN
    SELECT id FROM worker.tasks WHERE state = 'processing'::worker.task_state FOR UPDATE
  LOOP
    -- Reset the task to pending state.
    UPDATE worker.tasks
    SET state = 'pending'::worker.task_state,
        worker_pid = NULL,
        processed_at = NULL,
        error = NULL,
        duration_ms = NULL
    WHERE id = v_task.id;

    v_reset_count := v_reset_count + 1;
  END LOOP;
  RETURN v_reset_count;
END;
$function$;

END;

BEGIN;

-- Fix: reset_abandoned_processing_tasks was killing worker connections
-- across ALL databases (pg_stat_activity is cluster-wide).
-- When running multiple workers on different databases (e.g., test worker
-- on test_concurrent_* alongside production worker on statbus_local),
-- they would enter a death spiral — each one's reset function killing
-- the other's connections.
--
-- Fix: Add datname = current_database() filter so workers only terminate
-- stale connections to their OWN database.
CREATE OR REPLACE FUNCTION worker.reset_abandoned_processing_tasks()
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_reset_count int := 0;
  v_task RECORD;
  v_stale_pid INT;
BEGIN
  -- Terminate all other lingering worker backends FOR THIS DATABASE ONLY.
  -- The current worker holds the global advisory lock, so any other process with
  -- application_name = 'worker' connected to the same database is a stale remnant
  -- from a previous crash.
  -- CRITICAL: Filter by datname = current_database() because pg_stat_activity is
  -- cluster-wide. Without this filter, workers on different databases (e.g., test
  -- databases) would kill each other's connections.
  FOR v_stale_pid IN
    SELECT pid FROM pg_stat_activity
    WHERE application_name = 'worker'
      AND pid <> pg_backend_pid()
      AND datname = current_database()
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

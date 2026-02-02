-- Down Migration 20260202203218: add_process_tasks_mode_parameter
BEGIN;

-- Drop the new procedure signature (with p_mode parameter)
DROP PROCEDURE IF EXISTS worker.process_tasks(integer, integer, text, bigint, worker.process_mode);

-- Restore original process_tasks without p_mode parameter
CREATE OR REPLACE PROCEDURE worker.process_tasks(IN p_batch_size integer DEFAULT NULL::integer, IN p_max_runtime_ms integer DEFAULT NULL::integer, IN p_queue text DEFAULT NULL::text, IN p_max_priority bigint DEFAULT NULL::bigint)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
  task_record RECORD;
  start_time TIMESTAMPTZ;
  batch_start_time TIMESTAMPTZ;
  elapsed_ms NUMERIC;
  processed_count INT := 0;
  v_inside_transaction BOOLEAN;
  v_waiting_parent_id BIGINT;
BEGIN
  -- Check if we're inside a transaction
  SELECT pg_current_xact_id_if_assigned() IS NOT NULL INTO v_inside_transaction;
  RAISE DEBUG 'Running worker.process_tasks inside transaction: %, queue: %', v_inside_transaction, p_queue;

  batch_start_time := clock_timestamp();

  -- Process tasks in a loop until we hit limits or run out of tasks
  LOOP
    -- Check for time limit
    IF p_max_runtime_ms IS NOT NULL AND
       EXTRACT(EPOCH FROM (clock_timestamp() - batch_start_time)) * 1000 > p_max_runtime_ms THEN
      RAISE DEBUG 'Exiting worker loop: Time limit of % ms reached', p_max_runtime_ms;
      EXIT;
    END IF;

    -- STRUCTURED CONCURRENCY: Check if there's a waiting parent task
    -- If so, we're in concurrent mode and should pick its children
    SELECT t.id INTO v_waiting_parent_id
    FROM worker.tasks t
    JOIN worker.command_registry cr ON t.command = cr.command
    WHERE t.state = 'waiting'::worker.task_state
      AND (p_queue IS NULL OR cr.queue = p_queue)
    ORDER BY t.priority, t.id
    LIMIT 1;

    IF v_waiting_parent_id IS NOT NULL THEN
      -- CONCURRENT MODE: Pick a pending child of the waiting parent
      RAISE DEBUG 'Concurrent mode: picking child of waiting parent %', v_waiting_parent_id;
      
      SELECT t.*, cr.handler_procedure, cr.before_procedure, cr.after_procedure, cr.queue
      INTO task_record
      FROM worker.tasks t
      JOIN worker.command_registry cr ON t.command = cr.command
      WHERE t.state = 'pending'::worker.task_state
        AND t.parent_id = v_waiting_parent_id
        AND (t.scheduled_at IS NULL OR t.scheduled_at <= clock_timestamp())
        AND (p_max_priority IS NULL OR t.priority <= p_max_priority)
      ORDER BY t.priority ASC NULLS LAST, t.id
      LIMIT 1
      FOR UPDATE OF t SKIP LOCKED;
    ELSE
      -- SERIAL MODE: Pick a top-level pending task (parent_id IS NULL)
      RAISE DEBUG 'Serial mode: picking top-level task';
      
      SELECT t.*, cr.handler_procedure, cr.before_procedure, cr.after_procedure, cr.queue
      INTO task_record
      FROM worker.tasks t
      JOIN worker.command_registry cr ON t.command = cr.command
      WHERE t.state = 'pending'::worker.task_state
        AND t.parent_id IS NULL
        AND (t.scheduled_at IS NULL OR t.scheduled_at <= clock_timestamp())
        AND (p_queue IS NULL OR cr.queue = p_queue)
        AND (p_max_priority IS NULL OR t.priority <= p_max_priority)
      ORDER BY
        CASE WHEN t.scheduled_at IS NULL THEN 0 ELSE 1 END,
        t.scheduled_at,
        t.priority ASC NULLS LAST,
        t.id
      LIMIT 1
      FOR UPDATE OF t SKIP LOCKED;
    END IF;

    -- Exit if no more tasks
    IF NOT FOUND THEN
      RAISE DEBUG 'Exiting worker loop: No more pending tasks found';
      EXIT;
    END IF;

    -- Process the task
    start_time := clock_timestamp();

    -- Mark as processing and record the current backend PID
    UPDATE worker.tasks AS t
    SET state = 'processing'::worker.task_state,
        worker_pid = pg_backend_pid()
    WHERE t.id = task_record.id;

    -- Call before_procedure if defined
    IF task_record.before_procedure IS NOT NULL THEN
      BEGIN
        RAISE DEBUG 'Calling before_procedure: % for task % (%)', task_record.before_procedure, task_record.id, task_record.command;
        EXECUTE format('CALL %s()', task_record.before_procedure);
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Error in before_procedure % for task %: %', task_record.before_procedure, task_record.id, SQLERRM;
      END;
    END IF;

    -- Commit to see state change (only if not in a test transaction)
    IF NOT v_inside_transaction THEN
      COMMIT;
    END IF;

    DECLARE
      v_state worker.task_state;
      v_processed_at TIMESTAMPTZ;
      v_completed_at TIMESTAMPTZ;
      v_duration_ms NUMERIC;
      v_error TEXT DEFAULT NULL;
      v_has_children BOOLEAN;
    BEGIN
      DECLARE
        v_message_text TEXT;
        v_pg_exception_detail TEXT;
        v_pg_exception_hint TEXT;
        v_pg_exception_context TEXT;
      BEGIN
        -- Execute the handler procedure
        IF task_record.handler_procedure IS NOT NULL THEN
          EXECUTE format('CALL %s($1)', task_record.handler_procedure)
          USING task_record.payload;
        ELSE
          RAISE EXCEPTION 'No handler procedure found for command: %', task_record.command;
        END IF;

        -- Handler completed successfully
        elapsed_ms := EXTRACT(EPOCH FROM (clock_timestamp() - start_time)) * 1000;
        v_processed_at := clock_timestamp();
        v_duration_ms := elapsed_ms;

        -- STRUCTURED CONCURRENCY: Check if handler spawned children
        SELECT EXISTS (
          SELECT 1 FROM worker.tasks WHERE parent_id = task_record.id
        ) INTO v_has_children;

        IF v_has_children THEN
          -- Task spawned children: go to 'waiting' state
          v_state := 'waiting'::worker.task_state;
          v_completed_at := NULL;  -- Not completed yet, waiting for children
          RAISE DEBUG 'Task % (%) spawned children, entering waiting state', task_record.id, task_record.command;
        ELSE
          -- No children: task is completed
          v_state := 'completed'::worker.task_state;
          v_completed_at := clock_timestamp();
          RAISE DEBUG 'Task % (%) completed in % ms', task_record.id, task_record.command, elapsed_ms;
        END IF;

      EXCEPTION WHEN OTHERS THEN
        elapsed_ms := EXTRACT(EPOCH FROM (clock_timestamp() - start_time)) * 1000;
        v_state := 'failed'::worker.task_state;
        v_processed_at := clock_timestamp();
        v_completed_at := clock_timestamp();
        v_duration_ms := elapsed_ms;

        GET STACKED DIAGNOSTICS
          v_message_text = MESSAGE_TEXT,
          v_pg_exception_detail = PG_EXCEPTION_DETAIL,
          v_pg_exception_hint = PG_EXCEPTION_HINT,
          v_pg_exception_context = PG_EXCEPTION_CONTEXT;

        v_error := format(
          'Error: %s%sContext: %s%sDetail: %s%sHint: %s',
          v_message_text, E'\n',
          v_pg_exception_context, E'\n',
          COALESCE(v_pg_exception_detail, ''), E'\n',
          COALESCE(v_pg_exception_hint, '')
        );

        RAISE WARNING 'Task % (%) failed in % ms: %', task_record.id, task_record.command, elapsed_ms, v_error;
      END;

      -- Update the task with results
      UPDATE worker.tasks AS t
      SET state = v_state,
          processed_at = v_processed_at,
          completed_at = v_completed_at,
          duration_ms = v_duration_ms,
          error = v_error
      WHERE t.id = task_record.id;

      -- STRUCTURED CONCURRENCY: If this was a child and it completed/failed, check parent
      IF task_record.parent_id IS NOT NULL AND v_state IN ('completed', 'failed') THEN
        PERFORM worker.complete_parent_if_ready(task_record.id);
      END IF;

      -- Call after_procedure if defined
      IF task_record.after_procedure IS NOT NULL THEN
        BEGIN
          RAISE DEBUG 'Calling after_procedure: % for task % (%)', task_record.after_procedure, task_record.id, task_record.command;
          EXECUTE format('CALL %s()', task_record.after_procedure);
        EXCEPTION WHEN OTHERS THEN
          RAISE WARNING 'Error in after_procedure % for task %: %', task_record.after_procedure, task_record.id, SQLERRM;
        END;
      END IF;

      -- Commit if not in transaction
      IF NOT v_inside_transaction THEN
        COMMIT;
      END IF;
    END;

    -- Increment processed count and check batch limit
    processed_count := processed_count + 1;
    IF p_batch_size IS NOT NULL AND processed_count >= p_batch_size THEN
      RAISE DEBUG 'Exiting worker loop: Batch size limit of % reached', p_batch_size;
      EXIT;
    END IF;
  END LOOP;
END;
$procedure$;

-- Drop the enum type
DROP TYPE IF EXISTS worker.process_mode;

END;

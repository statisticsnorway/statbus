-- Migration 20260224131241: fix_stale_pipeline_progress_for_child_tasks
--
-- Bug: Step A in process_tasks inserted a pipeline_progress row for EVERY
-- analytics task, including child tasks. Child tasks (e.g.,
-- derive_statistical_unit_facet_partition) got their own rows but step D's
-- cleanup has a race condition when concurrent siblings complete: each child
-- sees the others as still 'processing' (not yet committed), so no child
-- deletes the orphaned row. Meanwhile complete_parent_if_ready only cleans
-- the parent's step, not the child's.
--
-- Fix: Guard step A to only insert for top-level tasks (parent_id IS NULL).
-- Child progress is already tracked via the parent's total/completed counters
-- in steps B and C.
BEGIN;

-- Clean up any stale pipeline_progress rows left by the bug
DELETE FROM worker.pipeline_progress AS pp
WHERE NOT EXISTS (
  SELECT 1 FROM worker.tasks AS t
  WHERE t.command = pp.step
  AND t.state IN ('pending', 'processing', 'waiting')
);

CREATE OR REPLACE PROCEDURE worker.process_tasks(IN p_batch_size integer DEFAULT NULL::integer, IN p_max_runtime_ms integer DEFAULT NULL::integer, IN p_queue text DEFAULT NULL::text, IN p_max_priority bigint DEFAULT NULL::bigint, IN p_mode worker.process_mode DEFAULT NULL::worker.process_mode)
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
  -- Retry-on-deadlock configuration
  v_max_retries CONSTANT INT := 3;
  v_retry_count INT;
  v_backoff_base_ms CONSTANT NUMERIC := 100;  -- 100ms base backoff
BEGIN
  -- Check if we're inside a transaction
  SELECT pg_current_xact_id_if_assigned() IS NOT NULL INTO v_inside_transaction;
  RAISE DEBUG 'Running worker.process_tasks inside transaction: %, queue: %, mode: %', v_inside_transaction, p_queue, COALESCE(p_mode::text, 'NULL');

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
    FROM worker.tasks AS t
    JOIN worker.command_registry AS cr ON t.command = cr.command
    WHERE t.state = 'waiting'::worker.task_state
      AND (p_queue IS NULL OR cr.queue = p_queue)
    ORDER BY t.priority, t.id
    LIMIT 1;

    -- MODE-SPECIFIC BEHAVIOR
    IF p_mode = 'top' THEN
      -- TOP MODE: Only process top-level tasks
      -- If a waiting parent exists, children need processing first - return immediately
      IF v_waiting_parent_id IS NOT NULL THEN
        RAISE DEBUG 'Top mode: waiting parent % exists, returning to let children process', v_waiting_parent_id;
        EXIT;
      END IF;

      -- Pick a top-level pending task (parent_id IS NULL)
      RAISE DEBUG 'Top mode: picking top-level task';

      SELECT t.*, cr.handler_procedure, cr.before_procedure, cr.after_procedure, cr.queue
      INTO task_record
      FROM worker.tasks AS t
      JOIN worker.command_registry AS cr ON t.command = cr.command
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

    ELSIF p_mode = 'child' THEN
      -- CHILD MODE: Only process children of waiting parents
      -- If no waiting parent exists, there's nothing for children to do - return immediately
      IF v_waiting_parent_id IS NULL THEN
        RAISE DEBUG 'Child mode: no waiting parent, returning';
        EXIT;
      END IF;

      -- Pick a pending child of the waiting parent
      RAISE DEBUG 'Child mode: picking child of waiting parent %', v_waiting_parent_id;

      SELECT t.*, cr.handler_procedure, cr.before_procedure, cr.after_procedure, cr.queue
      INTO task_record
      FROM worker.tasks AS t
      JOIN worker.command_registry AS cr ON t.command = cr.command
      WHERE t.state = 'pending'::worker.task_state
        AND t.parent_id = v_waiting_parent_id
        AND (t.scheduled_at IS NULL OR t.scheduled_at <= clock_timestamp())
        AND (p_max_priority IS NULL OR t.priority <= p_max_priority)
      ORDER BY t.priority ASC NULLS LAST, t.id
      LIMIT 1
      FOR UPDATE OF t SKIP LOCKED;

    ELSE
      -- NULL MODE (backward compatible): Original behavior
      -- Pick children if waiting parent exists, otherwise top-level task
      IF v_waiting_parent_id IS NOT NULL THEN
        -- CONCURRENT MODE: Pick a pending child of the waiting parent
        RAISE DEBUG 'Concurrent mode: picking child of waiting parent %', v_waiting_parent_id;

        SELECT t.*, cr.handler_procedure, cr.before_procedure, cr.after_procedure, cr.queue
        INTO task_record
        FROM worker.tasks AS t
        JOIN worker.command_registry AS cr ON t.command = cr.command
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
        FROM worker.tasks AS t
        JOIN worker.command_registry AS cr ON t.command = cr.command
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

    -- PIPELINE PROGRESS (A): Track task start for top-level analytics tasks only.
    -- Child tasks don't get their own rows — their progress is tracked via
    -- the parent's total/completed counters (steps B and C).
    IF task_record.queue = 'analytics' AND task_record.parent_id IS NULL THEN
      INSERT INTO worker.pipeline_progress (step, total, completed, updated_at)
      VALUES (task_record.command, 0, 0, clock_timestamp())
      ON CONFLICT (step) DO NOTHING;
    END IF;

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
      v_child_count INT;
    BEGIN
      -- Initialize retry counter for this task
      v_retry_count := 0;

      -- RETRY LOOP for handling transient errors (deadlocks, serialization failures)
      <<retry_loop>>
      LOOP
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

          -- Handler completed successfully - exit retry loop
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

            -- PIPELINE PROGRESS (B): Parent going to waiting, track child count
            IF task_record.queue = 'analytics' THEN
              SELECT count(*)::int INTO v_child_count
              FROM worker.tasks WHERE parent_id = task_record.id;

              UPDATE worker.pipeline_progress
              SET total = total + v_child_count,
                  updated_at = clock_timestamp()
              WHERE step = task_record.command;
            END IF;

            RAISE DEBUG 'Task % (%) spawned % children, entering waiting state', task_record.id, task_record.command, v_child_count;
          ELSE
            -- No children: task is completed
            v_state := 'completed'::worker.task_state;
            v_completed_at := clock_timestamp();
            RAISE DEBUG 'Task % (%) completed in % ms', task_record.id, task_record.command, elapsed_ms;
          END IF;

          EXIT retry_loop;  -- Success, exit the retry loop

        EXCEPTION
          WHEN deadlock_detected THEN
            -- DEADLOCK: Retry with exponential backoff
            v_retry_count := v_retry_count + 1;
            IF v_retry_count <= v_max_retries THEN
              RAISE WARNING 'Task % (%) deadlock detected, retry %/% after % ms',
                task_record.id, task_record.command, v_retry_count, v_max_retries,
                round(v_backoff_base_ms * power(2, v_retry_count - 1));
              -- Exponential backoff with jitter
              PERFORM pg_sleep((v_backoff_base_ms * power(2, v_retry_count - 1) + (random() * 50)) / 1000.0);
              CONTINUE retry_loop;  -- Retry the task
            ELSE
              -- Max retries exceeded - fall through to error handling
              RAISE WARNING 'Task % (%) max retries (%) exceeded for deadlock',
                task_record.id, task_record.command, v_max_retries;
            END IF;

            -- Capture error details for failed task
            elapsed_ms := EXTRACT(EPOCH FROM (clock_timestamp() - start_time)) * 1000;
            v_state := 'failed'::worker.task_state;
            v_processed_at := clock_timestamp();
            v_completed_at := clock_timestamp();
            v_duration_ms := elapsed_ms;
            v_error := format('Deadlock detected after %s retries', v_retry_count);
            EXIT retry_loop;

          WHEN serialization_failure THEN
            -- SERIALIZATION FAILURE: Retry with exponential backoff
            v_retry_count := v_retry_count + 1;
            IF v_retry_count <= v_max_retries THEN
              RAISE WARNING 'Task % (%) serialization failure, retry %/% after % ms',
                task_record.id, task_record.command, v_retry_count, v_max_retries,
                round(v_backoff_base_ms * power(2, v_retry_count - 1));
              PERFORM pg_sleep((v_backoff_base_ms * power(2, v_retry_count - 1) + (random() * 50)) / 1000.0);
              CONTINUE retry_loop;
            ELSE
              RAISE WARNING 'Task % (%) max retries (%) exceeded for serialization failure',
                task_record.id, task_record.command, v_max_retries;
            END IF;

            elapsed_ms := EXTRACT(EPOCH FROM (clock_timestamp() - start_time)) * 1000;
            v_state := 'failed'::worker.task_state;
            v_processed_at := clock_timestamp();
            v_completed_at := clock_timestamp();
            v_duration_ms := elapsed_ms;
            v_error := format('Serialization failure after %s retries', v_retry_count);
            EXIT retry_loop;

          WHEN OTHERS THEN
            -- OTHER ERRORS: Don't retry, fail immediately
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
            EXIT retry_loop;
        END;
      END LOOP retry_loop;

      -- Update the task with results
      UPDATE worker.tasks AS t
      SET state = v_state,
          processed_at = v_processed_at,
          completed_at = v_completed_at,
          duration_ms = v_duration_ms,
          error = v_error
      WHERE t.id = task_record.id;

      -- PIPELINE PROGRESS (D): Clean up completed leaf tasks
      IF task_record.queue = 'analytics' AND v_state IN ('completed', 'failed') AND NOT v_has_children THEN
        DELETE FROM worker.pipeline_progress
        WHERE step = task_record.command
        AND NOT EXISTS (
          SELECT 1 FROM worker.tasks
          WHERE command = task_record.command
          AND state IN ('pending', 'processing', 'waiting')
          AND id != task_record.id
        );
      END IF;

      -- STRUCTURED CONCURRENCY: For test transactions, check parent inline
      -- (all changes are visible within the same transaction)
      IF v_inside_transaction AND task_record.parent_id IS NOT NULL AND v_state IN ('completed', 'failed') THEN
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

      -- STRUCTURED CONCURRENCY: Post-commit parent check (RACE CONDITION FIX)
      -- After COMMIT, a new READ COMMITTED snapshot sees all sibling completions.
      -- The last fiber to reach this point will see all siblings as completed and
      -- will complete the parent. If two fibers reach it simultaneously, both try
      -- UPDATE ... WHERE state = 'waiting' — one succeeds, the other matches 0 rows.
      IF NOT v_inside_transaction AND task_record.parent_id IS NOT NULL AND v_state IN ('completed', 'failed') THEN
        PERFORM worker.complete_parent_if_ready(task_record.id);
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

END;

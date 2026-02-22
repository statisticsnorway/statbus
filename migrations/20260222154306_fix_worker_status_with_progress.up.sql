-- Migration 20260222154306: fix_worker_status_with_progress
--
-- Fixes:
-- 1. is_deriving_statistical_units() only checked 1 of 4 Phase 1 commands
-- 2. is_deriving_reports() only checked 1 of 10 Phase 2 commands
-- 3. All three notify_*_stop() procedures blindly sent status: false
-- 4. Only 2 of 14 analytics commands had notification hooks
-- 5. pipeline_progress table existed but was never populated
-- 6. All three functions returned boolean only (no granular progress)
-- 7. Import already tracked progress in import_job but is_importing() didn't expose it
BEGIN;

-- ============================================================================
-- Drop existing boolean-returning functions so we can recreate with jsonb return type
-- (PostgreSQL does not allow changing return type with CREATE OR REPLACE)
-- ============================================================================
DROP FUNCTION IF EXISTS public.is_importing();
DROP FUNCTION IF EXISTS public.is_deriving_statistical_units();
DROP FUNCTION IF EXISTS public.is_deriving_reports();

-- ============================================================================
-- Step 1: Change is_importing() to return jsonb with progress from import_job
-- ============================================================================
CREATE OR REPLACE FUNCTION public.is_importing()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $is_importing$
  SELECT jsonb_build_object(
    'active', EXISTS (
      SELECT 1 FROM public.import_job
      WHERE state IN ('analysing_data', 'processing_data')
    ),
    'jobs', COALESCE(
      (SELECT jsonb_agg(jsonb_build_object(
        'id', ij.id,
        'state', ij.state,
        'total_rows', ij.total_rows,
        'imported_rows', ij.imported_rows,
        'analysis_completed_pct', ij.analysis_completed_pct,
        'import_completed_pct', ij.import_completed_pct
      )) FROM public.import_job AS ij
      WHERE ij.state IN ('analysing_data', 'processing_data')),
      '[]'::jsonb
    )
  );
$is_importing$;

-- ============================================================================
-- Step 2: Change is_deriving_statistical_units() to return jsonb from pipeline_progress
-- Checks ALL Phase 1 commands, not just derive_statistical_unit
-- ============================================================================
CREATE OR REPLACE FUNCTION public.is_deriving_statistical_units()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $is_deriving_statistical_units$
  SELECT jsonb_build_object(
    'active', EXISTS (
      SELECT 1 FROM worker.pipeline_progress
      WHERE step IN (
        'derive_statistical_unit',
        'derive_statistical_unit_continue',
        'statistical_unit_refresh_batch',
        'statistical_unit_flush_staging'
      )
    ),
    'progress', COALESCE(
      (SELECT jsonb_agg(jsonb_build_object(
        'step', pp.step, 'total', pp.total, 'completed', pp.completed
      )) FROM worker.pipeline_progress AS pp
      WHERE pp.step IN (
        'derive_statistical_unit',
        'derive_statistical_unit_continue'
      )
        AND pp.total > 1),
      '[]'::jsonb
    )
  );
$is_deriving_statistical_units$;

-- ============================================================================
-- Step 3: Change is_deriving_reports() to return jsonb from pipeline_progress
-- Checks ALL Phase 2 commands, not just derive_reports
-- ============================================================================
CREATE OR REPLACE FUNCTION public.is_deriving_reports()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $is_deriving_reports$
  SELECT jsonb_build_object(
    'active', EXISTS (
      SELECT 1 FROM worker.pipeline_progress
      WHERE step IN (
        'derive_reports',
        'derive_statistical_history',
        'derive_statistical_history_period',
        'statistical_history_reduce',
        'derive_statistical_unit_facet',
        'derive_statistical_unit_facet_partition',
        'statistical_unit_facet_reduce',
        'derive_statistical_history_facet',
        'derive_statistical_history_facet_period',
        'statistical_history_facet_reduce'
      )
    ),
    'progress', COALESCE(
      (SELECT jsonb_agg(jsonb_build_object(
        'step', pp.step, 'total', pp.total, 'completed', pp.completed
      )) FROM worker.pipeline_progress AS pp
      WHERE pp.step IN (
        'derive_statistical_history',
        'derive_statistical_unit_facet',
        'derive_statistical_history_facet'
      )
        AND pp.total > 1),
      '[]'::jsonb
    )
  );
$is_deriving_reports$;

-- Re-grant EXECUTE to authenticated role (DROP removed the grants)
GRANT EXECUTE ON FUNCTION public.is_importing() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_deriving_statistical_units() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_deriving_reports() TO authenticated;

-- Grant DML on pipeline_progress to authenticated (process_tasks runs as caller)
GRANT INSERT, UPDATE, DELETE ON worker.pipeline_progress TO authenticated;

-- ============================================================================
-- Step 4: Fix notify stop procedures to re-check actual state
-- ============================================================================
CREATE OR REPLACE PROCEDURE worker.notify_is_importing_stop()
 LANGUAGE plpgsql
AS $notify_is_importing_stop$
BEGIN
  PERFORM pg_notify('worker_status',
    json_build_object(
      'type', 'is_importing',
      'status', (public.is_importing()->>'active')::boolean
    )::text
  );
END;
$notify_is_importing_stop$;

CREATE OR REPLACE PROCEDURE worker.notify_is_deriving_statistical_units_stop()
 LANGUAGE plpgsql
AS $notify_is_deriving_statistical_units_stop$
BEGIN
  PERFORM pg_notify('worker_status',
    json_build_object(
      'type', 'is_deriving_statistical_units',
      'status', (public.is_deriving_statistical_units()->>'active')::boolean
    )::text
  );
END;
$notify_is_deriving_statistical_units_stop$;

CREATE OR REPLACE PROCEDURE worker.notify_is_deriving_reports_stop()
 LANGUAGE plpgsql
AS $notify_is_deriving_reports_stop$
BEGIN
  PERFORM pg_notify('worker_status',
    json_build_object(
      'type', 'is_deriving_reports',
      'status', (public.is_deriving_reports()->>'active')::boolean
    )::text
  );
END;
$notify_is_deriving_reports_stop$;

-- ============================================================================
-- Step 5: Update complete_parent_if_ready to manage pipeline_progress
-- ============================================================================
CREATE OR REPLACE FUNCTION worker.complete_parent_if_ready(p_child_task_id bigint)
 RETURNS boolean
 LANGUAGE plpgsql
AS $complete_parent_if_ready$
DECLARE
    v_parent_id BIGINT;
    v_parent_command TEXT;
    v_child_command TEXT;
    v_parent_completed BOOLEAN := FALSE;
    v_any_failed BOOLEAN;
    v_parent_queue TEXT;
BEGIN
    -- Get the parent_id and child command from the child task
    SELECT parent_id, command INTO v_parent_id, v_child_command
    FROM worker.tasks
    WHERE id = p_child_task_id;

    -- If no parent, nothing to do
    IF v_parent_id IS NULL THEN
        RETURN FALSE;
    END IF;

    -- Get parent command and queue
    SELECT t.command, cr.queue INTO v_parent_command, v_parent_queue
    FROM worker.tasks AS t
    JOIN worker.command_registry AS cr ON t.command = cr.command
    WHERE t.id = v_parent_id;

    -- PIPELINE PROGRESS: Track child completion for analytics queue
    IF v_parent_queue = 'analytics' THEN
      UPDATE worker.pipeline_progress
      SET completed = completed + 1,
          updated_at = clock_timestamp()
      WHERE step = v_parent_command;

      -- Send progress notification
      PERFORM pg_notify('worker_status',
        json_build_object(
          'type', 'pipeline_progress',
          'steps', COALESCE(
            (SELECT json_agg(json_build_object(
              'step', pp.step, 'total', pp.total, 'completed', pp.completed
            )) FROM worker.pipeline_progress AS pp),
            '[]'::json
          )
        )::text
      );
    END IF;

    -- Check if parent still has pending children
    IF worker.has_pending_children(v_parent_id) THEN
        RETURN FALSE;
    END IF;

    -- All children done - check for failures
    SELECT EXISTS (
        SELECT 1 FROM worker.tasks
        WHERE parent_id = v_parent_id AND state = 'failed'
    ) INTO v_any_failed;

    IF v_any_failed THEN
        -- Parent fails because a child failed
        UPDATE worker.tasks
        SET state = 'failed',
            completed_at = clock_timestamp(),
            error = 'One or more child tasks failed'
        WHERE id = v_parent_id AND state = 'waiting';
    ELSE
        -- All children succeeded - parent completes
        UPDATE worker.tasks
        SET state = 'completed',
            completed_at = clock_timestamp()
        WHERE id = v_parent_id AND state = 'waiting';
    END IF;

    IF FOUND THEN
        v_parent_completed := TRUE;
        RAISE DEBUG 'complete_parent_if_ready: Parent task % completed (failed=%)', v_parent_id, v_any_failed;

        -- PIPELINE PROGRESS: Clean up parent's step when it completes
        IF v_parent_queue = 'analytics' THEN
          DELETE FROM worker.pipeline_progress WHERE step = v_parent_command;
        END IF;
    END IF;

    RETURN v_parent_completed;
END;
$complete_parent_if_ready$;

-- ============================================================================
-- Step 6: Update process_tasks with pipeline_progress lifecycle
-- ============================================================================
CREATE OR REPLACE PROCEDURE worker.process_tasks(IN p_batch_size integer DEFAULT NULL::integer, IN p_max_runtime_ms integer DEFAULT NULL::integer, IN p_queue text DEFAULT NULL::text, IN p_max_priority bigint DEFAULT NULL::bigint, IN p_mode worker.process_mode DEFAULT NULL::worker.process_mode)
 LANGUAGE plpgsql
AS $process_tasks$
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

    -- PIPELINE PROGRESS (A): Track task start for analytics queue
    IF task_record.queue = 'analytics' THEN
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
$process_tasks$;

-- ============================================================================
-- Step 7: Add notification hooks to analytics commands that were missing them
-- ============================================================================

-- Phase 1 commands: notify_is_deriving_statistical_units_stop
UPDATE worker.command_registry
SET after_procedure = 'worker.notify_is_deriving_statistical_units_stop'
WHERE command IN (
  'derive_statistical_unit_continue',
  'statistical_unit_flush_staging'
)
AND after_procedure IS NULL;

-- Phase 2 commands: notify_is_deriving_reports_stop
UPDATE worker.command_registry
SET after_procedure = 'worker.notify_is_deriving_reports_stop'
WHERE command IN (
  'derive_statistical_history',
  'derive_statistical_unit_facet',
  'derive_statistical_history_facet',
  'statistical_unit_facet_reduce',
  'statistical_history_reduce',
  'statistical_history_facet_reduce'
)
AND after_procedure IS NULL;

END;

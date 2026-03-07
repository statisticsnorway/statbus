BEGIN;

-- ============================================================================
-- 1a. Create pipeline_phase enum and recreate pipeline_progress table
-- ============================================================================

CREATE TYPE worker.pipeline_phase AS ENUM (
    'is_deriving_statistical_units',
    'is_deriving_reports'
);

DROP TABLE worker.pipeline_progress;

CREATE UNLOGGED TABLE worker.pipeline_progress (
    phase worker.pipeline_phase PRIMARY KEY,
    step TEXT,
    total INT NOT NULL DEFAULT 0,
    completed INT NOT NULL DEFAULT 0,
    affected_establishment_count INT DEFAULT NULL,
    affected_legal_unit_count INT DEFAULT NULL,
    affected_enterprise_count INT DEFAULT NULL,
    affected_power_group_count INT DEFAULT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

GRANT SELECT ON worker.pipeline_progress TO authenticated;
GRANT INSERT, UPDATE, DELETE ON worker.pipeline_progress TO authenticated;

-- ============================================================================
-- 1a2. Pipeline step weights table
-- ============================================================================

-- Stores the relative wall-clock weight of each step within its phase.
-- Used by the frontend to compute weighted progress percentages.
-- Weights are proportional (not required to sum to 100).
CREATE TABLE worker.pipeline_step_weight (
    phase worker.pipeline_phase NOT NULL,
    step TEXT NOT NULL,
    weight INT NOT NULL CHECK (weight > 0),
    seq INT NOT NULL DEFAULT 0,
    PRIMARY KEY (phase, step),
    FOREIGN KEY (step) REFERENCES worker.command_registry(command)
);

COMMENT ON TABLE worker.pipeline_step_weight IS
  'Relative wall-clock weights for pipeline steps, used by frontend progress bars. '
  'When adding a new step to a phase, add its weight here too.';

-- Phase 1 weights derived from production wall-clock times (no.statbus.org, 2026-02-24).
-- Dataset: 1.1M legal units + 826K establishments, analytics_partition_count=128.
INSERT INTO worker.pipeline_step_weight (phase, step, weight, seq) VALUES
  ('is_deriving_statistical_units', 'collect_changes', 1, 0),
  ('is_deriving_statistical_units', 'derive_statistical_unit', 87, 1),
  ('is_deriving_statistical_units', 'statistical_unit_flush_staging', 14, 2);

-- Phase 2 weights from same dataset.
INSERT INTO worker.pipeline_step_weight (phase, step, weight, seq) VALUES
  ('is_deriving_reports', 'derive_reports', 1, 0),
  ('is_deriving_reports', 'derive_statistical_history', 2, 1),
  ('is_deriving_reports', 'derive_statistical_unit_facet', 2, 2),
  ('is_deriving_reports', 'statistical_unit_facet_reduce', 3, 3),
  ('is_deriving_reports', 'derive_statistical_history_facet', 84, 4),
  ('is_deriving_reports', 'statistical_history_facet_reduce', 9, 5);

-- View for frontend access via PostgREST (/rest/pipeline_step_weight).
-- Read-only: the UNION ALL prevents PostgreSQL from marking it as auto-updatable.
CREATE VIEW public.pipeline_step_weight WITH (security_invoker = on) AS
SELECT phase::text, step, weight, seq
FROM worker.pipeline_step_weight
UNION ALL
SELECT NULL::text, NULL::text, NULL::integer, NULL::integer WHERE false;

GRANT SELECT ON public.pipeline_step_weight TO authenticated, regular_user, admin_user;

-- Worker needs SELECT on the base table for pipeline_progress_on_children_created
-- (checks if a command has a weight entry before setting the step field).
GRANT SELECT ON worker.pipeline_step_weight TO authenticated;

-- ============================================================================
-- 1a3. Helper function to notify frontend about pipeline progress
-- ============================================================================

CREATE OR REPLACE FUNCTION worker.notify_pipeline_progress()
RETURNS void
LANGUAGE plpgsql
AS $notify_pipeline_progress$
BEGIN
    PERFORM pg_notify('worker_status', (
        SELECT json_build_object(
            'type', 'pipeline_progress',
            'phases', COALESCE(json_agg(json_build_object(
                'phase', pp.phase,
                'step', pp.step,
                'total', pp.total,
                'completed', pp.completed,
                'affected_establishment_count', pp.affected_establishment_count,
                'affected_legal_unit_count', pp.affected_legal_unit_count,
                'affected_enterprise_count', pp.affected_enterprise_count,
                'affected_power_group_count', pp.affected_power_group_count
            )), '[]'::json)
        )::text
        FROM worker.pipeline_progress AS pp
    ));
END;
$notify_pipeline_progress$;

-- ============================================================================
-- 1b. Add phase column to command_registry
-- ============================================================================

ALTER TABLE worker.command_registry ADD COLUMN phase worker.pipeline_phase DEFAULT NULL;

UPDATE worker.command_registry SET phase = 'is_deriving_statistical_units'
WHERE command IN (
  'collect_changes',
  'derive_statistical_unit', 'derive_statistical_unit_continue',
  'statistical_unit_refresh_batch', 'statistical_unit_flush_staging'
);

UPDATE worker.command_registry SET phase = 'is_deriving_reports'
WHERE command IN (
  'derive_reports',
  'derive_statistical_history', 'derive_statistical_history_period', 'statistical_history_reduce',
  'derive_statistical_unit_facet', 'derive_statistical_unit_facet_partition', 'statistical_unit_facet_reduce',
  'derive_statistical_history_facet', 'derive_statistical_history_facet_period', 'statistical_history_facet_reduce'
);

-- ============================================================================
-- 1b2. Add lifecycle hook columns to command_registry
--      Stores complete call expressions with bound phase argument.
--      The generic worker just does EXECUTE format('CALL %s', hook) USING ...
-- ============================================================================

ALTER TABLE worker.command_registry ADD COLUMN on_children_created TEXT DEFAULT NULL;
ALTER TABLE worker.command_registry ADD COLUMN on_child_completed TEXT DEFAULT NULL;

-- Phase 1 parent commands (spawn children for statistical unit refresh)
UPDATE worker.command_registry
SET on_children_created = $$worker.pipeline_progress_on_children_created('is_deriving_statistical_units'::worker.pipeline_phase, $1, $2)$$,
    on_child_completed  = $$worker.pipeline_progress_on_child_completed('is_deriving_statistical_units'::worker.pipeline_phase, $1)$$
WHERE command IN ('derive_statistical_unit', 'derive_statistical_unit_continue');

-- Remove after_procedure from intermediate Phase 1 commands.
-- Only statistical_unit_flush_staging (the last Phase 1 step) keeps it.
-- Lifecycle hooks (on_child_completed) handle intermediate progress notifications.
-- Without this, next-round collect_changes (pending, phase='is_deriving_statistical_units')
-- causes the stop procedure to see active tasks and keep the Phase 1 progress row.
UPDATE worker.command_registry
SET after_procedure = NULL
WHERE command IN ('derive_statistical_unit', 'derive_statistical_unit_continue');

-- Phase 2 parent commands (spawn children for reports)
-- NOTE: derive_reports is excluded — it enqueues siblings, not children
UPDATE worker.command_registry
SET on_children_created = $$worker.pipeline_progress_on_children_created('is_deriving_reports'::worker.pipeline_phase, $1, $2)$$,
    on_child_completed  = $$worker.pipeline_progress_on_child_completed('is_deriving_reports'::worker.pipeline_phase, $1)$$
WHERE command IN (
    'derive_statistical_history', 'derive_statistical_unit_facet',
    'derive_statistical_history_facet'
);

-- ============================================================================
-- 1b3. Create lifecycle hook callback procedures
-- ============================================================================

CREATE OR REPLACE PROCEDURE worker.pipeline_progress_on_children_created(
    IN p_phase worker.pipeline_phase,
    IN p_parent_task_id BIGINT,
    IN p_child_count INT
)
LANGUAGE plpgsql
AS $pipeline_progress_on_children_created$
DECLARE
    v_parent_command TEXT;
BEGIN
    -- Look up the parent command for the step field
    SELECT command INTO v_parent_command
    FROM worker.tasks WHERE id = p_parent_task_id;

    -- Only set step if the command has a pipeline_step_weight entry
    -- (non-weighted commands like statistical_unit_refresh_batch should not overwrite step)
    IF EXISTS (SELECT 1 FROM worker.pipeline_step_weight WHERE step = v_parent_command AND phase = p_phase) THEN
        UPDATE worker.pipeline_progress
        SET total = total + p_child_count,
            step = v_parent_command,
            updated_at = clock_timestamp()
        WHERE phase = p_phase;
    ELSE
        UPDATE worker.pipeline_progress
        SET total = total + p_child_count,
            updated_at = clock_timestamp()
        WHERE phase = p_phase;
    END IF;
END;
$pipeline_progress_on_children_created$;

CREATE OR REPLACE PROCEDURE worker.pipeline_progress_on_child_completed(
    IN p_phase worker.pipeline_phase,
    IN p_parent_task_id BIGINT
)
LANGUAGE plpgsql
AS $pipeline_progress_on_child_completed$
BEGIN
    UPDATE worker.pipeline_progress
    SET completed = completed + 1,
        updated_at = clock_timestamp()
    WHERE phase = p_phase;

    PERFORM worker.notify_pipeline_progress();
END;
$pipeline_progress_on_child_completed$;

-- ============================================================================
-- 1c. Update notify_*_start — UPSERT phase rows
-- ============================================================================

CREATE OR REPLACE PROCEDURE worker.notify_is_deriving_statistical_units_start()
LANGUAGE plpgsql
AS $procedure$
BEGIN
  INSERT INTO worker.pipeline_progress (phase, step, total, completed, updated_at)
  VALUES ('is_deriving_statistical_units', 'derive_statistical_unit', 0, 0, clock_timestamp())
  ON CONFLICT (phase) DO UPDATE SET
    step = EXCLUDED.step, total = 0, completed = 0,
    -- Don't null counts — they were set by collect_changes and will be
    -- refined by derive_statistical_unit after batching.
    updated_at = clock_timestamp();

  PERFORM pg_notify('worker_status', json_build_object('type', 'is_deriving_statistical_units', 'status', true)::text);
  PERFORM worker.notify_pipeline_progress();
END;
$procedure$;

-- collect_changes needs its own before_procedure because
-- notify_is_deriving_statistical_units_start hardcodes step='derive_statistical_unit'.
-- collect_changes runs first and should show step='collect_changes'.
CREATE PROCEDURE worker.notify_collecting_changes_start()
LANGUAGE plpgsql
AS $notify_collecting_changes_start$
BEGIN
  INSERT INTO worker.pipeline_progress (phase, step, total, completed, updated_at)
  VALUES ('is_deriving_statistical_units', 'collect_changes', 0, 0, clock_timestamp())
  ON CONFLICT (phase) DO UPDATE SET
    step = 'collect_changes', total = 0, completed = 0,
    affected_establishment_count = NULL, affected_legal_unit_count = NULL,
    affected_enterprise_count = NULL, affected_power_group_count = NULL,
    updated_at = clock_timestamp();

  PERFORM pg_notify('worker_status',
    json_build_object('type', 'is_deriving_statistical_units', 'status', true)::text
  );
END;
$notify_collecting_changes_start$;

-- Wire collect_changes to use its own before_procedure
UPDATE worker.command_registry
SET before_procedure = 'worker.notify_collecting_changes_start'
WHERE command = 'collect_changes';

CREATE OR REPLACE PROCEDURE worker.notify_is_deriving_reports_start()
LANGUAGE plpgsql
AS $procedure$
BEGIN
  -- UPSERT phase row: resets progress but preserves unit counts
  -- (counts were pre-populated by derive_statistical_unit)
  INSERT INTO worker.pipeline_progress (phase, step, total, completed, updated_at)
  VALUES ('is_deriving_reports', 'derive_reports', 0, 0, clock_timestamp())
  ON CONFLICT (phase) DO UPDATE SET
    step = EXCLUDED.step, total = 0, completed = 0,
    updated_at = clock_timestamp();

  PERFORM pg_notify('worker_status', json_build_object('type', 'is_deriving_reports', 'status', true)::text);
END;
$procedure$;

-- ============================================================================
-- 1d. Update process_tasks — phase-driven progress tracking
-- ============================================================================

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

      SELECT t.*, cr.handler_procedure, cr.before_procedure, cr.after_procedure, cr.queue, cr.on_children_created
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

      SELECT t.*, cr.handler_procedure, cr.before_procedure, cr.after_procedure, cr.queue, cr.on_children_created
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

        SELECT t.*, cr.handler_procedure, cr.before_procedure, cr.after_procedure, cr.queue, cr.on_children_created
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

        SELECT t.*, cr.handler_procedure, cr.before_procedure, cr.after_procedure, cr.queue, cr.on_children_created
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

    -- Call before_procedure if defined (e.g., notify_*_start UPSERTs phase row)
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

            -- Lifecycle hook: on_children_created (generic — no domain knowledge)
            IF task_record.on_children_created IS NOT NULL THEN
              SELECT count(*)::int INTO v_child_count
              FROM worker.tasks WHERE parent_id = task_record.id;

              EXECUTE format('CALL %s', task_record.on_children_created)
              USING task_record.id, v_child_count;
            END IF;

            RAISE DEBUG 'Task % (%) spawned children, entering waiting state', task_record.id, task_record.command;
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

      -- PIPELINE PROGRESS (D): REMOVED — phase rows persist until notify_stop deletes them

      -- STRUCTURED CONCURRENCY: For test transactions, check parent inline
      -- (all changes are visible within the same transaction)
      IF v_inside_transaction AND task_record.parent_id IS NOT NULL AND v_state IN ('completed', 'failed') THEN
        PERFORM worker.complete_parent_if_ready(task_record.id);
      END IF;

      -- Call after_procedure only for terminal states (completed/failed).
      -- For 'waiting' tasks (spawned children), after_procedure fires later
      -- via complete_parent_if_ready when all children finish.
      IF task_record.after_procedure IS NOT NULL AND v_state IN ('completed', 'failed') THEN
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

-- ============================================================================
-- 1g. Update complete_parent_if_ready — use lifecycle hooks
-- ============================================================================

CREATE OR REPLACE FUNCTION worker.complete_parent_if_ready(p_child_task_id bigint)
 RETURNS boolean
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_parent_id BIGINT;
    v_parent_command TEXT;
    v_child_command TEXT;
    v_parent_completed BOOLEAN := FALSE;
    v_any_failed BOOLEAN;
    v_parent_on_child_completed TEXT;
    v_parent_after_procedure TEXT;
BEGIN
    -- Get the parent_id and child command from the child task
    SELECT parent_id, command INTO v_parent_id, v_child_command
    FROM worker.tasks
    WHERE id = p_child_task_id;

    -- If no parent, nothing to do
    IF v_parent_id IS NULL THEN
        RETURN FALSE;
    END IF;

    -- Get parent command, lifecycle hook, and after_procedure
    SELECT t.command, cr.on_child_completed, cr.after_procedure
    INTO v_parent_command, v_parent_on_child_completed, v_parent_after_procedure
    FROM worker.tasks AS t
    JOIN worker.command_registry AS cr ON t.command = cr.command
    WHERE t.id = v_parent_id;

    -- Lifecycle hook: on_child_completed (generic — no domain knowledge)
    IF v_parent_on_child_completed IS NOT NULL THEN
      EXECUTE format('CALL %s', v_parent_on_child_completed)
      USING v_parent_id;
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

        -- Fire parent's after_procedure now that task is truly complete.
        -- process_tasks skips after_procedure for 'waiting' tasks, so this
        -- is where parent tasks get their after_procedure called.
        IF v_parent_after_procedure IS NOT NULL THEN
          BEGIN
            RAISE DEBUG 'Calling after_procedure: % for completed parent task %', v_parent_after_procedure, v_parent_id;
            EXECUTE format('CALL %s()', v_parent_after_procedure);
          EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'Error in after_procedure % for parent task %: %', v_parent_after_procedure, v_parent_id, SQLERRM;
          END;
        END IF;
    END IF;

    RETURN v_parent_completed;
END;
$function$;

-- ============================================================================
-- 1h. Update derive_statistical_unit — create phase rows with counts
-- ============================================================================

-- NOTE: This function is defined without p_power_group_id_ranges at this point.
-- The power group parameter is added by the integrate_power_group migration.
-- This version includes pipeline progress with notify_pipeline_progress.
CREATE OR REPLACE FUNCTION worker.derive_statistical_unit(p_establishment_id_ranges int4multirange DEFAULT NULL::int4multirange, p_legal_unit_id_ranges int4multirange DEFAULT NULL::int4multirange, p_enterprise_id_ranges int4multirange DEFAULT NULL::int4multirange, p_valid_from date DEFAULT NULL::date, p_valid_until date DEFAULT NULL::date, p_task_id bigint DEFAULT NULL::bigint, p_round_priority_base bigint DEFAULT NULL::bigint)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_batch RECORD;
    v_establishment_ids INT[];
    v_legal_unit_ids INT[];
    v_enterprise_ids INT[];
    v_batch_count INT := 0;
    v_is_full_refresh BOOLEAN;
    v_child_priority BIGINT;
    v_orphan_enterprise_ids INT[];
    v_orphan_legal_unit_ids INT[];
    v_orphan_establishment_ids INT[];
    -- Unit count accumulators for pipeline progress
    v_enterprise_count INT := 0;
    v_legal_unit_count INT := 0;
    v_establishment_count INT := 0;
BEGIN
    v_is_full_refresh := (p_establishment_id_ranges IS NULL
                         AND p_legal_unit_id_ranges IS NULL
                         AND p_enterprise_id_ranges IS NULL);

    -- Priority for children: use round base if available, otherwise nextval
    v_child_priority := COALESCE(p_round_priority_base, nextval('public.worker_task_priority_seq'));

    IF v_is_full_refresh THEN
        -- Full refresh: spawn batch children (no orphan cleanup needed - covers everything)
        -- No dirty partition tracking needed: full refresh recomputes all partitions
        FOR v_batch IN SELECT * FROM public.get_closed_group_batches(p_target_batch_size := 1000)
        LOOP
            v_enterprise_count := v_enterprise_count + COALESCE(array_length(v_batch.enterprise_ids, 1), 0);
            v_legal_unit_count := v_legal_unit_count + COALESCE(array_length(v_batch.legal_unit_ids, 1), 0);
            v_establishment_count := v_establishment_count + COALESCE(array_length(v_batch.establishment_ids, 1), 0);

            PERFORM worker.spawn(
                p_command := 'statistical_unit_refresh_batch',
                p_payload := jsonb_build_object(
                    'command', 'statistical_unit_refresh_batch',
                    'batch_seq', v_batch.batch_seq,
                    'enterprise_ids', v_batch.enterprise_ids,
                    'legal_unit_ids', v_batch.legal_unit_ids,
                    'establishment_ids', v_batch.establishment_ids,
                    'valid_from', p_valid_from,
                    'valid_until', p_valid_until
                ),
                p_parent_id := p_task_id,
                p_priority := v_child_priority
            );
            v_batch_count := v_batch_count + 1;
        END LOOP;
    ELSE
        -- Partial refresh: convert multiranges to arrays
        v_establishment_ids := ARRAY(SELECT generate_series(lower(r), upper(r)-1) FROM unnest(COALESCE(p_establishment_id_ranges, '{}'::int4multirange)) AS t(r));
        v_legal_unit_ids := ARRAY(SELECT generate_series(lower(r), upper(r)-1) FROM unnest(COALESCE(p_legal_unit_id_ranges, '{}'::int4multirange)) AS t(r));
        v_enterprise_ids := ARRAY(SELECT generate_series(lower(r), upper(r)-1) FROM unnest(COALESCE(p_enterprise_id_ranges, '{}'::int4multirange)) AS t(r));

        -- ORPHAN CLEANUP: Handle deleted entities BEFORE batching
        IF COALESCE(array_length(v_enterprise_ids, 1), 0) > 0 THEN
            v_orphan_enterprise_ids := ARRAY(SELECT id FROM unnest(v_enterprise_ids) AS id EXCEPT SELECT e.id FROM public.enterprise AS e WHERE e.id = ANY(v_enterprise_ids));
            IF COALESCE(array_length(v_orphan_enterprise_ids, 1), 0) > 0 THEN
                RAISE DEBUG 'derive_statistical_unit: Cleaning up % orphan enterprise IDs', array_length(v_orphan_enterprise_ids, 1);
                DELETE FROM public.timepoints WHERE unit_type = 'enterprise' AND unit_id = ANY(v_orphan_enterprise_ids);
                DELETE FROM public.timesegments WHERE unit_type = 'enterprise' AND unit_id = ANY(v_orphan_enterprise_ids);
                DELETE FROM public.timeline_enterprise WHERE enterprise_id = ANY(v_orphan_enterprise_ids);
                DELETE FROM public.statistical_unit WHERE unit_type = 'enterprise' AND unit_id = ANY(v_orphan_enterprise_ids);
            END IF;
        END IF;
        IF COALESCE(array_length(v_legal_unit_ids, 1), 0) > 0 THEN
            v_orphan_legal_unit_ids := ARRAY(SELECT id FROM unnest(v_legal_unit_ids) AS id EXCEPT SELECT lu.id FROM public.legal_unit AS lu WHERE lu.id = ANY(v_legal_unit_ids));
            IF COALESCE(array_length(v_orphan_legal_unit_ids, 1), 0) > 0 THEN
                RAISE DEBUG 'derive_statistical_unit: Cleaning up % orphan legal_unit IDs', array_length(v_orphan_legal_unit_ids, 1);
                DELETE FROM public.timepoints WHERE unit_type = 'legal_unit' AND unit_id = ANY(v_orphan_legal_unit_ids);
                DELETE FROM public.timesegments WHERE unit_type = 'legal_unit' AND unit_id = ANY(v_orphan_legal_unit_ids);
                DELETE FROM public.timeline_legal_unit WHERE legal_unit_id = ANY(v_orphan_legal_unit_ids);
                DELETE FROM public.statistical_unit WHERE unit_type = 'legal_unit' AND unit_id = ANY(v_orphan_legal_unit_ids);
            END IF;
        END IF;
        IF COALESCE(array_length(v_establishment_ids, 1), 0) > 0 THEN
            v_orphan_establishment_ids := ARRAY(SELECT id FROM unnest(v_establishment_ids) AS id EXCEPT SELECT es.id FROM public.establishment AS es WHERE es.id = ANY(v_establishment_ids));
            IF COALESCE(array_length(v_orphan_establishment_ids, 1), 0) > 0 THEN
                RAISE DEBUG 'derive_statistical_unit: Cleaning up % orphan establishment IDs', array_length(v_orphan_establishment_ids, 1);
                DELETE FROM public.timepoints WHERE unit_type = 'establishment' AND unit_id = ANY(v_orphan_establishment_ids);
                DELETE FROM public.timesegments WHERE unit_type = 'establishment' AND unit_id = ANY(v_orphan_establishment_ids);
                DELETE FROM public.timeline_establishment WHERE establishment_id = ANY(v_orphan_establishment_ids);
                DELETE FROM public.statistical_unit WHERE unit_type = 'establishment' AND unit_id = ANY(v_orphan_establishment_ids);
            END IF;
        END IF;

        IF to_regclass('pg_temp._batches') IS NOT NULL THEN DROP TABLE _batches; END IF;
        CREATE TEMP TABLE _batches ON COMMIT DROP AS
        SELECT * FROM public.get_closed_group_batches(
            p_target_batch_size := 1000,
            p_establishment_ids := NULLIF(v_establishment_ids, '{}'),
            p_legal_unit_ids := NULLIF(v_legal_unit_ids, '{}'),
            p_enterprise_ids := NULLIF(v_enterprise_ids, '{}')
        );
        INSERT INTO public.statistical_unit_facet_dirty_partitions (partition_seq)
        SELECT DISTINCT public.report_partition_seq(t.unit_type, t.unit_id, (SELECT analytics_partition_count FROM public.settings))
        FROM (
            SELECT 'enterprise'::text AS unit_type, unnest(b.enterprise_ids) AS unit_id FROM _batches AS b
            UNION ALL SELECT 'legal_unit', unnest(b.legal_unit_ids) FROM _batches AS b
            UNION ALL SELECT 'establishment', unnest(b.establishment_ids) FROM _batches AS b
        ) AS t WHERE t.unit_id IS NOT NULL
        ON CONFLICT DO NOTHING;

        FOR v_batch IN SELECT * FROM _batches LOOP
            v_enterprise_count := v_enterprise_count + COALESCE(array_length(v_batch.enterprise_ids, 1), 0);
            v_legal_unit_count := v_legal_unit_count + COALESCE(array_length(v_batch.legal_unit_ids, 1), 0);
            v_establishment_count := v_establishment_count + COALESCE(array_length(v_batch.establishment_ids, 1), 0);

            PERFORM worker.spawn(
                p_command := 'statistical_unit_refresh_batch',
                p_payload := jsonb_build_object(
                    'command', 'statistical_unit_refresh_batch',
                    'batch_seq', v_batch.batch_seq,
                    'enterprise_ids', v_batch.enterprise_ids,
                    'legal_unit_ids', v_batch.legal_unit_ids,
                    'establishment_ids', v_batch.establishment_ids,
                    'valid_from', p_valid_from,
                    'valid_until', p_valid_until
                ),
                p_parent_id := p_task_id,
                p_priority := v_child_priority
            );
            v_batch_count := v_batch_count + 1;
        END LOOP;
    END IF;

    RAISE DEBUG 'derive_statistical_unit: Spawned % batch children with parent_id %, counts: es=%, lu=%, en=%',
        v_batch_count, p_task_id, v_establishment_count, v_legal_unit_count, v_enterprise_count;

    INSERT INTO worker.pipeline_progress
        (phase, step, total, completed,
         affected_establishment_count, affected_legal_unit_count, affected_enterprise_count,
         affected_power_group_count, updated_at)
    VALUES
        ('is_deriving_statistical_units', 'derive_statistical_unit', 0, 0,
         v_establishment_count, v_legal_unit_count, v_enterprise_count,
         0, clock_timestamp())
    ON CONFLICT (phase) DO UPDATE SET
        affected_establishment_count = EXCLUDED.affected_establishment_count,
        affected_legal_unit_count = EXCLUDED.affected_legal_unit_count,
        affected_enterprise_count = EXCLUDED.affected_enterprise_count,
        affected_power_group_count = EXCLUDED.affected_power_group_count,
        updated_at = EXCLUDED.updated_at;

    INSERT INTO worker.pipeline_progress
        (phase, step, total, completed,
         affected_establishment_count, affected_legal_unit_count, affected_enterprise_count,
         affected_power_group_count, updated_at)
    VALUES
        ('is_deriving_reports', NULL, 0, 0,
         v_establishment_count, v_legal_unit_count, v_enterprise_count,
         0, clock_timestamp())
    ON CONFLICT (phase) DO UPDATE SET
        affected_establishment_count = EXCLUDED.affected_establishment_count,
        affected_legal_unit_count = EXCLUDED.affected_legal_unit_count,
        affected_enterprise_count = EXCLUDED.affected_enterprise_count,
        affected_power_group_count = EXCLUDED.affected_power_group_count,
        updated_at = EXCLUDED.updated_at;

    -- Notify frontend with accurate counts
    PERFORM worker.notify_pipeline_progress();

    PERFORM public.activity_category_used_derive();
    PERFORM public.region_used_derive();
    PERFORM public.sector_used_derive();
    PERFORM public.data_source_used_derive();
    PERFORM public.legal_form_used_derive();
    PERFORM public.country_used_derive();

    PERFORM worker.enqueue_statistical_unit_flush_staging(
        p_round_priority_base := p_round_priority_base
    );
    PERFORM worker.enqueue_derive_reports(
        p_valid_from := p_valid_from,
        p_valid_until := p_valid_until,
        p_round_priority_base := p_round_priority_base
    );
END;
$function$;

-- ============================================================================
-- 1i. Update is_deriving_statistical_units — read from phase row
-- ============================================================================

CREATE OR REPLACE FUNCTION public.is_deriving_statistical_units()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
  -- pipeline_progress is the single source of truth:
  -- start procedure creates the row, lifecycle hooks update it, stop procedure deletes it.
  SELECT jsonb_build_object(
    'active', pp.phase IS NOT NULL,
    'step', pp.step,
    'total', COALESCE(pp.total, 0),
    'completed', COALESCE(pp.completed, 0),
    'affected_establishment_count', pp.affected_establishment_count,
    'affected_legal_unit_count', pp.affected_legal_unit_count,
    'affected_enterprise_count', pp.affected_enterprise_count,
    'affected_power_group_count', pp.affected_power_group_count
  )
  FROM (SELECT NULL) AS dummy
  LEFT JOIN worker.pipeline_progress AS pp ON pp.phase = 'is_deriving_statistical_units';
$function$;

-- ============================================================================
-- 1j. Update is_deriving_reports — same pattern
-- ============================================================================

CREATE OR REPLACE FUNCTION public.is_deriving_reports()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
  -- pipeline_progress is the single source of truth (same pattern as Phase 1).
  SELECT jsonb_build_object(
    'active', pp.phase IS NOT NULL,
    'step', pp.step,
    'total', COALESCE(pp.total, 0),
    'completed', COALESCE(pp.completed, 0),
    'affected_establishment_count', pp.affected_establishment_count,
    'affected_legal_unit_count', pp.affected_legal_unit_count,
    'affected_enterprise_count', pp.affected_enterprise_count,
    'affected_power_group_count', pp.affected_power_group_count
  )
  FROM (SELECT NULL) AS dummy
  LEFT JOIN worker.pipeline_progress AS pp ON pp.phase = 'is_deriving_reports';
$function$;

-- ============================================================================
-- 1k. Update notify_is_deriving_statistical_units_stop — DELETE phase row
-- ============================================================================

CREATE OR REPLACE PROCEDURE worker.notify_is_deriving_statistical_units_stop()
 LANGUAGE plpgsql
AS $procedure$
BEGIN
  -- Check if any Phase 1 tasks are still pending or running.
  -- By the time after_procedure fires, the calling task is already in 'completed' state,
  -- so this only finds OTHER Phase 1 tasks that still need to run.
  -- Exclude collect_changes: it always has a pending task queued via dedup index
  -- as the entry-point trigger — it's not actual derive work.
  IF EXISTS (
    SELECT 1 FROM worker.tasks AS t
    JOIN worker.command_registry AS cr ON cr.command = t.command
    WHERE cr.phase = 'is_deriving_statistical_units'
    AND t.command <> 'collect_changes'
    AND t.state IN ('pending', 'processing', 'waiting')
  ) THEN
    RETURN;  -- More Phase 1 work pending, don't stop yet
  END IF;

  -- If collect_changes is pending, more Phase 1 work is guaranteed
  -- (collect_changes always leads to derive_statistical_unit), so stay active.
  -- Reset to collect_changes step with cleared counts — the previous cycle's
  -- counts are stale and the new collect_changes will set fresh ones.
  IF EXISTS (
    SELECT 1 FROM worker.tasks
    WHERE command = 'collect_changes'
    AND state = 'pending'
  ) THEN
    UPDATE worker.pipeline_progress
    SET step = 'collect_changes', total = 0, completed = 0,
        affected_establishment_count = NULL,
        affected_legal_unit_count = NULL,
        affected_enterprise_count = NULL,
        affected_power_group_count = NULL,
        updated_at = clock_timestamp()
    WHERE phase = 'is_deriving_statistical_units';
    RETURN;
  END IF;

  DELETE FROM worker.pipeline_progress WHERE phase = 'is_deriving_statistical_units';
  PERFORM pg_notify('worker_status',
    json_build_object('type', 'is_deriving_statistical_units', 'status', false)::text
  );
END;
$procedure$;

-- ============================================================================
-- 1l. Update notify_is_deriving_reports_stop — DELETE phase row
-- ============================================================================

CREATE OR REPLACE PROCEDURE worker.notify_is_deriving_reports_stop()
 LANGUAGE plpgsql
AS $procedure$
BEGIN
  -- Check if any Phase 2 tasks are still pending or running.
  -- By the time after_procedure fires, the calling task is already in 'completed' state,
  -- so this only finds OTHER Phase 2 tasks that still need to run.
  IF EXISTS (
    SELECT 1 FROM worker.tasks AS t
    JOIN worker.command_registry AS cr ON cr.command = t.command
    WHERE cr.phase = 'is_deriving_reports'
    AND t.state IN ('pending', 'processing', 'waiting')
  ) THEN
    RETURN;  -- More Phase 2 work pending, don't stop yet
  END IF;

  DELETE FROM worker.pipeline_progress WHERE phase = 'is_deriving_reports';
  PERFORM pg_notify('worker_status',
    json_build_object('type', 'is_deriving_reports', 'status', false)::text
  );
END;
$procedure$;

-- ============================================================================
-- 1m. Fix statistical_unit_flush_staging — use working notification channel
-- ============================================================================

CREATE OR REPLACE PROCEDURE worker.statistical_unit_flush_staging(IN payload jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'worker', 'pg_temp'
AS $statistical_unit_flush_staging$
BEGIN
    UPDATE worker.pipeline_progress
    SET step = 'statistical_unit_flush_staging', updated_at = clock_timestamp()
    WHERE phase = 'is_deriving_statistical_units';
    PERFORM worker.notify_pipeline_progress();

    CALL public.statistical_unit_flush_staging();

    UPDATE worker.pipeline_progress
    SET completed = total, updated_at = clock_timestamp()
    WHERE phase = 'is_deriving_statistical_units';
    PERFORM worker.notify_pipeline_progress();
END;
$statistical_unit_flush_staging$;

-- ============================================================================
-- 1n. Fix is_importing — include 'preparing_data' state
-- ============================================================================

CREATE OR REPLACE FUNCTION public.is_importing()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
  SELECT jsonb_build_object(
    'active', EXISTS (
      SELECT 1 FROM public.import_job
      WHERE state IN ('preparing_data', 'analysing_data', 'processing_data')
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
      WHERE ij.state IN ('preparing_data', 'analysing_data', 'processing_data')),
      '[]'::jsonb
    )
  );
$function$;

COMMIT;

-- Down migration: revert notify_task_progress from procedure back to function
--
-- Reverses the up migration:
-- 1. Drop the procedure
-- 2. Recreate as function (RETURNS void)
-- 3. Restore process_tasks with PERFORM instead of CALL

BEGIN;

-- 1. Drop the procedure
DROP PROCEDURE IF EXISTS worker.notify_task_progress();

-- 2. Recreate as function (original definition from before the up migration)
CREATE OR REPLACE FUNCTION worker.notify_task_progress()
 RETURNS void
 LANGUAGE plpgsql
AS $notify_task_progress$
DECLARE
    v_payload JSONB;
    v_phases JSONB := '[]'::jsonb;
    -- Pipeline root
    v_pipeline_id BIGINT;
    v_pipeline_state worker.task_state;
    -- Phase roots
    v_units_phase_id BIGINT;
    v_units_phase_state worker.task_state;
    v_reports_phase_id BIGINT;
    v_reports_phase_state worker.task_state;
    -- Phase 1
    v_units_active BOOLEAN;
    v_units_step TEXT;
    v_units_total BIGINT;
    v_units_completed BIGINT;
    -- Phase 2
    v_reports_active BOOLEAN;
    v_reports_step TEXT;
    v_reports_total BIGINT;
    v_reports_completed BIGINT;
    -- Shared
    v_concurrent_parent_id BIGINT;
    v_effective_info JSONB;
BEGIN
    -- 1. Find the active pipeline root.
    -- Prefer processing/waiting (actively running) over interrupted/pending (queued).
    -- Without this, a second queued collect_changes would shadow the running one.
    SELECT id, state INTO v_pipeline_id, v_pipeline_state
    FROM worker.tasks
    WHERE command = 'collect_changes'
      AND state NOT IN ('completed', 'failed')
    ORDER BY
      CASE WHEN state IN ('processing', 'waiting') THEN 0 ELSE 1 END,
      id DESC
    LIMIT 1;

    IF v_pipeline_id IS NULL THEN
        -- No active pipeline. Send idle for both phases.
        PERFORM pg_notify('worker_status',
            json_build_object('type', 'is_deriving_statistical_units', 'status', false)::text);
        PERFORM pg_notify('worker_status',
            json_build_object('type', 'is_deriving_reports', 'status', false)::text);
        RETURN;
    END IF;

    -- 2. Find phase roots (direct children of pipeline root)
    SELECT id, state INTO v_units_phase_id, v_units_phase_state
    FROM worker.tasks
    WHERE parent_id = v_pipeline_id AND command = 'derive_units_phase';

    SELECT id, state INTO v_reports_phase_id, v_reports_phase_state
    FROM worker.tasks
    WHERE parent_id = v_pipeline_id AND command = 'derive_reports_phase';

    -- 3. Phase activity from root states
    -- Units: active when pipeline is collecting (interrupted/pending/processing)
    --        OR units phase root is not yet terminal
    v_units_active := v_pipeline_state IN ('interrupted', 'pending', 'processing')
        OR (v_units_phase_state IS NOT NULL
            AND v_units_phase_state NOT IN ('completed', 'failed'));

    -- Also check: is there a QUEUED pipeline behind the current one?
    -- An interrupted or pending collect_changes means new changes are waiting to be processed.
    -- Show units as pending so the UI indicates queued work.
    IF NOT v_units_active AND EXISTS (
        SELECT 1 FROM worker.tasks
        WHERE command = 'collect_changes' AND state IN ('interrupted', 'pending')
          AND id <> v_pipeline_id
    ) THEN
        v_units_active := true;
        v_units_step := 'collect_changes';
    END IF;

    -- Reports: active when reports phase root is processing/waiting,
    -- OR when reports is interrupted/pending but units is already done (bridges the gap
    -- between derive_units_phase completing and derive_reports_phase starting).
    v_reports_active := v_reports_phase_state IN ('processing', 'waiting')
        OR (v_reports_phase_state IN ('interrupted', 'pending')
            AND v_units_phase_state IN ('completed', 'failed'));

    -- 4. Effective counts: from the depth-2 child that has them (persists after completion)
    IF v_units_phase_id IS NOT NULL THEN
        SELECT t.info INTO v_effective_info
        FROM worker.tasks AS t
        WHERE t.parent_id = v_units_phase_id
          AND t.info ? 'effective_legal_unit_count'
        ORDER BY t.id LIMIT 1;
    END IF;

    -- 5. Phase 1 details
    IF v_units_active THEN
        -- Step: the depth-2 child of the phase root that's active.
        -- This matches pipeline_step_weight entries for weighted progress.
        IF v_pipeline_state IN ('interrupted', 'pending', 'processing') THEN
            v_units_step := 'collect_changes';
        ELSE
            SELECT t.command INTO v_units_step
            FROM worker.tasks AS t
            WHERE t.parent_id = v_units_phase_id
              AND t.state IN ('processing', 'waiting')
            ORDER BY t.id DESC LIMIT 1;
        END IF;

        -- Progress: children of the deepest active concurrent parent in the phase
        SELECT t.id INTO v_concurrent_parent_id
        FROM worker.tasks AS t
        WHERE t.parent_id = v_units_phase_id
          AND t.child_mode = 'concurrent'
          AND t.state IN ('processing', 'waiting')
        ORDER BY t.depth DESC LIMIT 1;

        IF v_concurrent_parent_id IS NOT NULL THEN
            SELECT count(*),
                   count(*) FILTER (WHERE state IN ('completed', 'failed'))
            INTO v_units_total, v_units_completed
            FROM worker.tasks
            WHERE parent_id = v_concurrent_parent_id;
        ELSE
            v_units_total := 0;
            v_units_completed := 0;
        END IF;

        v_phases := v_phases || jsonb_build_array(jsonb_build_object(
            'phase', 'is_deriving_statistical_units',
            'active', v_units_active,
            'pending', false,
            'step', v_units_step,
            'total', COALESCE(v_units_total, 0),
            'completed', COALESCE(v_units_completed, 0),
            'effective_establishment_count', (v_effective_info->>'effective_establishment_count')::int,
            'effective_legal_unit_count', (v_effective_info->>'effective_legal_unit_count')::int,
            'effective_enterprise_count', (v_effective_info->>'effective_enterprise_count')::int,
            'effective_power_group_count', (v_effective_info->>'effective_power_group_count')::int
        ));
    END IF;

    -- 6. Phase 2 details
    -- Always include reports when the phase exists (even when interrupted/pending),
    -- so the UI can show "pending" with effective counts.
    IF v_reports_phase_id IS NOT NULL AND v_reports_phase_state NOT IN ('completed', 'failed') THEN
        IF v_reports_active THEN
            -- Step: the depth-2 child of the phase root that's active.
            -- This matches pipeline_step_weight entries for weighted progress.
            SELECT t.command INTO v_reports_step
            FROM worker.tasks AS t
            WHERE t.parent_id = v_reports_phase_id
              AND t.state IN ('processing', 'waiting')
            ORDER BY t.id DESC LIMIT 1;

            -- Progress: children of the deepest active concurrent parent in the phase
            SELECT t.id INTO v_concurrent_parent_id
            FROM worker.tasks AS t
            WHERE t.parent_id = v_reports_phase_id
              AND t.child_mode = 'concurrent'
              AND t.state IN ('processing', 'waiting')
            ORDER BY t.depth DESC LIMIT 1;

            IF v_concurrent_parent_id IS NOT NULL THEN
                SELECT count(*),
                       count(*) FILTER (WHERE state IN ('completed', 'failed'))
                INTO v_reports_total, v_reports_completed
                FROM worker.tasks
                WHERE parent_id = v_concurrent_parent_id;
            END IF;
        END IF;

        v_phases := v_phases || jsonb_build_array(jsonb_build_object(
            'phase', 'is_deriving_reports',
            'active', v_reports_active,
            'pending', v_reports_phase_state IN ('interrupted', 'pending'),
            'step', v_reports_step,
            'total', COALESCE(v_reports_total, 0),
            'completed', COALESCE(v_reports_completed, 0),
            'effective_establishment_count', (v_effective_info->>'effective_establishment_count')::int,
            'effective_legal_unit_count', (v_effective_info->>'effective_legal_unit_count')::int,
            'effective_enterprise_count', (v_effective_info->>'effective_enterprise_count')::int,
            'effective_power_group_count', (v_effective_info->>'effective_power_group_count')::int
        ));
    END IF;

    -- 7. Send progress and idle signals
    IF jsonb_array_length(v_phases) > 0 THEN
        v_payload := jsonb_build_object('type', 'pipeline_progress', 'phases', v_phases);
        PERFORM pg_notify('worker_status', v_payload::text);
    END IF;

    -- Only send idle signals when the phase is truly idle (not active AND not pending).
    -- An interrupted or pending phase is queued work — not idle.
    IF NOT v_units_active THEN
        PERFORM pg_notify('worker_status',
            json_build_object('type', 'is_deriving_statistical_units', 'status', false)::text);
    END IF;
    IF NOT v_reports_active
       AND (v_reports_phase_state IS NULL OR v_reports_phase_state IN ('completed', 'failed')) THEN
        PERFORM pg_notify('worker_status',
            json_build_object('type', 'is_deriving_reports', 'status', false)::text);
    END IF;
END;
$notify_task_progress$;

-- 3. Restore process_tasks with PERFORM instead of CALL
--    The only change from the up migration body is:
--      CALL worker.notify_task_progress()  ->  PERFORM worker.notify_task_progress()
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
  v_waiting_concurrent_parent_id BIGINT;
  v_waiting_serial_parent_id BIGINT;
  v_max_retries CONSTANT INT := 3;
  v_retry_count INT;
  v_backoff_base_ms CONSTANT NUMERIC := 100;
BEGIN
  SELECT pg_current_xact_id_if_assigned() IS NOT NULL INTO v_inside_transaction;
  RAISE DEBUG 'Running worker.process_tasks inside transaction: %, queue: %, mode: %',
    v_inside_transaction, p_queue, COALESCE(p_mode::text, 'NULL');

  batch_start_time := clock_timestamp();

  LOOP
    IF p_max_runtime_ms IS NOT NULL AND
       EXTRACT(EPOCH FROM (clock_timestamp() - batch_start_time)) * 1000 > p_max_runtime_ms THEN
      EXIT;
    END IF;

    SELECT t.id
    INTO v_waiting_concurrent_parent_id
    FROM worker.tasks AS t
    JOIN worker.command_registry AS cr ON t.command = cr.command
    WHERE t.state = 'waiting'::worker.task_state
      AND t.child_mode = 'concurrent'
      AND (p_queue IS NULL OR cr.queue = p_queue)
    ORDER BY t.depth DESC, t.priority, t.id
    LIMIT 1;

    SELECT t.id
    INTO v_waiting_serial_parent_id
    FROM worker.tasks AS t
    JOIN worker.command_registry AS cr ON t.command = cr.command
    WHERE t.state = 'waiting'::worker.task_state
      AND t.child_mode = 'serial'
      AND (p_queue IS NULL OR cr.queue = p_queue)
      AND NOT EXISTS (
        SELECT 1 FROM worker.tasks AS sib
        WHERE sib.parent_id = t.id
          AND sib.state IN ('processing', 'waiting')
      )
    ORDER BY t.depth DESC, t.priority, t.id
    LIMIT 1;

    IF p_mode = 'serial' THEN
      IF v_waiting_concurrent_parent_id IS NOT NULL THEN
        RAISE DEBUG 'Serial mode: concurrent parent % exists, returning to Crystal',
          v_waiting_concurrent_parent_id;
        EXIT;
      END IF;

      IF v_waiting_serial_parent_id IS NOT NULL THEN
        SELECT t.*, cr.handler_procedure, cr.before_procedure, cr.after_procedure, cr.queue
        INTO task_record
        FROM worker.tasks AS t
        JOIN worker.command_registry AS cr ON t.command = cr.command
        WHERE t.state IN ('interrupted'::worker.task_state, 'pending'::worker.task_state)
          AND t.parent_id = v_waiting_serial_parent_id
          AND (t.scheduled_at IS NULL OR t.scheduled_at <= clock_timestamp())
          AND (p_max_priority IS NULL OR t.priority <= p_max_priority)
        ORDER BY CASE WHEN t.state = 'interrupted' THEN 0 ELSE 1 END, t.priority ASC NULLS LAST, t.id
        LIMIT 1
        FOR UPDATE OF t SKIP LOCKED;
      END IF;

      IF NOT FOUND OR v_waiting_serial_parent_id IS NULL THEN
        SELECT t.*, cr.handler_procedure, cr.before_procedure, cr.after_procedure, cr.queue
        INTO task_record
        FROM worker.tasks AS t
        JOIN worker.command_registry AS cr ON t.command = cr.command
        WHERE t.state IN ('interrupted'::worker.task_state, 'pending'::worker.task_state)
          AND t.parent_id IS NULL
          AND (t.scheduled_at IS NULL OR t.scheduled_at <= clock_timestamp())
          AND (p_queue IS NULL OR cr.queue = p_queue)
          AND (p_max_priority IS NULL OR t.priority <= p_max_priority)
        ORDER BY
          CASE WHEN t.state = 'interrupted' THEN 0 ELSE 1 END,
          CASE WHEN t.scheduled_at IS NULL THEN 0 ELSE 1 END,
          t.scheduled_at,
          t.priority ASC NULLS LAST,
          t.id
        LIMIT 1
        FOR UPDATE OF t SKIP LOCKED;
      END IF;

    ELSIF p_mode = 'concurrent' THEN
      IF v_waiting_concurrent_parent_id IS NULL THEN
        RAISE DEBUG 'Concurrent mode: no concurrent waiting parent, returning';
        EXIT;
      END IF;

      SELECT t.*, cr.handler_procedure, cr.before_procedure, cr.after_procedure, cr.queue
      INTO task_record
      FROM worker.tasks AS t
      JOIN worker.command_registry AS cr ON t.command = cr.command
      WHERE t.state IN ('interrupted'::worker.task_state, 'pending'::worker.task_state)
        AND t.parent_id = v_waiting_concurrent_parent_id
        AND (t.scheduled_at IS NULL OR t.scheduled_at <= clock_timestamp())
        AND (p_max_priority IS NULL OR t.priority <= p_max_priority)
      ORDER BY CASE WHEN t.state = 'interrupted' THEN 0 ELSE 1 END, t.priority ASC NULLS LAST, t.id
      LIMIT 1
      FOR UPDATE OF t SKIP LOCKED;

    ELSE
      IF v_waiting_concurrent_parent_id IS NOT NULL THEN
        SELECT t.*, cr.handler_procedure, cr.before_procedure, cr.after_procedure, cr.queue
        INTO task_record
        FROM worker.tasks AS t
        JOIN worker.command_registry AS cr ON t.command = cr.command
        WHERE t.state IN ('interrupted'::worker.task_state, 'pending'::worker.task_state)
          AND t.parent_id = v_waiting_concurrent_parent_id
          AND (t.scheduled_at IS NULL OR t.scheduled_at <= clock_timestamp())
          AND (p_max_priority IS NULL OR t.priority <= p_max_priority)
        ORDER BY CASE WHEN t.state = 'interrupted' THEN 0 ELSE 1 END, t.priority ASC NULLS LAST, t.id
        LIMIT 1
        FOR UPDATE OF t SKIP LOCKED;
      END IF;

      IF (v_waiting_concurrent_parent_id IS NULL OR NOT FOUND) AND v_waiting_serial_parent_id IS NOT NULL THEN
        SELECT t.*, cr.handler_procedure, cr.before_procedure, cr.after_procedure, cr.queue
        INTO task_record
        FROM worker.tasks AS t
        JOIN worker.command_registry AS cr ON t.command = cr.command
        WHERE t.state IN ('interrupted'::worker.task_state, 'pending'::worker.task_state)
          AND t.parent_id = v_waiting_serial_parent_id
          AND (t.scheduled_at IS NULL OR t.scheduled_at <= clock_timestamp())
          AND (p_max_priority IS NULL OR t.priority <= p_max_priority)
        ORDER BY CASE WHEN t.state = 'interrupted' THEN 0 ELSE 1 END, t.priority ASC NULLS LAST, t.id
        LIMIT 1
        FOR UPDATE OF t SKIP LOCKED;
      END IF;

      IF (v_waiting_concurrent_parent_id IS NULL AND v_waiting_serial_parent_id IS NULL) OR NOT FOUND THEN
        SELECT t.*, cr.handler_procedure, cr.before_procedure, cr.after_procedure, cr.queue
        INTO task_record
        FROM worker.tasks AS t
        JOIN worker.command_registry AS cr ON t.command = cr.command
        WHERE t.state IN ('interrupted'::worker.task_state, 'pending'::worker.task_state)
          AND t.parent_id IS NULL
          AND (t.scheduled_at IS NULL OR t.scheduled_at <= clock_timestamp())
          AND (p_queue IS NULL OR cr.queue = p_queue)
          AND (p_max_priority IS NULL OR t.priority <= p_max_priority)
        ORDER BY
          CASE WHEN t.state = 'interrupted' THEN 0 ELSE 1 END,
          CASE WHEN t.scheduled_at IS NULL THEN 0 ELSE 1 END,
          t.scheduled_at,
          t.priority ASC NULLS LAST,
          t.id
        LIMIT 1
        FOR UPDATE OF t SKIP LOCKED;
      END IF;
    END IF;

    IF NOT FOUND THEN
      EXIT;
    END IF;

    start_time := clock_timestamp();

    UPDATE worker.tasks AS t
    SET state = 'processing'::worker.task_state,
        worker_pid = pg_backend_pid(),
        process_start_at = start_time
    WHERE t.id = task_record.id;

    IF task_record.before_procedure IS NOT NULL THEN
      BEGIN
        EXECUTE format('CALL %s()', task_record.before_procedure);
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Error in before_procedure % for task %: %', task_record.before_procedure, task_record.id, SQLERRM;
      END;
    END IF;

    IF NOT v_inside_transaction THEN
      COMMIT;
    END IF;

    DECLARE
      v_state worker.task_state;
      v_process_stop_at TIMESTAMPTZ;
      v_completed_at TIMESTAMPTZ;
      v_process_duration_ms NUMERIC;
      v_completion_duration_ms NUMERIC;
      v_error TEXT DEFAULT NULL;
      v_has_children BOOLEAN;
      v_handler_info JSONB;
    BEGIN
      v_retry_count := 0;

      <<retry_loop>>
      LOOP
        DECLARE
          v_message_text TEXT;
          v_pg_exception_detail TEXT;
          v_pg_exception_hint TEXT;
          v_pg_exception_context TEXT;
        BEGIN
          IF task_record.handler_procedure IS NOT NULL THEN
            -- INOUT protocol: EXECUTE INTO captures the INOUT return value;
            -- plain EXECUTE USING does NOT capture INOUT in PG.
            EXECUTE format('CALL %s($1, $2)', task_record.handler_procedure)
            INTO v_handler_info
            USING task_record.payload, NULL::jsonb;
          ELSE
            RAISE EXCEPTION 'No handler procedure found for command: %', task_record.command;
          END IF;

          v_process_stop_at := clock_timestamp();
          v_process_duration_ms := EXTRACT(EPOCH FROM (v_process_stop_at - start_time)) * 1000;

          SELECT EXISTS (
            SELECT 1 FROM worker.tasks WHERE parent_id = task_record.id
          ) INTO v_has_children;

          IF v_has_children THEN
            v_state := 'waiting'::worker.task_state;
            v_completed_at := NULL;
            v_completion_duration_ms := NULL;
          ELSE
            v_state := 'completed'::worker.task_state;
            v_completed_at := clock_timestamp();
            v_completion_duration_ms := EXTRACT(EPOCH FROM (v_completed_at - start_time)) * 1000;
          END IF;

          EXIT retry_loop;

        EXCEPTION
          WHEN deadlock_detected THEN
            v_retry_count := v_retry_count + 1;
            IF v_retry_count <= v_max_retries THEN
              RAISE WARNING 'Task % (%) deadlock detected, retry %/%',
                task_record.id, task_record.command, v_retry_count, v_max_retries;
              PERFORM pg_sleep((v_backoff_base_ms * power(2, v_retry_count - 1) + (random() * 50)) / 1000.0);
              CONTINUE retry_loop;
            END IF;

            v_process_stop_at := clock_timestamp();
            v_state := 'failed'::worker.task_state;
            v_completed_at := v_process_stop_at;
            v_process_duration_ms := EXTRACT(EPOCH FROM (v_process_stop_at - start_time)) * 1000;
            v_completion_duration_ms := v_process_duration_ms;
            v_error := format('Deadlock detected after %s retries', v_retry_count);
            EXIT retry_loop;

          WHEN serialization_failure THEN
            v_retry_count := v_retry_count + 1;
            IF v_retry_count <= v_max_retries THEN
              RAISE WARNING 'Task % (%) serialization failure, retry %/%',
                task_record.id, task_record.command, v_retry_count, v_max_retries;
              PERFORM pg_sleep((v_backoff_base_ms * power(2, v_retry_count - 1) + (random() * 50)) / 1000.0);
              CONTINUE retry_loop;
            END IF;

            v_process_stop_at := clock_timestamp();
            v_state := 'failed'::worker.task_state;
            v_completed_at := v_process_stop_at;
            v_process_duration_ms := EXTRACT(EPOCH FROM (v_process_stop_at - start_time)) * 1000;
            v_completion_duration_ms := v_process_duration_ms;
            v_error := format('Serialization failure after %s retries', v_retry_count);
            EXIT retry_loop;

          WHEN OTHERS THEN
            v_process_stop_at := clock_timestamp();
            v_state := 'failed'::worker.task_state;
            v_completed_at := v_process_stop_at;
            v_process_duration_ms := EXTRACT(EPOCH FROM (v_process_stop_at - start_time)) * 1000;
            v_completion_duration_ms := v_process_duration_ms;

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

            RAISE WARNING 'Task % (%) failed in % ms: %', task_record.id, task_record.command, v_process_duration_ms, v_error;
            EXIT retry_loop;
        END;
      END LOOP retry_loop;

      -- Post-handler UPDATE now includes info from INOUT
      UPDATE worker.tasks AS t
      SET state = v_state,
          process_stop_at = v_process_stop_at,
          completed_at = v_completed_at,
          process_duration_ms = v_process_duration_ms,
          completion_duration_ms = v_completion_duration_ms,
          error = v_error,
          info = COALESCE(t.info, '{}'::jsonb) || COALESCE(v_handler_info, '{}'::jsonb)
      WHERE t.id = task_record.id;

      IF v_state = 'failed' THEN
        PERFORM worker.cascade_fail_descendants(task_record.id);
      END IF;

      IF v_inside_transaction AND task_record.parent_id IS NOT NULL AND v_state IN ('completed', 'failed') THEN
        PERFORM worker.complete_parent_if_ready(task_record.id);
      END IF;

      IF task_record.after_procedure IS NOT NULL AND v_state IN ('completed', 'failed') THEN
        BEGIN
          EXECUTE format('CALL %s()', task_record.after_procedure);
        EXCEPTION WHEN OTHERS THEN
          RAISE WARNING 'Error in after_procedure % for task %: %', task_record.after_procedure, task_record.id, SQLERRM;
        END;
      END IF;

      IF NOT v_inside_transaction THEN
        COMMIT;
      END IF;

      IF NOT v_inside_transaction AND task_record.parent_id IS NOT NULL AND v_state IN ('completed', 'failed') THEN
        PERFORM worker.complete_parent_if_ready(task_record.id);
        COMMIT;
      END IF;

      IF task_record.queue = 'analytics' THEN
        PERFORM worker.notify_task_progress();
        IF NOT v_inside_transaction THEN
          COMMIT;
        END IF;
      END IF;
    END;

    processed_count := processed_count + 1;
    IF p_batch_size IS NOT NULL AND processed_count >= p_batch_size THEN
      EXIT;
    END IF;
  END LOOP;
END;
$procedure$;

END;

BEGIN;

-- ============================================================================
-- Restore notify_is_deriving_reports_stop (original)
-- ============================================================================

CREATE OR REPLACE PROCEDURE worker.notify_is_deriving_reports_stop()
 LANGUAGE plpgsql
AS $procedure$
BEGIN
  PERFORM pg_notify('worker_status',
    json_build_object(
      'type', 'is_deriving_reports',
      'status', (public.is_deriving_reports()->>'active')::boolean
    )::text
  );
END;
$procedure$;

-- ============================================================================
-- Restore notify_is_deriving_statistical_units_stop (original)
-- ============================================================================

CREATE OR REPLACE PROCEDURE worker.notify_is_deriving_statistical_units_stop()
 LANGUAGE plpgsql
AS $procedure$
BEGIN
  PERFORM pg_notify('worker_status',
    json_build_object(
      'type', 'is_deriving_statistical_units',
      'status', (public.is_deriving_statistical_units()->>'active')::boolean
    )::text
  );
END;
$procedure$;

-- ============================================================================
-- Restore is_deriving_reports (original — step-based)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.is_deriving_reports()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
  SELECT jsonb_build_object(
    'active', (
      EXISTS (
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
      )
      OR EXISTS (
        SELECT 1 FROM worker.tasks AS t
        JOIN worker.command_registry AS cr ON t.command = cr.command
        WHERE cr.queue = 'analytics'
          AND t.command IN (
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
          AND t.state IN ('pending', 'processing', 'waiting')
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
$function$;

-- ============================================================================
-- Restore is_deriving_statistical_units (original — step-based)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.is_deriving_statistical_units()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
  SELECT jsonb_build_object(
    'active', (
      EXISTS (
        SELECT 1 FROM worker.pipeline_progress
        WHERE step IN (
          'derive_statistical_unit',
          'derive_statistical_unit_continue',
          'statistical_unit_refresh_batch',
          'statistical_unit_flush_staging'
        )
      )
      OR EXISTS (
        SELECT 1 FROM worker.tasks AS t
        JOIN worker.command_registry AS cr ON t.command = cr.command
        WHERE cr.queue = 'analytics'
          AND t.command IN (
            'derive_statistical_unit',
            'derive_statistical_unit_continue',
            'statistical_unit_refresh_batch',
            'statistical_unit_flush_staging'
          )
          AND t.state IN ('pending', 'processing', 'waiting')
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
$function$;

-- ============================================================================
-- Restore derive_statistical_unit function (original — no unit counts)
-- ============================================================================

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
BEGIN
    v_is_full_refresh := (p_establishment_id_ranges IS NULL
                         AND p_legal_unit_id_ranges IS NULL
                         AND p_enterprise_id_ranges IS NULL);

    -- Priority for children: use round base if available, otherwise nextval
    v_child_priority := COALESCE(p_round_priority_base, nextval('public.worker_task_priority_seq'));

    IF v_is_full_refresh THEN
        -- Full refresh: spawn batch children (no orphan cleanup needed - covers everything)
        -- No dirty partition tracking needed: full refresh recomputes all partitions
        FOR v_batch IN
            SELECT * FROM public.get_closed_group_batches(p_target_batch_size := 1000)
        LOOP
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
        v_establishment_ids := ARRAY(
            SELECT generate_series(lower(r), upper(r)-1)
            FROM unnest(COALESCE(p_establishment_id_ranges, '{}'::int4multirange)) AS t(r)
        );
        v_legal_unit_ids := ARRAY(
            SELECT generate_series(lower(r), upper(r)-1)
            FROM unnest(COALESCE(p_legal_unit_id_ranges, '{}'::int4multirange)) AS t(r)
        );
        v_enterprise_ids := ARRAY(
            SELECT generate_series(lower(r), upper(r)-1)
            FROM unnest(COALESCE(p_enterprise_id_ranges, '{}'::int4multirange)) AS t(r)
        );

        -- =====================================================================
        -- ORPHAN CLEANUP: Handle deleted entities BEFORE batching
        -- =====================================================================
        IF COALESCE(array_length(v_enterprise_ids, 1), 0) > 0 THEN
            v_orphan_enterprise_ids := ARRAY(
                SELECT id FROM unnest(v_enterprise_ids) AS id
                EXCEPT SELECT e.id FROM public.enterprise AS e WHERE e.id = ANY(v_enterprise_ids)
            );
            IF COALESCE(array_length(v_orphan_enterprise_ids, 1), 0) > 0 THEN
                RAISE DEBUG 'derive_statistical_unit: Cleaning up % orphan enterprise IDs',
                    array_length(v_orphan_enterprise_ids, 1);
                DELETE FROM public.timepoints WHERE unit_type = 'enterprise' AND unit_id = ANY(v_orphan_enterprise_ids);
                DELETE FROM public.timesegments WHERE unit_type = 'enterprise' AND unit_id = ANY(v_orphan_enterprise_ids);
                DELETE FROM public.timeline_enterprise WHERE enterprise_id = ANY(v_orphan_enterprise_ids);
                DELETE FROM public.statistical_unit WHERE unit_type = 'enterprise' AND unit_id = ANY(v_orphan_enterprise_ids);
            END IF;
        END IF;

        IF COALESCE(array_length(v_legal_unit_ids, 1), 0) > 0 THEN
            v_orphan_legal_unit_ids := ARRAY(
                SELECT id FROM unnest(v_legal_unit_ids) AS id
                EXCEPT SELECT lu.id FROM public.legal_unit AS lu WHERE lu.id = ANY(v_legal_unit_ids)
            );
            IF COALESCE(array_length(v_orphan_legal_unit_ids, 1), 0) > 0 THEN
                RAISE DEBUG 'derive_statistical_unit: Cleaning up % orphan legal_unit IDs',
                    array_length(v_orphan_legal_unit_ids, 1);
                DELETE FROM public.timepoints WHERE unit_type = 'legal_unit' AND unit_id = ANY(v_orphan_legal_unit_ids);
                DELETE FROM public.timesegments WHERE unit_type = 'legal_unit' AND unit_id = ANY(v_orphan_legal_unit_ids);
                DELETE FROM public.timeline_legal_unit WHERE legal_unit_id = ANY(v_orphan_legal_unit_ids);
                DELETE FROM public.statistical_unit WHERE unit_type = 'legal_unit' AND unit_id = ANY(v_orphan_legal_unit_ids);
            END IF;
        END IF;

        IF COALESCE(array_length(v_establishment_ids, 1), 0) > 0 THEN
            v_orphan_establishment_ids := ARRAY(
                SELECT id FROM unnest(v_establishment_ids) AS id
                EXCEPT SELECT es.id FROM public.establishment AS es WHERE es.id = ANY(v_establishment_ids)
            );
            IF COALESCE(array_length(v_orphan_establishment_ids, 1), 0) > 0 THEN
                RAISE DEBUG 'derive_statistical_unit: Cleaning up % orphan establishment IDs',
                    array_length(v_orphan_establishment_ids, 1);
                DELETE FROM public.timepoints WHERE unit_type = 'establishment' AND unit_id = ANY(v_orphan_establishment_ids);
                DELETE FROM public.timesegments WHERE unit_type = 'establishment' AND unit_id = ANY(v_orphan_establishment_ids);
                DELETE FROM public.timeline_establishment WHERE establishment_id = ANY(v_orphan_establishment_ids);
                DELETE FROM public.statistical_unit WHERE unit_type = 'establishment' AND unit_id = ANY(v_orphan_establishment_ids);
            END IF;
        END IF;

        -- =====================================================================
        -- BATCHING: Only existing entities, partitioned with no overlap
        -- Compute batches FIRST, then mark dirty partitions for ALL units
        -- in ALL batches (covers closed-group expansion).
        -- =====================================================================

        -- Collect all batches into a temp table for two-pass processing
        IF to_regclass('pg_temp._batches') IS NOT NULL THEN
            DROP TABLE _batches;
        END IF;
        CREATE TEMP TABLE _batches ON COMMIT DROP AS
        SELECT * FROM public.get_closed_group_batches(
            p_target_batch_size := 1000,
            p_establishment_ids := NULLIF(v_establishment_ids, '{}'),
            p_legal_unit_ids := NULLIF(v_legal_unit_ids, '{}'),
            p_enterprise_ids := NULLIF(v_enterprise_ids, '{}')
        );

        -- =====================================================================
        -- DIRTY PARTITION TRACKING: Mark partitions for ALL units in ALL batches
        -- Explicit count from settings (no function DEFAULT).
        -- =====================================================================
        INSERT INTO public.statistical_unit_facet_dirty_partitions (partition_seq)
        SELECT DISTINCT public.report_partition_seq(
            t.unit_type, t.unit_id,
            (SELECT analytics_partition_count FROM public.settings)
        )
        FROM (
            SELECT 'enterprise'::text AS unit_type, unnest(b.enterprise_ids) AS unit_id
            FROM _batches AS b
            UNION ALL
            SELECT 'legal_unit', unnest(b.legal_unit_ids)
            FROM _batches AS b
            UNION ALL
            SELECT 'establishment', unnest(b.establishment_ids)
            FROM _batches AS b
        ) AS t
        WHERE t.unit_id IS NOT NULL
        ON CONFLICT DO NOTHING;

        RAISE DEBUG 'derive_statistical_unit: Tracked dirty facet partitions for closed group across % batches',
            (SELECT count(*) FROM _batches);

        -- Spawn batch children
        FOR v_batch IN SELECT * FROM _batches
        LOOP
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

    RAISE DEBUG 'derive_statistical_unit: Spawned % batch children with parent_id %', v_batch_count, p_task_id;

    -- Refresh derived data (used flags) - always full refreshes, run synchronously
    PERFORM public.activity_category_used_derive();
    PERFORM public.region_used_derive();
    PERFORM public.sector_used_derive();
    PERFORM public.data_source_used_derive();
    PERFORM public.legal_form_used_derive();
    PERFORM public.country_used_derive();

    -- =========================================================================
    -- STAGING PATTERN: Enqueue flush task (runs after all batches complete)
    -- =========================================================================
    PERFORM worker.enqueue_statistical_unit_flush_staging(
        p_round_priority_base := p_round_priority_base
    );
    RAISE DEBUG 'derive_statistical_unit: Enqueued flush_staging task';

    -- Enqueue derive_reports as an "uncle" task (runs after flush completes)
    PERFORM worker.enqueue_derive_reports(
        p_valid_from := p_valid_from,
        p_valid_until := p_valid_until,
        p_round_priority_base := p_round_priority_base
    );

    RAISE DEBUG 'derive_statistical_unit: Enqueued derive_reports';
END;
$function$;

-- ============================================================================
-- Restore complete_parent_if_ready (original — step-based)
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
$function$;

-- ============================================================================
-- Restore process_tasks (original — step-based progress)
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
      IF v_waiting_parent_id IS NOT NULL THEN
        RAISE DEBUG 'Top mode: waiting parent % exists, returning to let children process', v_waiting_parent_id;
        EXIT;
      END IF;

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
      IF v_waiting_parent_id IS NULL THEN
        RAISE DEBUG 'Child mode: no waiting parent, returning';
        EXIT;
      END IF;

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
      IF v_waiting_parent_id IS NOT NULL THEN
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
            EXECUTE format('CALL %s($1)', task_record.handler_procedure)
            USING task_record.payload;
          ELSE
            RAISE EXCEPTION 'No handler procedure found for command: %', task_record.command;
          END IF;

          elapsed_ms := EXTRACT(EPOCH FROM (clock_timestamp() - start_time)) * 1000;
          v_processed_at := clock_timestamp();
          v_duration_ms := elapsed_ms;

          SELECT EXISTS (
            SELECT 1 FROM worker.tasks WHERE parent_id = task_record.id
          ) INTO v_has_children;

          IF v_has_children THEN
            v_state := 'waiting'::worker.task_state;
            v_completed_at := NULL;

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
            v_state := 'completed'::worker.task_state;
            v_completed_at := clock_timestamp();
            RAISE DEBUG 'Task % (%) completed in % ms', task_record.id, task_record.command, elapsed_ms;
          END IF;

          EXIT retry_loop;

        EXCEPTION
          WHEN deadlock_detected THEN
            v_retry_count := v_retry_count + 1;
            IF v_retry_count <= v_max_retries THEN
              RAISE WARNING 'Task % (%) deadlock detected, retry %/% after % ms',
                task_record.id, task_record.command, v_retry_count, v_max_retries,
                round(v_backoff_base_ms * power(2, v_retry_count - 1));
              PERFORM pg_sleep((v_backoff_base_ms * power(2, v_retry_count - 1) + (random() * 50)) / 1000.0);
              CONTINUE retry_loop;
            ELSE
              RAISE WARNING 'Task % (%) max retries (%) exceeded for deadlock',
                task_record.id, task_record.command, v_max_retries;
            END IF;

            elapsed_ms := EXTRACT(EPOCH FROM (clock_timestamp() - start_time)) * 1000;
            v_state := 'failed'::worker.task_state;
            v_processed_at := clock_timestamp();
            v_completed_at := clock_timestamp();
            v_duration_ms := elapsed_ms;
            v_error := format('Deadlock detected after %s retries', v_retry_count);
            EXIT retry_loop;

          WHEN serialization_failure THEN
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

      IF v_inside_transaction AND task_record.parent_id IS NOT NULL AND v_state IN ('completed', 'failed') THEN
        PERFORM worker.complete_parent_if_ready(task_record.id);
      END IF;

      IF task_record.after_procedure IS NOT NULL THEN
        BEGIN
          RAISE DEBUG 'Calling after_procedure: % for task % (%)', task_record.after_procedure, task_record.id, task_record.command;
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
    END;

    processed_count := processed_count + 1;
    IF p_batch_size IS NOT NULL AND processed_count >= p_batch_size THEN
      RAISE DEBUG 'Exiting worker loop: Batch size limit of % reached', p_batch_size;
      EXIT;
    END IF;
  END LOOP;
END;
$procedure$;

-- ============================================================================
-- Restore notify_*_start procedures (original — without UPSERT)
-- ============================================================================

CREATE OR REPLACE PROCEDURE worker.notify_is_deriving_statistical_units_start()
 LANGUAGE plpgsql
AS $procedure$
BEGIN
  PERFORM pg_notify('worker_status', json_build_object('type', 'is_deriving_statistical_units', 'status', true)::text);
END;
$procedure$;

CREATE OR REPLACE PROCEDURE worker.notify_is_deriving_reports_start()
 LANGUAGE plpgsql
AS $procedure$
BEGIN
  PERFORM pg_notify('worker_status', json_build_object('type', 'is_deriving_reports', 'status', true)::text);
END;
$procedure$;

-- ============================================================================
-- Drop lifecycle hook columns, procedures, phase column, and recreate original pipeline_progress
-- ============================================================================

DROP PROCEDURE IF EXISTS worker.pipeline_progress_on_children_created(worker.pipeline_phase, BIGINT, INT);
DROP PROCEDURE IF EXISTS worker.pipeline_progress_on_child_completed(worker.pipeline_phase, BIGINT);

ALTER TABLE worker.command_registry DROP COLUMN IF EXISTS on_children_created;
ALTER TABLE worker.command_registry DROP COLUMN IF EXISTS on_child_completed;
ALTER TABLE worker.command_registry DROP COLUMN phase;

DROP TABLE worker.pipeline_progress;

CREATE UNLOGGED TABLE worker.pipeline_progress (
    step TEXT NOT NULL PRIMARY KEY,
    total INT NOT NULL DEFAULT 0,
    completed INT NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

GRANT SELECT ON worker.pipeline_progress TO authenticated;
GRANT INSERT, UPDATE, DELETE ON worker.pipeline_progress TO authenticated;

DROP TYPE worker.pipeline_phase;

COMMIT;

BEGIN;

-- ============================================================================
-- Revert to advisory lock approach (from previous migration)
-- ============================================================================

-- Analytics queue remains at concurrency = 1 (no change needed)

-- ============================================================================
-- Restore timepoints_refresh with advisory locks
-- ============================================================================

CREATE OR REPLACE PROCEDURE public.timepoints_refresh(IN p_establishment_id_ranges int4multirange DEFAULT NULL::int4multirange, IN p_legal_unit_id_ranges int4multirange DEFAULT NULL::int4multirange, IN p_enterprise_id_ranges int4multirange DEFAULT NULL::int4multirange)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    rec RECORD;
    v_en_batch INT[];
    v_lu_batch INT[];
    v_es_batch INT[];
    v_batch_size INT := 32768;
    v_total_enterprises INT;
    v_processed_count INT := 0;
    v_batch_num INT := 0;
    v_batch_start_time timestamptz;
    v_batch_duration_ms numeric;
    v_batch_speed numeric;
    v_is_partial_refresh BOOLEAN;
BEGIN
    v_is_partial_refresh := (p_establishment_id_ranges IS NOT NULL 
                            OR p_legal_unit_id_ranges IS NOT NULL 
                            OR p_enterprise_id_ranges IS NOT NULL);

    -- Only ANALYZE for full refresh (sync points handle partial refresh ANALYZE)
    IF NOT v_is_partial_refresh THEN
        ANALYZE public.establishment, public.legal_unit, public.enterprise, public.activity, public.location, public.contact, public.stat_for_unit, public.person_for_unit;

        CREATE TEMP TABLE timepoints_new (LIKE public.timepoints) ON COMMIT DROP;

        SELECT count(*) INTO v_total_enterprises FROM public.enterprise;
        RAISE DEBUG 'Starting full timepoints refresh for % enterprises in batches of %...', v_total_enterprises, v_batch_size;

        FOR rec IN SELECT id FROM public.enterprise LOOP
            v_en_batch := array_append(v_en_batch, rec.id);

            IF array_length(v_en_batch, 1) >= v_batch_size THEN
                v_batch_start_time := clock_timestamp();
                v_processed_count := v_processed_count + array_length(v_en_batch, 1);
                v_batch_num := v_batch_num + 1;

                v_lu_batch := ARRAY(SELECT id FROM public.legal_unit WHERE enterprise_id = ANY(v_en_batch));
                v_es_batch := ARRAY(
                    SELECT id FROM public.establishment WHERE legal_unit_id = ANY(v_lu_batch)
                    UNION
                    SELECT id FROM public.establishment WHERE enterprise_id = ANY(v_en_batch)
                );

                INSERT INTO timepoints_new
                SELECT * FROM public.timepoints_calculate(
                    public.array_to_int4multirange(v_es_batch),
                    public.array_to_int4multirange(v_lu_batch),
                    public.array_to_int4multirange(v_en_batch)
                ) ON CONFLICT DO NOTHING;

                v_batch_duration_ms := (EXTRACT(EPOCH FROM (clock_timestamp() - v_batch_start_time))) * 1000;
                v_batch_speed := v_batch_size / (v_batch_duration_ms / 1000.0);
                RAISE DEBUG 'Timepoints batch %/% done. (% units, % ms, % units/s)', v_batch_num, ceil(v_total_enterprises::decimal / v_batch_size), v_batch_size, round(v_batch_duration_ms), round(v_batch_speed);

                v_en_batch := '{}';
            END IF;
        END LOOP;

        IF array_length(v_en_batch, 1) > 0 THEN
            v_batch_start_time := clock_timestamp();
            v_batch_num := v_batch_num + 1;
            v_lu_batch := ARRAY(SELECT id FROM public.legal_unit WHERE enterprise_id = ANY(v_en_batch));
            v_es_batch := ARRAY(
                SELECT id FROM public.establishment WHERE legal_unit_id = ANY(v_lu_batch)
                UNION
                SELECT id FROM public.establishment WHERE enterprise_id = ANY(v_en_batch)
            );
            INSERT INTO timepoints_new
            SELECT * FROM public.timepoints_calculate(
                public.array_to_int4multirange(v_es_batch),
                public.array_to_int4multirange(v_lu_batch),
                public.array_to_int4multirange(v_en_batch)
            ) ON CONFLICT DO NOTHING;
            v_batch_duration_ms := (EXTRACT(EPOCH FROM (clock_timestamp() - v_batch_start_time))) * 1000;
            v_batch_speed := array_length(v_en_batch, 1) / (v_batch_duration_ms / 1000.0);
            RAISE DEBUG 'Timepoints final batch done. (% units, % ms, % units/s)', array_length(v_en_batch, 1), round(v_batch_duration_ms), round(v_batch_speed);
        END IF;

        RAISE DEBUG 'Populated staging table, now swapping data...';
        TRUNCATE public.timepoints;
        INSERT INTO public.timepoints SELECT DISTINCT * FROM timepoints_new;
        RAISE DEBUG 'Full timepoints refresh complete.';

        ANALYZE public.timepoints;
    ELSE
        -- Partial refresh with ADVISORY LOCKS to prevent B-tree page contention
        -- Each unit_type is serialized across all concurrent batches
        RAISE DEBUG 'Starting partial timepoints refresh with advisory locks...';
        
        IF p_establishment_id_ranges IS NOT NULL THEN
            -- Acquire advisory lock for establishment operations
            PERFORM pg_advisory_xact_lock(hashtext('timepoints_establishment'));
            DELETE FROM public.timepoints WHERE unit_type = 'establishment' AND unit_id <@ p_establishment_id_ranges;
            INSERT INTO public.timepoints 
            SELECT * FROM public.timepoints_calculate(p_establishment_id_ranges, NULL, NULL)
            ON CONFLICT DO NOTHING;
        END IF;
        
        IF p_legal_unit_id_ranges IS NOT NULL THEN
            -- Acquire advisory lock for legal_unit operations
            PERFORM pg_advisory_xact_lock(hashtext('timepoints_legal_unit'));
            DELETE FROM public.timepoints WHERE unit_type = 'legal_unit' AND unit_id <@ p_legal_unit_id_ranges;
            INSERT INTO public.timepoints 
            SELECT * FROM public.timepoints_calculate(NULL, p_legal_unit_id_ranges, NULL)
            ON CONFLICT DO NOTHING;
        END IF;
        
        IF p_enterprise_id_ranges IS NOT NULL THEN
            -- Acquire advisory lock for enterprise operations
            PERFORM pg_advisory_xact_lock(hashtext('timepoints_enterprise'));
            DELETE FROM public.timepoints WHERE unit_type = 'enterprise' AND unit_id <@ p_enterprise_id_ranges;
            INSERT INTO public.timepoints 
            SELECT * FROM public.timepoints_calculate(NULL, NULL, p_enterprise_id_ranges)
            ON CONFLICT DO NOTHING;
        END IF;

        RAISE DEBUG 'Partial timepoints refresh complete.';
    END IF;
END;
$procedure$;

-- ============================================================================
-- Restore timesegments_refresh with advisory locks
-- ============================================================================

CREATE OR REPLACE PROCEDURE public.timesegments_refresh(IN p_establishment_id_ranges int4multirange DEFAULT NULL::int4multirange, IN p_legal_unit_id_ranges int4multirange DEFAULT NULL::int4multirange, IN p_enterprise_id_ranges int4multirange DEFAULT NULL::int4multirange)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_is_partial_refresh BOOLEAN;
BEGIN
    v_is_partial_refresh := (p_establishment_id_ranges IS NOT NULL 
                            OR p_legal_unit_id_ranges IS NOT NULL 
                            OR p_enterprise_id_ranges IS NOT NULL);

    IF NOT v_is_partial_refresh THEN
        -- Full refresh with ANALYZE
        ANALYZE public.timepoints;
        DELETE FROM public.timesegments;
        INSERT INTO public.timesegments SELECT * FROM public.timesegments_def;
        ANALYZE public.timesegments;
    ELSE
        -- Partial refresh with ADVISORY LOCKS to prevent B-tree page contention
        IF p_establishment_id_ranges IS NOT NULL THEN
            PERFORM pg_advisory_xact_lock(hashtext('timesegments_establishment'));
            DELETE FROM public.timesegments WHERE unit_type = 'establishment' AND unit_id <@ p_establishment_id_ranges;
            INSERT INTO public.timesegments SELECT * FROM public.timesegments_def WHERE unit_type = 'establishment' AND unit_id <@ p_establishment_id_ranges;
        END IF;
        IF p_legal_unit_id_ranges IS NOT NULL THEN
            PERFORM pg_advisory_xact_lock(hashtext('timesegments_legal_unit'));
            DELETE FROM public.timesegments WHERE unit_type = 'legal_unit' AND unit_id <@ p_legal_unit_id_ranges;
            INSERT INTO public.timesegments SELECT * FROM public.timesegments_def WHERE unit_type = 'legal_unit' AND unit_id <@ p_legal_unit_id_ranges;
        END IF;
        IF p_enterprise_id_ranges IS NOT NULL THEN
            PERFORM pg_advisory_xact_lock(hashtext('timesegments_enterprise'));
            DELETE FROM public.timesegments WHERE unit_type = 'enterprise' AND unit_id <@ p_enterprise_id_ranges;
            INSERT INTO public.timesegments SELECT * FROM public.timesegments_def WHERE unit_type = 'enterprise' AND unit_id <@ p_enterprise_id_ranges;
        END IF;
    END IF;
END;
$procedure$;

-- ============================================================================
-- Restore statistical_unit_refresh with advisory locks
-- ============================================================================

CREATE OR REPLACE PROCEDURE public.statistical_unit_refresh(IN p_establishment_id_ranges int4multirange DEFAULT NULL::int4multirange, IN p_legal_unit_id_ranges int4multirange DEFAULT NULL::int4multirange, IN p_enterprise_id_ranges int4multirange DEFAULT NULL::int4multirange)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_batch_size INT := 262144;
    v_min_id int; v_max_id int; v_start_id int; v_end_id int;
    v_batch_num INT;
    v_total_units INT;
    v_batch_start_time timestamptz;
    v_batch_duration_ms numeric;
    v_batch_speed numeric;
    v_current_batch_size int;
    v_is_partial_refresh BOOLEAN;
BEGIN
    v_is_partial_refresh := (p_establishment_id_ranges IS NOT NULL 
                            OR p_legal_unit_id_ranges IS NOT NULL 
                            OR p_enterprise_id_ranges IS NOT NULL);

    IF NOT v_is_partial_refresh THEN
        -- Full refresh with ANALYZE
        ANALYZE public.timeline_establishment, public.timeline_legal_unit, public.timeline_enterprise;

        CREATE TEMP TABLE statistical_unit_new (LIKE public.statistical_unit) ON COMMIT DROP;

        -- Establishments
        v_batch_num := 0;
        SELECT MIN(unit_id), MAX(unit_id), COUNT(unit_id) INTO v_min_id, v_max_id, v_total_units FROM public.timesegments WHERE unit_type = 'establishment';
        RAISE DEBUG 'Refreshing statistical units for % establishments in batches of %...', v_total_units, v_batch_size;
        IF v_min_id IS NOT NULL THEN FOR i IN v_min_id..v_max_id BY v_batch_size LOOP
            v_batch_start_time := clock_timestamp();
            v_batch_num := v_batch_num + 1;
            v_start_id := i; v_end_id := i + v_batch_size - 1;
            INSERT INTO statistical_unit_new SELECT * FROM public.statistical_unit_def
            WHERE unit_type = 'establishment' AND unit_id BETWEEN v_start_id AND v_end_id;
            v_batch_duration_ms := (EXTRACT(EPOCH FROM (clock_timestamp() - v_batch_start_time))) * 1000;
            v_current_batch_size := v_batch_size;
            v_batch_speed := v_current_batch_size / (v_batch_duration_ms / 1000.0);
            RAISE DEBUG 'Establishment SU batch %/% done. (% units, % ms, % units/s)', v_batch_num, ceil(v_total_units::decimal / v_batch_size), v_current_batch_size, round(v_batch_duration_ms), round(v_batch_speed);
        END LOOP; END IF;

        -- Legal Units
        v_batch_num := 0;
        SELECT MIN(unit_id), MAX(unit_id), COUNT(unit_id) INTO v_min_id, v_max_id, v_total_units FROM public.timesegments WHERE unit_type = 'legal_unit';
        RAISE DEBUG 'Refreshing statistical units for % legal units in batches of %...', v_total_units, v_batch_size;
        IF v_min_id IS NOT NULL THEN FOR i IN v_min_id..v_max_id BY v_batch_size LOOP
            v_batch_start_time := clock_timestamp();
            v_batch_num := v_batch_num + 1;
            v_start_id := i; v_end_id := i + v_batch_size - 1;
            INSERT INTO statistical_unit_new SELECT * FROM public.statistical_unit_def
            WHERE unit_type = 'legal_unit' AND unit_id BETWEEN v_start_id AND v_end_id;
            v_batch_duration_ms := (EXTRACT(EPOCH FROM (clock_timestamp() - v_batch_start_time))) * 1000;
            v_current_batch_size := v_batch_size;
            v_batch_speed := v_current_batch_size / (v_batch_duration_ms / 1000.0);
            RAISE DEBUG 'Legal unit SU batch %/% done. (% units, % ms, % units/s)', v_batch_num, ceil(v_total_units::decimal / v_batch_size), v_current_batch_size, round(v_batch_duration_ms), round(v_batch_speed);
        END LOOP; END IF;

        -- Enterprises
        v_batch_num := 0;
        SELECT MIN(unit_id), MAX(unit_id), COUNT(unit_id) INTO v_min_id, v_max_id, v_total_units FROM public.timesegments WHERE unit_type = 'enterprise';
        RAISE DEBUG 'Refreshing statistical units for % enterprises in batches of %...', v_total_units, v_batch_size;
        IF v_min_id IS NOT NULL THEN FOR i IN v_min_id..v_max_id BY v_batch_size LOOP
            v_batch_start_time := clock_timestamp();
            v_batch_num := v_batch_num + 1;
            v_start_id := i; v_end_id := i + v_batch_size - 1;
            INSERT INTO statistical_unit_new SELECT * FROM public.statistical_unit_def
            WHERE unit_type = 'enterprise' AND unit_id BETWEEN v_start_id AND v_end_id;
            v_batch_duration_ms := (EXTRACT(EPOCH FROM (clock_timestamp() - v_batch_start_time))) * 1000;
            v_current_batch_size := v_batch_size;
            v_batch_speed := v_current_batch_size / (v_batch_duration_ms / 1000.0);
            RAISE DEBUG 'Enterprise SU batch %/% done. (% units, % ms, % units/s)', v_batch_num, ceil(v_total_units::decimal / v_batch_size), v_current_batch_size, round(v_batch_duration_ms), round(v_batch_speed);
        END LOOP; END IF;

        TRUNCATE public.statistical_unit;
        INSERT INTO public.statistical_unit SELECT * FROM statistical_unit_new;

        ANALYZE public.statistical_unit;
    ELSE
        -- Partial refresh with ADVISORY LOCKS to prevent B-tree page contention
        IF p_establishment_id_ranges IS NOT NULL THEN
            PERFORM pg_advisory_xact_lock(hashtext('statistical_unit_establishment'));
            DELETE FROM public.statistical_unit WHERE unit_type = 'establishment' AND unit_id <@ p_establishment_id_ranges;
            INSERT INTO public.statistical_unit 
            SELECT * FROM import.get_statistical_unit_data_partial('establishment', p_establishment_id_ranges);
        END IF;
        IF p_legal_unit_id_ranges IS NOT NULL THEN
            PERFORM pg_advisory_xact_lock(hashtext('statistical_unit_legal_unit'));
            DELETE FROM public.statistical_unit WHERE unit_type = 'legal_unit' AND unit_id <@ p_legal_unit_id_ranges;
            INSERT INTO public.statistical_unit 
            SELECT * FROM import.get_statistical_unit_data_partial('legal_unit', p_legal_unit_id_ranges);
        END IF;
        IF p_enterprise_id_ranges IS NOT NULL THEN
            PERFORM pg_advisory_xact_lock(hashtext('statistical_unit_enterprise'));
            DELETE FROM public.statistical_unit WHERE unit_type = 'enterprise' AND unit_id <@ p_enterprise_id_ranges;
            INSERT INTO public.statistical_unit 
            SELECT * FROM import.get_statistical_unit_data_partial('enterprise', p_enterprise_id_ranges);
        END IF;
    END IF;
END;
$procedure$;

-- ============================================================================
-- Restore worker.process_tasks without retry logic
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
    FROM worker.tasks t
    JOIN worker.command_registry cr ON t.command = cr.command
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
      -- NULL MODE (backward compatible): Original behavior
      -- Pick children if waiting parent exists, otherwise top-level task
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

END;

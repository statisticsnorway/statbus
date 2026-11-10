BEGIN;

CREATE OR REPLACE FUNCTION admin.import_job_assign_batch_seq(p_data_table_name text, p_batch_size integer, p_for_processing boolean DEFAULT false, p_new_state import_data_state DEFAULT NULL::import_data_state, p_reset_priority boolean DEFAULT false)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_total_rows INTEGER;
    v_extra_sets TEXT := '';
BEGIN
    -- Build optional SET clauses for atomic multi-column update
    IF p_new_state IS NOT NULL THEN
        v_extra_sets := v_extra_sets || format(', state = %L', p_new_state);
    END IF;
    IF p_reset_priority THEN
        v_extra_sets := v_extra_sets || ', last_completed_priority = 0';
    END IF;

    IF p_for_processing THEN
        -- For processing phase: assign batch_seq only to rows with action = 'use'.
        -- NULL out batch_seq for non-'use' rows. These rows should already be in 'error' state
        -- (set by analyse_external_idents when action='skip'), but we defensively ensure it here
        -- to satisfy the CHECK constraint (which requires batch_seq IS NOT NULL for 'analysing' state).
        EXECUTE format($$UPDATE public.%1$I SET batch_seq = NULL, state = 'error' WHERE action IS DISTINCT FROM 'use' AND state != 'error'$$, p_data_table_name);
        
        -- Re-assign batch_seq to 'use' rows, optionally updating state and priority atomically.
        EXECUTE format($$
            WITH numbered AS (
                SELECT row_id, 
                       ((row_number() OVER (ORDER BY row_id) - 1) / %2$L + 1)::INTEGER as batch_num
                FROM public.%1$I
                WHERE action = 'use'
            )
            UPDATE public.%1$I dt
            SET batch_seq = numbered.batch_num %3$s
            FROM numbered
            WHERE dt.row_id = numbered.row_id
        $$, p_data_table_name, p_batch_size, v_extra_sets);
    ELSE
        -- For analysis phase: assign batch_seq to ALL rows, optionally updating state atomically.
        EXECUTE format($$
            UPDATE public.%1$I
            SET batch_seq = ((row_id - 1) / %2$L + 1)::INTEGER %3$s
            WHERE true -- every row: the analysis phase numbers all rows
        $$, p_data_table_name, p_batch_size, v_extra_sets);
    END IF;
    
    GET DIAGNOSTICS v_total_rows = ROW_COUNT;
    RETURN v_total_rows;
END;
$function$

;

CREATE OR REPLACE PROCEDURE worker.statistical_unit_flush_staging(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_staging_count bigint;
    v_history_task worker.tasks;
BEGIN
    -- Clean up obsolete years
    DELETE FROM public.timesegments_years AS ty
    WHERE NOT EXISTS (
        SELECT 1 FROM public.timesegments AS t
        WHERE t.valid_from >= make_date(ty.year, 1, 1)
          AND t.valid_from < make_date(ty.year + 1, 1, 1)
        LIMIT 1
    );

    -- Auto-tune partition count target based on current data size
    CALL admin.adjust_partition_count_target();

    SELECT h.* INTO v_history_task
      FROM worker.tasks AS me
      JOIN worker.tasks AS h ON h.parent_id = me.parent_id AND h.command = 'derive_statistical_history_facet_delta'
     WHERE me.state = 'processing' AND me.worker_pid = pg_backend_pid() AND me.command = 'statistical_unit_flush_staging'
     ORDER BY h.id DESC LIMIT 1;
    IF v_history_task.state = 'completed' THEN
        UPDATE worker.statistical_history_facet_delta_state SET flushed_generation = v_history_task.id
         WHERE true; -- the single state row (unique index on (true))
    ELSIF EXISTS (SELECT 1 FROM public.statistical_unit_staging) THEN
        UPDATE worker.statistical_history_facet_delta_state SET rebuild_needed = true
         WHERE NOT rebuild_needed;
    END IF;

    SELECT count(*) INTO v_staging_count FROM public.statistical_unit_staging;
    CALL public.statistical_unit_flush_staging();
    PERFORM pg_notify('worker_status',
        json_build_object('type', 'is_deriving_statistical_units', 'status', false)::text);
    p_info := jsonb_build_object('rows_flushed', v_staging_count,
                                 'history_generation_flushed', CASE WHEN v_history_task.state = 'completed' THEN v_history_task.id END);
END;
$procedure$

;

CREATE OR REPLACE PROCEDURE worker.derive_statistical_history_facet_delta(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_task_id bigint;
    v_state worker.statistical_history_facet_delta_state;
    v_rebuild boolean;
    v_range_size integer;
    v_range int4range;
    v_child_count integer := 0;
    v_discarded bigint := 0;
BEGIN
    SELECT id INTO v_task_id FROM worker.tasks
     WHERE state = 'processing' AND worker_pid = pg_backend_pid()
     ORDER BY id DESC LIMIT 1;
    SELECT * INTO v_state FROM worker.statistical_history_facet_delta_state FOR UPDATE;

    -- Rebuild on an all-time derive (valid_from = -infinity, valid_until = infinity:
    -- worker.enqueue_derive_statistical_unit_all), while an earlier rebuild is not yet added, when units
    -- were flushed without their deltas, and on a cycle that finds the tables empty while statistical_unit
    -- has rows.
    v_rebuild := ((payload->>'valid_from')::date = '-infinity'::date AND (payload->>'valid_until')::date = 'infinity'::date)
        OR v_state.rebuild_generation IS NOT NULL
        OR v_state.rebuild_needed
        OR (NOT EXISTS (SELECT 1 FROM public.statistical_history_facet_delta LIMIT 1)
            AND EXISTS (SELECT 1 FROM public.statistical_unit LIMIT 1));

    IF v_rebuild THEN
        -- The rebuild's rows replace the tables, so no earlier staged row is needed.
        SELECT count(*) INTO v_discarded FROM public.statistical_history_facet_delta_staging;
        TRUNCATE public.statistical_history_facet_delta_staging;
        UPDATE worker.statistical_history_facet_delta_state
           SET rebuild_generation = v_task_id, rebuild_needed = false
         WHERE true; -- the single state row (unique index on (true))
    ELSE
        -- Rows of a cycle whose flush never committed: its units are still in statistical_unit_staging
        -- and are staged again below, against the same statistical_unit.
        WITH s AS (DELETE FROM public.statistical_history_facet_delta_staging
                    WHERE generation > v_state.flushed_generation RETURNING 1)
        SELECT count(*) INTO v_discarded FROM s;
    END IF;

    v_range_size := GREATEST(1, 16384 / public.partition_count_target_for(GREATEST(
        (SELECT count(*) FROM public.statistical_unit),
        (SELECT count(*) FROM public.statistical_unit_staging))));

    FOR v_range IN
        SELECT DISTINCT int4range((s.hash_slot / v_range_size) * v_range_size,
                                  LEAST((s.hash_slot / v_range_size) * v_range_size + v_range_size, 16384))
          FROM (SELECT hash_slot FROM public.statistical_unit_staging
                UNION ALL
                SELECT hash_slot FROM public.statistical_unit WHERE v_rebuild) AS s
         ORDER BY 1
    LOOP
        PERFORM worker.spawn(
            p_command => 'derive_statistical_history_facet_delta_partition',
            p_payload => jsonb_build_object('command', 'derive_statistical_history_facet_delta_partition',
                                            'hash_range', v_range::text, 'rebuild', v_rebuild,
                                            'generation', v_task_id),
            p_parent_id => v_task_id);
        v_child_count := v_child_count + 1;
    END LOOP;

    p_info := jsonb_build_object('child_count', v_child_count, 'rebuild', v_rebuild, 'range_size', v_range_size,
                                 'unflushed_rows_discarded', v_discarded);
END;
$procedure$

;

CREATE OR REPLACE PROCEDURE worker.statistical_history_facet_delta_reduce(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_state worker.statistical_history_facet_delta_state;
    v_staged bigint;
    v_applied text;
BEGIN
    SELECT * INTO v_state FROM worker.statistical_history_facet_delta_state FOR UPDATE;
    SELECT count(*) INTO v_staged FROM public.statistical_history_facet_delta_staging
     WHERE generation <= v_state.flushed_generation;
    IF v_state.rebuild_generation IS NULL THEN
        CALL worker.statistical_history_facet_delta_apply();
        v_applied := 'added';
    ELSIF v_state.rebuild_generation <= v_state.flushed_generation THEN
        CALL worker.statistical_history_facet_delta_apply(p_replace => true);
        UPDATE worker.statistical_history_facet_delta_state SET rebuild_generation = NULL
         WHERE rebuild_generation IS NOT NULL;
        v_applied := 'replaced';
    ELSE
        -- The rebuild cycle's flush has not committed: the tables keep their rows, and the next cycle
        -- rebuilds again.
        v_applied := 'rebuild not flushed';
    END IF;
    CALL public.statistical_history_period_refresh();
    TRUNCATE public.statistical_unit_facet_dirty_hash_slots;
    PERFORM pg_notify('worker_status',
        json_build_object('type', 'is_deriving_reports', 'status', false)::text);
    p_info := jsonb_build_object('rows_staged', v_staged, 'applied', v_applied);
END;
$procedure$

;


END;

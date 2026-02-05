-- Down Migration: Revert O(n²) fix for timeline_enterprise refresh
BEGIN;

-- Restore original timeline_enterprise_refresh procedure that uses dynamic SQL with the view
CREATE OR REPLACE PROCEDURE public.timeline_enterprise_refresh(p_unit_id_ranges int4multirange DEFAULT NULL)
LANGUAGE plpgsql
AS $timeline_enterprise_refresh$
DECLARE
    p_target_table text := 'timeline_enterprise';
    p_unit_type public.statistical_unit_type := 'enterprise';
    v_batch_size INT := 32768;
    v_def_view_name text := p_target_table || '_def';
    v_min_id int; v_max_id int; v_start_id int; v_end_id int;
    v_batch_num INT := 0;
    v_total_units INT;
    v_batch_start_time timestamptz;
    v_batch_duration_ms numeric;
    v_batch_speed numeric;
    v_current_batch_size int;
    -- Array for btree-optimized queries
    v_unit_ids INT[];
BEGIN
    -- Only ANALYZE for full refresh (sync points handle partial refresh ANALYZE)
    IF p_unit_id_ranges IS NULL THEN
        ANALYZE public.timesegments, public.enterprise, public.timeline_legal_unit, public.timeline_establishment;
    END IF;

    IF p_unit_id_ranges IS NOT NULL THEN
        -- Partial refresh: Use = ANY(array) for btree index optimization
        v_unit_ids := public.int4multirange_to_array(p_unit_id_ranges);

        EXECUTE format('DELETE FROM public.%I WHERE unit_type = %L AND unit_id = ANY(%L::INT[])',
                       p_target_table, p_unit_type, v_unit_ids);
        EXECUTE format('INSERT INTO public.%I SELECT * FROM public.%I WHERE unit_type = %L AND unit_id = ANY(%L::INT[])',
                       p_target_table, v_def_view_name, p_unit_type, v_unit_ids);
    ELSE
        -- Full refresh
        SELECT MIN(unit_id), MAX(unit_id), COUNT(unit_id) INTO v_min_id, v_max_id, v_total_units FROM public.timesegments WHERE unit_type = p_unit_type;
        IF v_min_id IS NULL THEN RETURN; END IF;

        RAISE DEBUG 'Refreshing enterprise timeline for % units in batches of %...', v_total_units, v_batch_size;
        FOR i IN v_min_id..v_max_id BY v_batch_size LOOP
            v_batch_start_time := clock_timestamp();
            v_batch_num := v_batch_num + 1;
            v_start_id := i; v_end_id := i + v_batch_size - 1;
            EXECUTE format('DELETE FROM public.%I WHERE unit_type = %L AND unit_id BETWEEN %L AND %L',
                           p_target_table, p_unit_type, v_start_id, v_end_id);
            EXECUTE format('INSERT INTO public.%I SELECT * FROM public.%I WHERE unit_type = %L AND unit_id BETWEEN %L AND %L',
                           p_target_table, v_def_view_name, p_unit_type, v_start_id, v_end_id);

            v_batch_duration_ms := (EXTRACT(EPOCH FROM (clock_timestamp() - v_batch_start_time))) * 1000;
            v_current_batch_size := v_batch_size;
            v_batch_speed := v_current_batch_size / (v_batch_duration_ms / 1000.0);
            RAISE DEBUG 'Enterprise timeline batch %/% done. (% units, % ms, % units/s)', v_batch_num, ceil(v_total_units::decimal / v_batch_size), v_current_batch_size, round(v_batch_duration_ms), round(v_batch_speed);
        END LOOP;

        EXECUTE format('ANALYZE public.%I', p_target_table);
    END IF;
END;
$timeline_enterprise_refresh$;

END;

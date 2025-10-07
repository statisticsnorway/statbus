```sql
CREATE OR REPLACE PROCEDURE public.timeline_refresh(IN p_target_table text, IN p_unit_type statistical_unit_type, IN p_unit_id_ranges int4multirange DEFAULT NULL::int4multirange)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_batch_size INT := 65536;
    v_def_view_name text := p_target_table || '_def';
    v_min_id int; v_max_id int; v_start_id int; v_end_id int;
    v_batch_num INT := 0;
    v_total_units INT;
    v_batch_start_time timestamptz;
    v_batch_duration_ms numeric;
    v_batch_speed numeric;
    v_current_batch_size int;
BEGIN
    IF p_unit_id_ranges IS NOT NULL THEN
        EXECUTE format('DELETE FROM public.%I WHERE unit_type = %L AND unit_id <@ %L::int4multirange', p_target_table, p_unit_type, p_unit_id_ranges);
        EXECUTE format('INSERT INTO public.%I SELECT * FROM public.%I WHERE unit_type = %L AND unit_id <@ %L::int4multirange',
                       p_target_table, v_def_view_name, p_unit_type, p_unit_id_ranges);
    ELSE
        SELECT MIN(unit_id), MAX(unit_id), COUNT(unit_id) INTO v_min_id, v_max_id, v_total_units FROM public.timesegments WHERE unit_type = p_unit_type;
        IF v_min_id IS NULL THEN RETURN; END IF;

        RAISE DEBUG 'Refreshing % for % units in batches of %...', p_target_table, v_total_units, v_batch_size;
        FOR i IN v_min_id..v_max_id BY v_batch_size LOOP
            v_batch_start_time := clock_timestamp();
            v_batch_num := v_batch_num + 1;
            v_start_id := i; v_end_id := i + v_batch_size - 1;

            EXECUTE format('DELETE FROM public.%I WHERE unit_type = %L AND unit_id BETWEEN %L AND %L',
                           p_target_table, p_unit_type, v_start_id, v_end_id);
            EXECUTE format('INSERT INTO public.%I SELECT * FROM public.%I WHERE unit_type = %L AND unit_id BETWEEN %L AND %L',
                           p_target_table, v_def_view_name, p_unit_type, v_start_id, v_end_id);

            v_batch_duration_ms := (EXTRACT(EPOCH FROM (clock_timestamp() - v_batch_start_time))) * 1000;
            v_current_batch_size := v_batch_size; -- Simplified for this loop type
            v_batch_speed := v_current_batch_size / (v_batch_duration_ms / 1000.0);
            RAISE DEBUG '% batch %/% done. (% units, % ms, % units/s)', p_target_table, v_batch_num, ceil(v_total_units::decimal / v_batch_size), v_current_batch_size, round(v_batch_duration_ms), round(v_batch_speed);
        END LOOP;
    END IF;

    EXECUTE format('ANALYZE public.%I', p_target_table);
END;
$procedure$
```

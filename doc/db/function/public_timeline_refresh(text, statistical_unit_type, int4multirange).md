```sql
CREATE OR REPLACE PROCEDURE public.timeline_refresh(IN p_target_table text, IN p_unit_type statistical_unit_type, IN p_unit_id_ranges int4multirange DEFAULT NULL::int4multirange)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_batch_size INT := 50000;
    v_def_view_name text := p_target_table || '_def';
    v_min_id int; v_max_id int; v_start_id int; v_end_id int;
BEGIN
    IF p_unit_id_ranges IS NOT NULL THEN
        EXECUTE format('DELETE FROM public.%I WHERE unit_type = %L AND unit_id <@ %L::int4multirange', p_target_table, p_unit_type, p_unit_id_ranges);
        EXECUTE format('INSERT INTO public.%I SELECT * FROM public.%I WHERE unit_type = %L AND unit_id <@ %L::int4multirange',
                       p_target_table, v_def_view_name, p_unit_type, p_unit_id_ranges);
    ELSE
        SELECT MIN(unit_id), MAX(unit_id) INTO v_min_id, v_max_id FROM public.timesegments WHERE unit_type = p_unit_type;
        IF v_min_id IS NULL THEN RETURN; END IF;

        FOR i IN v_min_id..v_max_id BY v_batch_size LOOP
            v_start_id := i; v_end_id := i + v_batch_size - 1;
            EXECUTE format('DELETE FROM public.%I WHERE unit_type = %L AND unit_id BETWEEN %L AND %L',
                           p_target_table, p_unit_type, v_start_id, v_end_id);
            EXECUTE format('INSERT INTO public.%I SELECT * FROM public.%I WHERE unit_type = %L AND unit_id BETWEEN %L AND %L',
                           p_target_table, v_def_view_name, p_unit_type, v_start_id, v_end_id);
        END LOOP;
    END IF;

    EXECUTE format('ANALYZE public.%I', p_target_table);
END;
$procedure$
```

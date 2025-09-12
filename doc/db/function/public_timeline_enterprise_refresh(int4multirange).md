```sql
CREATE OR REPLACE PROCEDURE public.timeline_enterprise_refresh(IN p_unit_id_ranges int4multirange DEFAULT NULL::int4multirange)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    p_target_table text := 'timeline_enterprise';
    p_unit_type public.statistical_unit_type := 'enterprise';
    v_batch_size INT := 10000; -- Reduced batch size for enterprises
    v_def_view_name text := p_target_table || '_def';
    v_min_id int; v_max_id int; v_start_id int; v_end_id int;
BEGIN
    ANALYZE public.timesegments, public.enterprise, public.timeline_legal_unit, public.timeline_establishment;

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

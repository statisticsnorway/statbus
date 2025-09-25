```sql
CREATE OR REPLACE PROCEDURE public.statistical_unit_refresh(IN p_establishment_id_ranges int4multirange DEFAULT NULL::int4multirange, IN p_legal_unit_id_ranges int4multirange DEFAULT NULL::int4multirange, IN p_enterprise_id_ranges int4multirange DEFAULT NULL::int4multirange)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_batch_size INT := 50000;
    v_min_id int; v_max_id int; v_start_id int; v_end_id int;
BEGIN
    ANALYZE public.timeline_establishment, public.timeline_legal_unit, public.timeline_enterprise;

    IF p_establishment_id_ranges IS NULL AND p_legal_unit_id_ranges IS NULL AND p_enterprise_id_ranges IS NULL THEN
        -- Full refresh: Use a staging table for performance and to minimize lock duration.
        CREATE TEMP TABLE statistical_unit_new (LIKE public.statistical_unit) ON COMMIT DROP;

        -- Establishments
        SELECT MIN(unit_id), MAX(unit_id) INTO v_min_id, v_max_id FROM public.timesegments WHERE unit_type = 'establishment';
        IF v_min_id IS NOT NULL THEN FOR i IN v_min_id..v_max_id BY v_batch_size LOOP
            v_start_id := i; v_end_id := i + v_batch_size - 1;
            INSERT INTO statistical_unit_new SELECT * FROM public.statistical_unit_def
            WHERE unit_type = 'establishment' AND unit_id BETWEEN v_start_id AND v_end_id;
        END LOOP; END IF;

        -- Legal Units
        SELECT MIN(unit_id), MAX(unit_id) INTO v_min_id, v_max_id FROM public.timesegments WHERE unit_type = 'legal_unit';
        IF v_min_id IS NOT NULL THEN FOR i IN v_min_id..v_max_id BY v_batch_size LOOP
            v_start_id := i; v_end_id := i + v_batch_size - 1;
            INSERT INTO statistical_unit_new SELECT * FROM public.statistical_unit_def
            WHERE unit_type = 'legal_unit' AND unit_id BETWEEN v_start_id AND v_end_id;
        END LOOP; END IF;

        -- Enterprises
        SELECT MIN(unit_id), MAX(unit_id) INTO v_min_id, v_max_id FROM public.timesegments WHERE unit_type = 'enterprise';
        IF v_min_id IS NOT NULL THEN FOR i IN v_min_id..v_max_id BY v_batch_size LOOP
            v_start_id := i; v_end_id := i + v_batch_size - 1;
            INSERT INTO statistical_unit_new SELECT * FROM public.statistical_unit_def
            WHERE unit_type = 'enterprise' AND unit_id BETWEEN v_start_id AND v_end_id;
        END LOOP; END IF;

        -- Atomically swap the data
        TRUNCATE public.statistical_unit;
        INSERT INTO public.statistical_unit SELECT * FROM statistical_unit_new;

    ELSE
        -- Partial refresh
        IF p_establishment_id_ranges IS NOT NULL THEN
            DELETE FROM public.statistical_unit WHERE unit_type = 'establishment' AND unit_id <@ p_establishment_id_ranges;
            INSERT INTO public.statistical_unit SELECT * FROM public.statistical_unit_def WHERE unit_type = 'establishment' AND unit_id <@ p_establishment_id_ranges;
        END IF;
        IF p_legal_unit_id_ranges IS NOT NULL THEN
            DELETE FROM public.statistical_unit WHERE unit_type = 'legal_unit' AND unit_id <@ p_legal_unit_id_ranges;
            INSERT INTO public.statistical_unit SELECT * FROM public.statistical_unit_def WHERE unit_type = 'legal_unit' AND unit_id <@ p_legal_unit_id_ranges;
        END IF;
        IF p_enterprise_id_ranges IS NOT NULL THEN
            DELETE FROM public.statistical_unit WHERE unit_type = 'enterprise' AND unit_id <@ p_enterprise_id_ranges;
            INSERT INTO public.statistical_unit SELECT * FROM public.statistical_unit_def WHERE unit_type = 'enterprise' AND unit_id <@ p_enterprise_id_ranges;
        END IF;
    END IF;

    ANALYZE public.statistical_unit;
END;
$procedure$
```

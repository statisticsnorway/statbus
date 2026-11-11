```sql
CREATE OR REPLACE PROCEDURE public.timesegments_refresh(IN p_establishment_id_ranges int4multirange DEFAULT NULL::int4multirange, IN p_legal_unit_id_ranges int4multirange DEFAULT NULL::int4multirange, IN p_enterprise_id_ranges int4multirange DEFAULT NULL::int4multirange, IN p_power_group_id_ranges int4multirange DEFAULT NULL::int4multirange)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_is_partial_refresh BOOLEAN;
    v_establishment_ids INT[]; v_legal_unit_ids INT[]; v_enterprise_ids INT[]; v_power_group_ids INT[];
BEGIN
    v_is_partial_refresh := (p_establishment_id_ranges IS NOT NULL
                            OR p_legal_unit_id_ranges IS NOT NULL
                            OR p_enterprise_id_ranges IS NOT NULL
                            OR p_power_group_id_ranges IS NOT NULL);
    IF NOT v_is_partial_refresh THEN
        ANALYZE public.timepoints;
        DELETE FROM public.timesegments WHERE true; -- every row: rebuilt below from timesegments_def
        INSERT INTO public.timesegments SELECT * FROM public.timesegments_def;
        ANALYZE public.timesegments;
        -- Full refresh: record all years from the new timesegments
        INSERT INTO public.timesegments_years (year)
        SELECT DISTINCT EXTRACT(year FROM t.valid_from)::int
        FROM public.timesegments AS t
        ON CONFLICT (year) DO NOTHING;
    ELSE
        IF p_establishment_id_ranges IS NOT NULL THEN
            v_establishment_ids := public.int4multirange_to_array(p_establishment_id_ranges);
            DELETE FROM public.timesegments WHERE unit_type = 'establishment' AND unit_id = ANY(v_establishment_ids);
            INSERT INTO public.timesegments SELECT * FROM public.timesegments_def WHERE unit_type = 'establishment' AND unit_id = ANY(v_establishment_ids);
        END IF;
        IF p_legal_unit_id_ranges IS NOT NULL THEN
            v_legal_unit_ids := public.int4multirange_to_array(p_legal_unit_id_ranges);
            DELETE FROM public.timesegments WHERE unit_type = 'legal_unit' AND unit_id = ANY(v_legal_unit_ids);
            INSERT INTO public.timesegments SELECT * FROM public.timesegments_def WHERE unit_type = 'legal_unit' AND unit_id = ANY(v_legal_unit_ids);
        END IF;
        IF p_enterprise_id_ranges IS NOT NULL THEN
            v_enterprise_ids := public.int4multirange_to_array(p_enterprise_id_ranges);
            DELETE FROM public.timesegments WHERE unit_type = 'enterprise' AND unit_id = ANY(v_enterprise_ids);
            INSERT INTO public.timesegments SELECT * FROM public.timesegments_def WHERE unit_type = 'enterprise' AND unit_id = ANY(v_enterprise_ids);
        END IF;
        IF p_power_group_id_ranges IS NOT NULL THEN
            v_power_group_ids := public.int4multirange_to_array(p_power_group_id_ranges);
            DELETE FROM public.timesegments WHERE unit_type = 'power_group' AND unit_id = ANY(v_power_group_ids);
            INSERT INTO public.timesegments SELECT * FROM public.timesegments_def WHERE unit_type = 'power_group' AND unit_id = ANY(v_power_group_ids);
        END IF;
        -- Partial refresh: record years from the batch's timesegments (O(batch_size)).
        -- Handles historical data: extracts actual years from whatever dates are processed.
        -- One statement per unit type, each with only its own id filter, so its plan reads the batch's
        -- segments through the (unit_type, unit_id) btree at any call count. A single statement OR-ing four
        -- flag-guarded filters got a generic plan after five calls in a worker session; not knowing which
        -- filters applied, it read through the GiST daterange index on its non-leading columns: 1,234 ms
        -- per 8000-unit batch instead of 11 ms (STATBUS-615).
        IF p_establishment_id_ranges IS NOT NULL THEN
            INSERT INTO public.timesegments_years (year)
            SELECT DISTINCT EXTRACT(year FROM t.valid_from)::int
            FROM public.timesegments AS t
            WHERE t.unit_type = 'establishment' AND t.unit_id = ANY(v_establishment_ids)
            ON CONFLICT (year) DO NOTHING;
        END IF;
        IF p_legal_unit_id_ranges IS NOT NULL THEN
            INSERT INTO public.timesegments_years (year)
            SELECT DISTINCT EXTRACT(year FROM t.valid_from)::int
            FROM public.timesegments AS t
            WHERE t.unit_type = 'legal_unit' AND t.unit_id = ANY(v_legal_unit_ids)
            ON CONFLICT (year) DO NOTHING;
        END IF;
        IF p_enterprise_id_ranges IS NOT NULL THEN
            INSERT INTO public.timesegments_years (year)
            SELECT DISTINCT EXTRACT(year FROM t.valid_from)::int
            FROM public.timesegments AS t
            WHERE t.unit_type = 'enterprise' AND t.unit_id = ANY(v_enterprise_ids)
            ON CONFLICT (year) DO NOTHING;
        END IF;
        IF p_power_group_id_ranges IS NOT NULL THEN
            INSERT INTO public.timesegments_years (year)
            SELECT DISTINCT EXTRACT(year FROM t.valid_from)::int
            FROM public.timesegments AS t
            WHERE t.unit_type = 'power_group' AND t.unit_id = ANY(v_power_group_ids)
            ON CONFLICT (year) DO NOTHING;
        END IF;
    END IF;
END;
$procedure$
```

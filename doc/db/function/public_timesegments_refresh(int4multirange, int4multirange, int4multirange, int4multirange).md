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
        DELETE FROM public.timesegments;
        INSERT INTO public.timesegments SELECT * FROM public.timesegments_def;
        ANALYZE public.timesegments;
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
    END IF;
END;
$procedure$
```

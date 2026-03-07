```sql
CREATE OR REPLACE PROCEDURE public.timeline_power_group_refresh(IN p_unit_id_ranges int4multirange DEFAULT NULL::int4multirange)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_unit_ids INT[];
BEGIN
    IF p_unit_id_ranges IS NULL THEN
        TRUNCATE public.timeline_power_group;
        INSERT INTO public.timeline_power_group SELECT * FROM public.timeline_power_group_def;
        ANALYZE public.timeline_power_group;
    ELSE
        v_unit_ids := public.int4multirange_to_array(p_unit_id_ranges);
        DELETE FROM public.timeline_power_group WHERE unit_id = ANY(v_unit_ids);
        INSERT INTO public.timeline_power_group
        SELECT * FROM public.timeline_power_group_def WHERE unit_id = ANY(v_unit_ids);
    END IF;
END;
$procedure$
```

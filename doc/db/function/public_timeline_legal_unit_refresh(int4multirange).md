```sql
CREATE OR REPLACE PROCEDURE public.timeline_legal_unit_refresh(IN p_unit_id_ranges int4multirange DEFAULT NULL::int4multirange)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_unit_ids INT[];
BEGIN
    IF p_unit_id_ranges IS NULL THEN
        -- Full refresh: GUC not set, view scans everything
        ANALYZE public.timesegments, public.legal_unit, public.activity, public.location, public.contact, public.stat_for_unit, public.timeline_establishment;
        CALL public.timeline_refresh('timeline_legal_unit', 'legal_unit', p_unit_id_ranges);
    ELSE
        -- Partial refresh: set GUC so the view self-filters its CTEs
        v_unit_ids := public.int4multirange_to_array(p_unit_id_ranges);
        PERFORM set_config('statbus.filter_unit_ids',
                           array_to_string(v_unit_ids, ','), true);
        CALL public.timeline_refresh('timeline_legal_unit', 'legal_unit', p_unit_id_ranges);
        -- Clear GUC (also auto-clears on transaction end, but be explicit)
        PERFORM set_config('statbus.filter_unit_ids', '', true);
    END IF;
END;
$procedure$
```

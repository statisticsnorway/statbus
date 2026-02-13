```sql
CREATE OR REPLACE PROCEDURE public.timeline_establishment_refresh(IN p_unit_id_ranges int4multirange DEFAULT NULL::int4multirange)
 LANGUAGE plpgsql
AS $procedure$
BEGIN
    -- Only ANALYZE for full refresh (sync points handle partial refresh ANALYZE)
    IF p_unit_id_ranges IS NULL THEN
        ANALYZE public.timesegments, public.establishment, public.activity, public.location, public.contact, public.stat_for_unit;
    END IF;
    CALL public.timeline_refresh('timeline_establishment', 'establishment', p_unit_id_ranges);
END;
$procedure$
```

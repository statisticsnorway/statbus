```sql
CREATE OR REPLACE PROCEDURE public.timeline_establishment_refresh(IN p_unit_id_ranges int4multirange DEFAULT NULL::int4multirange)
 LANGUAGE plpgsql
AS $procedure$
BEGIN
    ANALYZE public.timesegments, public.establishment, public.activity, public.location, public.contact, public.stat_for_unit;
    CALL public.timeline_refresh('timeline_establishment', 'establishment', p_unit_id_ranges);
END;
$procedure$
```

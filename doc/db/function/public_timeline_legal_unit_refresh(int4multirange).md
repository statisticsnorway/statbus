```sql
CREATE OR REPLACE PROCEDURE public.timeline_legal_unit_refresh(IN p_unit_id_ranges int4multirange DEFAULT NULL::int4multirange)
 LANGUAGE plpgsql
AS $procedure$
BEGIN
    ANALYZE public.timesegments, public.legal_unit, public.activity, public.location, public.contact, public.stat_for_unit, public.timeline_establishment;
    CALL public.timeline_refresh('timeline_legal_unit', 'legal_unit', p_unit_id_ranges);
END;
$procedure$
```

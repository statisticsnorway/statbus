```sql
CREATE OR REPLACE PROCEDURE public.timeline_establishment_refresh(IN p_unit_id_ranges int4multirange DEFAULT NULL::int4multirange)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_unit_ids INT[];
BEGIN
    IF p_unit_id_ranges IS NULL THEN
        -- Full refresh: the view (timeline_establishment_def_for(NULL)) in ranges of unit ids.
        ANALYZE public.timesegments, public.establishment, public.activity, public.location, public.contact, public.stat_for_unit;
        CALL public.timeline_refresh('timeline_establishment', 'establishment', p_unit_id_ranges);
    ELSE
        -- Partial refresh: the batch's ids go to timeline_establishment_def_for, which reads only their rows.
        -- EXECUTE plans each call with the batch's ids; a cached generic plan of a static
        -- statement would not know them and read every establishment's timesegments.
        v_unit_ids := public.int4multirange_to_array(p_unit_id_ranges);
        EXECUTE $refresh$
            DELETE FROM public.timeline_establishment
             WHERE unit_type = 'establishment' AND unit_id = ANY($1)
        $refresh$ USING v_unit_ids;
        EXECUTE $refresh$
            INSERT INTO public.timeline_establishment
            SELECT * FROM public.timeline_establishment_def_for($1)
        $refresh$ USING v_unit_ids;
    END IF;
END;
$procedure$
```

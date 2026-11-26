```sql
CREATE OR REPLACE FUNCTION worker.log_region_change()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_est_ids int4multirange;
    v_lu_ids int4multirange;
    v_valid_ranges datemultirange;
    v_source TEXT;
BEGIN
    -- Build source query based on operation. An UPDATE reaches the units only through a region
    -- whose path changed: units carry the region's path and code (code is generated from path),
    -- not its name or centre. A changed name is set in region_used here.
    CASE TG_OP
        WHEN 'INSERT' THEN v_source := 'SELECT * FROM new_rows';
        WHEN 'DELETE' THEN v_source := 'SELECT * FROM old_rows';
        WHEN 'UPDATE' THEN
            v_source := 'SELECT o.* FROM old_rows AS o JOIN new_rows AS n ON n.id = o.id'
                     || ' WHERE n.path OPERATOR(public.<>) o.path';
            -- A renamed region's name in region_used, in place: only the renamed rows.
            UPDATE public.region_used AS ru
               SET name = n.name
              FROM new_rows AS n
             WHERE ru.id = n.id
               AND ru.name IS DISTINCT FROM n.name;
        ELSE RAISE EXCEPTION 'log_region_change: unsupported operation %', TG_OP;
    END CASE;

    -- Find affected units by joining region → location
    EXECUTE format(
        $SQL$
        SELECT
            COALESCE(range_agg(int4range(l.establishment_id, l.establishment_id, '[]')) FILTER (WHERE l.establishment_id IS NOT NULL), '{}'::int4multirange),
            COALESCE(range_agg(int4range(l.legal_unit_id, l.legal_unit_id, '[]')) FILTER (WHERE l.legal_unit_id IS NOT NULL), '{}'::int4multirange),
            COALESCE(range_agg(l.valid_range) FILTER (WHERE l.valid_range IS NOT NULL), '{}'::datemultirange)
        FROM (%s) AS affected_regions
        JOIN public.location AS l ON l.region_id = affected_regions.id
        $SQL$,
        v_source
    ) INTO v_est_ids, v_lu_ids, v_valid_ranges;

    IF v_est_ids != '{}'::int4multirange
       OR v_lu_ids != '{}'::int4multirange THEN
        INSERT INTO worker.base_change_log (establishment_ids, legal_unit_ids, enterprise_ids, power_group_ids, valid_ranges)
        VALUES (v_est_ids, v_lu_ids, '{}'::int4multirange, '{}'::int4multirange, v_valid_ranges);

        PERFORM worker.publish_base_change_wakeup();
    END IF;

    RETURN NULL;
END;
$function$
```

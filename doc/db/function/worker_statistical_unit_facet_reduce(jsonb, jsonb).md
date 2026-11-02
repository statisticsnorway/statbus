```sql
CREATE OR REPLACE PROCEDURE worker.statistical_unit_facet_reduce(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_dirty_hash_slots int[];
    v_row_count bigint;
BEGIN
    -- Read dirty hash slots for diagnostic logging only. The MERGE below
    -- is geometry-agnostic and operates on the full staging-aggregate, so
    -- the dirty set no longer gates which rows get touched.
    SELECT array_agg(dp.dirty_hash_slot)
      INTO v_dirty_hash_slots
      FROM public.statistical_unit_facet_dirty_hash_slots AS dp;

    MERGE INTO public.statistical_unit_facet AS target
    USING (
        SELECT s.valid_from, s.valid_to, s.valid_until, s.unit_type,
               s.physical_region_path, s.primary_activity_category_path,
               s.sector_path, s.legal_form_id, s.physical_country_id, s.status_id,
               SUM(s.count)::BIGINT AS count,
               jsonb_stats_merge_agg(s.stats_summary) AS stats_summary
          FROM public.statistical_unit_facet_staging AS s
         GROUP BY s.valid_from, s.valid_to, s.valid_until, s.unit_type,
                  s.physical_region_path, s.primary_activity_category_path,
                  s.sector_path, s.legal_form_id, s.physical_country_id, s.status_id
    ) AS source
       ON target.valid_from = source.valid_from
      AND target.valid_to = source.valid_to
      AND COALESCE(target.valid_until, 'infinity'::date) = COALESCE(source.valid_until, 'infinity'::date)
      AND target.unit_type = source.unit_type
      AND COALESCE(target.physical_region_path::text, '') = COALESCE(source.physical_region_path::text, '')
      AND COALESCE(target.primary_activity_category_path::text, '') = COALESCE(source.primary_activity_category_path::text, '')
      AND COALESCE(target.sector_path::text, '') = COALESCE(source.sector_path::text, '')
      AND COALESCE(target.legal_form_id, -1) = COALESCE(source.legal_form_id, -1)
      AND COALESCE(target.physical_country_id, -1) = COALESCE(source.physical_country_id, -1)
      AND COALESCE(target.status_id, -1) = COALESCE(source.status_id, -1)
    WHEN MATCHED AND (target.count <> source.count
                      OR target.stats_summary IS DISTINCT FROM source.stats_summary)
        THEN UPDATE SET count = source.count,
                        stats_summary = source.stats_summary
    WHEN NOT MATCHED BY TARGET
        THEN INSERT (valid_from, valid_to, valid_until, unit_type,
                     physical_region_path, primary_activity_category_path,
                     sector_path, legal_form_id, physical_country_id, status_id,
                     count, stats_summary)
             VALUES (source.valid_from, source.valid_to, source.valid_until, source.unit_type,
                     source.physical_region_path, source.primary_activity_category_path,
                     source.sector_path, source.legal_form_id, source.physical_country_id, source.status_id,
                     source.count, source.stats_summary)
    WHEN NOT MATCHED BY SOURCE THEN DELETE;
    GET DIAGNOSTICS v_row_count := ROW_COUNT;

    p_info := jsonb_build_object(
        'mode', 'global',
        'dirty_hash_slots', to_jsonb(v_dirty_hash_slots),
        'rows_merged', v_row_count);
END;
$procedure$
```

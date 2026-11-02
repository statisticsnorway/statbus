```sql
CREATE OR REPLACE PROCEDURE worker.statistical_unit_facet_reduce(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_dirty_hash_slots int[];
    v_row_count bigint;
    v_mode text;
    v_changed_count bigint;
BEGIN
    -- Read dirty hash slots for diagnostic logging.
    SELECT array_agg(dp.dirty_hash_slot)
      INTO v_dirty_hash_slots
      FROM public.statistical_unit_facet_dirty_hash_slots AS dp;

    -- Reduce as the sibling worker.derive_statistical_unit_facet derived: in
    -- 'dirty' mode its children recorded every changed combination, so only
    -- those are recomputed. Anything else (a full derive, or a direct CALL
    -- outside the pipeline) recomputes the whole cache.
    SELECT sibling.info->>'mode'
      INTO v_mode
      FROM worker.tasks AS self
      JOIN worker.tasks AS sibling
        ON sibling.parent_id = self.parent_id
       AND sibling.command = 'derive_statistical_unit_facet'
     WHERE self.state = 'processing' AND self.worker_pid = pg_backend_pid()
       AND self.command = 'statistical_unit_facet_reduce'
     ORDER BY self.id DESC, sibling.id DESC
     LIMIT 1;

    IF v_mode = 'dirty' THEN
        -- Each changed combination with its total over the whole cache, or
        -- NULL when no slot supports it any more.
        IF to_regclass('pg_temp._unit_facet_changed_total') IS NOT NULL THEN DROP TABLE _unit_facet_changed_total; END IF;
        CREATE TEMP TABLE _unit_facet_changed_total ON COMMIT DROP AS
        SELECT c.valid_from, c.valid_to, c.valid_until, c.unit_type,
               c.physical_region_path, c.primary_activity_category_path,
               c.sector_path, c.legal_form_id, c.physical_country_id, c.status_id,
               SUM(s.count)::BIGINT AS count,
               jsonb_stats_merge_agg(s.stats_summary) AS stats_summary
          FROM worker.statistical_unit_facet_changed AS c
          LEFT JOIN public.statistical_unit_facet_staging AS s
            ON s.valid_from = c.valid_from
           AND s.valid_to = c.valid_to
           AND COALESCE(s.valid_until, 'infinity'::date) = COALESCE(c.valid_until, 'infinity'::date)
           AND s.unit_type = c.unit_type
           AND COALESCE(s.physical_region_path::text, '') = COALESCE(c.physical_region_path::text, '')
           AND COALESCE(s.primary_activity_category_path::text, '') = COALESCE(c.primary_activity_category_path::text, '')
           AND COALESCE(s.sector_path::text, '') = COALESCE(c.sector_path::text, '')
           AND COALESCE(s.legal_form_id, -1) = COALESCE(c.legal_form_id, -1)
           AND COALESCE(s.physical_country_id, -1) = COALESCE(c.physical_country_id, -1)
           AND COALESCE(s.status_id, -1) = COALESCE(c.status_id, -1)
         GROUP BY c.valid_from, c.valid_to, c.valid_until, c.unit_type,
                  c.physical_region_path, c.primary_activity_category_path,
                  c.sector_path, c.legal_form_id, c.physical_country_id, c.status_id;

        MERGE INTO public.statistical_unit_facet AS target
        USING _unit_facet_changed_total AS source
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
        WHEN MATCHED AND source.count IS NULL
            THEN DELETE
        WHEN MATCHED AND (target.count <> source.count
                          OR target.stats_summary IS DISTINCT FROM source.stats_summary)
            THEN UPDATE SET count = source.count,
                            stats_summary = source.stats_summary
        WHEN NOT MATCHED BY TARGET AND source.count IS NOT NULL
            THEN INSERT (valid_from, valid_to, valid_until, unit_type,
                         physical_region_path, primary_activity_category_path,
                         sector_path, legal_form_id, physical_country_id, status_id,
                         count, stats_summary)
                 VALUES (source.valid_from, source.valid_to, source.valid_until, source.unit_type,
                         source.physical_region_path, source.primary_activity_category_path,
                         source.sector_path, source.legal_form_id, source.physical_country_id, source.status_id,
                         source.count, source.stats_summary);
        GET DIAGNOSTICS v_row_count := ROW_COUNT;
        SELECT count(*) INTO v_changed_count FROM _unit_facet_changed_total;

        TRUNCATE worker.statistical_unit_facet_changed;

        p_info := jsonb_build_object(
            'mode', 'dirty',
            'changed_combinations', v_changed_count,
            'dirty_hash_slots', to_jsonb(v_dirty_hash_slots),
            'rows_merged', v_row_count);
        RETURN;
    END IF;

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

    -- The whole cache is reduced, which covers every recorded change.
    TRUNCATE worker.statistical_unit_facet_changed;

    p_info := jsonb_build_object(
        'mode', 'full',
        'dirty_hash_slots', to_jsonb(v_dirty_hash_slots),
        'rows_merged', v_row_count);
END;
$procedure$
```

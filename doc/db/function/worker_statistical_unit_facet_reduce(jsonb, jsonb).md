```sql
CREATE OR REPLACE PROCEDURE worker.statistical_unit_facet_reduce(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_dirty_hash_slots int[];
    v_row_count bigint;
    v_delete_count bigint;
BEGIN
    -- Read dirty partitions BEFORE anything else, because
    -- statistical_history_facet_reduce (which runs later) truncates them.
    SELECT array_agg(dp.dirty_hash_slot)
      INTO v_dirty_hash_slots
      FROM public.statistical_unit_facet_dirty_hash_slots AS dp;

    IF v_dirty_hash_slots IS NULL OR array_length(v_dirty_hash_slots, 1) IS NULL THEN
        ---------------------------------------------------------------
        -- Full refresh: TRUNCATE + INSERT (original path, unchanged)
        ---------------------------------------------------------------
        TRUNCATE public.statistical_unit_facet;

        INSERT INTO public.statistical_unit_facet
            (valid_from, valid_to, valid_until, unit_type,
             physical_region_path, primary_activity_category_path,
             sector_path, legal_form_id, physical_country_id, status_id,
             count, stats_summary)
        SELECT s.valid_from, s.valid_to, s.valid_until, s.unit_type,
               s.physical_region_path, s.primary_activity_category_path,
               s.sector_path, s.legal_form_id, s.physical_country_id, s.status_id,
               SUM(s.count)::BIGINT,
               jsonb_stats_merge_agg(s.stats_summary)
          FROM public.statistical_unit_facet_staging AS s
         GROUP BY s.valid_from, s.valid_to, s.valid_until, s.unit_type,
                  s.physical_region_path, s.primary_activity_category_path,
                  s.sector_path, s.legal_form_id, s.physical_country_id, s.status_id;
        GET DIAGNOSTICS v_row_count := ROW_COUNT;

        p_info := jsonb_build_object('mode', 'full', 'rows_reduced', v_row_count);
    ELSIF array_length(v_dirty_hash_slots, 1) <= 128 THEN
        ---------------------------------------------------------------
        -- Path B: Scoped MERGE (few dirty partitions).
        -- Uses row-value IN with ::text cast for Hash Join (3.8s verified).
        -- Only re-aggregates dim combos from dirty partitions + snapshot.
        ---------------------------------------------------------------

        -- Scoped aggregate using row-value IN (::text cast = Hash Join)
        IF to_regclass('pg_temp._scoped_agg') IS NOT NULL THEN
            DROP TABLE _scoped_agg;
        END IF;
        CREATE TEMP TABLE _scoped_agg ON COMMIT DROP AS
        SELECT s.valid_from, s.valid_to, s.valid_until, s.unit_type,
               s.physical_region_path, s.primary_activity_category_path,
               s.sector_path, s.legal_form_id, s.physical_country_id, s.status_id,
               SUM(s.count)::BIGINT AS count,
               jsonb_stats_merge_agg(s.stats_summary) AS stats_summary
        FROM public.statistical_unit_facet_staging AS s
        WHERE (s.valid_from, s.valid_to,
               COALESCE(s.valid_until, 'infinity'::date), s.unit_type,
               COALESCE(s.physical_region_path::text, ''),
               COALESCE(s.primary_activity_category_path::text, ''),
               COALESCE(s.sector_path::text, ''),
               COALESCE(s.legal_form_id, -1),
               COALESCE(s.physical_country_id, -1),
               COALESCE(s.status_id, -1))
            IN (
                -- Current staging dims for dirty partitions (new/changed)
                SELECT d.valid_from, d.valid_to,
                       COALESCE(d.valid_until, 'infinity'::date), d.unit_type,
                       COALESCE(d.physical_region_path::text, ''),
                       COALESCE(d.primary_activity_category_path::text, ''),
                       COALESCE(d.sector_path::text, ''),
                       COALESCE(d.legal_form_id, -1),
                       COALESCE(d.physical_country_id, -1),
                       COALESCE(d.status_id, -1)
                FROM public.statistical_unit_facet_staging AS d
                WHERE d.hash_slot = ANY(v_dirty_hash_slots)
                UNION
                -- Pre-dirty snapshot (disappeared combos)
                SELECT p.valid_from, p.valid_to,
                       COALESCE(p.valid_until, 'infinity'::date), p.unit_type,
                       COALESCE(p.physical_region_path::text, ''),
                       COALESCE(p.primary_activity_category_path::text, ''),
                       COALESCE(p.sector_path::text, ''),
                       COALESCE(p.legal_form_id, -1),
                       COALESCE(p.physical_country_id, -1),
                       COALESCE(p.status_id, -1)
                FROM public.statistical_unit_facet_pre_dirty_dims AS p
            )
        GROUP BY s.valid_from, s.valid_to, s.valid_until, s.unit_type,
                 s.physical_region_path, s.primary_activity_category_path,
                 s.sector_path, s.legal_form_id, s.physical_country_id, s.status_id;

        -- Scoped MERGE into final table
        MERGE INTO public.statistical_unit_facet AS target
        USING _scoped_agg AS source
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
                         source.count, source.stats_summary);
        GET DIAGNOSTICS v_row_count := ROW_COUNT;

        -- DELETE stale combos (in snapshot but not in scoped aggregate)
        DELETE FROM public.statistical_unit_facet AS f
        WHERE (f.valid_from, f.valid_to,
               COALESCE(f.valid_until, 'infinity'::date), f.unit_type,
               COALESCE(f.physical_region_path::text, ''),
               COALESCE(f.primary_activity_category_path::text, ''),
               COALESCE(f.sector_path::text, ''),
               COALESCE(f.legal_form_id, -1),
               COALESCE(f.physical_country_id, -1),
               COALESCE(f.status_id, -1))
            IN (
                SELECT p.valid_from, p.valid_to,
                       COALESCE(p.valid_until, 'infinity'::date), p.unit_type,
                       COALESCE(p.physical_region_path::text, ''),
                       COALESCE(p.primary_activity_category_path::text, ''),
                       COALESCE(p.sector_path::text, ''),
                       COALESCE(p.legal_form_id, -1),
                       COALESCE(p.physical_country_id, -1),
                       COALESCE(p.status_id, -1)
                FROM public.statistical_unit_facet_pre_dirty_dims AS p
            )
            AND NOT EXISTS (
                SELECT 1 FROM _scoped_agg AS a
                WHERE a.valid_from = f.valid_from
                  AND a.valid_to = f.valid_to
                  AND COALESCE(a.valid_until, 'infinity'::date) = COALESCE(f.valid_until, 'infinity'::date)
                  AND a.unit_type = f.unit_type
                  AND COALESCE(a.physical_region_path::text, '') = COALESCE(f.physical_region_path::text, '')
                  AND COALESCE(a.primary_activity_category_path::text, '') = COALESCE(f.primary_activity_category_path::text, '')
                  AND COALESCE(a.sector_path::text, '') = COALESCE(f.sector_path::text, '')
                  AND COALESCE(a.legal_form_id, -1) = COALESCE(f.legal_form_id, -1)
                  AND COALESCE(a.physical_country_id, -1) = COALESCE(f.physical_country_id, -1)
                  AND COALESCE(a.status_id, -1) = COALESCE(f.status_id, -1)
            );
        GET DIAGNOSTICS v_delete_count := ROW_COUNT;

        p_info := jsonb_build_object(
            'mode', 'scoped',
            'dirty_hash_slots', to_jsonb(v_dirty_hash_slots),
            'rows_merged', v_row_count,
            'rows_deleted', v_delete_count);
    ELSE
        ---------------------------------------------------------------
        -- Path C: Full MERGE (many dirty partitions > 128).
        -- Full aggregate is faster than scoped when most partitions dirty.
        ---------------------------------------------------------------
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
            'mode', 'incremental',
            'dirty_hash_slots', to_jsonb(v_dirty_hash_slots),
            'rows_merged', v_row_count);
    END IF;
END;
$procedure$
```

-- Down Migration 20260429233218: collapse facet reduce to global merge
--
-- Restore rc.42's 3-path procedure bodies verbatim. The collapsed global
-- MERGE is replaced with the original Path A (TRUNCATE+INSERT for full),
-- Path B (scoped MERGE for ≤128 dirty), Path C (full MERGE for >128).
-- Same one-time public.statistical_unit_facet_derive(-inf, inf) +
-- public.statistical_history_facet_derive(-inf, inf) for symmetry — under
-- restored 3-path code, Path A handles full rebuild correctly, so the
-- cleanup just resets target to a clean baseline before the next derive
-- cycle resumes the (buggy) incremental flow.

BEGIN;

CREATE OR REPLACE PROCEDURE worker.statistical_history_facet_reduce(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_dirty_hash_slots int[];
    v_row_count bigint;
    v_delete_count bigint;
BEGIN
    -- Read dirty partitions before truncating them at the end.
    SELECT array_agg(dp.dirty_hash_slot)
      INTO v_dirty_hash_slots
      FROM public.statistical_unit_facet_dirty_hash_slots AS dp;

    IF v_dirty_hash_slots IS NULL OR array_length(v_dirty_hash_slots, 1) IS NULL THEN
        ---------------------------------------------------------------
        -- Full refresh: drop indexes, TRUNCATE + INSERT, rebuild indexes
        ---------------------------------------------------------------
        DROP INDEX IF EXISTS public.idx_statistical_history_facet_year;
        DROP INDEX IF EXISTS public.idx_statistical_history_facet_month;
        DROP INDEX IF EXISTS public.idx_statistical_history_facet_unit_type;
        DROP INDEX IF EXISTS public.idx_statistical_history_facet_primary_activity_category_path;
        DROP INDEX IF EXISTS public.idx_gist_statistical_history_facet_primary_activity_category_pa;
        DROP INDEX IF EXISTS public.idx_statistical_history_facet_secondary_activity_category_path;
        DROP INDEX IF EXISTS public.idx_gist_statistical_history_facet_secondary_activity_category_;
        DROP INDEX IF EXISTS public.idx_statistical_history_facet_sector_path;
        DROP INDEX IF EXISTS public.idx_gist_statistical_history_facet_sector_path;
        DROP INDEX IF EXISTS public.idx_statistical_history_facet_legal_form_id;
        DROP INDEX IF EXISTS public.idx_statistical_history_facet_physical_region_path;
        DROP INDEX IF EXISTS public.idx_gist_statistical_history_facet_physical_region_path;
        DROP INDEX IF EXISTS public.idx_statistical_history_facet_physical_country_id;
        DROP INDEX IF EXISTS public.idx_statistical_history_facet_stats_summary;
        DROP INDEX IF EXISTS public.statistical_history_facet_month_key;
        DROP INDEX IF EXISTS public.statistical_history_facet_year_key;

        TRUNCATE public.statistical_history_facet;

        INSERT INTO public.statistical_history_facet (
            resolution, year, month, unit_type,
            primary_activity_category_path, secondary_activity_category_path,
            sector_path, legal_form_id, physical_region_path,
            physical_country_id, unit_size_id, status_id,
            exists_count, exists_change, exists_added_count, exists_removed_count,
            countable_count, countable_change, countable_added_count, countable_removed_count,
            births, deaths,
            name_change_count, primary_activity_category_change_count,
            secondary_activity_category_change_count, sector_change_count,
            legal_form_change_count, physical_region_change_count,
            physical_country_change_count, physical_address_change_count,
            unit_size_change_count, status_change_count,
            stats_summary
        )
        SELECT
            resolution, year, month, unit_type,
            primary_activity_category_path, secondary_activity_category_path,
            sector_path, legal_form_id, physical_region_path,
            physical_country_id, unit_size_id, status_id,
            SUM(exists_count)::integer, SUM(exists_change)::integer,
            SUM(exists_added_count)::integer, SUM(exists_removed_count)::integer,
            SUM(countable_count)::integer, SUM(countable_change)::integer,
            SUM(countable_added_count)::integer, SUM(countable_removed_count)::integer,
            SUM(births)::integer, SUM(deaths)::integer,
            SUM(name_change_count)::integer, SUM(primary_activity_category_change_count)::integer,
            SUM(secondary_activity_category_change_count)::integer, SUM(sector_change_count)::integer,
            SUM(legal_form_change_count)::integer, SUM(physical_region_change_count)::integer,
            SUM(physical_country_change_count)::integer, SUM(physical_address_change_count)::integer,
            SUM(unit_size_change_count)::integer, SUM(status_change_count)::integer,
            jsonb_stats_merge_agg(stats_summary)
        FROM public.statistical_history_facet_partitions
        GROUP BY resolution, year, month, unit_type,
                 primary_activity_category_path, secondary_activity_category_path,
                 sector_path, legal_form_id, physical_region_path,
                 physical_country_id, unit_size_id, status_id;
        GET DIAGNOSTICS v_row_count := ROW_COUNT;

        CREATE UNIQUE INDEX statistical_history_facet_month_key
            ON public.statistical_history_facet (resolution, year, month, unit_type,
                primary_activity_category_path, secondary_activity_category_path,
                sector_path, legal_form_id, physical_region_path, physical_country_id)
            WHERE resolution = 'year-month'::public.history_resolution;
        CREATE UNIQUE INDEX statistical_history_facet_year_key
            ON public.statistical_history_facet (year, month, unit_type,
                primary_activity_category_path, secondary_activity_category_path,
                sector_path, legal_form_id, physical_region_path, physical_country_id)
            WHERE resolution = 'year'::public.history_resolution;
        CREATE INDEX idx_statistical_history_facet_year ON public.statistical_history_facet (year);
        CREATE INDEX idx_statistical_history_facet_month ON public.statistical_history_facet (month);
        CREATE INDEX idx_statistical_history_facet_unit_type ON public.statistical_history_facet (unit_type);
        CREATE INDEX idx_statistical_history_facet_primary_activity_category_path ON public.statistical_history_facet (primary_activity_category_path);
        CREATE INDEX idx_gist_statistical_history_facet_primary_activity_category_pa ON public.statistical_history_facet USING GIST (primary_activity_category_path);
        CREATE INDEX idx_statistical_history_facet_secondary_activity_category_path ON public.statistical_history_facet (secondary_activity_category_path);
        CREATE INDEX idx_gist_statistical_history_facet_secondary_activity_category_ ON public.statistical_history_facet USING GIST (secondary_activity_category_path);
        CREATE INDEX idx_statistical_history_facet_sector_path ON public.statistical_history_facet (sector_path);
        CREATE INDEX idx_gist_statistical_history_facet_sector_path ON public.statistical_history_facet USING GIST (sector_path);
        CREATE INDEX idx_statistical_history_facet_legal_form_id ON public.statistical_history_facet (legal_form_id);
        CREATE INDEX idx_statistical_history_facet_physical_region_path ON public.statistical_history_facet (physical_region_path);
        CREATE INDEX idx_gist_statistical_history_facet_physical_region_path ON public.statistical_history_facet USING GIST (physical_region_path);
        CREATE INDEX idx_statistical_history_facet_physical_country_id ON public.statistical_history_facet (physical_country_id);
        CREATE INDEX idx_statistical_history_facet_stats_summary ON public.statistical_history_facet USING GIN (stats_summary jsonb_path_ops);

        p_info := jsonb_build_object('mode', 'full', 'rows_reduced', v_row_count);
    ELSIF array_length(v_dirty_hash_slots, 1) <= 128 THEN
        ---------------------------------------------------------------
        -- Path B: Scoped MERGE (few dirty partitions).
        -- Uses row-value IN with ::text cast for Hash Join.
        ---------------------------------------------------------------

        -- Scoped aggregate using row-value IN (::text cast = Hash Join)
        IF to_regclass('pg_temp._scoped_history_agg') IS NOT NULL THEN
            DROP TABLE _scoped_history_agg;
        END IF;
        CREATE TEMP TABLE _scoped_history_agg ON COMMIT DROP AS
        SELECT
            s.resolution, s.year, s.month, s.unit_type,
            s.primary_activity_category_path, s.secondary_activity_category_path,
            s.sector_path, s.legal_form_id, s.physical_region_path,
            s.physical_country_id, s.unit_size_id, s.status_id,
            SUM(s.exists_count)::integer AS exists_count,
            SUM(s.exists_change)::integer AS exists_change,
            SUM(s.exists_added_count)::integer AS exists_added_count,
            SUM(s.exists_removed_count)::integer AS exists_removed_count,
            SUM(s.countable_count)::integer AS countable_count,
            SUM(s.countable_change)::integer AS countable_change,
            SUM(s.countable_added_count)::integer AS countable_added_count,
            SUM(s.countable_removed_count)::integer AS countable_removed_count,
            SUM(s.births)::integer AS births,
            SUM(s.deaths)::integer AS deaths,
            SUM(s.name_change_count)::integer AS name_change_count,
            SUM(s.primary_activity_category_change_count)::integer AS primary_activity_category_change_count,
            SUM(s.secondary_activity_category_change_count)::integer AS secondary_activity_category_change_count,
            SUM(s.sector_change_count)::integer AS sector_change_count,
            SUM(s.legal_form_change_count)::integer AS legal_form_change_count,
            SUM(s.physical_region_change_count)::integer AS physical_region_change_count,
            SUM(s.physical_country_change_count)::integer AS physical_country_change_count,
            SUM(s.physical_address_change_count)::integer AS physical_address_change_count,
            SUM(s.unit_size_change_count)::integer AS unit_size_change_count,
            SUM(s.status_change_count)::integer AS status_change_count,
            jsonb_stats_merge_agg(s.stats_summary) AS stats_summary
        FROM public.statistical_history_facet_partitions AS s
        WHERE (s.resolution::text, s.year, COALESCE(s.month, -1), s.unit_type::text,
               COALESCE(s.primary_activity_category_path::text, ''),
               COALESCE(s.secondary_activity_category_path::text, ''),
               COALESCE(s.sector_path::text, ''),
               COALESCE(s.legal_form_id, -1),
               COALESCE(s.physical_region_path::text, ''),
               COALESCE(s.physical_country_id, -1),
               COALESCE(s.unit_size_id, -1),
               COALESCE(s.status_id, -1))
            IN (
                SELECT d.resolution::text, d.year, COALESCE(d.month, -1), d.unit_type::text,
                       COALESCE(d.primary_activity_category_path::text, ''),
                       COALESCE(d.secondary_activity_category_path::text, ''),
                       COALESCE(d.sector_path::text, ''),
                       COALESCE(d.legal_form_id, -1),
                       COALESCE(d.physical_region_path::text, ''),
                       COALESCE(d.physical_country_id, -1),
                       COALESCE(d.unit_size_id, -1),
                       COALESCE(d.status_id, -1)
                FROM public.statistical_history_facet_partitions AS d
                WHERE d.hash_slot = ANY(v_dirty_hash_slots)
                UNION
                SELECT p.resolution::text, p.year, COALESCE(p.month, -1), p.unit_type::text,
                       COALESCE(p.primary_activity_category_path::text, ''),
                       COALESCE(p.secondary_activity_category_path::text, ''),
                       COALESCE(p.sector_path::text, ''),
                       COALESCE(p.legal_form_id, -1),
                       COALESCE(p.physical_region_path::text, ''),
                       COALESCE(p.physical_country_id, -1),
                       COALESCE(p.unit_size_id, -1),
                       COALESCE(p.status_id, -1)
                FROM public.statistical_history_facet_pre_dirty_dims AS p
            )
        GROUP BY s.resolution, s.year, s.month, s.unit_type,
                 s.primary_activity_category_path, s.secondary_activity_category_path,
                 s.sector_path, s.legal_form_id, s.physical_region_path,
                 s.physical_country_id, s.unit_size_id, s.status_id;

        -- Scoped MERGE
        MERGE INTO public.statistical_history_facet AS target
        USING _scoped_history_agg AS source
           ON target.resolution = source.resolution
          AND target.year = source.year
          AND COALESCE(target.month, -1) = COALESCE(source.month, -1)
          AND target.unit_type = source.unit_type
          AND COALESCE(target.primary_activity_category_path::text, '') = COALESCE(source.primary_activity_category_path::text, '')
          AND COALESCE(target.secondary_activity_category_path::text, '') = COALESCE(source.secondary_activity_category_path::text, '')
          AND COALESCE(target.sector_path::text, '') = COALESCE(source.sector_path::text, '')
          AND COALESCE(target.legal_form_id, -1) = COALESCE(source.legal_form_id, -1)
          AND COALESCE(target.physical_region_path::text, '') = COALESCE(source.physical_region_path::text, '')
          AND COALESCE(target.physical_country_id, -1) = COALESCE(source.physical_country_id, -1)
          AND COALESCE(target.unit_size_id, -1) = COALESCE(source.unit_size_id, -1)
          AND COALESCE(target.status_id, -1) = COALESCE(source.status_id, -1)
        WHEN MATCHED AND (
                target.exists_count <> source.exists_count
             OR target.exists_change <> source.exists_change
             OR target.exists_added_count <> source.exists_added_count
             OR target.exists_removed_count <> source.exists_removed_count
             OR target.countable_count <> source.countable_count
             OR target.countable_change <> source.countable_change
             OR target.countable_added_count <> source.countable_added_count
             OR target.countable_removed_count <> source.countable_removed_count
             OR target.births <> source.births
             OR target.deaths <> source.deaths
             OR target.name_change_count <> source.name_change_count
             OR target.primary_activity_category_change_count <> source.primary_activity_category_change_count
             OR target.secondary_activity_category_change_count <> source.secondary_activity_category_change_count
             OR target.sector_change_count <> source.sector_change_count
             OR target.legal_form_change_count <> source.legal_form_change_count
             OR target.physical_region_change_count <> source.physical_region_change_count
             OR target.physical_country_change_count <> source.physical_country_change_count
             OR target.physical_address_change_count <> source.physical_address_change_count
             OR target.unit_size_change_count <> source.unit_size_change_count
             OR target.status_change_count <> source.status_change_count
             OR target.stats_summary IS DISTINCT FROM source.stats_summary)
            THEN UPDATE SET
                exists_count = source.exists_count,
                exists_change = source.exists_change,
                exists_added_count = source.exists_added_count,
                exists_removed_count = source.exists_removed_count,
                countable_count = source.countable_count,
                countable_change = source.countable_change,
                countable_added_count = source.countable_added_count,
                countable_removed_count = source.countable_removed_count,
                births = source.births,
                deaths = source.deaths,
                name_change_count = source.name_change_count,
                primary_activity_category_change_count = source.primary_activity_category_change_count,
                secondary_activity_category_change_count = source.secondary_activity_category_change_count,
                sector_change_count = source.sector_change_count,
                legal_form_change_count = source.legal_form_change_count,
                physical_region_change_count = source.physical_region_change_count,
                physical_country_change_count = source.physical_country_change_count,
                physical_address_change_count = source.physical_address_change_count,
                unit_size_change_count = source.unit_size_change_count,
                status_change_count = source.status_change_count,
                stats_summary = source.stats_summary
        WHEN NOT MATCHED BY TARGET
            THEN INSERT (
                resolution, year, month, unit_type,
                primary_activity_category_path, secondary_activity_category_path,
                sector_path, legal_form_id, physical_region_path,
                physical_country_id, unit_size_id, status_id,
                exists_count, exists_change, exists_added_count, exists_removed_count,
                countable_count, countable_change, countable_added_count, countable_removed_count,
                births, deaths,
                name_change_count, primary_activity_category_change_count,
                secondary_activity_category_change_count, sector_change_count,
                legal_form_change_count, physical_region_change_count,
                physical_country_change_count, physical_address_change_count,
                unit_size_change_count, status_change_count,
                stats_summary)
            VALUES (
                source.resolution, source.year, source.month, source.unit_type,
                source.primary_activity_category_path, source.secondary_activity_category_path,
                source.sector_path, source.legal_form_id, source.physical_region_path,
                source.physical_country_id, source.unit_size_id, source.status_id,
                source.exists_count, source.exists_change, source.exists_added_count, source.exists_removed_count,
                source.countable_count, source.countable_change, source.countable_added_count, source.countable_removed_count,
                source.births, source.deaths,
                source.name_change_count, source.primary_activity_category_change_count,
                source.secondary_activity_category_change_count, source.sector_change_count,
                source.legal_form_change_count, source.physical_region_change_count,
                source.physical_country_change_count, source.physical_address_change_count,
                source.unit_size_change_count, source.status_change_count,
                source.stats_summary);
        GET DIAGNOSTICS v_row_count := ROW_COUNT;

        -- DELETE stale combos (in snapshot but not in scoped aggregate)
        DELETE FROM public.statistical_history_facet AS f
        WHERE (f.resolution::text, f.year, COALESCE(f.month, -1), f.unit_type::text,
               COALESCE(f.primary_activity_category_path::text, ''),
               COALESCE(f.secondary_activity_category_path::text, ''),
               COALESCE(f.sector_path::text, ''),
               COALESCE(f.legal_form_id, -1),
               COALESCE(f.physical_region_path::text, ''),
               COALESCE(f.physical_country_id, -1),
               COALESCE(f.unit_size_id, -1),
               COALESCE(f.status_id, -1))
            IN (
                SELECT p.resolution::text, p.year, COALESCE(p.month, -1), p.unit_type::text,
                       COALESCE(p.primary_activity_category_path::text, ''),
                       COALESCE(p.secondary_activity_category_path::text, ''),
                       COALESCE(p.sector_path::text, ''),
                       COALESCE(p.legal_form_id, -1),
                       COALESCE(p.physical_region_path::text, ''),
                       COALESCE(p.physical_country_id, -1),
                       COALESCE(p.unit_size_id, -1),
                       COALESCE(p.status_id, -1)
                FROM public.statistical_history_facet_pre_dirty_dims AS p
            )
            AND NOT EXISTS (
                SELECT 1 FROM _scoped_history_agg AS a
                WHERE a.resolution = f.resolution
                  AND a.year = f.year
                  AND COALESCE(a.month, -1) = COALESCE(f.month, -1)
                  AND a.unit_type = f.unit_type
                  AND COALESCE(a.primary_activity_category_path::text, '') = COALESCE(f.primary_activity_category_path::text, '')
                  AND COALESCE(a.secondary_activity_category_path::text, '') = COALESCE(f.secondary_activity_category_path::text, '')
                  AND COALESCE(a.sector_path::text, '') = COALESCE(f.sector_path::text, '')
                  AND COALESCE(a.legal_form_id, -1) = COALESCE(f.legal_form_id, -1)
                  AND COALESCE(a.physical_region_path::text, '') = COALESCE(f.physical_region_path::text, '')
                  AND COALESCE(a.physical_country_id, -1) = COALESCE(f.physical_country_id, -1)
                  AND COALESCE(a.unit_size_id, -1) = COALESCE(f.unit_size_id, -1)
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
        -- Skip index drop/rebuild since MERGE preserves indexes.
        ---------------------------------------------------------------
        MERGE INTO public.statistical_history_facet AS target
        USING (
            SELECT
                resolution, year, month, unit_type,
                primary_activity_category_path, secondary_activity_category_path,
                sector_path, legal_form_id, physical_region_path,
                physical_country_id, unit_size_id, status_id,
                SUM(exists_count)::integer AS exists_count,
                SUM(exists_change)::integer AS exists_change,
                SUM(exists_added_count)::integer AS exists_added_count,
                SUM(exists_removed_count)::integer AS exists_removed_count,
                SUM(countable_count)::integer AS countable_count,
                SUM(countable_change)::integer AS countable_change,
                SUM(countable_added_count)::integer AS countable_added_count,
                SUM(countable_removed_count)::integer AS countable_removed_count,
                SUM(births)::integer AS births,
                SUM(deaths)::integer AS deaths,
                SUM(name_change_count)::integer AS name_change_count,
                SUM(primary_activity_category_change_count)::integer AS primary_activity_category_change_count,
                SUM(secondary_activity_category_change_count)::integer AS secondary_activity_category_change_count,
                SUM(sector_change_count)::integer AS sector_change_count,
                SUM(legal_form_change_count)::integer AS legal_form_change_count,
                SUM(physical_region_change_count)::integer AS physical_region_change_count,
                SUM(physical_country_change_count)::integer AS physical_country_change_count,
                SUM(physical_address_change_count)::integer AS physical_address_change_count,
                SUM(unit_size_change_count)::integer AS unit_size_change_count,
                SUM(status_change_count)::integer AS status_change_count,
                jsonb_stats_merge_agg(stats_summary) AS stats_summary
            FROM public.statistical_history_facet_partitions
            GROUP BY resolution, year, month, unit_type,
                     primary_activity_category_path, secondary_activity_category_path,
                     sector_path, legal_form_id, physical_region_path,
                     physical_country_id, unit_size_id, status_id
        ) AS source
           ON target.resolution = source.resolution
          AND target.year = source.year
          AND COALESCE(target.month, -1) = COALESCE(source.month, -1)
          AND target.unit_type = source.unit_type
          AND COALESCE(target.primary_activity_category_path::text, '') = COALESCE(source.primary_activity_category_path::text, '')
          AND COALESCE(target.secondary_activity_category_path::text, '') = COALESCE(source.secondary_activity_category_path::text, '')
          AND COALESCE(target.sector_path::text, '') = COALESCE(source.sector_path::text, '')
          AND COALESCE(target.legal_form_id, -1) = COALESCE(source.legal_form_id, -1)
          AND COALESCE(target.physical_region_path::text, '') = COALESCE(source.physical_region_path::text, '')
          AND COALESCE(target.physical_country_id, -1) = COALESCE(source.physical_country_id, -1)
          AND COALESCE(target.unit_size_id, -1) = COALESCE(source.unit_size_id, -1)
          AND COALESCE(target.status_id, -1) = COALESCE(source.status_id, -1)
        WHEN MATCHED AND (
                target.exists_count <> source.exists_count
             OR target.stats_summary IS DISTINCT FROM source.stats_summary)
            THEN UPDATE SET
                exists_count = source.exists_count,
                exists_change = source.exists_change,
                exists_added_count = source.exists_added_count,
                exists_removed_count = source.exists_removed_count,
                countable_count = source.countable_count,
                countable_change = source.countable_change,
                countable_added_count = source.countable_added_count,
                countable_removed_count = source.countable_removed_count,
                births = source.births,
                deaths = source.deaths,
                name_change_count = source.name_change_count,
                primary_activity_category_change_count = source.primary_activity_category_change_count,
                secondary_activity_category_change_count = source.secondary_activity_category_change_count,
                sector_change_count = source.sector_change_count,
                legal_form_change_count = source.legal_form_change_count,
                physical_region_change_count = source.physical_region_change_count,
                physical_country_change_count = source.physical_country_change_count,
                physical_address_change_count = source.physical_address_change_count,
                unit_size_change_count = source.unit_size_change_count,
                status_change_count = source.status_change_count,
                stats_summary = source.stats_summary
        WHEN NOT MATCHED BY TARGET
            THEN INSERT (
                resolution, year, month, unit_type,
                primary_activity_category_path, secondary_activity_category_path,
                sector_path, legal_form_id, physical_region_path,
                physical_country_id, unit_size_id, status_id,
                exists_count, exists_change, exists_added_count, exists_removed_count,
                countable_count, countable_change, countable_added_count, countable_removed_count,
                births, deaths,
                name_change_count, primary_activity_category_change_count,
                secondary_activity_category_change_count, sector_change_count,
                legal_form_change_count, physical_region_change_count,
                physical_country_change_count, physical_address_change_count,
                unit_size_change_count, status_change_count,
                stats_summary)
            VALUES (
                source.resolution, source.year, source.month, source.unit_type,
                source.primary_activity_category_path, source.secondary_activity_category_path,
                source.sector_path, source.legal_form_id, source.physical_region_path,
                source.physical_country_id, source.unit_size_id, source.status_id,
                source.exists_count, source.exists_change, source.exists_added_count, source.exists_removed_count,
                source.countable_count, source.countable_change, source.countable_added_count, source.countable_removed_count,
                source.births, source.deaths,
                source.name_change_count, source.primary_activity_category_change_count,
                source.secondary_activity_category_change_count, source.sector_change_count,
                source.legal_form_change_count, source.physical_region_change_count,
                source.physical_country_change_count, source.physical_address_change_count,
                source.unit_size_change_count, source.status_change_count,
                source.stats_summary)
        WHEN NOT MATCHED BY SOURCE THEN DELETE;
        GET DIAGNOSTICS v_row_count := ROW_COUNT;

        p_info := jsonb_build_object(
            'mode', 'incremental',
            'dirty_hash_slots', to_jsonb(v_dirty_hash_slots),
            'rows_merged', v_row_count);
    END IF;

    -- Clean up dirty partitions at the very end, after all consumers have read them
    TRUNCATE public.statistical_unit_facet_dirty_hash_slots;

    PERFORM pg_notify('worker_status',
        json_build_object('type', 'is_deriving_reports', 'status', false)::text);
END;
$procedure$;

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
$procedure$;


-- One-time data cleanup (symmetric with up.sql).
SELECT public.statistical_unit_facet_derive('-infinity'::date, 'infinity'::date);
SELECT public.statistical_history_facet_derive('-infinity'::date, 'infinity'::date);

END;

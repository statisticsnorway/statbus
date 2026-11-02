```sql
CREATE OR REPLACE PROCEDURE worker.statistical_history_facet_reduce(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
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

    -- Reduce as the sibling worker.derive_statistical_history_facet derived:
    -- in 'dirty' mode its children recorded every changed combination, so
    -- only those are recomputed. Anything else (a full derive, or a direct
    -- CALL outside the pipeline) recomputes the whole cache.
    SELECT sibling.info->>'mode'
      INTO v_mode
      FROM worker.tasks AS self
      JOIN worker.tasks AS sibling
        ON sibling.parent_id = self.parent_id
       AND sibling.command = 'derive_statistical_history_facet'
     WHERE self.state = 'processing' AND self.worker_pid = pg_backend_pid()
       AND self.command = 'statistical_history_facet_reduce'
     ORDER BY self.id DESC, sibling.id DESC
     LIMIT 1;

    IF v_mode = 'dirty' THEN
        -- Each changed combination with its totals over the whole cache, or
        -- NULL when no slot supports it any more.
        IF to_regclass('pg_temp._history_facet_changed_total') IS NOT NULL THEN DROP TABLE _history_facet_changed_total; END IF;
        CREATE TEMP TABLE _history_facet_changed_total ON COMMIT DROP AS
        SELECT
            c.resolution, c.year, c.month, c.unit_type,
            c.primary_activity_category_path, c.secondary_activity_category_path,
            c.sector_path, c.legal_form_id, c.physical_region_path,
            c.physical_country_id, c.unit_size_id, c.status_id,
            COUNT(p.hash_slot) AS supporting_rows,
            SUM(p.exists_count)::integer AS exists_count,
            SUM(p.exists_change)::integer AS exists_change,
            SUM(p.exists_added_count)::integer AS exists_added_count,
            SUM(p.exists_removed_count)::integer AS exists_removed_count,
            SUM(p.countable_count)::integer AS countable_count,
            SUM(p.countable_change)::integer AS countable_change,
            SUM(p.countable_added_count)::integer AS countable_added_count,
            SUM(p.countable_removed_count)::integer AS countable_removed_count,
            SUM(p.births)::integer AS births,
            SUM(p.deaths)::integer AS deaths,
            SUM(p.name_change_count)::integer AS name_change_count,
            SUM(p.primary_activity_category_change_count)::integer AS primary_activity_category_change_count,
            SUM(p.secondary_activity_category_change_count)::integer AS secondary_activity_category_change_count,
            SUM(p.sector_change_count)::integer AS sector_change_count,
            SUM(p.legal_form_change_count)::integer AS legal_form_change_count,
            SUM(p.physical_region_change_count)::integer AS physical_region_change_count,
            SUM(p.physical_country_change_count)::integer AS physical_country_change_count,
            SUM(p.physical_address_change_count)::integer AS physical_address_change_count,
            SUM(p.unit_size_change_count)::integer AS unit_size_change_count,
            SUM(p.status_change_count)::integer AS status_change_count,
            jsonb_stats_merge_agg(p.stats_summary) AS stats_summary
        FROM worker.statistical_history_facet_changed AS c
        LEFT JOIN public.statistical_history_facet_partitions AS p
          ON p.resolution = c.resolution
         AND p.year = c.year
         AND COALESCE(p.month, -1) = COALESCE(c.month, -1)
         AND p.unit_type = c.unit_type
         AND COALESCE(p.primary_activity_category_path::text, '') = COALESCE(c.primary_activity_category_path::text, '')
         AND COALESCE(p.secondary_activity_category_path::text, '') = COALESCE(c.secondary_activity_category_path::text, '')
         AND COALESCE(p.sector_path::text, '') = COALESCE(c.sector_path::text, '')
         AND COALESCE(p.legal_form_id, -1) = COALESCE(c.legal_form_id, -1)
         AND COALESCE(p.physical_region_path::text, '') = COALESCE(c.physical_region_path::text, '')
         AND COALESCE(p.physical_country_id, -1) = COALESCE(c.physical_country_id, -1)
         AND COALESCE(p.unit_size_id, -1) = COALESCE(c.unit_size_id, -1)
         AND COALESCE(p.status_id, -1) = COALESCE(c.status_id, -1)
        GROUP BY c.resolution, c.year, c.month, c.unit_type,
                 c.primary_activity_category_path, c.secondary_activity_category_path,
                 c.sector_path, c.legal_form_id, c.physical_region_path,
                 c.physical_country_id, c.unit_size_id, c.status_id;

        MERGE INTO public.statistical_history_facet AS target
        USING _history_facet_changed_total AS source
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
        WHEN MATCHED AND source.supporting_rows = 0
            THEN DELETE
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
        WHEN NOT MATCHED BY TARGET AND source.supporting_rows > 0
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
        SELECT count(*) INTO v_changed_count FROM _history_facet_changed_total;

        TRUNCATE worker.statistical_history_facet_changed;

        p_info := jsonb_build_object(
            'mode', 'dirty',
            'changed_combinations', v_changed_count,
            'dirty_hash_slots', to_jsonb(v_dirty_hash_slots),
            'rows_merged', v_row_count);
    ELSE
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

    -- The whole cache is reduced, which covers every recorded change.
    TRUNCATE worker.statistical_history_facet_changed;

    p_info := jsonb_build_object(
        'mode', 'full',
        'dirty_hash_slots', to_jsonb(v_dirty_hash_slots),
        'rows_merged', v_row_count);
    END IF;

    -- Clean up dirty partitions at the very end, after all consumers have read them.
    -- (statistical_unit_facet_reduce ran earlier in the pipeline and read dirty_hash_slots
    -- for diagnostic logging; truncating here is safe because no later step needs it.)
    TRUNCATE public.statistical_unit_facet_dirty_hash_slots;

    PERFORM pg_notify('worker_status',
        json_build_object('type', 'is_deriving_reports', 'status', false)::text);
END;
$procedure$
```

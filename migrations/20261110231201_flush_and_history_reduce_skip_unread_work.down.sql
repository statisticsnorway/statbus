-- Migration 20261110231201: flush and history reduce skip unread work (STATBUS-613)
-- Restores the definitions from before 20261110231201: dumped with \sf from statbus_seed at 20261110175021.
BEGIN;

DROP INDEX public.statistical_unit_unit_idx;

CREATE OR REPLACE PROCEDURE public.statistical_unit_flush_staging()
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_staging_count BIGINT;
    v_start_time timestamptz;
    v_delete_duration_ms numeric;
    v_merge_duration_ms numeric;
BEGIN
    -- Bail early if nothing to flush.
    SELECT count(*) INTO v_staging_count FROM public.statistical_unit_staging;
    IF v_staging_count = 0 THEN
        RAISE DEBUG 'statistical_unit_flush_staging: Nothing to flush (staging empty)';
        RETURN;
    END IF;

    RAISE DEBUG 'statistical_unit_flush_staging: Flushing % rows from staging', v_staging_count;

    -- Staging is truncated after every flush and refilled by the refresh
    -- batches, so its statistics describe an earlier, usually much smaller
    -- load. Plans built from them treat a large staging as small and match
    -- it unit by unit through the main table's index (STATBUS-599: 1.8M
    -- staged rows took 221 s instead of 25 s). Fresh statistics let the
    -- DELETE and MERGE below choose hash joins for large loads and index
    -- lookups for small ones.
    ANALYZE public.statistical_unit_staging;

    -- Step 1: Pre-cleanup DELETE.
    -- Remove main rows for affected (unit_type, unit_id) tuples that have
    -- no matching temporal slice in staging. Scoped to affected units so we
    -- never touch unrelated rows.
    v_start_time := clock_timestamp();
    DELETE FROM public.statistical_unit AS t
    USING (
        SELECT DISTINCT unit_type, unit_id FROM public.statistical_unit_staging
    ) AS u
    WHERE t.unit_type = u.unit_type AND t.unit_id = u.unit_id
      AND NOT EXISTS (
          SELECT 1 FROM public.statistical_unit_staging AS s
          WHERE s.unit_type = t.unit_type
            AND s.unit_id = t.unit_id
            AND s.valid_from = t.valid_from
            AND s.valid_to = t.valid_to
            AND COALESCE(s.valid_until, 'infinity'::date) = COALESCE(t.valid_until, 'infinity'::date)
      );
    v_delete_duration_ms := EXTRACT(EPOCH FROM (clock_timestamp() - v_start_time)) * 1000;
    RAISE DEBUG 'statistical_unit_flush_staging: Pre-cleanup DELETE in % ms', round(v_delete_duration_ms);

    -- Step 2: MERGE with skip-unchanged.
    -- Match on (unit_type, unit_id, valid_from, valid_to, valid_until).
    -- WHEN MATCHED AND row tuples differ → UPDATE; identical → skip (no WAL,
    -- no index churn). WHEN NOT MATCHED BY TARGET → INSERT.
    v_start_time := clock_timestamp();
    MERGE INTO public.statistical_unit AS target
    USING public.statistical_unit_staging AS source
       ON target.unit_type = source.unit_type
      AND target.unit_id   = source.unit_id
      AND target.valid_from = source.valid_from
      AND target.valid_to   = source.valid_to
      AND COALESCE(target.valid_until, 'infinity'::date) = COALESCE(source.valid_until, 'infinity'::date)
    WHEN MATCHED AND (
           (target.external_idents, target.name, target.birth_date, target.death_date, target.search,
            target.primary_activity_category_id, target.primary_activity_category_path, target.primary_activity_category_code,
            target.secondary_activity_category_id, target.secondary_activity_category_path, target.secondary_activity_category_code,
            target.activity_category_paths, target.sector_id, target.sector_path, target.sector_code, target.sector_name,
            target.data_source_ids, target.data_source_codes, target.legal_form_id, target.legal_form_code, target.legal_form_name,
            target.physical_address_part1, target.physical_address_part2, target.physical_address_part3, target.physical_postcode, target.physical_postplace,
            target.physical_region_id, target.physical_region_path, target.physical_region_code, target.physical_country_id, target.physical_country_iso_2,
            target.physical_latitude, target.physical_longitude, target.physical_altitude, target.domestic,
            target.postal_address_part1, target.postal_address_part2, target.postal_address_part3, target.postal_postcode, target.postal_postplace,
            target.postal_region_id, target.postal_region_path, target.postal_region_code, target.postal_country_id, target.postal_country_iso_2,
            target.postal_latitude, target.postal_longitude, target.postal_altitude,
            target.web_address, target.email_address, target.phone_number, target.landline, target.mobile_number, target.fax_number,
            target.unit_size_id, target.unit_size_code, target.status_id, target.status_code, target.used_for_counting,
            target.last_edit_comment, target.last_edit_by_user_id, target.last_edit_at, target.has_legal_unit,
            target.related_establishment_ids, target.excluded_establishment_ids, target.included_establishment_ids,
            target.related_legal_unit_ids, target.excluded_legal_unit_ids, target.included_legal_unit_ids,
            target.related_enterprise_ids, target.excluded_enterprise_ids, target.included_enterprise_ids,
            target.stats, target.stats_summary, target.included_establishment_count, target.included_legal_unit_count, target.included_enterprise_count, target.tag_paths)
           IS DISTINCT FROM
           (source.external_idents, source.name, source.birth_date, source.death_date, source.search,
            source.primary_activity_category_id, source.primary_activity_category_path, source.primary_activity_category_code,
            source.secondary_activity_category_id, source.secondary_activity_category_path, source.secondary_activity_category_code,
            source.activity_category_paths, source.sector_id, source.sector_path, source.sector_code, source.sector_name,
            source.data_source_ids, source.data_source_codes, source.legal_form_id, source.legal_form_code, source.legal_form_name,
            source.physical_address_part1, source.physical_address_part2, source.physical_address_part3, source.physical_postcode, source.physical_postplace,
            source.physical_region_id, source.physical_region_path, source.physical_region_code, source.physical_country_id, source.physical_country_iso_2,
            source.physical_latitude, source.physical_longitude, source.physical_altitude, source.domestic,
            source.postal_address_part1, source.postal_address_part2, source.postal_address_part3, source.postal_postcode, source.postal_postplace,
            source.postal_region_id, source.postal_region_path, source.postal_region_code, source.postal_country_id, source.postal_country_iso_2,
            source.postal_latitude, source.postal_longitude, source.postal_altitude,
            source.web_address, source.email_address, source.phone_number, source.landline, source.mobile_number, source.fax_number,
            source.unit_size_id, source.unit_size_code, source.status_id, source.status_code, source.used_for_counting,
            source.last_edit_comment, source.last_edit_by_user_id, source.last_edit_at, source.has_legal_unit,
            source.related_establishment_ids, source.excluded_establishment_ids, source.included_establishment_ids,
            source.related_legal_unit_ids, source.excluded_legal_unit_ids, source.included_legal_unit_ids,
            source.related_enterprise_ids, source.excluded_enterprise_ids, source.included_enterprise_ids,
            source.stats, source.stats_summary, source.included_establishment_count, source.included_legal_unit_count, source.included_enterprise_count, source.tag_paths)
       ) THEN UPDATE SET
            external_idents = source.external_idents, name = source.name, birth_date = source.birth_date, death_date = source.death_date, search = source.search,
            primary_activity_category_id = source.primary_activity_category_id, primary_activity_category_path = source.primary_activity_category_path, primary_activity_category_code = source.primary_activity_category_code,
            secondary_activity_category_id = source.secondary_activity_category_id, secondary_activity_category_path = source.secondary_activity_category_path, secondary_activity_category_code = source.secondary_activity_category_code,
            activity_category_paths = source.activity_category_paths, sector_id = source.sector_id, sector_path = source.sector_path, sector_code = source.sector_code, sector_name = source.sector_name,
            data_source_ids = source.data_source_ids, data_source_codes = source.data_source_codes, legal_form_id = source.legal_form_id, legal_form_code = source.legal_form_code, legal_form_name = source.legal_form_name,
            physical_address_part1 = source.physical_address_part1, physical_address_part2 = source.physical_address_part2, physical_address_part3 = source.physical_address_part3, physical_postcode = source.physical_postcode, physical_postplace = source.physical_postplace,
            physical_region_id = source.physical_region_id, physical_region_path = source.physical_region_path, physical_region_code = source.physical_region_code, physical_country_id = source.physical_country_id, physical_country_iso_2 = source.physical_country_iso_2,
            physical_latitude = source.physical_latitude, physical_longitude = source.physical_longitude, physical_altitude = source.physical_altitude, domestic = source.domestic,
            postal_address_part1 = source.postal_address_part1, postal_address_part2 = source.postal_address_part2, postal_address_part3 = source.postal_address_part3, postal_postcode = source.postal_postcode, postal_postplace = source.postal_postplace,
            postal_region_id = source.postal_region_id, postal_region_path = source.postal_region_path, postal_region_code = source.postal_region_code, postal_country_id = source.postal_country_id, postal_country_iso_2 = source.postal_country_iso_2,
            postal_latitude = source.postal_latitude, postal_longitude = source.postal_longitude, postal_altitude = source.postal_altitude,
            web_address = source.web_address, email_address = source.email_address, phone_number = source.phone_number, landline = source.landline, mobile_number = source.mobile_number, fax_number = source.fax_number,
            unit_size_id = source.unit_size_id, unit_size_code = source.unit_size_code, status_id = source.status_id, status_code = source.status_code, used_for_counting = source.used_for_counting,
            last_edit_comment = source.last_edit_comment, last_edit_by_user_id = source.last_edit_by_user_id, last_edit_at = source.last_edit_at, has_legal_unit = source.has_legal_unit,
            related_establishment_ids = source.related_establishment_ids, excluded_establishment_ids = source.excluded_establishment_ids, included_establishment_ids = source.included_establishment_ids,
            related_legal_unit_ids = source.related_legal_unit_ids, excluded_legal_unit_ids = source.excluded_legal_unit_ids, included_legal_unit_ids = source.included_legal_unit_ids,
            related_enterprise_ids = source.related_enterprise_ids, excluded_enterprise_ids = source.excluded_enterprise_ids, included_enterprise_ids = source.included_enterprise_ids,
            stats = source.stats, stats_summary = source.stats_summary, included_establishment_count = source.included_establishment_count, included_legal_unit_count = source.included_legal_unit_count, included_enterprise_count = source.included_enterprise_count, tag_paths = source.tag_paths
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (unit_type, unit_id, valid_from, valid_to, valid_until, external_idents, name, birth_date, death_date, search,
                primary_activity_category_id, primary_activity_category_path, primary_activity_category_code,
                secondary_activity_category_id, secondary_activity_category_path, secondary_activity_category_code,
                activity_category_paths, sector_id, sector_path, sector_code, sector_name,
                data_source_ids, data_source_codes, legal_form_id, legal_form_code, legal_form_name,
                physical_address_part1, physical_address_part2, physical_address_part3, physical_postcode, physical_postplace,
                physical_region_id, physical_region_path, physical_region_code, physical_country_id, physical_country_iso_2,
                physical_latitude, physical_longitude, physical_altitude, domestic,
                postal_address_part1, postal_address_part2, postal_address_part3, postal_postcode, postal_postplace,
                postal_region_id, postal_region_path, postal_region_code, postal_country_id, postal_country_iso_2,
                postal_latitude, postal_longitude, postal_altitude,
                web_address, email_address, phone_number, landline, mobile_number, fax_number,
                unit_size_id, unit_size_code, status_id, status_code, used_for_counting,
                last_edit_comment, last_edit_by_user_id, last_edit_at, has_legal_unit,
                related_establishment_ids, excluded_establishment_ids, included_establishment_ids,
                related_legal_unit_ids, excluded_legal_unit_ids, included_legal_unit_ids,
                related_enterprise_ids, excluded_enterprise_ids, included_enterprise_ids,
                stats, stats_summary, included_establishment_count, included_legal_unit_count, included_enterprise_count, tag_paths)
        VALUES (source.unit_type, source.unit_id, source.valid_from, source.valid_to, source.valid_until, source.external_idents, source.name, source.birth_date, source.death_date, source.search,
                source.primary_activity_category_id, source.primary_activity_category_path, source.primary_activity_category_code,
                source.secondary_activity_category_id, source.secondary_activity_category_path, source.secondary_activity_category_code,
                source.activity_category_paths, source.sector_id, source.sector_path, source.sector_code, source.sector_name,
                source.data_source_ids, source.data_source_codes, source.legal_form_id, source.legal_form_code, source.legal_form_name,
                source.physical_address_part1, source.physical_address_part2, source.physical_address_part3, source.physical_postcode, source.physical_postplace,
                source.physical_region_id, source.physical_region_path, source.physical_region_code, source.physical_country_id, source.physical_country_iso_2,
                source.physical_latitude, source.physical_longitude, source.physical_altitude, source.domestic,
                source.postal_address_part1, source.postal_address_part2, source.postal_address_part3, source.postal_postcode, source.postal_postplace,
                source.postal_region_id, source.postal_region_path, source.postal_region_code, source.postal_country_id, source.postal_country_iso_2,
                source.postal_latitude, source.postal_longitude, source.postal_altitude,
                source.web_address, source.email_address, source.phone_number, source.landline, source.mobile_number, source.fax_number,
                source.unit_size_id, source.unit_size_code, source.status_id, source.status_code, source.used_for_counting,
                source.last_edit_comment, source.last_edit_by_user_id, source.last_edit_at, source.has_legal_unit,
                source.related_establishment_ids, source.excluded_establishment_ids, source.included_establishment_ids,
                source.related_legal_unit_ids, source.excluded_legal_unit_ids, source.included_legal_unit_ids,
                source.related_enterprise_ids, source.excluded_enterprise_ids, source.included_enterprise_ids,
                source.stats, source.stats_summary, source.included_establishment_count, source.included_legal_unit_count, source.included_enterprise_count, source.tag_paths);
    v_merge_duration_ms := EXTRACT(EPOCH FROM (clock_timestamp() - v_start_time)) * 1000;
    RAISE DEBUG 'statistical_unit_flush_staging: MERGE in % ms', round(v_merge_duration_ms);

    -- Step 3: Clear staging table
    TRUNCATE public.statistical_unit_staging;

    -- Step 4: Update statistics
    ANALYZE public.statistical_unit;

    RAISE DEBUG 'statistical_unit_flush_staging: Complete (delete: % ms, merge: % ms)',
        round(v_delete_duration_ms), round(v_merge_duration_ms);
END;
$procedure$
;

CREATE OR REPLACE PROCEDURE worker.statistical_history_facet_delta_apply(IN p_replace boolean DEFAULT false)
 LANGUAGE plpgsql
 SET enable_mergejoin TO 'off'
AS $procedure$
DECLARE
    v_up_to bigint := (SELECT flushed_generation FROM worker.statistical_history_facet_delta_state);
BEGIN
    LOCK TABLE public.statistical_history_facet_delta_staging IN EXCLUSIVE MODE;
    IF p_replace THEN
        DELETE FROM public.statistical_history_facet_delta WHERE true; -- every row: p_replace rebuilds the delta table
    END IF;

    IF to_regclass('pg_temp.hd_sum') IS NOT NULL THEN DROP TABLE pg_temp.hd_sum; END IF;
    CREATE TEMP TABLE hd_sum AS
    SELECT unit_type, primary_activity_category_path, secondary_activity_category_path, sector_path, legal_form_id,
           physical_region_path, physical_country_id, unit_size_id, status_id, on_month,
           sum(exists_added_count)::int AS exists_added_count, sum(exists_removed_count)::int AS exists_removed_count,
           sum(countable_added_count)::int AS countable_added_count, sum(countable_removed_count)::int AS countable_removed_count,
           sum(exists_moved_in_count)::int AS exists_moved_in_count, sum(exists_moved_out_count)::int AS exists_moved_out_count,
           sum(countable_moved_in_count)::int AS countable_moved_in_count, sum(countable_moved_out_count)::int AS countable_moved_out_count,
           sum(births)::int AS births, sum(deaths)::int AS deaths, sum(name_change_count)::int AS name_change_count,
           sum(primary_activity_category_change_count)::int AS primary_activity_category_change_count,
           sum(secondary_activity_category_change_count)::int AS secondary_activity_category_change_count,
           sum(sector_change_count)::int AS sector_change_count, sum(legal_form_change_count)::int AS legal_form_change_count,
           sum(physical_region_change_count)::int AS physical_region_change_count,
           sum(physical_country_change_count)::int AS physical_country_change_count,
           sum(physical_address_change_count)::int AS physical_address_change_count,
           sum(unit_size_change_count)::int AS unit_size_change_count, sum(status_change_count)::int AS status_change_count,
           public.jsonb_stats_delta_nullif_zero(public.jsonb_stats_delta_agg(stats_delta)) AS stats_delta,
           public.jsonb_stats_delta_nullif_zero(public.jsonb_stats_delta_agg(stats_ended_month)) AS stats_ended_month,
           public.jsonb_stats_delta_nullif_zero(public.jsonb_stats_delta_agg(stats_ended_year)) AS stats_ended_year,
           array_agg(unit_id ORDER BY unit_id) FILTER (WHERE sign > 0) AS plus_ids,
           array_agg(unit_id ORDER BY unit_id) FILTER (WHERE sign < 0) AS minus_ids
      FROM public.statistical_history_facet_delta_staging
     WHERE generation <= v_up_to
     GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10;

    -- The dimensions are nullable, and IS NOT DISTINCT FROM cannot drive a hash join; their row as text
    -- (NULL renders empty, '' renders quoted) is an exact key that can, so the MERGE stays linear.
    MERGE INTO public.statistical_history_facet_delta AS t
    USING hd_sum AS s
       ON t.unit_type = s.unit_type AND t.on_month = s.on_month
      AND ROW(t.primary_activity_category_path, t.secondary_activity_category_path, t.sector_path, t.legal_form_id, t.physical_region_path, t.physical_country_id, t.unit_size_id, t.status_id)::text = ROW(s.primary_activity_category_path, s.secondary_activity_category_path, s.sector_path, s.legal_form_id, s.physical_region_path, s.physical_country_id, s.unit_size_id, s.status_id)::text
      AND t.primary_activity_category_path IS NOT DISTINCT FROM s.primary_activity_category_path
      AND t.secondary_activity_category_path IS NOT DISTINCT FROM s.secondary_activity_category_path
      AND t.sector_path IS NOT DISTINCT FROM s.sector_path
      AND t.legal_form_id IS NOT DISTINCT FROM s.legal_form_id
      AND t.physical_region_path IS NOT DISTINCT FROM s.physical_region_path
      AND t.physical_country_id IS NOT DISTINCT FROM s.physical_country_id
      AND t.unit_size_id IS NOT DISTINCT FROM s.unit_size_id
      AND t.status_id IS NOT DISTINCT FROM s.status_id
    WHEN MATCHED THEN UPDATE SET
        exists_added_count = t.exists_added_count + s.exists_added_count,
        exists_removed_count = t.exists_removed_count + s.exists_removed_count,
        countable_added_count = t.countable_added_count + s.countable_added_count,
        countable_removed_count = t.countable_removed_count + s.countable_removed_count,
        exists_moved_in_count = t.exists_moved_in_count + s.exists_moved_in_count,
        exists_moved_out_count = t.exists_moved_out_count + s.exists_moved_out_count,
        countable_moved_in_count = t.countable_moved_in_count + s.countable_moved_in_count,
        countable_moved_out_count = t.countable_moved_out_count + s.countable_moved_out_count,
        births = t.births + s.births,
        deaths = t.deaths + s.deaths,
        name_change_count = t.name_change_count + s.name_change_count,
        primary_activity_category_change_count = t.primary_activity_category_change_count + s.primary_activity_category_change_count,
        secondary_activity_category_change_count = t.secondary_activity_category_change_count + s.secondary_activity_category_change_count,
        sector_change_count = t.sector_change_count + s.sector_change_count,
        legal_form_change_count = t.legal_form_change_count + s.legal_form_change_count,
        physical_region_change_count = t.physical_region_change_count + s.physical_region_change_count,
        physical_country_change_count = t.physical_country_change_count + s.physical_country_change_count,
        physical_address_change_count = t.physical_address_change_count + s.physical_address_change_count,
        unit_size_change_count = t.unit_size_change_count + s.unit_size_change_count,
        status_change_count = t.status_change_count + s.status_change_count,
        stats_delta = public.jsonb_stats_delta_nullif_zero(CASE WHEN t.stats_delta IS NULL THEN s.stats_delta
                           WHEN s.stats_delta IS NULL THEN t.stats_delta
                           ELSE public.jsonb_stats_delta_merge(t.stats_delta, s.stats_delta) END),
        stats_ended_month = public.jsonb_stats_delta_nullif_zero(CASE WHEN t.stats_ended_month IS NULL THEN s.stats_ended_month
                           WHEN s.stats_ended_month IS NULL THEN t.stats_ended_month
                           ELSE public.jsonb_stats_delta_merge(t.stats_ended_month, s.stats_ended_month) END),
        stats_ended_year = public.jsonb_stats_delta_nullif_zero(CASE WHEN t.stats_ended_year IS NULL THEN s.stats_ended_year
                           WHEN s.stats_ended_year IS NULL THEN t.stats_ended_year
                           ELSE public.jsonb_stats_delta_merge(t.stats_ended_year, s.stats_ended_year) END),
        unit_ids = worker.unit_ids_apply(t.unit_ids, s.plus_ids, s.minus_ids)
    WHEN NOT MATCHED THEN INSERT (unit_type, primary_activity_category_path, secondary_activity_category_path,
        sector_path, legal_form_id, physical_region_path, physical_country_id, unit_size_id, status_id, on_month,
        exists_added_count, exists_removed_count, countable_added_count, countable_removed_count,
        exists_moved_in_count, exists_moved_out_count, countable_moved_in_count, countable_moved_out_count,
        births, deaths, name_change_count, primary_activity_category_change_count,
        secondary_activity_category_change_count, sector_change_count, legal_form_change_count,
        physical_region_change_count, physical_country_change_count, physical_address_change_count,
        unit_size_change_count, status_change_count, stats_delta, stats_ended_month, stats_ended_year, unit_ids)
      VALUES (s.unit_type, s.primary_activity_category_path, s.secondary_activity_category_path,
        s.sector_path, s.legal_form_id, s.physical_region_path, s.physical_country_id, s.unit_size_id, s.status_id, s.on_month,
        s.exists_added_count, s.exists_removed_count, s.countable_added_count, s.countable_removed_count,
        s.exists_moved_in_count, s.exists_moved_out_count, s.countable_moved_in_count, s.countable_moved_out_count,
        s.births, s.deaths, s.name_change_count, s.primary_activity_category_change_count,
        s.secondary_activity_category_change_count, s.sector_change_count, s.legal_form_change_count,
        s.physical_region_change_count, s.physical_country_change_count, s.physical_address_change_count,
        s.unit_size_change_count, s.status_change_count, s.stats_delta, s.stats_ended_month, s.stats_ended_year,
        worker.unit_ids_apply('{}', s.plus_ids, s.minus_ids));
    DELETE FROM public.statistical_history_facet_delta WHERE cardinality(unit_ids) = 0;

    IF EXISTS (SELECT 1 FROM public.statistical_history_facet_delta_staging WHERE generation > v_up_to) THEN
        DELETE FROM public.statistical_history_facet_delta_staging WHERE generation <= v_up_to;
    ELSE
        TRUNCATE public.statistical_history_facet_delta_staging;
    END IF;
END;
$procedure$
;

END;

-- Migration: Fix O(n²) behavior in timeline_enterprise refresh
--
-- Problem: The timeline_enterprise_def view's LATERAL joins against timeline_legal_unit
-- and timeline_establishment scan the ENTIRE tables for each row during partial refresh.
-- This causes:
--   - 172K rows × 4,924 loops = 848M row evaluations per batch
--   - Query times of 29-33 seconds per batch
--
-- Root cause: Same as timeline_legal_unit - the temporal overlap condition uses GIST index
-- which returns all temporally matching rows, then btree filter for enterprise_id applied
-- as post-filter.
--
-- Solution: Pre-materialize filtered timeline_legal_unit and timeline_establishment rows
-- into temp tables BEFORE the main join. This changes:
--   O(n × T) where T = total rows in each timeline table
-- to:
--   O(n × k) where k = avg related units per enterprise (~constant)
BEGIN;

-- ============================================================================
-- Modify timeline_enterprise_refresh to use pre-materialized temp tables
-- ============================================================================
CREATE OR REPLACE PROCEDURE public.timeline_enterprise_refresh(p_unit_id_ranges int4multirange DEFAULT NULL)
LANGUAGE plpgsql
AS $timeline_enterprise_refresh$
DECLARE
    p_target_table text := 'timeline_enterprise';
    p_unit_type public.statistical_unit_type := 'enterprise';
    v_batch_size INT := 32768;
    v_def_view_name text := p_target_table || '_def';
    v_min_id int; v_max_id int; v_start_id int; v_end_id int;
    v_batch_num INT := 0;
    v_total_units INT;
    v_batch_start_time timestamptz;
    v_batch_duration_ms numeric;
    v_batch_speed numeric;
    v_current_batch_size int;
    v_unit_ids INT[];
BEGIN
    IF p_unit_id_ranges IS NULL THEN
        -- Full refresh: ANALYZE and use the generic view-based approach
        ANALYZE public.timesegments, public.enterprise, public.timeline_legal_unit, public.timeline_establishment;

        SELECT MIN(unit_id), MAX(unit_id), COUNT(unit_id) INTO v_min_id, v_max_id, v_total_units
        FROM public.timesegments WHERE unit_type = p_unit_type;
        IF v_min_id IS NULL THEN RETURN; END IF;

        RAISE DEBUG 'Refreshing enterprise timeline for % units in batches of %...', v_total_units, v_batch_size;
        FOR i IN v_min_id..v_max_id BY v_batch_size LOOP
            v_batch_start_time := clock_timestamp();
            v_batch_num := v_batch_num + 1;
            v_start_id := i; v_end_id := i + v_batch_size - 1;
            EXECUTE format('DELETE FROM public.%I WHERE unit_type = %L AND unit_id BETWEEN %L AND %L',
                           p_target_table, p_unit_type, v_start_id, v_end_id);
            EXECUTE format('INSERT INTO public.%I SELECT * FROM public.%I WHERE unit_type = %L AND unit_id BETWEEN %L AND %L',
                           p_target_table, v_def_view_name, p_unit_type, v_start_id, v_end_id);

            v_batch_duration_ms := (EXTRACT(EPOCH FROM (clock_timestamp() - v_batch_start_time))) * 1000;
            v_current_batch_size := v_batch_size;
            v_batch_speed := v_current_batch_size / (v_batch_duration_ms / 1000.0);
            RAISE DEBUG 'Enterprise timeline batch %/% done. (% units, % ms, % units/s)',
                v_batch_num, ceil(v_total_units::decimal / v_batch_size), v_current_batch_size,
                round(v_batch_duration_ms), round(v_batch_speed);
        END LOOP;

        EXECUTE format('ANALYZE public.%I', p_target_table);
    ELSE
        -- Partial refresh: Pre-materialize filtered tables to avoid O(n²) scan
        v_unit_ids := public.int4multirange_to_array(p_unit_id_ranges);

        -- Drop staging tables if exist from previous run (silent, no NOTICE)
        PERFORM set_config('client_min_messages', 'warning', true);
        DROP TABLE IF EXISTS public.timeline_legal_unit_filtered;
        DROP TABLE IF EXISTS public.timeline_establishment_filtered;
        PERFORM set_config('client_min_messages', 'notice', true);

        -- Pre-filter timeline_legal_unit to only rows for these enterprises
        -- Use UNLOGGED for cross-session visibility (enables concurrency > 1)
        CREATE UNLOGGED TABLE public.timeline_legal_unit_filtered AS
        SELECT tlu.*
        FROM public.timeline_legal_unit tlu
        WHERE tlu.enterprise_id = ANY(v_unit_ids);

        -- Create index for the join
        CREATE INDEX ON public.timeline_legal_unit_filtered (enterprise_id, valid_from, valid_until);
        ANALYZE public.timeline_legal_unit_filtered;

        -- Pre-filter timeline_establishment to only rows for these enterprises
        CREATE UNLOGGED TABLE public.timeline_establishment_filtered AS
        SELECT tes.*
        FROM public.timeline_establishment tes
        WHERE tes.enterprise_id = ANY(v_unit_ids);

        -- Create index for the join
        CREATE INDEX ON public.timeline_establishment_filtered (enterprise_id, valid_from, valid_until);
        ANALYZE public.timeline_establishment_filtered;

        -- Delete existing rows for these units
        DELETE FROM public.timeline_enterprise
        WHERE unit_type = 'enterprise' AND unit_id = ANY(v_unit_ids);

        -- Insert using pre-filtered temp tables
        -- This is the timeline_enterprise_def query but using temp tables
        INSERT INTO public.timeline_enterprise
        WITH aggregation AS (
            SELECT ten.enterprise_id,
                ten.valid_from,
                ten.valid_until,
                public.array_distinct_concat(COALESCE(array_cat(tlu.data_source_ids, tes.data_source_ids), tlu.data_source_ids, tes.data_source_ids)) AS data_source_ids,
                public.array_distinct_concat(COALESCE(array_cat(tlu.data_source_codes, tes.data_source_codes), tlu.data_source_codes, tes.data_source_codes)) AS data_source_codes,
                public.array_distinct_concat(COALESCE(array_cat(tlu.related_establishment_ids, tes.related_establishment_ids), tlu.related_establishment_ids, tes.related_establishment_ids)) AS related_establishment_ids,
                public.array_distinct_concat(COALESCE(array_cat(tlu.excluded_establishment_ids, tes.excluded_establishment_ids), tlu.excluded_establishment_ids, tes.excluded_establishment_ids)) AS excluded_establishment_ids,
                public.array_distinct_concat(COALESCE(array_cat(tlu.included_establishment_ids, tes.included_establishment_ids), tlu.included_establishment_ids, tes.included_establishment_ids)) AS included_establishment_ids,
                public.array_distinct_concat(tlu.related_legal_unit_ids) AS related_legal_unit_ids,
                public.array_distinct_concat(tlu.excluded_legal_unit_ids) AS excluded_legal_unit_ids,
                public.array_distinct_concat(tlu.included_legal_unit_ids) AS included_legal_unit_ids,
                COALESCE(public.jsonb_stats_summary_merge_agg(COALESCE(public.jsonb_stats_summary_merge(tlu.stats_summary, tes.stats_summary), tlu.stats_summary, tes.stats_summary)), '{}'::jsonb) AS stats_summary
            FROM (
                SELECT t.unit_type,
                    t.unit_id,
                    t.valid_from,
                    t.valid_until,
                    en.id,
                    en.active,
                    en.short_name,
                    en.edit_comment,
                    en.edit_by_user_id,
                    en.edit_at,
                    en.id AS enterprise_id
                FROM public.timesegments t
                JOIN public.enterprise en ON t.unit_type = 'enterprise'::public.statistical_unit_type AND t.unit_id = en.id
                WHERE t.unit_id = ANY(v_unit_ids)
            ) ten
            -- CRITICAL FIX: Join against pre-filtered temp table instead of full timeline_legal_unit
            LEFT JOIN LATERAL (
                SELECT tlu_f.enterprise_id,
                    ten.valid_from,
                    ten.valid_until,
                    public.array_distinct_concat(tlu_f.data_source_ids) AS data_source_ids,
                    public.array_distinct_concat(tlu_f.data_source_codes) AS data_source_codes,
                    public.array_distinct_concat(tlu_f.related_establishment_ids) AS related_establishment_ids,
                    public.array_distinct_concat(tlu_f.excluded_establishment_ids) AS excluded_establishment_ids,
                    public.array_distinct_concat(tlu_f.included_establishment_ids) AS included_establishment_ids,
                    array_agg(DISTINCT tlu_f.legal_unit_id) AS related_legal_unit_ids,
                    array_agg(DISTINCT tlu_f.legal_unit_id) FILTER (WHERE NOT tlu_f.used_for_counting) AS excluded_legal_unit_ids,
                    array_agg(DISTINCT tlu_f.legal_unit_id) FILTER (WHERE tlu_f.used_for_counting) AS included_legal_unit_ids,
                    public.jsonb_stats_summary_merge_agg(tlu_f.stats_summary) FILTER (WHERE tlu_f.used_for_counting) AS stats_summary
                FROM public.timeline_legal_unit_filtered tlu_f
                WHERE tlu_f.enterprise_id = ten.enterprise_id
                  AND public.from_until_overlaps(ten.valid_from, ten.valid_until, tlu_f.valid_from, tlu_f.valid_until)
                GROUP BY tlu_f.enterprise_id, ten.valid_from, ten.valid_until
            ) tlu ON true
            -- CRITICAL FIX: Join against pre-filtered temp table instead of full timeline_establishment
            LEFT JOIN LATERAL (
                SELECT tes_f.enterprise_id,
                    ten.valid_from,
                    ten.valid_until,
                    public.array_distinct_concat(tes_f.data_source_ids) AS data_source_ids,
                    public.array_distinct_concat(tes_f.data_source_codes) AS data_source_codes,
                    array_agg(DISTINCT tes_f.establishment_id) AS related_establishment_ids,
                    array_agg(DISTINCT tes_f.establishment_id) FILTER (WHERE NOT tes_f.used_for_counting) AS excluded_establishment_ids,
                    array_agg(DISTINCT tes_f.establishment_id) FILTER (WHERE tes_f.used_for_counting) AS included_establishment_ids,
                    public.jsonb_stats_summary_merge_agg(tes_f.stats_summary) FILTER (WHERE tes_f.used_for_counting) AS stats_summary
                FROM public.timeline_establishment_filtered tes_f
                WHERE tes_f.enterprise_id = ten.enterprise_id
                  AND public.from_until_overlaps(ten.valid_from, ten.valid_until, tes_f.valid_from, tes_f.valid_until)
                GROUP BY tes_f.enterprise_id, ten.valid_from, ten.valid_until
            ) tes ON true
            GROUP BY ten.enterprise_id, ten.valid_from, ten.valid_until
        ), enterprise_with_primary_and_aggregation AS (
            SELECT
                (SELECT array_agg(DISTINCT ids.id) FROM (
                    SELECT unnest(basis.data_source_ids) AS id
                    UNION
                    SELECT unnest(aggregation.data_source_ids) AS id
                ) ids) AS data_source_ids,
                (SELECT array_agg(DISTINCT codes.code) FROM (
                    SELECT unnest(basis.data_source_codes) AS code
                    UNION ALL
                    SELECT unnest(aggregation.data_source_codes) AS code
                ) codes) AS data_source_codes,
                basis.unit_type,
                basis.unit_id,
                basis.valid_from,
                basis.valid_to,
                basis.valid_until,
                basis.name,
                basis.birth_date,
                basis.death_date,
                basis.search,
                basis.primary_activity_category_id,
                basis.primary_activity_category_path,
                basis.primary_activity_category_code,
                basis.secondary_activity_category_id,
                basis.secondary_activity_category_path,
                basis.secondary_activity_category_code,
                basis.activity_category_paths,
                basis.sector_id,
                basis.sector_path,
                basis.sector_code,
                basis.sector_name,
                basis.legal_form_id,
                basis.legal_form_code,
                basis.legal_form_name,
                basis.physical_address_part1,
                basis.physical_address_part2,
                basis.physical_address_part3,
                basis.physical_postcode,
                basis.physical_postplace,
                basis.physical_region_id,
                basis.physical_region_path,
                basis.physical_region_code,
                basis.physical_country_id,
                basis.physical_country_iso_2,
                basis.physical_latitude,
                basis.physical_longitude,
                basis.physical_altitude,
                basis.domestic,
                basis.postal_address_part1,
                basis.postal_address_part2,
                basis.postal_address_part3,
                basis.postal_postcode,
                basis.postal_postplace,
                basis.postal_region_id,
                basis.postal_region_path,
                basis.postal_region_code,
                basis.postal_country_id,
                basis.postal_country_iso_2,
                basis.postal_latitude,
                basis.postal_longitude,
                basis.postal_altitude,
                basis.web_address,
                basis.email_address,
                basis.phone_number,
                basis.landline,
                basis.mobile_number,
                basis.fax_number,
                basis.unit_size_id,
                basis.unit_size_code,
                basis.status_id,
                basis.status_code,
                basis.used_for_counting,
                basis.last_edit_comment,
                basis.last_edit_by_user_id,
                basis.last_edit_at,
                basis.invalid_codes,
                basis.has_legal_unit,
                aggregation.related_establishment_ids,
                aggregation.excluded_establishment_ids,
                aggregation.included_establishment_ids,
                aggregation.related_legal_unit_ids,
                aggregation.excluded_legal_unit_ids,
                aggregation.included_legal_unit_ids,
                basis.enterprise_id,
                basis.primary_establishment_id,
                basis.primary_legal_unit_id,
                CASE WHEN basis.used_for_counting THEN aggregation.stats_summary ELSE '{}'::jsonb END AS stats_summary
            FROM (
                SELECT
                    t.unit_type,
                    t.unit_id,
                    t.valid_from,
                    (t.valid_until - '1 day'::interval)::date AS valid_to,
                    t.valid_until,
                    COALESCE(NULLIF(en.short_name::text, ''::text), plu.name::text, pes.name::text) AS name,
                    COALESCE(plu.birth_date, pes.birth_date) AS birth_date,
                    COALESCE(plu.death_date, pes.death_date) AS death_date,
                    to_tsvector('simple'::regconfig, COALESCE(NULLIF(en.short_name::text, ''::text), plu.name::text, pes.name::text)) AS search,
                    COALESCE(plu.primary_activity_category_id, pes.primary_activity_category_id) AS primary_activity_category_id,
                    COALESCE(plu.primary_activity_category_path, pes.primary_activity_category_path) AS primary_activity_category_path,
                    COALESCE(plu.primary_activity_category_code, pes.primary_activity_category_code) AS primary_activity_category_code,
                    COALESCE(plu.secondary_activity_category_id, pes.secondary_activity_category_id) AS secondary_activity_category_id,
                    COALESCE(plu.secondary_activity_category_path, pes.secondary_activity_category_path) AS secondary_activity_category_path,
                    COALESCE(plu.secondary_activity_category_code, pes.secondary_activity_category_code) AS secondary_activity_category_code,
                    COALESCE(plu.activity_category_paths, pes.activity_category_paths) AS activity_category_paths,
                    COALESCE(plu.sector_id, pes.sector_id) AS sector_id,
                    COALESCE(plu.sector_path, pes.sector_path) AS sector_path,
                    COALESCE(plu.sector_code, pes.sector_code) AS sector_code,
                    COALESCE(plu.sector_name, pes.sector_name) AS sector_name,
                    COALESCE(plu.data_source_ids, pes.data_source_ids) AS data_source_ids,
                    COALESCE(plu.data_source_codes, pes.data_source_codes) AS data_source_codes,
                    COALESCE(plu.legal_form_id, pes.legal_form_id) AS legal_form_id,
                    COALESCE(plu.legal_form_code, pes.legal_form_code) AS legal_form_code,
                    COALESCE(plu.legal_form_name, pes.legal_form_name) AS legal_form_name,
                    COALESCE(plu.physical_address_part1, pes.physical_address_part1) AS physical_address_part1,
                    COALESCE(plu.physical_address_part2, pes.physical_address_part2) AS physical_address_part2,
                    COALESCE(plu.physical_address_part3, pes.physical_address_part3) AS physical_address_part3,
                    COALESCE(plu.physical_postcode, pes.physical_postcode) AS physical_postcode,
                    COALESCE(plu.physical_postplace, pes.physical_postplace) AS physical_postplace,
                    COALESCE(plu.physical_region_id, pes.physical_region_id) AS physical_region_id,
                    COALESCE(plu.physical_region_path, pes.physical_region_path) AS physical_region_path,
                    COALESCE(plu.physical_region_code, pes.physical_region_code) AS physical_region_code,
                    COALESCE(plu.physical_country_id, pes.physical_country_id) AS physical_country_id,
                    COALESCE(plu.physical_country_iso_2, pes.physical_country_iso_2) AS physical_country_iso_2,
                    COALESCE(plu.physical_latitude, pes.physical_latitude) AS physical_latitude,
                    COALESCE(plu.physical_longitude, pes.physical_longitude) AS physical_longitude,
                    COALESCE(plu.physical_altitude, pes.physical_altitude) AS physical_altitude,
                    COALESCE(plu.domestic, pes.domestic) AS domestic,
                    COALESCE(plu.postal_address_part1, pes.postal_address_part1) AS postal_address_part1,
                    COALESCE(plu.postal_address_part2, pes.postal_address_part2) AS postal_address_part2,
                    COALESCE(plu.postal_address_part3, pes.postal_address_part3) AS postal_address_part3,
                    COALESCE(plu.postal_postcode, pes.postal_postcode) AS postal_postcode,
                    COALESCE(plu.postal_postplace, pes.postal_postplace) AS postal_postplace,
                    COALESCE(plu.postal_region_id, pes.postal_region_id) AS postal_region_id,
                    COALESCE(plu.postal_region_path, pes.postal_region_path) AS postal_region_path,
                    COALESCE(plu.postal_region_code, pes.postal_region_code) AS postal_region_code,
                    COALESCE(plu.postal_country_id, pes.postal_country_id) AS postal_country_id,
                    COALESCE(plu.postal_country_iso_2, pes.postal_country_iso_2) AS postal_country_iso_2,
                    COALESCE(plu.postal_latitude, pes.postal_latitude) AS postal_latitude,
                    COALESCE(plu.postal_longitude, pes.postal_longitude) AS postal_longitude,
                    COALESCE(plu.postal_altitude, pes.postal_altitude) AS postal_altitude,
                    COALESCE(plu.web_address, pes.web_address) AS web_address,
                    COALESCE(plu.email_address, pes.email_address) AS email_address,
                    COALESCE(plu.phone_number, pes.phone_number) AS phone_number,
                    COALESCE(plu.landline, pes.landline) AS landline,
                    COALESCE(plu.mobile_number, pes.mobile_number) AS mobile_number,
                    COALESCE(plu.fax_number, pes.fax_number) AS fax_number,
                    COALESCE(plu.unit_size_id, pes.unit_size_id) AS unit_size_id,
                    COALESCE(plu.unit_size_code, pes.unit_size_code) AS unit_size_code,
                    COALESCE(plu.status_id, pes.status_id) AS status_id,
                    COALESCE(plu.status_code, pes.status_code) AS status_code,
                    COALESCE(plu.used_for_counting, pes.used_for_counting, false) AS used_for_counting,
                    last_edit.edit_comment AS last_edit_comment,
                    last_edit.edit_by_user_id AS last_edit_by_user_id,
                    last_edit.edit_at AS last_edit_at,
                    COALESCE(plu.invalid_codes, pes.invalid_codes) AS invalid_codes,
                    plu.legal_unit_id IS NOT NULL AS has_legal_unit,
                    en.id AS enterprise_id,
                    pes.establishment_id AS primary_establishment_id,
                    plu.legal_unit_id AS primary_legal_unit_id
                FROM public.timesegments t
                JOIN public.enterprise en ON t.unit_type = 'enterprise'::public.statistical_unit_type AND t.unit_id = en.id
                -- Use temp table for primary legal unit lookup
                LEFT JOIN LATERAL (
                    SELECT tlu_f.*
                    FROM public.timeline_legal_unit_filtered tlu_f
                    WHERE tlu_f.enterprise_id = en.id
                      AND tlu_f.primary_for_enterprise = true
                      AND public.from_until_overlaps(t.valid_from, t.valid_until, tlu_f.valid_from, tlu_f.valid_until)
                    ORDER BY tlu_f.valid_from DESC, tlu_f.legal_unit_id DESC
                    LIMIT 1
                ) plu ON true
                -- Use temp table for primary establishment lookup
                LEFT JOIN LATERAL (
                    SELECT tes_f.*
                    FROM public.timeline_establishment_filtered tes_f
                    WHERE tes_f.enterprise_id = en.id
                      AND tes_f.primary_for_enterprise = true
                      AND public.from_until_overlaps(t.valid_from, t.valid_until, tes_f.valid_from, tes_f.valid_until)
                    ORDER BY tes_f.valid_from DESC, tes_f.establishment_id DESC
                    LIMIT 1
                ) pes ON true
                -- Pick the most recent edit from enterprise, primary legal unit, or primary establishment
                LEFT JOIN LATERAL (
                    SELECT all_edits.edit_comment,
                           all_edits.edit_by_user_id,
                           all_edits.edit_at
                    FROM ( VALUES
                        (en.edit_comment, en.edit_by_user_id, en.edit_at),
                        (plu.last_edit_comment, plu.last_edit_by_user_id, plu.last_edit_at),
                        (pes.last_edit_comment, pes.last_edit_by_user_id, pes.last_edit_at)
                    ) all_edits(edit_comment, edit_by_user_id, edit_at)
                    WHERE all_edits.edit_at IS NOT NULL
                    ORDER BY all_edits.edit_at DESC
                    LIMIT 1
                ) last_edit ON true
                WHERE t.unit_id = ANY(v_unit_ids)
            ) basis
            JOIN aggregation ON basis.enterprise_id = aggregation.enterprise_id
                AND basis.valid_from = aggregation.valid_from
                AND basis.valid_until = aggregation.valid_until
        )
        SELECT
            unit_type,
            unit_id,
            valid_from,
            valid_to,
            valid_until,
            name,
            birth_date,
            death_date,
            search,
            primary_activity_category_id,
            primary_activity_category_path,
            primary_activity_category_code,
            secondary_activity_category_id,
            secondary_activity_category_path,
            secondary_activity_category_code,
            activity_category_paths,
            sector_id,
            sector_path,
            sector_code,
            sector_name,
            data_source_ids,
            data_source_codes,
            legal_form_id,
            legal_form_code,
            legal_form_name,
            physical_address_part1,
            physical_address_part2,
            physical_address_part3,
            physical_postcode,
            physical_postplace,
            physical_region_id,
            physical_region_path,
            physical_region_code,
            physical_country_id,
            physical_country_iso_2,
            physical_latitude,
            physical_longitude,
            physical_altitude,
            domestic,
            postal_address_part1,
            postal_address_part2,
            postal_address_part3,
            postal_postcode,
            postal_postplace,
            postal_region_id,
            postal_region_path,
            postal_region_code,
            postal_country_id,
            postal_country_iso_2,
            postal_latitude,
            postal_longitude,
            postal_altitude,
            web_address,
            email_address,
            phone_number,
            landline,
            mobile_number,
            fax_number,
            unit_size_id,
            unit_size_code,
            status_id,
            status_code,
            used_for_counting,
            last_edit_comment,
            last_edit_by_user_id,
            last_edit_at,
            invalid_codes,
            has_legal_unit,
            related_establishment_ids,
            excluded_establishment_ids,
            included_establishment_ids,
            related_legal_unit_ids,
            excluded_legal_unit_ids,
            included_legal_unit_ids,
            ARRAY[enterprise_id] AS related_enterprise_ids,
            ARRAY[]::integer[] AS excluded_enterprise_ids,
            CASE WHEN used_for_counting THEN ARRAY[enterprise_id] ELSE ARRAY[]::integer[] END AS included_enterprise_ids,
            enterprise_id,
            primary_establishment_id,
            primary_legal_unit_id,
            stats_summary
        FROM enterprise_with_primary_and_aggregation
        ORDER BY unit_type, unit_id, valid_from;

        -- Clean up staging tables (silent, no NOTICE)
        PERFORM set_config('client_min_messages', 'warning', true);
        DROP TABLE IF EXISTS public.timeline_legal_unit_filtered;
        DROP TABLE IF EXISTS public.timeline_establishment_filtered;
        PERFORM set_config('client_min_messages', 'notice', true);
    END IF;
END;
$timeline_enterprise_refresh$;

END;

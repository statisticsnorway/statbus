-- Migration 20260206211707: fix_derive_pipeline_consistency
--
-- Fix: Defer DELETE from statistical_unit main table to flush_staging.
-- Before: Each batch DELETEs from main immediately, creating holes if worker crashes.
-- After:  Batches only write to staging. Flush atomically replaces main rows.
--         Worker crash at any point leaves main table complete (old data).
BEGIN;

-- =============================================================================
-- 1. statistical_unit_refresh: Remove DELETE from main table in partial mode
--    Batches now only write to staging; flush handles the main table swap.
-- =============================================================================
CREATE OR REPLACE PROCEDURE public.statistical_unit_refresh(IN p_establishment_id_ranges int4multirange DEFAULT NULL::int4multirange, IN p_legal_unit_id_ranges int4multirange DEFAULT NULL::int4multirange, IN p_enterprise_id_ranges int4multirange DEFAULT NULL::int4multirange)
 LANGUAGE plpgsql
AS $statistical_unit_refresh$
DECLARE
    v_batch_size INT := 262144;
    v_min_id int; v_max_id int; v_start_id int; v_end_id int;
    v_batch_num INT;
    v_total_units INT;
    v_batch_start_time timestamptz;
    v_batch_duration_ms numeric;
    v_batch_speed numeric;
    v_current_batch_size int;
    v_is_partial_refresh BOOLEAN;
BEGIN
    v_is_partial_refresh := (p_establishment_id_ranges IS NOT NULL
                            OR p_legal_unit_id_ranges IS NOT NULL
                            OR p_enterprise_id_ranges IS NOT NULL);

    IF NOT v_is_partial_refresh THEN
        -- Full refresh with ANALYZE
        ANALYZE public.timeline_establishment, public.timeline_legal_unit, public.timeline_enterprise;

        -- Create temp table WITHOUT valid_range (it's GENERATED in the target)
        CREATE TEMP TABLE statistical_unit_new (LIKE public.statistical_unit) ON COMMIT DROP;
        ALTER TABLE statistical_unit_new DROP COLUMN IF EXISTS valid_range;

        -- Establishments
        v_batch_num := 0;
        SELECT MIN(unit_id), MAX(unit_id), COUNT(unit_id) INTO v_min_id, v_max_id, v_total_units FROM public.timesegments WHERE unit_type = 'establishment';
        RAISE DEBUG 'Refreshing statistical units for % establishments in batches of %...', v_total_units, v_batch_size;
        IF v_min_id IS NOT NULL THEN FOR i IN v_min_id..v_max_id BY v_batch_size LOOP
            v_batch_start_time := clock_timestamp();
            v_batch_num := v_batch_num + 1;
            v_start_id := i; v_end_id := i + v_batch_size - 1;
            INSERT INTO statistical_unit_new (
                unit_type, unit_id, valid_from, valid_to, valid_until, external_idents, name, birth_date, death_date, search,
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
                last_edit_comment, last_edit_by_user_id, last_edit_at, invalid_codes, has_legal_unit,
                related_establishment_ids, excluded_establishment_ids, included_establishment_ids,
                related_legal_unit_ids, excluded_legal_unit_ids, included_legal_unit_ids,
                related_enterprise_ids, excluded_enterprise_ids, included_enterprise_ids,
                stats, stats_summary, included_establishment_count, included_legal_unit_count, included_enterprise_count, tag_paths
            )
            SELECT
                unit_type, unit_id, valid_from, valid_to, valid_until, external_idents, name, birth_date, death_date, search,
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
                last_edit_comment, last_edit_by_user_id, last_edit_at, invalid_codes, has_legal_unit,
                related_establishment_ids, excluded_establishment_ids, included_establishment_ids,
                related_legal_unit_ids, excluded_legal_unit_ids, included_legal_unit_ids,
                related_enterprise_ids, excluded_enterprise_ids, included_enterprise_ids,
                stats, stats_summary, included_establishment_count, included_legal_unit_count, included_enterprise_count, tag_paths
            FROM public.statistical_unit_def
            WHERE unit_type = 'establishment' AND unit_id BETWEEN v_start_id AND v_end_id;
            v_batch_duration_ms := (EXTRACT(EPOCH FROM (clock_timestamp() - v_batch_start_time))) * 1000;
            v_current_batch_size := v_batch_size;
            v_batch_speed := v_current_batch_size / (v_batch_duration_ms / 1000.0);
            RAISE DEBUG 'Establishment SU batch %/% done. (% units, % ms, % units/s)', v_batch_num, ceil(v_total_units::decimal / v_batch_size), v_current_batch_size, round(v_batch_duration_ms), round(v_batch_speed);
        END LOOP; END IF;

        -- Legal Units
        v_batch_num := 0;
        SELECT MIN(unit_id), MAX(unit_id), COUNT(unit_id) INTO v_min_id, v_max_id, v_total_units FROM public.timesegments WHERE unit_type = 'legal_unit';
        RAISE DEBUG 'Refreshing statistical units for % legal units in batches of %...', v_total_units, v_batch_size;
        IF v_min_id IS NOT NULL THEN FOR i IN v_min_id..v_max_id BY v_batch_size LOOP
            v_batch_start_time := clock_timestamp();
            v_batch_num := v_batch_num + 1;
            v_start_id := i; v_end_id := i + v_batch_size - 1;
            INSERT INTO statistical_unit_new (
                unit_type, unit_id, valid_from, valid_to, valid_until, external_idents, name, birth_date, death_date, search,
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
                last_edit_comment, last_edit_by_user_id, last_edit_at, invalid_codes, has_legal_unit,
                related_establishment_ids, excluded_establishment_ids, included_establishment_ids,
                related_legal_unit_ids, excluded_legal_unit_ids, included_legal_unit_ids,
                related_enterprise_ids, excluded_enterprise_ids, included_enterprise_ids,
                stats, stats_summary, included_establishment_count, included_legal_unit_count, included_enterprise_count, tag_paths
            )
            SELECT
                unit_type, unit_id, valid_from, valid_to, valid_until, external_idents, name, birth_date, death_date, search,
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
                last_edit_comment, last_edit_by_user_id, last_edit_at, invalid_codes, has_legal_unit,
                related_establishment_ids, excluded_establishment_ids, included_establishment_ids,
                related_legal_unit_ids, excluded_legal_unit_ids, included_legal_unit_ids,
                related_enterprise_ids, excluded_enterprise_ids, included_enterprise_ids,
                stats, stats_summary, included_establishment_count, included_legal_unit_count, included_enterprise_count, tag_paths
            FROM public.statistical_unit_def
            WHERE unit_type = 'legal_unit' AND unit_id BETWEEN v_start_id AND v_end_id;
            v_batch_duration_ms := (EXTRACT(EPOCH FROM (clock_timestamp() - v_batch_start_time))) * 1000;
            v_current_batch_size := v_batch_size;
            v_batch_speed := v_current_batch_size / (v_batch_duration_ms / 1000.0);
            RAISE DEBUG 'Legal unit SU batch %/% done. (% units, % ms, % units/s)', v_batch_num, ceil(v_total_units::decimal / v_batch_size), v_current_batch_size, round(v_batch_duration_ms), round(v_batch_speed);
        END LOOP; END IF;

        -- Enterprises
        v_batch_num := 0;
        SELECT MIN(unit_id), MAX(unit_id), COUNT(unit_id) INTO v_min_id, v_max_id, v_total_units FROM public.timesegments WHERE unit_type = 'enterprise';
        RAISE DEBUG 'Refreshing statistical units for % enterprises in batches of %...', v_total_units, v_batch_size;
        IF v_min_id IS NOT NULL THEN FOR i IN v_min_id..v_max_id BY v_batch_size LOOP
            v_batch_start_time := clock_timestamp();
            v_batch_num := v_batch_num + 1;
            v_start_id := i; v_end_id := i + v_batch_size - 1;
            INSERT INTO statistical_unit_new (
                unit_type, unit_id, valid_from, valid_to, valid_until, external_idents, name, birth_date, death_date, search,
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
                last_edit_comment, last_edit_by_user_id, last_edit_at, invalid_codes, has_legal_unit,
                related_establishment_ids, excluded_establishment_ids, included_establishment_ids,
                related_legal_unit_ids, excluded_legal_unit_ids, included_legal_unit_ids,
                related_enterprise_ids, excluded_enterprise_ids, included_enterprise_ids,
                stats, stats_summary, included_establishment_count, included_legal_unit_count, included_enterprise_count, tag_paths
            )
            SELECT
                unit_type, unit_id, valid_from, valid_to, valid_until, external_idents, name, birth_date, death_date, search,
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
                last_edit_comment, last_edit_by_user_id, last_edit_at, invalid_codes, has_legal_unit,
                related_establishment_ids, excluded_establishment_ids, included_establishment_ids,
                related_legal_unit_ids, excluded_legal_unit_ids, included_legal_unit_ids,
                related_enterprise_ids, excluded_enterprise_ids, included_enterprise_ids,
                stats, stats_summary, included_establishment_count, included_legal_unit_count, included_enterprise_count, tag_paths
            FROM public.statistical_unit_def
            WHERE unit_type = 'enterprise' AND unit_id BETWEEN v_start_id AND v_end_id;
            v_batch_duration_ms := (EXTRACT(EPOCH FROM (clock_timestamp() - v_batch_start_time))) * 1000;
            v_current_batch_size := v_batch_size;
            v_batch_speed := v_current_batch_size / (v_batch_duration_ms / 1000.0);
            RAISE DEBUG 'Enterprise SU batch %/% done. (% units, % ms, % units/s)', v_batch_num, ceil(v_total_units::decimal / v_batch_size), v_current_batch_size, round(v_batch_duration_ms), round(v_batch_speed);
        END LOOP; END IF;

        TRUNCATE public.statistical_unit;
        -- Use explicit column list for final insert (temp table has no valid_range)
        INSERT INTO public.statistical_unit (
            unit_type, unit_id, valid_from, valid_to, valid_until, external_idents, name, birth_date, death_date, search,
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
            last_edit_comment, last_edit_by_user_id, last_edit_at, invalid_codes, has_legal_unit,
            related_establishment_ids, excluded_establishment_ids, included_establishment_ids,
            related_legal_unit_ids, excluded_legal_unit_ids, included_legal_unit_ids,
            related_enterprise_ids, excluded_enterprise_ids, included_enterprise_ids,
            stats, stats_summary, included_establishment_count, included_legal_unit_count, included_enterprise_count, tag_paths
        )
        SELECT
            unit_type, unit_id, valid_from, valid_to, valid_until, external_idents, name, birth_date, death_date, search,
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
            last_edit_comment, last_edit_by_user_id, last_edit_at, invalid_codes, has_legal_unit,
            related_establishment_ids, excluded_establishment_ids, included_establishment_ids,
            related_legal_unit_ids, excluded_legal_unit_ids, included_legal_unit_ids,
            related_enterprise_ids, excluded_enterprise_ids, included_enterprise_ids,
            stats, stats_summary, included_establishment_count, included_legal_unit_count, included_enterprise_count, tag_paths
        FROM statistical_unit_new;

        ANALYZE public.statistical_unit;
    ELSE
        -- =====================================================================
        -- PARTIAL REFRESH: Write only to staging table.
        -- Main table is NOT modified here — flush_staging handles the atomic swap.
        -- This means worker crash leaves main table complete (with old data).
        -- =====================================================================

        IF p_establishment_id_ranges IS NOT NULL THEN
            -- Delete from staging to handle multiple updates to same unit within a derive cycle
            DELETE FROM public.statistical_unit_staging WHERE unit_type = 'establishment' AND unit_id <@ p_establishment_id_ranges;
            -- Insert to staging table (explicit columns - staging doesn't have valid_range)
            INSERT INTO public.statistical_unit_staging (
                unit_type, unit_id, valid_from, valid_to, valid_until, external_idents, name, birth_date, death_date, search,
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
                last_edit_comment, last_edit_by_user_id, last_edit_at, invalid_codes, has_legal_unit,
                related_establishment_ids, excluded_establishment_ids, included_establishment_ids,
                related_legal_unit_ids, excluded_legal_unit_ids, included_legal_unit_ids,
                related_enterprise_ids, excluded_enterprise_ids, included_enterprise_ids,
                stats, stats_summary, included_establishment_count, included_legal_unit_count, included_enterprise_count, tag_paths
            )
            SELECT
                unit_type, unit_id, valid_from, valid_to, valid_until, external_idents, name, birth_date, death_date, search,
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
                last_edit_comment, last_edit_by_user_id, last_edit_at, invalid_codes, has_legal_unit,
                related_establishment_ids, excluded_establishment_ids, included_establishment_ids,
                related_legal_unit_ids, excluded_legal_unit_ids, included_legal_unit_ids,
                related_enterprise_ids, excluded_enterprise_ids, included_enterprise_ids,
                stats, stats_summary, included_establishment_count, included_legal_unit_count, included_enterprise_count, tag_paths
            FROM import.get_statistical_unit_data_partial('establishment', p_establishment_id_ranges);
        END IF;
        IF p_legal_unit_id_ranges IS NOT NULL THEN
            -- Delete from staging to handle multiple updates to same unit within a derive cycle
            DELETE FROM public.statistical_unit_staging WHERE unit_type = 'legal_unit' AND unit_id <@ p_legal_unit_id_ranges;
            -- Insert to staging table (explicit columns - staging doesn't have valid_range)
            INSERT INTO public.statistical_unit_staging (
                unit_type, unit_id, valid_from, valid_to, valid_until, external_idents, name, birth_date, death_date, search,
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
                last_edit_comment, last_edit_by_user_id, last_edit_at, invalid_codes, has_legal_unit,
                related_establishment_ids, excluded_establishment_ids, included_establishment_ids,
                related_legal_unit_ids, excluded_legal_unit_ids, included_legal_unit_ids,
                related_enterprise_ids, excluded_enterprise_ids, included_enterprise_ids,
                stats, stats_summary, included_establishment_count, included_legal_unit_count, included_enterprise_count, tag_paths
            )
            SELECT
                unit_type, unit_id, valid_from, valid_to, valid_until, external_idents, name, birth_date, death_date, search,
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
                last_edit_comment, last_edit_by_user_id, last_edit_at, invalid_codes, has_legal_unit,
                related_establishment_ids, excluded_establishment_ids, included_establishment_ids,
                related_legal_unit_ids, excluded_legal_unit_ids, included_legal_unit_ids,
                related_enterprise_ids, excluded_enterprise_ids, included_enterprise_ids,
                stats, stats_summary, included_establishment_count, included_legal_unit_count, included_enterprise_count, tag_paths
            FROM import.get_statistical_unit_data_partial('legal_unit', p_legal_unit_id_ranges);
        END IF;
        IF p_enterprise_id_ranges IS NOT NULL THEN
            -- Delete from staging to handle multiple updates to same unit within a derive cycle
            DELETE FROM public.statistical_unit_staging WHERE unit_type = 'enterprise' AND unit_id <@ p_enterprise_id_ranges;
            -- Insert to staging table (explicit columns - staging doesn't have valid_range)
            INSERT INTO public.statistical_unit_staging (
                unit_type, unit_id, valid_from, valid_to, valid_until, external_idents, name, birth_date, death_date, search,
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
                last_edit_comment, last_edit_by_user_id, last_edit_at, invalid_codes, has_legal_unit,
                related_establishment_ids, excluded_establishment_ids, included_establishment_ids,
                related_legal_unit_ids, excluded_legal_unit_ids, included_legal_unit_ids,
                related_enterprise_ids, excluded_enterprise_ids, included_enterprise_ids,
                stats, stats_summary, included_establishment_count, included_legal_unit_count, included_enterprise_count, tag_paths
            )
            SELECT
                unit_type, unit_id, valid_from, valid_to, valid_until, external_idents, name, birth_date, death_date, search,
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
                last_edit_comment, last_edit_by_user_id, last_edit_at, invalid_codes, has_legal_unit,
                related_establishment_ids, excluded_establishment_ids, included_establishment_ids,
                related_legal_unit_ids, excluded_legal_unit_ids, included_legal_unit_ids,
                related_enterprise_ids, excluded_enterprise_ids, included_enterprise_ids,
                stats, stats_summary, included_establishment_count, included_legal_unit_count, included_enterprise_count, tag_paths
            FROM import.get_statistical_unit_data_partial('enterprise', p_enterprise_id_ranges);
        END IF;
    END IF;
END;
$statistical_unit_refresh$;

-- =============================================================================
-- 2. statistical_unit_flush_staging: Add DELETE-from-main before INSERT
--    Targeted DELETE+INSERT with indices is fast for typical staging volumes
--    (1-10k rows per derive cycle). No need to drop/recreate indices.
-- =============================================================================
CREATE OR REPLACE PROCEDURE public.statistical_unit_flush_staging()
 LANGUAGE plpgsql
AS $statistical_unit_flush_staging$
DECLARE
    v_staging_count BIGINT;
    v_start_time timestamptz;
    v_delete_duration_ms numeric;
    v_insert_duration_ms numeric;
BEGIN
    -- Check if there's anything to flush
    SELECT count(*) INTO v_staging_count FROM public.statistical_unit_staging;

    IF v_staging_count = 0 THEN
        RAISE DEBUG 'statistical_unit_flush_staging: Nothing to flush (staging empty)';
        RETURN;
    END IF;

    RAISE DEBUG 'statistical_unit_flush_staging: Flushing % rows from staging', v_staging_count;

    -- Step 1: Delete from main the rows being replaced (targeted by staging IDs)
    -- This is the atomic swap: old rows out, new rows in, within same transaction.
    v_start_time := clock_timestamp();
    DELETE FROM public.statistical_unit AS su
    USING (SELECT DISTINCT unit_type, unit_id FROM public.statistical_unit_staging) AS s
    WHERE su.unit_type = s.unit_type AND su.unit_id = s.unit_id;
    v_delete_duration_ms := EXTRACT(EPOCH FROM (clock_timestamp() - v_start_time)) * 1000;
    RAISE DEBUG 'statistical_unit_flush_staging: Deleted old rows in % ms', round(v_delete_duration_ms);

    -- Step 2: Insert new data from staging (sorted for B-tree locality)
    v_start_time := clock_timestamp();
    INSERT INTO public.statistical_unit (
        unit_type, unit_id, valid_from, valid_to, valid_until, external_idents, name, birth_date, death_date, search,
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
        last_edit_comment, last_edit_by_user_id, last_edit_at, invalid_codes, has_legal_unit,
        related_establishment_ids, excluded_establishment_ids, included_establishment_ids,
        related_legal_unit_ids, excluded_legal_unit_ids, included_legal_unit_ids,
        related_enterprise_ids, excluded_enterprise_ids, included_enterprise_ids,
        stats, stats_summary, included_establishment_count, included_legal_unit_count, included_enterprise_count, tag_paths
    )
    SELECT
        unit_type, unit_id, valid_from, valid_to, valid_until, external_idents, name, birth_date, death_date, search,
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
        last_edit_comment, last_edit_by_user_id, last_edit_at, invalid_codes, has_legal_unit,
        related_establishment_ids, excluded_establishment_ids, included_establishment_ids,
        related_legal_unit_ids, excluded_legal_unit_ids, included_legal_unit_ids,
        related_enterprise_ids, excluded_enterprise_ids, included_enterprise_ids,
        stats, stats_summary, included_establishment_count, included_legal_unit_count, included_enterprise_count, tag_paths
    FROM public.statistical_unit_staging
    ORDER BY unit_type, unit_id, valid_from;
    v_insert_duration_ms := EXTRACT(EPOCH FROM (clock_timestamp() - v_start_time)) * 1000;
    RAISE DEBUG 'statistical_unit_flush_staging: Inserted % rows in % ms', v_staging_count, round(v_insert_duration_ms);

    -- Step 3: Clear staging table
    TRUNCATE public.statistical_unit_staging;

    -- Step 4: Update statistics
    ANALYZE public.statistical_unit;

    RAISE DEBUG 'statistical_unit_flush_staging: Complete (delete: % ms, insert: % ms)',
        round(v_delete_duration_ms), round(v_insert_duration_ms);
END;
$statistical_unit_flush_staging$;

-- =============================================================================
-- 3. derive_statistical_unit: Clean staging at start of pipeline run
--    Ensures no stale data from interrupted previous runs contaminates new run.
-- =============================================================================
CREATE OR REPLACE FUNCTION worker.derive_statistical_unit(p_establishment_id_ranges int4multirange DEFAULT NULL::int4multirange, p_legal_unit_id_ranges int4multirange DEFAULT NULL::int4multirange, p_enterprise_id_ranges int4multirange DEFAULT NULL::int4multirange, p_valid_from date DEFAULT NULL::date, p_valid_until date DEFAULT NULL::date, p_task_id bigint DEFAULT NULL::bigint)
 RETURNS void
 LANGUAGE plpgsql
AS $derive_statistical_unit$
DECLARE
    v_batch RECORD;
    v_establishment_ids INT[];
    v_legal_unit_ids INT[];
    v_enterprise_ids INT[];
    v_batch_count INT := 0;
    v_is_full_refresh BOOLEAN;
    v_child_priority BIGINT;
    v_uncle_priority BIGINT;
    -- Orphan IDs: requested but no longer exist in base tables
    v_orphan_enterprise_ids INT[];
    v_orphan_legal_unit_ids INT[];
    v_orphan_establishment_ids INT[];
BEGIN
    v_is_full_refresh := (p_establishment_id_ranges IS NULL
                         AND p_legal_unit_id_ranges IS NULL
                         AND p_enterprise_id_ranges IS NULL);

    -- Clean staging from any interrupted previous run
    TRUNCATE public.statistical_unit_staging;

    -- Priority for children: same as current task (will run next due to structured concurrency)
    v_child_priority := nextval('public.worker_task_priority_seq');
    -- Priority for uncle (derive_reports): lower priority (higher number), runs after parent completes
    v_uncle_priority := nextval('public.worker_task_priority_seq');

    IF v_is_full_refresh THEN
        -- Full refresh: spawn batch children (no orphan cleanup needed - covers everything)
        FOR v_batch IN
            SELECT * FROM public.get_closed_group_batches(p_target_batch_size := 1000)
        LOOP
            PERFORM worker.spawn(
                p_command := 'statistical_unit_refresh_batch',
                p_payload := jsonb_build_object(
                    'command', 'statistical_unit_refresh_batch',
                    'batch_seq', v_batch.batch_seq,
                    'enterprise_ids', v_batch.enterprise_ids,
                    'legal_unit_ids', v_batch.legal_unit_ids,
                    'establishment_ids', v_batch.establishment_ids,
                    'valid_from', p_valid_from,
                    'valid_until', p_valid_until
                ),
                p_parent_id := p_task_id,
                p_priority := v_child_priority
            );
            v_batch_count := v_batch_count + 1;
        END LOOP;
    ELSE
        -- Partial refresh: convert multiranges to arrays
        v_establishment_ids := ARRAY(
            SELECT generate_series(lower(r), upper(r)-1)
            FROM unnest(COALESCE(p_establishment_id_ranges, '{}'::int4multirange)) AS t(r)
        );
        v_legal_unit_ids := ARRAY(
            SELECT generate_series(lower(r), upper(r)-1)
            FROM unnest(COALESCE(p_legal_unit_id_ranges, '{}'::int4multirange)) AS t(r)
        );
        v_enterprise_ids := ARRAY(
            SELECT generate_series(lower(r), upper(r)-1)
            FROM unnest(COALESCE(p_enterprise_id_ranges, '{}'::int4multirange)) AS t(r)
        );

        -- =====================================================================
        -- ORPHAN CLEANUP: Handle deleted entities BEFORE batching
        -- Find IDs that were requested but no longer exist in base tables.
        -- Delete their stale rows from derived tables directly.
        -- This keeps batches clean - only existing entities, no overlap.
        -- =====================================================================
        IF COALESCE(array_length(v_enterprise_ids, 1), 0) > 0 THEN
            v_orphan_enterprise_ids := ARRAY(
                SELECT id FROM unnest(v_enterprise_ids) AS id
                EXCEPT SELECT e.id FROM public.enterprise AS e WHERE e.id = ANY(v_enterprise_ids)
            );
            IF COALESCE(array_length(v_orphan_enterprise_ids, 1), 0) > 0 THEN
                RAISE DEBUG 'derive_statistical_unit: Cleaning up % orphan enterprise IDs',
                    array_length(v_orphan_enterprise_ids, 1);
                DELETE FROM public.timepoints WHERE unit_type = 'enterprise' AND unit_id = ANY(v_orphan_enterprise_ids);
                DELETE FROM public.timesegments WHERE unit_type = 'enterprise' AND unit_id = ANY(v_orphan_enterprise_ids);
                DELETE FROM public.timeline_enterprise WHERE enterprise_id = ANY(v_orphan_enterprise_ids);
                DELETE FROM public.statistical_unit WHERE unit_type = 'enterprise' AND unit_id = ANY(v_orphan_enterprise_ids);
            END IF;
        END IF;

        IF COALESCE(array_length(v_legal_unit_ids, 1), 0) > 0 THEN
            v_orphan_legal_unit_ids := ARRAY(
                SELECT id FROM unnest(v_legal_unit_ids) AS id
                EXCEPT SELECT lu.id FROM public.legal_unit AS lu WHERE lu.id = ANY(v_legal_unit_ids)
            );
            IF COALESCE(array_length(v_orphan_legal_unit_ids, 1), 0) > 0 THEN
                RAISE DEBUG 'derive_statistical_unit: Cleaning up % orphan legal_unit IDs',
                    array_length(v_orphan_legal_unit_ids, 1);
                DELETE FROM public.timepoints WHERE unit_type = 'legal_unit' AND unit_id = ANY(v_orphan_legal_unit_ids);
                DELETE FROM public.timesegments WHERE unit_type = 'legal_unit' AND unit_id = ANY(v_orphan_legal_unit_ids);
                DELETE FROM public.timeline_legal_unit WHERE legal_unit_id = ANY(v_orphan_legal_unit_ids);
                DELETE FROM public.statistical_unit WHERE unit_type = 'legal_unit' AND unit_id = ANY(v_orphan_legal_unit_ids);
            END IF;
        END IF;

        IF COALESCE(array_length(v_establishment_ids, 1), 0) > 0 THEN
            v_orphan_establishment_ids := ARRAY(
                SELECT id FROM unnest(v_establishment_ids) AS id
                EXCEPT SELECT es.id FROM public.establishment AS es WHERE es.id = ANY(v_establishment_ids)
            );
            IF COALESCE(array_length(v_orphan_establishment_ids, 1), 0) > 0 THEN
                RAISE DEBUG 'derive_statistical_unit: Cleaning up % orphan establishment IDs',
                    array_length(v_orphan_establishment_ids, 1);
                DELETE FROM public.timepoints WHERE unit_type = 'establishment' AND unit_id = ANY(v_orphan_establishment_ids);
                DELETE FROM public.timesegments WHERE unit_type = 'establishment' AND unit_id = ANY(v_orphan_establishment_ids);
                DELETE FROM public.timeline_establishment WHERE establishment_id = ANY(v_orphan_establishment_ids);
                DELETE FROM public.statistical_unit WHERE unit_type = 'establishment' AND unit_id = ANY(v_orphan_establishment_ids);
            END IF;
        END IF;

        -- =====================================================================
        -- BATCHING: Only existing entities, partitioned with no overlap
        -- =====================================================================
        FOR v_batch IN
            SELECT * FROM public.get_closed_group_batches(
                p_target_batch_size := 1000,
                p_establishment_ids := NULLIF(v_establishment_ids, '{}'),
                p_legal_unit_ids := NULLIF(v_legal_unit_ids, '{}'),
                p_enterprise_ids := NULLIF(v_enterprise_ids, '{}')
            )
        LOOP
            PERFORM worker.spawn(
                p_command := 'statistical_unit_refresh_batch',
                p_payload := jsonb_build_object(
                    'command', 'statistical_unit_refresh_batch',
                    'batch_seq', v_batch.batch_seq,
                    'enterprise_ids', v_batch.enterprise_ids,
                    'legal_unit_ids', v_batch.legal_unit_ids,
                    'establishment_ids', v_batch.establishment_ids,
                    'valid_from', p_valid_from,
                    'valid_until', p_valid_until
                ),
                p_parent_id := p_task_id,
                p_priority := v_child_priority
            );
            v_batch_count := v_batch_count + 1;
        END LOOP;
    END IF;

    RAISE DEBUG 'derive_statistical_unit: Spawned % batch children with parent_id %', v_batch_count, p_task_id;

    -- Refresh derived data (used flags) - always full refreshes, run synchronously
    PERFORM public.activity_category_used_derive();
    PERFORM public.region_used_derive();
    PERFORM public.sector_used_derive();
    PERFORM public.data_source_used_derive();
    PERFORM public.legal_form_used_derive();
    PERFORM public.country_used_derive();

    -- =========================================================================
    -- STAGING PATTERN: Enqueue flush task (runs after all batches complete)
    -- =========================================================================
    PERFORM worker.enqueue_statistical_unit_flush_staging();
    RAISE DEBUG 'derive_statistical_unit: Enqueued flush_staging task';

    -- Enqueue derive_reports as an "uncle" task (runs after flush completes)
    PERFORM worker.enqueue_derive_reports(
        p_valid_from := p_valid_from,
        p_valid_until := p_valid_until
    );

    RAISE DEBUG 'derive_statistical_unit: Enqueued derive_reports';
END;
$derive_statistical_unit$;

END;

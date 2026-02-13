```sql
CREATE OR REPLACE PROCEDURE public.statistical_unit_refresh(IN p_establishment_id_ranges int4multirange DEFAULT NULL::int4multirange, IN p_legal_unit_id_ranges int4multirange DEFAULT NULL::int4multirange, IN p_enterprise_id_ranges int4multirange DEFAULT NULL::int4multirange)
 LANGUAGE plpgsql
AS $procedure$
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
$procedure$
```

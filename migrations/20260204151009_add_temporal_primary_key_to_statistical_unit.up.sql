-- Migration 20260203233456: add_temporal_primary_key_to_statistical_unit
BEGIN;

-- PERFORMANCE OPTIMIZATION: Replace GIST exclusion with native temporal PRIMARY KEY
--
-- Problem: GIST exclusion constraint causes 1.24M checks for 35K rows
--   EXCLUDE USING gist (unit_type WITH =, unit_id WITH =, daterange(...) WITH &&)
--   - GIST index maintenance is slow
--   - Poor for INSERT-heavy workloads
--
-- Solution: Use PostgreSQL 17+ native temporal PRIMARY KEY
--   PRIMARY KEY (unit_type, unit_id, valid_range WITHOUT OVERLAPS)
--   - B-tree index (faster maintenance)
--   - Same semantic guarantees (no overlapping periods)
--   - 2.66x faster for small refresh batches in benchmarks
--
-- Note: We keep valid_from/valid_until as canonical columns (not using full sql_saga)
-- The valid_range column is GENERATED from valid_from/valid_until.

-- Step 1: Add valid_range column (GENERATED from existing valid_from/valid_until)
ALTER TABLE public.statistical_unit 
ADD COLUMN valid_range daterange 
GENERATED ALWAYS AS (daterange(valid_from, valid_until)) STORED;

-- Step 2: Drop old GIST exclusion constraint
ALTER TABLE public.statistical_unit 
DROP CONSTRAINT statistical_unit_type_id_daterange_excl;

-- Step 3: Add temporal PRIMARY KEY (PostgreSQL 17+ feature)
-- Creates a B-tree index with WITHOUT OVERLAPS semantics
ALTER TABLE public.statistical_unit 
ADD CONSTRAINT statistical_unit_temporal_pk 
PRIMARY KEY (unit_type, unit_id, valid_range WITHOUT OVERLAPS);

-- Step 4: Remove redundant unique indexes (now covered by temporal PK)
DROP INDEX IF EXISTS statistical_unit_upsert_pkey;
DROP INDEX IF EXISTS statistical_unit_from_key;

-- Step 5: Update statistical_unit_refresh to exclude valid_range from INSERTs
-- GENERATED columns cannot be inserted into - must use explicit column list
CREATE OR REPLACE PROCEDURE public.statistical_unit_refresh(
    IN p_establishment_id_ranges int4multirange DEFAULT NULL::int4multirange,
    IN p_legal_unit_id_ranges int4multirange DEFAULT NULL::int4multirange,
    IN p_enterprise_id_ranges int4multirange DEFAULT NULL::int4multirange
)
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
    -- PERF: Arrays for efficient = ANY() filtering
    v_es_ids INT[];
    v_lu_ids INT[];
    v_en_ids INT[];
BEGIN
    v_is_partial_refresh := (p_establishment_id_ranges IS NOT NULL 
                            OR p_legal_unit_id_ranges IS NOT NULL 
                            OR p_enterprise_id_ranges IS NOT NULL);

    IF NOT v_is_partial_refresh THEN
        -- Full refresh with ANALYZE
        ANALYZE public.timeline_establishment, public.timeline_legal_unit, public.timeline_enterprise;

        -- Create temp table WITHOUT the valid_range column (it's GENERATED)
        CREATE TEMP TABLE statistical_unit_new (LIKE public.statistical_unit) ON COMMIT DROP;
        -- Drop the inherited valid_range column - we'll let it regenerate on INSERT
        ALTER TABLE statistical_unit_new DROP COLUMN valid_range;

        -- Establishments
        v_batch_num := 0;
        SELECT MIN(unit_id), MAX(unit_id), COUNT(unit_id) INTO v_min_id, v_max_id, v_total_units FROM public.timesegments WHERE unit_type = 'establishment';
        RAISE DEBUG 'Refreshing statistical units for % establishments in batches of %...', v_total_units, v_batch_size;
        IF v_min_id IS NOT NULL THEN FOR i IN v_min_id..v_max_id BY v_batch_size LOOP
            v_batch_start_time := clock_timestamp();
            v_batch_num := v_batch_num + 1;
            v_start_id := i; v_end_id := i + v_batch_size - 1;
            -- Exclude valid_range - it's GENERATED
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
            -- Exclude valid_range - it's GENERATED
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
            -- Exclude valid_range - it's GENERATED
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
        -- Final insert also needs explicit columns
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
        SELECT * FROM statistical_unit_new;

        ANALYZE public.statistical_unit;
    ELSE
        -- Partial refresh with SORTED INSERTS to prevent B-tree page lock deadlocks
        -- ORDER BY ensures all concurrent batches acquire page locks in the same direction
        
        -- PERF: Convert multiranges to arrays once for efficient = ANY() filtering
        v_es_ids := public.int4multirange_to_array(p_establishment_id_ranges);
        v_lu_ids := public.int4multirange_to_array(p_legal_unit_id_ranges);
        v_en_ids := public.int4multirange_to_array(p_enterprise_id_ranges);
        
        IF v_es_ids IS NOT NULL THEN
            DELETE FROM public.statistical_unit WHERE unit_type = 'establishment' AND unit_id = ANY(v_es_ids);
            -- Exclude valid_range - it's GENERATED
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
            FROM import.get_statistical_unit_data_partial('establishment', p_establishment_id_ranges)
            ORDER BY unit_type, unit_id, valid_from;  -- CRITICAL: Deterministic order prevents deadlocks
        END IF;
        IF v_lu_ids IS NOT NULL THEN
            DELETE FROM public.statistical_unit WHERE unit_type = 'legal_unit' AND unit_id = ANY(v_lu_ids);
            -- Exclude valid_range - it's GENERATED
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
            FROM import.get_statistical_unit_data_partial('legal_unit', p_legal_unit_id_ranges)
            ORDER BY unit_type, unit_id, valid_from;  -- CRITICAL: Deterministic order prevents deadlocks
        END IF;
        IF v_en_ids IS NOT NULL THEN
            DELETE FROM public.statistical_unit WHERE unit_type = 'enterprise' AND unit_id = ANY(v_en_ids);
            -- Exclude valid_range - it's GENERATED
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
            FROM import.get_statistical_unit_data_partial('enterprise', p_enterprise_id_ranges)
            ORDER BY unit_type, unit_id, valid_from;  -- CRITICAL: Deterministic order prevents deadlocks
        END IF;
    END IF;
END;
$statistical_unit_refresh$;

-- Step 6: Update get_statistical_unit_data_partial to include valid_range in output
-- The function returns SETOF statistical_unit, which now includes valid_range column.
-- We compute it from valid_from/valid_until to match the table's GENERATED column.
CREATE OR REPLACE FUNCTION import.get_statistical_unit_data_partial(p_unit_type statistical_unit_type, p_id_ranges int4multirange)
 RETURNS SETOF statistical_unit
 LANGUAGE plpgsql
 STABLE
AS $get_statistical_unit_data_partial$
DECLARE
    -- PERF: Convert multirange to array once for efficient = ANY() filtering
    v_ids INT[] := public.int4multirange_to_array(p_id_ranges);
BEGIN
    IF p_unit_type = 'establishment' THEN
        RETURN QUERY
        SELECT
            t.unit_type,
            t.unit_id,
            t.valid_from,
            t.valid_to,
            t.valid_until,
            COALESCE(eia1.external_idents, '{}'::jsonb) AS external_idents,
            t.name,
            t.birth_date,
            t.death_date,
            t.search,
            t.primary_activity_category_id,
            t.primary_activity_category_path,
            t.primary_activity_category_code,
            t.secondary_activity_category_id,
            t.secondary_activity_category_path,
            t.secondary_activity_category_code,
            t.activity_category_paths,
            t.sector_id,
            t.sector_path,
            t.sector_code,
            t.sector_name,
            t.data_source_ids,
            t.data_source_codes,
            t.legal_form_id,
            t.legal_form_code,
            t.legal_form_name,
            t.physical_address_part1,
            t.physical_address_part2,
            t.physical_address_part3,
            t.physical_postcode,
            t.physical_postplace,
            t.physical_region_id,
            t.physical_region_path,
            t.physical_region_code,
            t.physical_country_id,
            t.physical_country_iso_2,
            t.physical_latitude,
            t.physical_longitude,
            t.physical_altitude,
            t.domestic,
            t.postal_address_part1,
            t.postal_address_part2,
            t.postal_address_part3,
            t.postal_postcode,
            t.postal_postplace,
            t.postal_region_id,
            t.postal_region_path,
            t.postal_region_code,
            t.postal_country_id,
            t.postal_country_iso_2,
            t.postal_latitude,
            t.postal_longitude,
            t.postal_altitude,
            t.web_address,
            t.email_address,
            t.phone_number,
            t.landline,
            t.mobile_number,
            t.fax_number,
            t.unit_size_id,
            t.unit_size_code,
            t.status_id,
            t.status_code,
            t.used_for_counting,
            t.last_edit_comment,
            t.last_edit_by_user_id,
            t.last_edit_at,
            t.invalid_codes,
            t.has_legal_unit,
            t.related_establishment_ids,
            t.excluded_establishment_ids,
            t.included_establishment_ids,
            t.related_legal_unit_ids,
            t.excluded_legal_unit_ids,
            t.included_legal_unit_ids,
            t.related_enterprise_ids,
            t.excluded_enterprise_ids,
            t.included_enterprise_ids,
            t.stats,
            t.stats_summary,
            array_length(t.included_establishment_ids, 1) AS included_establishment_count,
            array_length(t.included_legal_unit_ids, 1) AS included_legal_unit_count,
            array_length(t.included_enterprise_ids, 1) AS included_enterprise_count,
            COALESCE(tpa.tag_paths, ARRAY[]::public.ltree[]) AS tag_paths,
            daterange(t.valid_from, t.valid_until) AS valid_range
        FROM public.timeline_establishment t
        LEFT JOIN LATERAL (
            SELECT jsonb_object_agg(eit.code, COALESCE(ei.ident, ei.idents::text)) AS external_idents
            FROM public.external_ident ei
            JOIN public.external_ident_type eit ON ei.type_id = eit.id
            WHERE ei.establishment_id = t.unit_id
        ) eia1 ON true
        LEFT JOIN LATERAL (
            SELECT array_agg(tag.path ORDER BY tag.path) AS tag_paths
            FROM public.tag_for_unit tfu
            JOIN public.tag ON tfu.tag_id = tag.id
            WHERE tfu.establishment_id = t.unit_id
        ) tpa ON true
        WHERE t.unit_id = ANY(v_ids);

    ELSIF p_unit_type = 'legal_unit' THEN
        RETURN QUERY
        SELECT
            t.unit_type,
            t.unit_id,
            t.valid_from,
            t.valid_to,
            t.valid_until,
            COALESCE(eia1.external_idents, '{}'::jsonb) AS external_idents,
            t.name,
            t.birth_date,
            t.death_date,
            t.search,
            t.primary_activity_category_id,
            t.primary_activity_category_path,
            t.primary_activity_category_code,
            t.secondary_activity_category_id,
            t.secondary_activity_category_path,
            t.secondary_activity_category_code,
            t.activity_category_paths,
            t.sector_id,
            t.sector_path,
            t.sector_code,
            t.sector_name,
            t.data_source_ids,
            t.data_source_codes,
            t.legal_form_id,
            t.legal_form_code,
            t.legal_form_name,
            t.physical_address_part1,
            t.physical_address_part2,
            t.physical_address_part3,
            t.physical_postcode,
            t.physical_postplace,
            t.physical_region_id,
            t.physical_region_path,
            t.physical_region_code,
            t.physical_country_id,
            t.physical_country_iso_2,
            t.physical_latitude,
            t.physical_longitude,
            t.physical_altitude,
            t.domestic,
            t.postal_address_part1,
            t.postal_address_part2,
            t.postal_address_part3,
            t.postal_postcode,
            t.postal_postplace,
            t.postal_region_id,
            t.postal_region_path,
            t.postal_region_code,
            t.postal_country_id,
            t.postal_country_iso_2,
            t.postal_latitude,
            t.postal_longitude,
            t.postal_altitude,
            t.web_address,
            t.email_address,
            t.phone_number,
            t.landline,
            t.mobile_number,
            t.fax_number,
            t.unit_size_id,
            t.unit_size_code,
            t.status_id,
            t.status_code,
            t.used_for_counting,
            t.last_edit_comment,
            t.last_edit_by_user_id,
            t.last_edit_at,
            t.invalid_codes,
            t.has_legal_unit,
            t.related_establishment_ids,
            t.excluded_establishment_ids,
            t.included_establishment_ids,
            t.related_legal_unit_ids,
            t.excluded_legal_unit_ids,
            t.included_legal_unit_ids,
            t.related_enterprise_ids,
            t.excluded_enterprise_ids,
            t.included_enterprise_ids,
            t.stats,
            t.stats_summary,
            array_length(t.included_establishment_ids, 1) AS included_establishment_count,
            array_length(t.included_legal_unit_ids, 1) AS included_legal_unit_count,
            array_length(t.included_enterprise_ids, 1) AS included_enterprise_count,
            COALESCE(tpa.tag_paths, ARRAY[]::public.ltree[]) AS tag_paths,
            daterange(t.valid_from, t.valid_until) AS valid_range
        FROM public.timeline_legal_unit t
        LEFT JOIN LATERAL (
            SELECT jsonb_object_agg(eit.code, COALESCE(ei.ident, ei.idents::text)) AS external_idents
            FROM public.external_ident ei
            JOIN public.external_ident_type eit ON ei.type_id = eit.id
            WHERE ei.legal_unit_id = t.unit_id
        ) eia1 ON true
        LEFT JOIN LATERAL (
            SELECT array_agg(tag.path ORDER BY tag.path) AS tag_paths
            FROM public.tag_for_unit tfu
            JOIN public.tag ON tfu.tag_id = tag.id
            WHERE tfu.legal_unit_id = t.unit_id
        ) tpa ON true
        WHERE t.unit_id = ANY(v_ids);

    ELSIF p_unit_type = 'enterprise' THEN
        RETURN QUERY
        SELECT
            t.unit_type,
            t.unit_id,
            t.valid_from,
            t.valid_to,
            t.valid_until,
            COALESCE(
                eia1.external_idents,
                eia2.external_idents,
                eia3.external_idents,
                '{}'::jsonb
            ) AS external_idents,
            t.name::varchar,
            t.birth_date,
            t.death_date,
            t.search,
            t.primary_activity_category_id,
            t.primary_activity_category_path,
            t.primary_activity_category_code,
            t.secondary_activity_category_id,
            t.secondary_activity_category_path,
            t.secondary_activity_category_code,
            t.activity_category_paths,
            t.sector_id,
            t.sector_path,
            t.sector_code,
            t.sector_name,
            t.data_source_ids,
            t.data_source_codes,
            t.legal_form_id,
            t.legal_form_code,
            t.legal_form_name,
            t.physical_address_part1,
            t.physical_address_part2,
            t.physical_address_part3,
            t.physical_postcode,
            t.physical_postplace,
            t.physical_region_id,
            t.physical_region_path,
            t.physical_region_code,
            t.physical_country_id,
            t.physical_country_iso_2,
            t.physical_latitude,
            t.physical_longitude,
            t.physical_altitude,
            t.domestic,
            t.postal_address_part1,
            t.postal_address_part2,
            t.postal_address_part3,
            t.postal_postcode,
            t.postal_postplace,
            t.postal_region_id,
            t.postal_region_path,
            t.postal_region_code,
            t.postal_country_id,
            t.postal_country_iso_2,
            t.postal_latitude,
            t.postal_longitude,
            t.postal_altitude,
            t.web_address,
            t.email_address,
            t.phone_number,
            t.landline,
            t.mobile_number,
            t.fax_number,
            t.unit_size_id,
            t.unit_size_code,
            t.status_id,
            t.status_code,
            t.used_for_counting,
            t.last_edit_comment,
            t.last_edit_by_user_id,
            t.last_edit_at,
            t.invalid_codes,
            t.has_legal_unit,
            t.related_establishment_ids,
            t.excluded_establishment_ids,
            t.included_establishment_ids,
            t.related_legal_unit_ids,
            t.excluded_legal_unit_ids,
            t.included_legal_unit_ids,
            t.related_enterprise_ids,
            t.excluded_enterprise_ids,
            t.included_enterprise_ids,
            NULL::JSONB AS stats,
            t.stats_summary,
            array_length(t.included_establishment_ids, 1) AS included_establishment_count,
            array_length(t.included_legal_unit_ids, 1) AS included_legal_unit_count,
            array_length(t.included_enterprise_ids, 1) AS included_enterprise_count,
            COALESCE(tpa.tag_paths, ARRAY[]::public.ltree[]) AS tag_paths,
            daterange(t.valid_from, t.valid_until) AS valid_range
        FROM public.timeline_enterprise t
        LEFT JOIN LATERAL (
            SELECT jsonb_object_agg(eit.code, COALESCE(ei.ident, ei.idents::text)) AS external_idents
            FROM public.external_ident ei
            JOIN public.external_ident_type eit ON ei.type_id = eit.id
            WHERE ei.enterprise_id = t.unit_id
        ) eia1 ON true
        LEFT JOIN LATERAL (
            SELECT jsonb_object_agg(eit.code, COALESCE(ei.ident, ei.idents::text)) AS external_idents
            FROM public.external_ident ei
            JOIN public.external_ident_type eit ON ei.type_id = eit.id
            WHERE ei.establishment_id = t.primary_establishment_id
        ) eia2 ON true
        LEFT JOIN LATERAL (
            SELECT jsonb_object_agg(eit.code, COALESCE(ei.ident, ei.idents::text)) AS external_idents
            FROM public.external_ident ei
            JOIN public.external_ident_type eit ON ei.type_id = eit.id
            WHERE ei.legal_unit_id = t.primary_legal_unit_id
        ) eia3 ON true
        LEFT JOIN LATERAL (
            SELECT array_agg(tag.path ORDER BY tag.path) AS tag_paths
            FROM public.tag_for_unit tfu
            JOIN public.tag ON tfu.tag_id = tag.id
            WHERE tfu.enterprise_id = t.unit_id
        ) tpa ON true
        WHERE t.unit_id = ANY(v_ids);
    END IF;
END;
$get_statistical_unit_data_partial$;

-- Step 7: Update relevant_statistical_units to include valid_range column
CREATE OR REPLACE FUNCTION public.relevant_statistical_units(
    unit_type public.statistical_unit_type, -- $1
    unit_id INTEGER,                        -- $2
    valid_on DATE DEFAULT current_date      -- $3
) RETURNS SETOF public.statistical_unit LANGUAGE sql STABLE AS $$
    WITH valid_units AS (
        SELECT * FROM public.statistical_unit
        WHERE valid_from <= $3 AND $3 < valid_until
    ), root_unit AS (
        SELECT * FROM valid_units
        WHERE unit_type = 'enterprise'
          AND unit_id = public.statistical_unit_enterprise_id($1, $2, $3)
    ), related_units AS (
        SELECT * FROM valid_units
        WHERE unit_type = 'legal_unit'
          AND unit_id IN (SELECT unnest(related_legal_unit_ids) FROM root_unit)
            UNION ALL
        SELECT * FROM valid_units
        WHERE unit_type = 'establishment'
          AND unit_id IN (SELECT unnest(related_establishment_ids) FROM root_unit)
    ), relevant_units AS (
        SELECT * FROM root_unit
            UNION ALL
        SELECT * FROM related_units
    ), ordered_units AS (
      SELECT ru.*
          , first_external.ident AS first_external_ident
        FROM relevant_units ru
      LEFT JOIN LATERAL (
          SELECT eit.code, (ru.external_idents->>eit.code)::text AS ident
          FROM public.external_ident_type eit
          ORDER BY eit.priority
          LIMIT 1
      ) first_external ON true
      ORDER BY unit_type, first_external_ident NULLS LAST, unit_id
    )
    SELECT unit_type
         , unit_id
         , valid_from
         , valid_to
         , valid_until
         , external_idents
         , name
         , birth_date
         , death_date
         , search
         , primary_activity_category_id
         , primary_activity_category_path
         , primary_activity_category_code
         , secondary_activity_category_id
         , secondary_activity_category_path
         , secondary_activity_category_code
         , activity_category_paths
         , sector_id
         , sector_path
         , sector_code
         , sector_name
         , data_source_ids
         , data_source_codes
         , legal_form_id
         , legal_form_code
         , legal_form_name
         --
         , physical_address_part1
         , physical_address_part2
         , physical_address_part3
         , physical_postcode
         , physical_postplace
         , physical_region_id
         , physical_region_path
         , physical_region_code
         , physical_country_id
         , physical_country_iso_2
         , physical_latitude
         , physical_longitude
         , physical_altitude
         --
         , domestic
         --
         , postal_address_part1
         , postal_address_part2
         , postal_address_part3
         , postal_postcode
         , postal_postplace
         , postal_region_id
         , postal_region_path
         , postal_region_code
         , postal_country_id
         , postal_country_iso_2
         , postal_latitude
         , postal_longitude
         , postal_altitude
         --
         , web_address
         , email_address
         , phone_number
         , landline
         , mobile_number
         , fax_number
         --
         , unit_size_id
         , unit_size_code
         --
         , status_id
         , status_code
         , used_for_counting
         --
         , last_edit_comment
         , last_edit_by_user_id
         , last_edit_at
         --
         , invalid_codes
         , has_legal_unit
         , related_establishment_ids
         , excluded_establishment_ids
         , included_establishment_ids
         , related_legal_unit_ids
         , excluded_legal_unit_ids
         , included_legal_unit_ids
         , related_enterprise_ids
         , excluded_enterprise_ids
         , included_enterprise_ids
         , stats
         , stats_summary
         , included_establishment_count
         , included_legal_unit_count
         , included_enterprise_count
         , tag_paths
         , daterange(valid_from, valid_until) AS valid_range
    FROM ordered_units;
$$;

END;

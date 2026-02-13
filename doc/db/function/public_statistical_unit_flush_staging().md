```sql
CREATE OR REPLACE PROCEDURE public.statistical_unit_flush_staging()
 LANGUAGE plpgsql
AS $procedure$
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
$procedure$
```

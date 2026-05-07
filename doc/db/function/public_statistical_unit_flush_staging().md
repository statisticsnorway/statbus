```sql
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
```

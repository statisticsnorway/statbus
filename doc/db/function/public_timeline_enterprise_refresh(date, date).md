```sql
CREATE OR REPLACE FUNCTION public.timeline_enterprise_refresh(p_valid_after date DEFAULT NULL::date, p_valid_to date DEFAULT NULL::date)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_valid_after date;
    v_valid_to date;
BEGIN
    -- Set the time range for filtering
    v_valid_after := COALESCE(p_valid_after, '-infinity'::date);
    v_valid_to := COALESCE(p_valid_to, 'infinity'::date);

    -- Create a temporary table with the new data
    CREATE TEMPORARY TABLE temp_timeline_enterprise ON COMMIT DROP AS
    SELECT * FROM public.timeline_enterprise_def
    WHERE after_to_overlaps(valid_after, valid_to, v_valid_after, v_valid_to);

    -- Delete records that exist in the main table but not in the temp table
    DELETE FROM public.timeline_enterprise te
    WHERE after_to_overlaps(te.valid_after, te.valid_to, v_valid_after, v_valid_to)
    AND NOT EXISTS (
        SELECT 1 FROM temp_timeline_enterprise tte
        WHERE tte.unit_type = te.unit_type
        AND tte.unit_id = te.unit_id
        AND tte.valid_after = te.valid_after
        AND tte.valid_to = te.valid_to
    );

    -- Insert or update records from the temp table into the main table
    INSERT INTO public.timeline_enterprise
    SELECT tte.* FROM temp_timeline_enterprise tte
    ON CONFLICT (unit_type, unit_id, valid_after) DO UPDATE SET
        valid_to = EXCLUDED.valid_to,
        valid_from = EXCLUDED.valid_from,
        name = EXCLUDED.name,
        birth_date = EXCLUDED.birth_date,
        death_date = EXCLUDED.death_date,
        search = EXCLUDED.search,
        primary_activity_category_id = EXCLUDED.primary_activity_category_id,
        primary_activity_category_path = EXCLUDED.primary_activity_category_path,
        primary_activity_category_code = EXCLUDED.primary_activity_category_code,
        secondary_activity_category_id = EXCLUDED.secondary_activity_category_id,
        secondary_activity_category_path = EXCLUDED.secondary_activity_category_path,
        secondary_activity_category_code = EXCLUDED.secondary_activity_category_code,
        activity_category_paths = EXCLUDED.activity_category_paths,
        sector_id = EXCLUDED.sector_id,
        sector_path = EXCLUDED.sector_path,
        sector_code = EXCLUDED.sector_code,
        sector_name = EXCLUDED.sector_name,
        data_source_ids = EXCLUDED.data_source_ids,
        data_source_codes = EXCLUDED.data_source_codes,
        legal_form_id = EXCLUDED.legal_form_id,
        legal_form_code = EXCLUDED.legal_form_code,
        legal_form_name = EXCLUDED.legal_form_name,
        physical_address_part1 = EXCLUDED.physical_address_part1,
        physical_address_part2 = EXCLUDED.physical_address_part2,
        physical_address_part3 = EXCLUDED.physical_address_part3,
        physical_postcode = EXCLUDED.physical_postcode,
        physical_postplace = EXCLUDED.physical_postplace,
        physical_region_id = EXCLUDED.physical_region_id,
        physical_region_path = EXCLUDED.physical_region_path,
        physical_region_code = EXCLUDED.physical_region_code,
        physical_country_id = EXCLUDED.physical_country_id,
        physical_country_iso_2 = EXCLUDED.physical_country_iso_2,
        physical_latitude = EXCLUDED.physical_latitude,
        physical_longitude = EXCLUDED.physical_longitude,
        physical_altitude = EXCLUDED.physical_altitude,
        postal_address_part1 = EXCLUDED.postal_address_part1,
        postal_address_part2 = EXCLUDED.postal_address_part2,
        postal_address_part3 = EXCLUDED.postal_address_part3,
        postal_postcode = EXCLUDED.postal_postcode,
        postal_postplace = EXCLUDED.postal_postplace,
        postal_region_id = EXCLUDED.postal_region_id,
        postal_region_path = EXCLUDED.postal_region_path,
        postal_region_code = EXCLUDED.postal_region_code,
        postal_country_id = EXCLUDED.postal_country_id,
        postal_country_iso_2 = EXCLUDED.postal_country_iso_2,
        postal_latitude = EXCLUDED.postal_latitude,
        postal_longitude = EXCLUDED.postal_longitude,
        postal_altitude = EXCLUDED.postal_altitude,
        web_address = EXCLUDED.web_address,
        email_address = EXCLUDED.email_address,
        phone_number = EXCLUDED.phone_number,
        landline = EXCLUDED.landline,
        mobile_number = EXCLUDED.mobile_number,
        fax_number = EXCLUDED.fax_number,
        unit_size_id = EXCLUDED.unit_size_id,
        unit_size_code = EXCLUDED.unit_size_code,
        status_id = EXCLUDED.status_id,
        status_code = EXCLUDED.status_code,
        include_unit_in_reports = EXCLUDED.include_unit_in_reports,
        last_edit_comment = EXCLUDED.last_edit_comment,
        last_edit_by_user_id = EXCLUDED.last_edit_by_user_id,
        last_edit_at = EXCLUDED.last_edit_at,
        invalid_codes = EXCLUDED.invalid_codes,
        has_legal_unit = EXCLUDED.has_legal_unit,
        related_establishment_ids = EXCLUDED.related_establishment_ids,
        excluded_establishment_ids = EXCLUDED.excluded_establishment_ids,
        included_establishment_ids = EXCLUDED.included_establishment_ids,
        related_legal_unit_ids = EXCLUDED.related_legal_unit_ids,
        excluded_legal_unit_ids = EXCLUDED.excluded_legal_unit_ids,
        included_legal_unit_ids = EXCLUDED.included_legal_unit_ids,
        enterprise_id = EXCLUDED.enterprise_id,
        primary_establishment_id = EXCLUDED.primary_establishment_id,
        primary_legal_unit_id = EXCLUDED.primary_legal_unit_id,
        stats_summary = EXCLUDED.stats_summary;

    -- Drop the temporary table
    DROP TABLE temp_timeline_enterprise;

    -- Ensure sql execution planning takes in to account table changes.
    ANALYZE public.timeline_enterprise;
END;
$function$
```

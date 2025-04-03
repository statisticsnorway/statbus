BEGIN;

CREATE VIEW public.statistical_unit_def
    ( unit_type
    , unit_id
    , valid_after
    , valid_from
    , valid_to
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
    , include_unit_in_reports
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
    )
    AS
    WITH data AS (
      SELECT unit_type
           , unit_id
           , valid_after
           , valid_from
           , valid_to
           , public.get_external_idents(unit_type, unit_id) AS external_idents
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
           , include_unit_in_reports
           --
           , last_edit_comment
           , last_edit_by_user_id
           , last_edit_at
           --
           , invalid_codes
           , has_legal_unit
           , CASE WHEN establishment_id IS NOT NULL THEN ARRAY[establishment_id] ELSE ARRAY[]::INT[] END AS related_establishment_ids
           , NULL::INT[] AS excluded_establishment_ids
           , NULL::INT[] AS included_establishment_ids
           , CASE WHEN legal_unit_id IS NOT NULL THEN ARRAY[legal_unit_id] ELSE ARRAY[]::INT[] END AS related_legal_unit_ids
           , NULL::INT[] AS excluded_legal_unit_ids
           , NULL::INT[] AS included_legal_unit_ids
           , CASE WHEN enterprise_id IS NOT NULL THEN ARRAY[enterprise_id] ELSE ARRAY[]::INT[] END AS related_enterprise_ids
           , NULL::INT[] AS excluded_enterprise_ids
           , NULL::INT[] AS included_enterprise_ids
           , stats
           , COALESCE(public.jsonb_stats_to_summary('{}'::JSONB,stats), '{}'::JSONB) AS stats_summary
      FROM public.timeline_establishment
      UNION ALL
      SELECT unit_type
           , unit_id
           , valid_after
           , valid_from
           , valid_to
           , public.get_external_idents(unit_type, unit_id) AS external_idents
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
           , include_unit_in_reports
           --
           , last_edit_comment
           , last_edit_by_user_id
           , last_edit_at
           --
           , invalid_codes
           , has_legal_unit
           , COALESCE(related_establishment_ids,ARRAY[]::INT[]) AS related_establishment_ids
           , COALESCE(excluded_establishment_ids,ARRAY[]::INT[]) AS excluded_establishment_ids
           , COALESCE(included_establishment_ids,ARRAY[]::INT[]) AS included_establishment_ids
           , CASE WHEN legal_unit_id IS NOT NULL THEN ARRAY[legal_unit_id] ELSE ARRAY[]::INT[] END AS related_legal_unit_ids
           , NULL::INT[] AS excluded_legal_unit_ids
           , NULL::INT[] AS included_legal_unit_ids
           , CASE WHEN enterprise_id IS NOT NULL THEN ARRAY[enterprise_id] ELSE ARRAY[]::INT[] END AS related_enterprise_ids
           , NULL::INT[] AS excluded_enterprise_ids
           , NULL::INT[] AS included_enterprise_ids
           , stats
           , stats_summary
      FROM public.timeline_legal_unit
      UNION ALL
      SELECT unit_type
           , unit_id
           , valid_after
           , valid_from
           , valid_to
           , COALESCE(
             public.get_external_idents(unit_type, unit_id),
             public.get_external_idents('establishment'::public.statistical_unit_type, primary_establishment_id),
             public.get_external_idents('legal_unit'::public.statistical_unit_type, primary_legal_unit_id)
           ) AS external_idents
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
           , include_unit_in_reports
           --
           , last_edit_comment
           , last_edit_by_user_id
           , last_edit_at
           --
           , invalid_codes
           , has_legal_unit
           , COALESCE(related_establishment_ids,ARRAY[]::INT[]) AS related_establishment_ids
           , COALESCE(excluded_establishment_ids,ARRAY[]::INT[]) AS excluded_establishment_ids
           , COALESCE(included_establishment_ids,ARRAY[]::INT[]) AS included_establishment_ids
           , COALESCE(related_legal_unit_ids,ARRAY[]::INT[]) AS related_legal_unit_ids
           , COALESCE(excluded_legal_unit_ids,ARRAY[]::INT[]) AS excluded_legal_unit_ids
           , COALESCE(included_legal_unit_ids,ARRAY[]::INT[]) AS included_legal_unit_ids
           , CASE WHEN enterprise_id IS NOT NULL THEN ARRAY[enterprise_id] ELSE ARRAY[]::INT[] END AS related_enterprise_ids
           , NULL::INT[] AS excluded_enterprise_ids
           , NULL::INT[] AS included_enterprise_ids
           , NULL::JSONB AS stats
           , stats_summary
      FROM public.timeline_enterprise
      --UNION ALL
      --SELECT * FROM enterprise_group_timeline
    )
    SELECT data.unit_type
         , data.unit_id
         , data.valid_after
         , data.valid_from
         , data.valid_to
         , data.external_idents
         , data.name
         , data.birth_date
         , data.death_date
         , data.search
         , data.primary_activity_category_id
         , data.primary_activity_category_path
         , data.primary_activity_category_code
         , data.secondary_activity_category_id
         , data.secondary_activity_category_path
         , data.secondary_activity_category_code
         , data.activity_category_paths
         , data.sector_id
         , data.sector_path
         , data.sector_code
         , data.sector_name
         , data.data_source_ids
         , data.data_source_codes
         , data.legal_form_id
         , data.legal_form_code
         , data.legal_form_name
         --
         , data.physical_address_part1
         , data.physical_address_part2
         , data.physical_address_part3
         , data.physical_postcode
         , data.physical_postplace
         , data.physical_region_id
         , data.physical_region_path
         , data.physical_region_code
         , data.physical_country_id
         , data.physical_country_iso_2
         , data.physical_latitude
         , data.physical_longitude
         , data.physical_altitude
         --
         , data.postal_address_part1
         , data.postal_address_part2
         , data.postal_address_part3
         , data.postal_postcode
         , data.postal_postplace
         , data.postal_region_id
         , data.postal_region_path
         , data.postal_region_code
         , data.postal_country_id
         , data.postal_country_iso_2
         , data.postal_latitude
         , data.postal_longitude
         , data.postal_altitude
         --
         , data.web_address
         , data.email_address
         , data.phone_number
         , data.landline
         , data.mobile_number
         , data.fax_number
         --
         , data.unit_size_id
         , data.unit_size_code
         --
         , data.status_id
         , data.status_code
         , data.include_unit_in_reports
         --
         , data.last_edit_comment
         , data.last_edit_by_user_id
         , data.last_edit_at
         --
         , data.invalid_codes
         , data.has_legal_unit
         , data.related_establishment_ids
         , data.excluded_establishment_ids
         , data.included_establishment_ids
         , data.related_legal_unit_ids
         , data.excluded_legal_unit_ids
         , data.included_legal_unit_ids
         , data.related_enterprise_ids
         , data.excluded_enterprise_ids
         , data.included_enterprise_ids
         , data.stats
         , data.stats_summary
         , array_length(data.included_establishment_ids,1) AS included_establishment_count
         , array_length(data.included_legal_unit_ids,1) AS included_legal_unit_count
         , array_length(data.included_enterprise_ids,1) AS included_enterprise_count
         , COALESCE(
             (
               SELECT array_agg(t.path ORDER BY t.path)
               FROM public.tag_for_unit AS tfu
               JOIN public.tag AS t ON t.id = tfu.tag_id
               WHERE
                 CASE data.unit_type
                 WHEN 'enterprise' THEN tfu.enterprise_id = data.unit_id
                 WHEN 'legal_unit' THEN tfu.legal_unit_id = data.unit_id
                 WHEN 'establishment' THEN tfu.establishment_id = data.unit_id
                 WHEN 'enterprise_group' THEN tfu.enterprise_group_id = data.unit_id
                 END
             ),
             ARRAY[]::public.ltree[]
           ) AS tag_paths
    FROM data
;


CREATE OR REPLACE FUNCTION public.statistical_unit_refresh(
  p_establishment_ids int[] DEFAULT NULL,
  p_legal_unit_ids int[] DEFAULT NULL,
  p_enterprise_ids int[] DEFAULT NULL,
  p_valid_after date DEFAULT NULL,
  p_valid_to date DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
AS $statistical_unit_refresh$
DECLARE
  v_affected_count int;
  v_valid_after date;
  v_valid_to date;
BEGIN
  -- Set the time range for filtering
  v_valid_after := COALESCE(p_valid_after, '-infinity'::date);
  v_valid_to := COALESCE(p_valid_to, 'infinity'::date);

  -- Create a temporary table to store the new data to avoid running the expensive view calculation multiple times.
  CREATE TEMPORARY TABLE temp_statistical_unit AS
  SELECT * FROM public.statistical_unit_def AS sud
  WHERE (
    (p_establishment_ids IS NULL OR sud.related_establishment_ids && p_establishment_ids) OR
    (p_legal_unit_ids    IS NULL OR sud.related_legal_unit_ids && p_legal_unit_ids) OR
    (p_enterprise_ids    IS NULL OR sud.related_enterprise_ids && p_enterprise_ids)
  )
  AND after_to_overlaps(sud.valid_after, sud.valid_to, v_valid_after, v_valid_to);

  -- Delete records that exist in the main table but not in the temp table
  DELETE FROM public.statistical_unit su
  WHERE (
    (p_establishment_ids IS NULL OR su.related_establishment_ids && p_establishment_ids) OR
    (p_legal_unit_ids    IS NULL OR su.related_legal_unit_ids && p_legal_unit_ids) OR
    (p_enterprise_ids    IS NULL OR su.related_enterprise_ids && p_enterprise_ids)
  )
  AND after_to_overlaps(su.valid_after, su.valid_to, v_valid_after, v_valid_to)
  AND NOT EXISTS (
    SELECT 1 FROM temp_statistical_unit tsu
    WHERE tsu.unit_type = su.unit_type
    AND tsu.unit_id = su.unit_id
    AND tsu.valid_after = su.valid_after
    AND tsu.valid_to = su.valid_to
  );

  -- Insert or update records from the temp table into the main table
  INSERT INTO public.statistical_unit
  SELECT tsu.* FROM temp_statistical_unit tsu
  ON CONFLICT (unit_type, unit_id, valid_after) DO UPDATE SET
    valid_to = EXCLUDED.valid_to,
    valid_from = EXCLUDED.valid_from,
    external_idents = EXCLUDED.external_idents,
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
    related_enterprise_ids = EXCLUDED.related_enterprise_ids,
    excluded_enterprise_ids = EXCLUDED.excluded_enterprise_ids,
    included_enterprise_ids = EXCLUDED.included_enterprise_ids,
    stats = EXCLUDED.stats,
    stats_summary = EXCLUDED.stats_summary,
    included_establishment_count = EXCLUDED.included_establishment_count,
    included_legal_unit_count = EXCLUDED.included_legal_unit_count,
    included_enterprise_count = EXCLUDED.included_enterprise_count,
    tag_paths = EXCLUDED.tag_paths;

  -- Drop the temporary table
  DROP TABLE temp_statistical_unit;

  -- Ensure sql execution planning takes in to account table changes.
  ANALYZE public.statistical_unit;
END;
$statistical_unit_refresh$;

END;

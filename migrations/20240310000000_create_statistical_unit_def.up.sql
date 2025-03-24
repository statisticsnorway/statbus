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
    , child_establishment_ids
    , child_legal_unit_ids
    , child_enterprise_ids
    , related_establishment_ids
    , related_legal_unit_ids
    , related_enterprise_ids
    , stats
    , stats_summary
    , child_establishment_count
    , child_legal_unit_count
    , child_enterprise_count
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
           , NULL::INT[] AS child_establishment_ids
           , NULL::INT[] AS child_legal_unit_ids
           , NULL::INT[] AS child_enterprise_ids
           , CASE WHEN establishment_id IS NULL THEN ARRAY[]::INT[] ELSE ARRAY[establishment_id] END AS related_establishment_ids
           , CASE WHEN legal_unit_id IS NULL THEN ARRAY[]::INT[] ELSE ARRAY[legal_unit_id] END AS related_legal_unit_ids
           , CASE WHEN enterprise_id IS NULL THEN ARRAY[]::INT[] ELSE ARRAY[enterprise_id] END AS related_enterprise_ids
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
           , COALESCE(establishment_ids,ARRAY[]::INT[]) AS child_establishment_ids
           , NULL::INT[] AS child_legal_unit_ids
           , NULL::INT[] AS child_enterprise_ids
           , COALESCE(establishment_ids,ARRAY[]::INT[]) AS related_establishment_ids
           , CASE WHEN legal_unit_id IS NULL THEN ARRAY[]::INT[] ELSE ARRAY[legal_unit_id] END AS related_legal_unit_ids
           , CASE WHEN enterprise_id IS NULL THEN ARRAY[]::INT[] ELSE ARRAY[enterprise_id] END AS related_enterprise_ids
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
           , COALESCE(establishment_ids,ARRAY[]::INT[]) AS child_establishment_ids
           , COALESCE(legal_unit_ids,ARRAY[]::INT[]) AS child_legal_unit_ids
           , NULL::INT[] AS child_enterprise_ids
           , COALESCE(establishment_ids,ARRAY[]::INT[]) AS related_establishment_ids
           , COALESCE(legal_unit_ids,ARRAY[]::INT[]) AS related_legal_unit_ids
           , CASE WHEN enterprise_id IS NULL THEN ARRAY[]::INT[] ELSE ARRAY[enterprise_id] END AS related_enterprise_ids
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
         , data.child_establishment_ids
         , data.child_legal_unit_ids
         , data.child_enterprise_ids
         , data.related_establishment_ids
         , data.related_legal_unit_ids
         , data.related_enterprise_ids
         , data.stats
         , data.stats_summary
         , array_length(data.child_establishment_ids,1) AS child_establishment_count
         , array_length(data.child_legal_unit_ids,1) AS child_legal_unit_count
         , array_length(data.child_enterprise_ids,1) AS child_enterprise_count
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


CREATE FUNCTION public.statistical_unit_refresh(
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
BEGIN
  -- Create a temporary table to store the new data to avoid running the expensive view calculation multiple times.
  CREATE TEMPORARY TABLE temp_statistical_unit AS
  SELECT * FROM public.statistical_unit_def AS sud
  WHERE (
    (p_establishment_ids IS NULL OR sud.related_establishment_ids && p_establishment_ids) OR
    (p_legal_unit_ids    IS NULL OR sud.related_legal_unit_ids && p_legal_unit_ids) OR
    (p_enterprise_ids    IS NULL OR sud.related_enterprise_ids && p_enterprise_ids)
  )
  AND daterange(sud.valid_after, sud.valid_to, '(]') &&
      daterange(COALESCE(p_valid_after, '-infinity'::date),
              COALESCE(p_valid_to, 'infinity'::date), '(]');

  -- Delete records that exist in the main table but not in the temp table
  DELETE FROM public.statistical_unit su
  WHERE (
    (p_establishment_ids IS NULL OR su.related_establishment_ids && p_establishment_ids) OR
    (p_legal_unit_ids    IS NULL OR su.related_legal_unit_ids && p_legal_unit_ids) OR
    (p_enterprise_ids    IS NULL OR su.related_enterprise_ids && p_enterprise_ids)
  )
  AND daterange(su.valid_after, su.valid_to, '(]') &&
      daterange(COALESCE(p_valid_after, '-infinity'::date),
              COALESCE(p_valid_to, 'infinity'::date), '(]')
  AND NOT EXISTS (
    SELECT 1 FROM temp_statistical_unit tsu
    WHERE tsu.unit_type = su.unit_type
    AND tsu.unit_id = su.unit_id
    AND tsu.valid_after = su.valid_after
    AND tsu.valid_to = su.valid_to
  );

  -- Insert records that exist in the temp table but not in the main table
  INSERT INTO public.statistical_unit
  SELECT tsu.* FROM temp_statistical_unit tsu
  WHERE NOT EXISTS (
    SELECT 1 FROM public.statistical_unit su
    WHERE su.unit_type = tsu.unit_type
    AND su.unit_id = tsu.unit_id
    AND su.valid_after = tsu.valid_after
    AND su.valid_to = tsu.valid_to
  );

  -- Drop the temporary table
  DROP TABLE temp_statistical_unit;
END;
$statistical_unit_refresh$;

END;

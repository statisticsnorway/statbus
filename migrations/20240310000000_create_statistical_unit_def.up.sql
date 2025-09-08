BEGIN;

CREATE OR REPLACE VIEW public.statistical_unit_def
    ( unit_type
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
    WITH external_idents_agg AS (
        SELECT
            unit_type,
            unit_id,
            jsonb_object_agg(
                type_code,
                ident
            ) AS external_idents
        FROM (
            SELECT
                'establishment'::public.statistical_unit_type AS unit_type,
                ei.establishment_id AS unit_id,
                eit.code AS type_code,
                ei.ident
            FROM public.external_ident ei
            JOIN public.external_ident_type eit ON ei.type_id = eit.id
            WHERE ei.establishment_id IS NOT NULL
            UNION ALL
            SELECT
                'legal_unit'::public.statistical_unit_type AS unit_type,
                ei.legal_unit_id AS unit_id,
                eit.code AS type_code,
                ei.ident
            FROM public.external_ident ei
            JOIN public.external_ident_type eit ON ei.type_id = eit.id
            WHERE ei.legal_unit_id IS NOT NULL
            UNION ALL
            SELECT
                'enterprise'::public.statistical_unit_type AS unit_type,
                ei.enterprise_id AS unit_id,
                eit.code AS type_code,
                ei.ident
            FROM public.external_ident ei
            JOIN public.external_ident_type eit ON ei.type_id = eit.id
            WHERE ei.enterprise_id IS NOT NULL
            UNION ALL
            SELECT
                'enterprise_group'::public.statistical_unit_type AS unit_type,
                ei.enterprise_group_id AS unit_id,
                eit.code AS type_code,
                ei.ident
            FROM public.external_ident ei
            JOIN public.external_ident_type eit ON ei.type_id = eit.id
            WHERE ei.enterprise_group_id IS NOT NULL
        ) AS all_idents
        GROUP BY unit_type, unit_id
    ),
    tag_paths_agg AS (
        SELECT
            unit_type,
            unit_id,
            array_agg(path ORDER BY path) AS tag_paths
        FROM (
            SELECT 'establishment'::public.statistical_unit_type AS unit_type, tfu.establishment_id AS unit_id, t.path FROM public.tag_for_unit tfu JOIN public.tag t ON tfu.tag_id = t.id WHERE tfu.establishment_id IS NOT NULL
            UNION ALL
            SELECT 'legal_unit'::public.statistical_unit_type AS unit_type, tfu.legal_unit_id AS unit_id, t.path FROM public.tag_for_unit tfu JOIN public.tag t ON tfu.tag_id = t.id WHERE tfu.legal_unit_id IS NOT NULL
            UNION ALL
            SELECT 'enterprise'::public.statistical_unit_type AS unit_type, tfu.enterprise_id AS unit_id, t.path FROM public.tag_for_unit tfu JOIN public.tag t ON tfu.tag_id = t.id WHERE tfu.enterprise_id IS NOT NULL
            UNION ALL
            SELECT 'enterprise_group'::public.statistical_unit_type AS unit_type, tfu.enterprise_group_id AS unit_id, t.path FROM public.tag_for_unit tfu JOIN public.tag t ON tfu.tag_id = t.id WHERE tfu.enterprise_group_id IS NOT NULL
        ) AS all_tags
        GROUP BY unit_type, unit_id
    ),
    data AS (
      SELECT unit_type
           , unit_id
           , valid_from
           , valid_to
           , valid_until
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
           , NULL::INT AS primary_establishment_id
           , NULL::INT AS primary_legal_unit_id
      FROM public.timeline_establishment
      UNION ALL
      SELECT unit_type
           , unit_id
           , valid_from
           , valid_to
           , valid_until
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
           , NULL::INT AS primary_establishment_id
           , NULL::INT AS primary_legal_unit_id
      FROM public.timeline_legal_unit
      UNION ALL
      SELECT unit_type
           , unit_id
           , valid_from
           , valid_to
           , valid_until
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
           , primary_establishment_id
           , primary_legal_unit_id
      FROM public.timeline_enterprise
      --UNION ALL
      --SELECT * FROM enterprise_group_timeline
    )
    SELECT data.unit_type
         , data.unit_id
         , data.valid_from
         , data.valid_to
         , data.valid_until
         , COALESCE(
             eia1.external_idents, -- Direct idents for unit
             eia2.external_idents, -- Fallback to primary establishment
             eia3.external_idents, -- Fallback to primary legal unit
             '{}'::jsonb
           ) AS external_idents
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
         , COALESCE(tpa.tag_paths, ARRAY[]::public.ltree[]) AS tag_paths
    FROM data
    LEFT JOIN external_idents_agg AS eia1
        ON eia1.unit_type = data.unit_type AND eia1.unit_id = data.unit_id
    LEFT JOIN external_idents_agg AS eia2
        ON eia2.unit_type = 'establishment' AND eia2.unit_id = data.primary_establishment_id
    LEFT JOIN external_idents_agg AS eia3
        ON eia3.unit_type = 'legal_unit' AND eia3.unit_id = data.primary_legal_unit_id
    LEFT JOIN tag_paths_agg AS tpa
        ON tpa.unit_type = data.unit_type AND tpa.unit_id = data.unit_id;


END;

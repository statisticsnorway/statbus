BEGIN;

\echo public.statistical_unit_def
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
    , secondary_activity_category_id
    , secondary_activity_category_path
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
    , physical_address_part1
    , physical_address_part2
    , physical_address_part3
    , physical_postcode
    , physical_postplace
    , physical_region_id
    , physical_region_path
    , physical_country_id
    , physical_country_iso_2
    , postal_address_part1
    , postal_address_part2
    , postal_address_part3
    , postal_postcode
    , postal_postplace
    , postal_region_id
    , postal_region_path
    , postal_country_id
    , postal_country_iso_2
    , invalid_codes
    , has_legal_unit
    , establishment_ids
    , legal_unit_ids
    , enterprise_ids
    , stats
    , stats_summary
    , establishment_count
    , legal_unit_count
    , enterprise_count
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
           , secondary_activity_category_id
           , secondary_activity_category_path
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
           , physical_address_part1
           , physical_address_part2
           , physical_address_part3
           , physical_postcode
           , physical_postplace
           , physical_region_id
           , physical_region_path
           , physical_country_id
           , physical_country_iso_2
           , postal_address_part1
           , postal_address_part2
           , postal_address_part3
           , postal_postcode
           , postal_postplace
           , postal_region_id
           , postal_region_path
           , postal_country_id
           , postal_country_iso_2
           , invalid_codes
           , has_legal_unit
           , NULL::INT[] AS establishment_ids
           , NULL::INT[] AS legal_unit_ids
           , NULL::INT[] AS enterprise_ids
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
           , secondary_activity_category_id
           , secondary_activity_category_path
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
           , physical_address_part1
           , physical_address_part2
           , physical_address_part3
           , physical_postcode
           , physical_postplace
           , physical_region_id
           , physical_region_path
           , physical_country_id
           , physical_country_iso_2
           , postal_address_part1
           , postal_address_part2
           , postal_address_part3
           , postal_postcode
           , postal_postplace
           , postal_region_id
           , postal_region_path
           , postal_country_id
           , postal_country_iso_2
           , invalid_codes
           , has_legal_unit
           , COALESCE(establishment_ids,ARRAY[]::INT[]) AS establishment_ids
           , NULL::INT[] AS legal_unit_ids
           , NULL::INT[] AS enterprise_ids
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
           , secondary_activity_category_id
           , secondary_activity_category_path
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
           , physical_address_part1
           , physical_address_part2
           , physical_address_part3
           , physical_postcode
           , physical_postplace
           , physical_region_id
           , physical_region_path
           , physical_country_id
           , physical_country_iso_2
           , postal_address_part1
           , postal_address_part2
           , postal_address_part3
           , postal_postcode
           , postal_postplace
           , postal_region_id
           , postal_region_path
           , postal_country_id
           , postal_country_iso_2
           , invalid_codes
           , has_legal_unit
           , COALESCE(establishment_ids,ARRAY[]::INT[]) AS establishment_ids
           , COALESCE(legal_unit_ids,ARRAY[]::INT[]) AS legal_unit_ids
           , NULL::INT[] AS enterprise_ids
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
         , data.secondary_activity_category_id
         , data.secondary_activity_category_path
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
         , data.physical_address_part1
         , data.physical_address_part2
         , data.physical_address_part3
         , data.physical_postcode
         , data.physical_postplace
         , data.physical_region_id
         , data.physical_region_path
         , data.physical_country_id
         , data.physical_country_iso_2
         , data.postal_address_part1
         , data.postal_address_part2
         , data.postal_address_part3
         , data.postal_postcode
         , data.postal_postplace
         , data.postal_region_id
         , data.postal_region_path
         , data.postal_country_id
         , data.postal_country_iso_2
         , data.invalid_codes
         , data.has_legal_unit
         , data.establishment_ids
         , data.legal_unit_ids
         , data.enterprise_ids
         , data.stats
         , data.stats_summary
         , array_length(data.establishment_ids,1) AS establishment_count
         , array_length(data.legal_unit_ids,1) AS legal_unit_count
         , array_length(data.enterprise_ids,1) AS enterprise_count
         , public.get_tag_paths(data.unit_type, data.unit_id) AS tag_paths
    FROM data;
;

END;
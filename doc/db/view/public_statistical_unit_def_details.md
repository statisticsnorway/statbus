```sql
                                          View "public.statistical_unit_def"
              Column              |           Type           | Collation | Nullable | Default | Storage  | Description 
----------------------------------+--------------------------+-----------+----------+---------+----------+-------------
 unit_type                        | statistical_unit_type    |           |          |         | plain    | 
 unit_id                          | integer                  |           |          |         | plain    | 
 valid_from                       | date                     |           |          |         | plain    | 
 valid_to                         | date                     |           |          |         | plain    | 
 valid_until                      | date                     |           |          |         | plain    | 
 external_idents                  | jsonb                    |           |          |         | extended | 
 name                             | character varying(256)   |           |          |         | extended | 
 birth_date                       | date                     |           |          |         | plain    | 
 death_date                       | date                     |           |          |         | plain    | 
 search                           | tsvector                 |           |          |         | extended | 
 primary_activity_category_id     | integer                  |           |          |         | plain    | 
 primary_activity_category_path   | ltree                    |           |          |         | extended | 
 primary_activity_category_code   | character varying        |           |          |         | extended | 
 secondary_activity_category_id   | integer                  |           |          |         | plain    | 
 secondary_activity_category_path | ltree                    |           |          |         | extended | 
 secondary_activity_category_code | character varying        |           |          |         | extended | 
 activity_category_paths          | ltree[]                  |           |          |         | extended | 
 sector_id                        | integer                  |           |          |         | plain    | 
 sector_path                      | ltree                    |           |          |         | extended | 
 sector_code                      | character varying        |           |          |         | extended | 
 sector_name                      | text                     |           |          |         | extended | 
 data_source_ids                  | integer[]                |           |          |         | extended | 
 data_source_codes                | text[]                   |           |          |         | extended | 
 legal_form_id                    | integer                  |           |          |         | plain    | 
 legal_form_code                  | text                     |           |          |         | extended | 
 legal_form_name                  | text                     |           |          |         | extended | 
 physical_address_part1           | character varying(200)   |           |          |         | extended | 
 physical_address_part2           | character varying(200)   |           |          |         | extended | 
 physical_address_part3           | character varying(200)   |           |          |         | extended | 
 physical_postcode                | character varying(200)   |           |          |         | extended | 
 physical_postplace               | character varying(200)   |           |          |         | extended | 
 physical_region_id               | integer                  |           |          |         | plain    | 
 physical_region_path             | ltree                    |           |          |         | extended | 
 physical_region_code             | character varying        |           |          |         | extended | 
 physical_country_id              | integer                  |           |          |         | plain    | 
 physical_country_iso_2           | text                     |           |          |         | extended | 
 physical_latitude                | numeric(9,6)             |           |          |         | main     | 
 physical_longitude               | numeric(9,6)             |           |          |         | main     | 
 physical_altitude                | numeric(6,1)             |           |          |         | main     | 
 postal_address_part1             | character varying(200)   |           |          |         | extended | 
 postal_address_part2             | character varying(200)   |           |          |         | extended | 
 postal_address_part3             | character varying(200)   |           |          |         | extended | 
 postal_postcode                  | character varying(200)   |           |          |         | extended | 
 postal_postplace                 | character varying(200)   |           |          |         | extended | 
 postal_region_id                 | integer                  |           |          |         | plain    | 
 postal_region_path               | ltree                    |           |          |         | extended | 
 postal_region_code               | character varying        |           |          |         | extended | 
 postal_country_id                | integer                  |           |          |         | plain    | 
 postal_country_iso_2             | text                     |           |          |         | extended | 
 postal_latitude                  | numeric(9,6)             |           |          |         | main     | 
 postal_longitude                 | numeric(9,6)             |           |          |         | main     | 
 postal_altitude                  | numeric(6,1)             |           |          |         | main     | 
 web_address                      | character varying(256)   |           |          |         | extended | 
 email_address                    | character varying(50)    |           |          |         | extended | 
 phone_number                     | character varying(50)    |           |          |         | extended | 
 landline                         | character varying(50)    |           |          |         | extended | 
 mobile_number                    | character varying(50)    |           |          |         | extended | 
 fax_number                       | character varying(50)    |           |          |         | extended | 
 unit_size_id                     | integer                  |           |          |         | plain    | 
 unit_size_code                   | text                     |           |          |         | extended | 
 status_id                        | integer                  |           |          |         | plain    | 
 status_code                      | character varying        |           |          |         | extended | 
 include_unit_in_reports          | boolean                  |           |          |         | plain    | 
 last_edit_comment                | character varying(512)   |           |          |         | extended | 
 last_edit_by_user_id             | integer                  |           |          |         | plain    | 
 last_edit_at                     | timestamp with time zone |           |          |         | plain    | 
 invalid_codes                    | jsonb                    |           |          |         | extended | 
 has_legal_unit                   | boolean                  |           |          |         | plain    | 
 related_establishment_ids        | integer[]                |           |          |         | extended | 
 excluded_establishment_ids       | integer[]                |           |          |         | extended | 
 included_establishment_ids       | integer[]                |           |          |         | extended | 
 related_legal_unit_ids           | integer[]                |           |          |         | extended | 
 excluded_legal_unit_ids          | integer[]                |           |          |         | extended | 
 included_legal_unit_ids          | integer[]                |           |          |         | extended | 
 related_enterprise_ids           | integer[]                |           |          |         | extended | 
 excluded_enterprise_ids          | integer[]                |           |          |         | extended | 
 included_enterprise_ids          | integer[]                |           |          |         | extended | 
 stats                            | jsonb                    |           |          |         | extended | 
 stats_summary                    | jsonb                    |           |          |         | extended | 
 included_establishment_count     | integer                  |           |          |         | plain    | 
 included_legal_unit_count        | integer                  |           |          |         | plain    | 
 included_enterprise_count        | integer                  |           |          |         | plain    | 
 tag_paths                        | ltree[]                  |           |          |         | extended | 
View definition:
 WITH external_idents_agg AS (
         SELECT all_idents.unit_type,
            all_idents.unit_id,
            jsonb_object_agg(all_idents.type_code, all_idents.ident) AS external_idents
           FROM ( SELECT 'establishment'::statistical_unit_type AS unit_type,
                    ei.establishment_id AS unit_id,
                    eit.code AS type_code,
                    ei.ident
                   FROM external_ident ei
                     JOIN external_ident_type eit ON ei.type_id = eit.id
                  WHERE ei.establishment_id IS NOT NULL
                UNION ALL
                 SELECT 'legal_unit'::statistical_unit_type AS unit_type,
                    ei.legal_unit_id AS unit_id,
                    eit.code AS type_code,
                    ei.ident
                   FROM external_ident ei
                     JOIN external_ident_type eit ON ei.type_id = eit.id
                  WHERE ei.legal_unit_id IS NOT NULL
                UNION ALL
                 SELECT 'enterprise'::statistical_unit_type AS unit_type,
                    ei.enterprise_id AS unit_id,
                    eit.code AS type_code,
                    ei.ident
                   FROM external_ident ei
                     JOIN external_ident_type eit ON ei.type_id = eit.id
                  WHERE ei.enterprise_id IS NOT NULL
                UNION ALL
                 SELECT 'enterprise_group'::statistical_unit_type AS unit_type,
                    ei.enterprise_group_id AS unit_id,
                    eit.code AS type_code,
                    ei.ident
                   FROM external_ident ei
                     JOIN external_ident_type eit ON ei.type_id = eit.id
                  WHERE ei.enterprise_group_id IS NOT NULL) all_idents
          GROUP BY all_idents.unit_type, all_idents.unit_id
        ), tag_paths_agg AS (
         SELECT all_tags.unit_type,
            all_tags.unit_id,
            array_agg(all_tags.path ORDER BY all_tags.path) AS tag_paths
           FROM ( SELECT 'establishment'::statistical_unit_type AS unit_type,
                    tfu.establishment_id AS unit_id,
                    t.path
                   FROM tag_for_unit tfu
                     JOIN tag t ON tfu.tag_id = t.id
                  WHERE tfu.establishment_id IS NOT NULL
                UNION ALL
                 SELECT 'legal_unit'::statistical_unit_type AS unit_type,
                    tfu.legal_unit_id AS unit_id,
                    t.path
                   FROM tag_for_unit tfu
                     JOIN tag t ON tfu.tag_id = t.id
                  WHERE tfu.legal_unit_id IS NOT NULL
                UNION ALL
                 SELECT 'enterprise'::statistical_unit_type AS unit_type,
                    tfu.enterprise_id AS unit_id,
                    t.path
                   FROM tag_for_unit tfu
                     JOIN tag t ON tfu.tag_id = t.id
                  WHERE tfu.enterprise_id IS NOT NULL
                UNION ALL
                 SELECT 'enterprise_group'::statistical_unit_type AS unit_type,
                    tfu.enterprise_group_id AS unit_id,
                    t.path
                   FROM tag_for_unit tfu
                     JOIN tag t ON tfu.tag_id = t.id
                  WHERE tfu.enterprise_group_id IS NOT NULL) all_tags
          GROUP BY all_tags.unit_type, all_tags.unit_id
        ), data AS (
         SELECT timeline_establishment.unit_type,
            timeline_establishment.unit_id,
            timeline_establishment.valid_from,
            timeline_establishment.valid_to,
            timeline_establishment.valid_until,
            timeline_establishment.name,
            timeline_establishment.birth_date,
            timeline_establishment.death_date,
            timeline_establishment.search,
            timeline_establishment.primary_activity_category_id,
            timeline_establishment.primary_activity_category_path,
            timeline_establishment.primary_activity_category_code,
            timeline_establishment.secondary_activity_category_id,
            timeline_establishment.secondary_activity_category_path,
            timeline_establishment.secondary_activity_category_code,
            timeline_establishment.activity_category_paths,
            timeline_establishment.sector_id,
            timeline_establishment.sector_path,
            timeline_establishment.sector_code,
            timeline_establishment.sector_name,
            timeline_establishment.data_source_ids,
            timeline_establishment.data_source_codes,
            timeline_establishment.legal_form_id,
            timeline_establishment.legal_form_code,
            timeline_establishment.legal_form_name,
            timeline_establishment.physical_address_part1,
            timeline_establishment.physical_address_part2,
            timeline_establishment.physical_address_part3,
            timeline_establishment.physical_postcode,
            timeline_establishment.physical_postplace,
            timeline_establishment.physical_region_id,
            timeline_establishment.physical_region_path,
            timeline_establishment.physical_region_code,
            timeline_establishment.physical_country_id,
            timeline_establishment.physical_country_iso_2,
            timeline_establishment.physical_latitude,
            timeline_establishment.physical_longitude,
            timeline_establishment.physical_altitude,
            timeline_establishment.postal_address_part1,
            timeline_establishment.postal_address_part2,
            timeline_establishment.postal_address_part3,
            timeline_establishment.postal_postcode,
            timeline_establishment.postal_postplace,
            timeline_establishment.postal_region_id,
            timeline_establishment.postal_region_path,
            timeline_establishment.postal_region_code,
            timeline_establishment.postal_country_id,
            timeline_establishment.postal_country_iso_2,
            timeline_establishment.postal_latitude,
            timeline_establishment.postal_longitude,
            timeline_establishment.postal_altitude,
            timeline_establishment.web_address,
            timeline_establishment.email_address,
            timeline_establishment.phone_number,
            timeline_establishment.landline,
            timeline_establishment.mobile_number,
            timeline_establishment.fax_number,
            timeline_establishment.unit_size_id,
            timeline_establishment.unit_size_code,
            timeline_establishment.status_id,
            timeline_establishment.status_code,
            timeline_establishment.include_unit_in_reports,
            timeline_establishment.last_edit_comment,
            timeline_establishment.last_edit_by_user_id,
            timeline_establishment.last_edit_at,
            timeline_establishment.invalid_codes,
            timeline_establishment.has_legal_unit,
            timeline_establishment.related_establishment_ids,
            timeline_establishment.excluded_establishment_ids,
            timeline_establishment.included_establishment_ids,
            timeline_establishment.related_legal_unit_ids,
            timeline_establishment.excluded_legal_unit_ids,
            timeline_establishment.included_legal_unit_ids,
            timeline_establishment.related_enterprise_ids,
            timeline_establishment.excluded_enterprise_ids,
            timeline_establishment.included_enterprise_ids,
            timeline_establishment.stats,
            timeline_establishment.stats_summary,
            NULL::integer AS primary_establishment_id,
            NULL::integer AS primary_legal_unit_id
           FROM timeline_establishment
        UNION ALL
         SELECT timeline_legal_unit.unit_type,
            timeline_legal_unit.unit_id,
            timeline_legal_unit.valid_from,
            timeline_legal_unit.valid_to,
            timeline_legal_unit.valid_until,
            timeline_legal_unit.name,
            timeline_legal_unit.birth_date,
            timeline_legal_unit.death_date,
            timeline_legal_unit.search,
            timeline_legal_unit.primary_activity_category_id,
            timeline_legal_unit.primary_activity_category_path,
            timeline_legal_unit.primary_activity_category_code,
            timeline_legal_unit.secondary_activity_category_id,
            timeline_legal_unit.secondary_activity_category_path,
            timeline_legal_unit.secondary_activity_category_code,
            timeline_legal_unit.activity_category_paths,
            timeline_legal_unit.sector_id,
            timeline_legal_unit.sector_path,
            timeline_legal_unit.sector_code,
            timeline_legal_unit.sector_name,
            timeline_legal_unit.data_source_ids,
            timeline_legal_unit.data_source_codes,
            timeline_legal_unit.legal_form_id,
            timeline_legal_unit.legal_form_code,
            timeline_legal_unit.legal_form_name,
            timeline_legal_unit.physical_address_part1,
            timeline_legal_unit.physical_address_part2,
            timeline_legal_unit.physical_address_part3,
            timeline_legal_unit.physical_postcode,
            timeline_legal_unit.physical_postplace,
            timeline_legal_unit.physical_region_id,
            timeline_legal_unit.physical_region_path,
            timeline_legal_unit.physical_region_code,
            timeline_legal_unit.physical_country_id,
            timeline_legal_unit.physical_country_iso_2,
            timeline_legal_unit.physical_latitude,
            timeline_legal_unit.physical_longitude,
            timeline_legal_unit.physical_altitude,
            timeline_legal_unit.postal_address_part1,
            timeline_legal_unit.postal_address_part2,
            timeline_legal_unit.postal_address_part3,
            timeline_legal_unit.postal_postcode,
            timeline_legal_unit.postal_postplace,
            timeline_legal_unit.postal_region_id,
            timeline_legal_unit.postal_region_path,
            timeline_legal_unit.postal_region_code,
            timeline_legal_unit.postal_country_id,
            timeline_legal_unit.postal_country_iso_2,
            timeline_legal_unit.postal_latitude,
            timeline_legal_unit.postal_longitude,
            timeline_legal_unit.postal_altitude,
            timeline_legal_unit.web_address,
            timeline_legal_unit.email_address,
            timeline_legal_unit.phone_number,
            timeline_legal_unit.landline,
            timeline_legal_unit.mobile_number,
            timeline_legal_unit.fax_number,
            timeline_legal_unit.unit_size_id,
            timeline_legal_unit.unit_size_code,
            timeline_legal_unit.status_id,
            timeline_legal_unit.status_code,
            timeline_legal_unit.include_unit_in_reports,
            timeline_legal_unit.last_edit_comment,
            timeline_legal_unit.last_edit_by_user_id,
            timeline_legal_unit.last_edit_at,
            timeline_legal_unit.invalid_codes,
            timeline_legal_unit.has_legal_unit,
            timeline_legal_unit.related_establishment_ids,
            timeline_legal_unit.excluded_establishment_ids,
            timeline_legal_unit.included_establishment_ids,
            timeline_legal_unit.related_legal_unit_ids,
            timeline_legal_unit.excluded_legal_unit_ids,
            timeline_legal_unit.included_legal_unit_ids,
            timeline_legal_unit.related_enterprise_ids,
            timeline_legal_unit.excluded_enterprise_ids,
            timeline_legal_unit.included_enterprise_ids,
            timeline_legal_unit.stats,
            timeline_legal_unit.stats_summary,
            NULL::integer AS primary_establishment_id,
            NULL::integer AS primary_legal_unit_id
           FROM timeline_legal_unit
        UNION ALL
         SELECT timeline_enterprise.unit_type,
            timeline_enterprise.unit_id,
            timeline_enterprise.valid_from,
            timeline_enterprise.valid_to,
            timeline_enterprise.valid_until,
            timeline_enterprise.name,
            timeline_enterprise.birth_date,
            timeline_enterprise.death_date,
            timeline_enterprise.search,
            timeline_enterprise.primary_activity_category_id,
            timeline_enterprise.primary_activity_category_path,
            timeline_enterprise.primary_activity_category_code,
            timeline_enterprise.secondary_activity_category_id,
            timeline_enterprise.secondary_activity_category_path,
            timeline_enterprise.secondary_activity_category_code,
            timeline_enterprise.activity_category_paths,
            timeline_enterprise.sector_id,
            timeline_enterprise.sector_path,
            timeline_enterprise.sector_code,
            timeline_enterprise.sector_name,
            timeline_enterprise.data_source_ids,
            timeline_enterprise.data_source_codes,
            timeline_enterprise.legal_form_id,
            timeline_enterprise.legal_form_code,
            timeline_enterprise.legal_form_name,
            timeline_enterprise.physical_address_part1,
            timeline_enterprise.physical_address_part2,
            timeline_enterprise.physical_address_part3,
            timeline_enterprise.physical_postcode,
            timeline_enterprise.physical_postplace,
            timeline_enterprise.physical_region_id,
            timeline_enterprise.physical_region_path,
            timeline_enterprise.physical_region_code,
            timeline_enterprise.physical_country_id,
            timeline_enterprise.physical_country_iso_2,
            timeline_enterprise.physical_latitude,
            timeline_enterprise.physical_longitude,
            timeline_enterprise.physical_altitude,
            timeline_enterprise.postal_address_part1,
            timeline_enterprise.postal_address_part2,
            timeline_enterprise.postal_address_part3,
            timeline_enterprise.postal_postcode,
            timeline_enterprise.postal_postplace,
            timeline_enterprise.postal_region_id,
            timeline_enterprise.postal_region_path,
            timeline_enterprise.postal_region_code,
            timeline_enterprise.postal_country_id,
            timeline_enterprise.postal_country_iso_2,
            timeline_enterprise.postal_latitude,
            timeline_enterprise.postal_longitude,
            timeline_enterprise.postal_altitude,
            timeline_enterprise.web_address,
            timeline_enterprise.email_address,
            timeline_enterprise.phone_number,
            timeline_enterprise.landline,
            timeline_enterprise.mobile_number,
            timeline_enterprise.fax_number,
            timeline_enterprise.unit_size_id,
            timeline_enterprise.unit_size_code,
            timeline_enterprise.status_id,
            timeline_enterprise.status_code,
            timeline_enterprise.include_unit_in_reports,
            timeline_enterprise.last_edit_comment,
            timeline_enterprise.last_edit_by_user_id,
            timeline_enterprise.last_edit_at,
            timeline_enterprise.invalid_codes,
            timeline_enterprise.has_legal_unit,
            timeline_enterprise.related_establishment_ids,
            timeline_enterprise.excluded_establishment_ids,
            timeline_enterprise.included_establishment_ids,
            timeline_enterprise.related_legal_unit_ids,
            timeline_enterprise.excluded_legal_unit_ids,
            timeline_enterprise.included_legal_unit_ids,
            timeline_enterprise.related_enterprise_ids,
            timeline_enterprise.excluded_enterprise_ids,
            timeline_enterprise.included_enterprise_ids,
            NULL::jsonb AS stats,
            timeline_enterprise.stats_summary,
            timeline_enterprise.primary_establishment_id,
            timeline_enterprise.primary_legal_unit_id
           FROM timeline_enterprise
        )
 SELECT data.unit_type,
    data.unit_id,
    data.valid_from,
    data.valid_to,
    data.valid_until,
    COALESCE(eia1.external_idents, eia2.external_idents, eia3.external_idents, '{}'::jsonb) AS external_idents,
    data.name,
    data.birth_date,
    data.death_date,
    data.search,
    data.primary_activity_category_id,
    data.primary_activity_category_path,
    data.primary_activity_category_code,
    data.secondary_activity_category_id,
    data.secondary_activity_category_path,
    data.secondary_activity_category_code,
    data.activity_category_paths,
    data.sector_id,
    data.sector_path,
    data.sector_code,
    data.sector_name,
    data.data_source_ids,
    data.data_source_codes,
    data.legal_form_id,
    data.legal_form_code,
    data.legal_form_name,
    data.physical_address_part1,
    data.physical_address_part2,
    data.physical_address_part3,
    data.physical_postcode,
    data.physical_postplace,
    data.physical_region_id,
    data.physical_region_path,
    data.physical_region_code,
    data.physical_country_id,
    data.physical_country_iso_2,
    data.physical_latitude,
    data.physical_longitude,
    data.physical_altitude,
    data.postal_address_part1,
    data.postal_address_part2,
    data.postal_address_part3,
    data.postal_postcode,
    data.postal_postplace,
    data.postal_region_id,
    data.postal_region_path,
    data.postal_region_code,
    data.postal_country_id,
    data.postal_country_iso_2,
    data.postal_latitude,
    data.postal_longitude,
    data.postal_altitude,
    data.web_address,
    data.email_address,
    data.phone_number,
    data.landline,
    data.mobile_number,
    data.fax_number,
    data.unit_size_id,
    data.unit_size_code,
    data.status_id,
    data.status_code,
    data.include_unit_in_reports,
    data.last_edit_comment,
    data.last_edit_by_user_id,
    data.last_edit_at,
    data.invalid_codes,
    data.has_legal_unit,
    data.related_establishment_ids,
    data.excluded_establishment_ids,
    data.included_establishment_ids,
    data.related_legal_unit_ids,
    data.excluded_legal_unit_ids,
    data.included_legal_unit_ids,
    data.related_enterprise_ids,
    data.excluded_enterprise_ids,
    data.included_enterprise_ids,
    data.stats,
    data.stats_summary,
    array_length(data.included_establishment_ids, 1) AS included_establishment_count,
    array_length(data.included_legal_unit_ids, 1) AS included_legal_unit_count,
    array_length(data.included_enterprise_ids, 1) AS included_enterprise_count,
    COALESCE(tpa.tag_paths, ARRAY[]::ltree[]) AS tag_paths
   FROM data
     LEFT JOIN external_idents_agg eia1 ON eia1.unit_type = data.unit_type AND eia1.unit_id = data.unit_id
     LEFT JOIN external_idents_agg eia2 ON eia2.unit_type = 'establishment'::statistical_unit_type AND eia2.unit_id = data.primary_establishment_id
     LEFT JOIN external_idents_agg eia3 ON eia3.unit_type = 'legal_unit'::statistical_unit_type AND eia3.unit_id = data.primary_legal_unit_id
     LEFT JOIN tag_paths_agg tpa ON tpa.unit_type = data.unit_type AND tpa.unit_id = data.unit_id;

```

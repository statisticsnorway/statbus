```sql
                                          View "public.statistical_unit_def"
              Column              |           Type           | Collation | Nullable | Default | Storage  | Description 
----------------------------------+--------------------------+-----------+----------+---------+----------+-------------
 unit_type                        | statistical_unit_type    |           |          |         | plain    | 
 unit_id                          | integer                  |           |          |         | plain    | 
 valid_after                      | date                     |           |          |         | plain    | 
 valid_from                       | date                     |           |          |         | plain    | 
 valid_to                         | date                     |           |          |         | plain    | 
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
 WITH data AS (
         SELECT timeline_establishment.unit_type,
            timeline_establishment.unit_id,
            timeline_establishment.valid_after,
            timeline_establishment.valid_from,
            timeline_establishment.valid_to,
            get_external_idents(timeline_establishment.unit_type, timeline_establishment.unit_id) AS external_idents,
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
                CASE
                    WHEN timeline_establishment.establishment_id IS NOT NULL THEN ARRAY[timeline_establishment.establishment_id]
                    ELSE ARRAY[]::integer[]
                END AS related_establishment_ids,
            NULL::integer[] AS excluded_establishment_ids,
            NULL::integer[] AS included_establishment_ids,
                CASE
                    WHEN timeline_establishment.legal_unit_id IS NOT NULL THEN ARRAY[timeline_establishment.legal_unit_id]
                    ELSE ARRAY[]::integer[]
                END AS related_legal_unit_ids,
            NULL::integer[] AS excluded_legal_unit_ids,
            NULL::integer[] AS included_legal_unit_ids,
                CASE
                    WHEN timeline_establishment.enterprise_id IS NOT NULL THEN ARRAY[timeline_establishment.enterprise_id]
                    ELSE ARRAY[]::integer[]
                END AS related_enterprise_ids,
            NULL::integer[] AS excluded_enterprise_ids,
            NULL::integer[] AS included_enterprise_ids,
            timeline_establishment.stats,
            COALESCE(jsonb_stats_to_summary('{}'::jsonb, timeline_establishment.stats), '{}'::jsonb) AS stats_summary
           FROM timeline_establishment
        UNION ALL
         SELECT timeline_legal_unit.unit_type,
            timeline_legal_unit.unit_id,
            timeline_legal_unit.valid_after,
            timeline_legal_unit.valid_from,
            timeline_legal_unit.valid_to,
            get_external_idents(timeline_legal_unit.unit_type, timeline_legal_unit.unit_id) AS external_idents,
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
            COALESCE(timeline_legal_unit.related_establishment_ids, ARRAY[]::integer[]) AS related_establishment_ids,
            COALESCE(timeline_legal_unit.excluded_establishment_ids, ARRAY[]::integer[]) AS excluded_establishment_ids,
            COALESCE(timeline_legal_unit.included_establishment_ids, ARRAY[]::integer[]) AS included_establishment_ids,
                CASE
                    WHEN timeline_legal_unit.legal_unit_id IS NOT NULL THEN ARRAY[timeline_legal_unit.legal_unit_id]
                    ELSE ARRAY[]::integer[]
                END AS related_legal_unit_ids,
            NULL::integer[] AS excluded_legal_unit_ids,
            NULL::integer[] AS included_legal_unit_ids,
                CASE
                    WHEN timeline_legal_unit.enterprise_id IS NOT NULL THEN ARRAY[timeline_legal_unit.enterprise_id]
                    ELSE ARRAY[]::integer[]
                END AS related_enterprise_ids,
            NULL::integer[] AS excluded_enterprise_ids,
            NULL::integer[] AS included_enterprise_ids,
            timeline_legal_unit.stats,
            timeline_legal_unit.stats_summary
           FROM timeline_legal_unit
        UNION ALL
         SELECT timeline_enterprise.unit_type,
            timeline_enterprise.unit_id,
            timeline_enterprise.valid_after,
            timeline_enterprise.valid_from,
            timeline_enterprise.valid_to,
            COALESCE(get_external_idents(timeline_enterprise.unit_type, timeline_enterprise.unit_id), get_external_idents('establishment'::statistical_unit_type, timeline_enterprise.primary_establishment_id), get_external_idents('legal_unit'::statistical_unit_type, timeline_enterprise.primary_legal_unit_id)) AS external_idents,
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
            COALESCE(timeline_enterprise.related_establishment_ids, ARRAY[]::integer[]) AS related_establishment_ids,
            COALESCE(timeline_enterprise.excluded_establishment_ids, ARRAY[]::integer[]) AS excluded_establishment_ids,
            COALESCE(timeline_enterprise.included_establishment_ids, ARRAY[]::integer[]) AS included_establishment_ids,
            COALESCE(timeline_enterprise.related_legal_unit_ids, ARRAY[]::integer[]) AS related_legal_unit_ids,
            COALESCE(timeline_enterprise.excluded_legal_unit_ids, ARRAY[]::integer[]) AS excluded_legal_unit_ids,
            COALESCE(timeline_enterprise.included_legal_unit_ids, ARRAY[]::integer[]) AS included_legal_unit_ids,
                CASE
                    WHEN timeline_enterprise.enterprise_id IS NOT NULL THEN ARRAY[timeline_enterprise.enterprise_id]
                    ELSE ARRAY[]::integer[]
                END AS related_enterprise_ids,
            NULL::integer[] AS excluded_enterprise_ids,
            NULL::integer[] AS included_enterprise_ids,
            NULL::jsonb AS stats,
            timeline_enterprise.stats_summary
           FROM timeline_enterprise
        )
 SELECT unit_type,
    unit_id,
    valid_after,
    valid_from,
    valid_to,
    external_idents,
    name,
    birth_date,
    death_date,
    search,
    primary_activity_category_id,
    primary_activity_category_path,
    primary_activity_category_code,
    secondary_activity_category_id,
    secondary_activity_category_path,
    secondary_activity_category_code,
    activity_category_paths,
    sector_id,
    sector_path,
    sector_code,
    sector_name,
    data_source_ids,
    data_source_codes,
    legal_form_id,
    legal_form_code,
    legal_form_name,
    physical_address_part1,
    physical_address_part2,
    physical_address_part3,
    physical_postcode,
    physical_postplace,
    physical_region_id,
    physical_region_path,
    physical_region_code,
    physical_country_id,
    physical_country_iso_2,
    physical_latitude,
    physical_longitude,
    physical_altitude,
    postal_address_part1,
    postal_address_part2,
    postal_address_part3,
    postal_postcode,
    postal_postplace,
    postal_region_id,
    postal_region_path,
    postal_region_code,
    postal_country_id,
    postal_country_iso_2,
    postal_latitude,
    postal_longitude,
    postal_altitude,
    web_address,
    email_address,
    phone_number,
    landline,
    mobile_number,
    fax_number,
    unit_size_id,
    unit_size_code,
    status_id,
    status_code,
    include_unit_in_reports,
    last_edit_comment,
    last_edit_by_user_id,
    last_edit_at,
    invalid_codes,
    has_legal_unit,
    related_establishment_ids,
    excluded_establishment_ids,
    included_establishment_ids,
    related_legal_unit_ids,
    excluded_legal_unit_ids,
    included_legal_unit_ids,
    related_enterprise_ids,
    excluded_enterprise_ids,
    included_enterprise_ids,
    stats,
    stats_summary,
    array_length(included_establishment_ids, 1) AS included_establishment_count,
    array_length(included_legal_unit_ids, 1) AS included_legal_unit_count,
    array_length(included_enterprise_ids, 1) AS included_enterprise_count,
    COALESCE(( SELECT array_agg(t.path ORDER BY t.path) AS array_agg
           FROM tag_for_unit tfu
             JOIN tag t ON t.id = tfu.tag_id
          WHERE
                CASE data.unit_type
                    WHEN 'enterprise'::statistical_unit_type THEN tfu.enterprise_id = data.unit_id
                    WHEN 'legal_unit'::statistical_unit_type THEN tfu.legal_unit_id = data.unit_id
                    WHEN 'establishment'::statistical_unit_type THEN tfu.establishment_id = data.unit_id
                    WHEN 'enterprise_group'::statistical_unit_type THEN tfu.enterprise_group_id = data.unit_id
                    ELSE NULL::boolean
                END), ARRAY[]::ltree[]) AS tag_paths
   FROM data;

```

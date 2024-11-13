```sql
                                         View "public.statistical_unit_def"
              Column              |          Type          | Collation | Nullable | Default | Storage  | Description 
----------------------------------+------------------------+-----------+----------+---------+----------+-------------
 unit_type                        | statistical_unit_type  |           |          |         | plain    | 
 unit_id                          | integer                |           |          |         | plain    | 
 valid_after                      | date                   |           |          |         | plain    | 
 valid_from                       | date                   |           |          |         | plain    | 
 valid_to                         | date                   |           |          |         | plain    | 
 external_idents                  | jsonb                  |           |          |         | extended | 
 name                             | character varying(256) |           |          |         | extended | 
 birth_date                       | date                   |           |          |         | plain    | 
 death_date                       | date                   |           |          |         | plain    | 
 search                           | tsvector               |           |          |         | extended | 
 primary_activity_category_id     | integer                |           |          |         | plain    | 
 primary_activity_category_path   | ltree                  |           |          |         | extended | 
 secondary_activity_category_id   | integer                |           |          |         | plain    | 
 secondary_activity_category_path | ltree                  |           |          |         | extended | 
 activity_category_paths          | ltree[]                |           |          |         | extended | 
 sector_id                        | integer                |           |          |         | plain    | 
 sector_path                      | ltree                  |           |          |         | extended | 
 sector_code                      | character varying      |           |          |         | extended | 
 sector_name                      | text                   |           |          |         | extended | 
 data_source_ids                  | integer[]              |           |          |         | extended | 
 data_source_codes                | text[]                 |           |          |         | extended | 
 legal_form_id                    | integer                |           |          |         | plain    | 
 legal_form_code                  | text                   |           |          |         | extended | 
 legal_form_name                  | text                   |           |          |         | extended | 
 physical_address_part1           | character varying(200) |           |          |         | extended | 
 physical_address_part2           | character varying(200) |           |          |         | extended | 
 physical_address_part3           | character varying(200) |           |          |         | extended | 
 physical_postal_code             | character varying(200) |           |          |         | extended | 
 physical_postal_place            | character varying(200) |           |          |         | extended | 
 physical_region_id               | integer                |           |          |         | plain    | 
 physical_region_path             | ltree                  |           |          |         | extended | 
 physical_country_id              | integer                |           |          |         | plain    | 
 physical_country_iso_2           | text                   |           |          |         | extended | 
 postal_address_part1             | character varying(200) |           |          |         | extended | 
 postal_address_part2             | character varying(200) |           |          |         | extended | 
 postal_address_part3             | character varying(200) |           |          |         | extended | 
 postal_postal_code               | character varying(200) |           |          |         | extended | 
 postal_postal_place              | character varying(200) |           |          |         | extended | 
 postal_region_id                 | integer                |           |          |         | plain    | 
 postal_region_path               | ltree                  |           |          |         | extended | 
 postal_country_id                | integer                |           |          |         | plain    | 
 postal_country_iso_2             | text                   |           |          |         | extended | 
 invalid_codes                    | jsonb                  |           |          |         | extended | 
 establishment_ids                | integer[]              |           |          |         | extended | 
 legal_unit_ids                   | integer[]              |           |          |         | extended | 
 enterprise_ids                   | integer[]              |           |          |         | extended | 
 stats                            | jsonb                  |           |          |         | extended | 
 stats_summary                    | jsonb                  |           |          |         | extended | 
 establishment_count              | integer                |           |          |         | plain    | 
 legal_unit_count                 | integer                |           |          |         | plain    | 
 enterprise_count                 | integer                |           |          |         | plain    | 
 tag_paths                        | ltree[]                |           |          |         | extended | 
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
            timeline_establishment.secondary_activity_category_id,
            timeline_establishment.secondary_activity_category_path,
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
            timeline_establishment.physical_postal_code,
            timeline_establishment.physical_postal_place,
            timeline_establishment.physical_region_id,
            timeline_establishment.physical_region_path,
            timeline_establishment.physical_country_id,
            timeline_establishment.physical_country_iso_2,
            timeline_establishment.postal_address_part1,
            timeline_establishment.postal_address_part2,
            timeline_establishment.postal_address_part3,
            timeline_establishment.postal_postal_code,
            timeline_establishment.postal_postal_place,
            timeline_establishment.postal_region_id,
            timeline_establishment.postal_region_path,
            timeline_establishment.postal_country_id,
            timeline_establishment.postal_country_iso_2,
            timeline_establishment.invalid_codes,
            ARRAY[timeline_establishment.establishment_id] AS establishment_ids,
                CASE
                    WHEN timeline_establishment.legal_unit_id IS NULL THEN ARRAY[]::integer[]
                    ELSE ARRAY[timeline_establishment.legal_unit_id]
                END AS legal_unit_ids,
                CASE
                    WHEN timeline_establishment.enterprise_id IS NULL THEN ARRAY[]::integer[]
                    ELSE ARRAY[timeline_establishment.enterprise_id]
                END AS enterprise_ids,
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
            timeline_legal_unit.secondary_activity_category_id,
            timeline_legal_unit.secondary_activity_category_path,
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
            timeline_legal_unit.physical_postal_code,
            timeline_legal_unit.physical_postal_place,
            timeline_legal_unit.physical_region_id,
            timeline_legal_unit.physical_region_path,
            timeline_legal_unit.physical_country_id,
            timeline_legal_unit.physical_country_iso_2,
            timeline_legal_unit.postal_address_part1,
            timeline_legal_unit.postal_address_part2,
            timeline_legal_unit.postal_address_part3,
            timeline_legal_unit.postal_postal_code,
            timeline_legal_unit.postal_postal_place,
            timeline_legal_unit.postal_region_id,
            timeline_legal_unit.postal_region_path,
            timeline_legal_unit.postal_country_id,
            timeline_legal_unit.postal_country_iso_2,
            timeline_legal_unit.invalid_codes,
            timeline_legal_unit.establishment_ids,
            ARRAY[timeline_legal_unit.legal_unit_id] AS legal_unit_ids,
            ARRAY[timeline_legal_unit.enterprise_id] AS enterprise_ids,
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
            timeline_enterprise.secondary_activity_category_id,
            timeline_enterprise.secondary_activity_category_path,
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
            timeline_enterprise.physical_postal_code,
            timeline_enterprise.physical_postal_place,
            timeline_enterprise.physical_region_id,
            timeline_enterprise.physical_region_path,
            timeline_enterprise.physical_country_id,
            timeline_enterprise.physical_country_iso_2,
            timeline_enterprise.postal_address_part1,
            timeline_enterprise.postal_address_part2,
            timeline_enterprise.postal_address_part3,
            timeline_enterprise.postal_postal_code,
            timeline_enterprise.postal_postal_place,
            timeline_enterprise.postal_region_id,
            timeline_enterprise.postal_region_path,
            timeline_enterprise.postal_country_id,
            timeline_enterprise.postal_country_iso_2,
            timeline_enterprise.invalid_codes,
            timeline_enterprise.establishment_ids,
            timeline_enterprise.legal_unit_ids,
            ARRAY[timeline_enterprise.enterprise_id] AS enterprise_ids,
            NULL::jsonb AS stats,
            timeline_enterprise.stats_summary
           FROM timeline_enterprise
        )
 SELECT data.unit_type,
    data.unit_id,
    data.valid_after,
    data.valid_from,
    data.valid_to,
    data.external_idents,
    data.name,
    data.birth_date,
    data.death_date,
    data.search,
    data.primary_activity_category_id,
    data.primary_activity_category_path,
    data.secondary_activity_category_id,
    data.secondary_activity_category_path,
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
    data.physical_postal_code,
    data.physical_postal_place,
    data.physical_region_id,
    data.physical_region_path,
    data.physical_country_id,
    data.physical_country_iso_2,
    data.postal_address_part1,
    data.postal_address_part2,
    data.postal_address_part3,
    data.postal_postal_code,
    data.postal_postal_place,
    data.postal_region_id,
    data.postal_region_path,
    data.postal_country_id,
    data.postal_country_iso_2,
    data.invalid_codes,
    data.establishment_ids,
    data.legal_unit_ids,
    data.enterprise_ids,
    data.stats,
    data.stats_summary,
    COALESCE(array_length(data.establishment_ids, 1), 0) AS establishment_count,
    COALESCE(array_length(data.legal_unit_ids, 1), 0) AS legal_unit_count,
    COALESCE(array_length(data.enterprise_ids, 1), 0) AS enterprise_count,
    get_tag_paths(data.unit_type, data.unit_id) AS tag_paths
   FROM data;

```

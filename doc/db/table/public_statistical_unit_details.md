```sql
                                                   Materialized view "public.statistical_unit"
              Column              |          Type          | Collation | Nullable | Default | Storage  | Compression | Stats target | Description 
----------------------------------+------------------------+-----------+----------+---------+----------+-------------+--------------+-------------
 unit_type                        | statistical_unit_type  |           |          |         | plain    |             |              | 
 unit_id                          | integer                |           |          |         | plain    |             |              | 
 valid_after                      | date                   |           |          |         | plain    |             |              | 
 valid_from                       | date                   |           |          |         | plain    |             |              | 
 valid_to                         | date                   |           |          |         | plain    |             |              | 
 external_idents                  | jsonb                  |           |          |         | extended |             |              | 
 name                             | character varying(256) |           |          |         | extended |             |              | 
 birth_date                       | date                   |           |          |         | plain    |             |              | 
 death_date                       | date                   |           |          |         | plain    |             |              | 
 search                           | tsvector               |           |          |         | extended |             |              | 
 primary_activity_category_id     | integer                |           |          |         | plain    |             |              | 
 primary_activity_category_path   | ltree                  |           |          |         | extended |             |              | 
 primary_activity_category_code   | character varying      |           |          |         | extended |             |              | 
 secondary_activity_category_id   | integer                |           |          |         | plain    |             |              | 
 secondary_activity_category_path | ltree                  |           |          |         | extended |             |              | 
 secondary_activity_category_code | character varying      |           |          |         | extended |             |              | 
 activity_category_paths          | ltree[]                |           |          |         | extended |             |              | 
 sector_id                        | integer                |           |          |         | plain    |             |              | 
 sector_path                      | ltree                  |           |          |         | extended |             |              | 
 sector_code                      | character varying      |           |          |         | extended |             |              | 
 sector_name                      | text                   |           |          |         | extended |             |              | 
 data_source_ids                  | integer[]              |           |          |         | extended |             |              | 
 data_source_codes                | text[]                 |           |          |         | extended |             |              | 
 legal_form_id                    | integer                |           |          |         | plain    |             |              | 
 legal_form_code                  | text                   |           |          |         | extended |             |              | 
 legal_form_name                  | text                   |           |          |         | extended |             |              | 
 physical_address_part1           | character varying(200) |           |          |         | extended |             |              | 
 physical_address_part2           | character varying(200) |           |          |         | extended |             |              | 
 physical_address_part3           | character varying(200) |           |          |         | extended |             |              | 
 physical_postcode                | character varying(200) |           |          |         | extended |             |              | 
 physical_postplace               | character varying(200) |           |          |         | extended |             |              | 
 physical_region_id               | integer                |           |          |         | plain    |             |              | 
 physical_region_path             | ltree                  |           |          |         | extended |             |              | 
 physical_region_code             | character varying      |           |          |         | extended |             |              | 
 physical_country_id              | integer                |           |          |         | plain    |             |              | 
 physical_country_iso_2           | text                   |           |          |         | extended |             |              | 
 physical_latitude                | numeric(9,6)           |           |          |         | main     |             |              | 
 physical_longitude               | numeric(9,6)           |           |          |         | main     |             |              | 
 physical_altitude                | numeric(6,1)           |           |          |         | main     |             |              | 
 postal_address_part1             | character varying(200) |           |          |         | extended |             |              | 
 postal_address_part2             | character varying(200) |           |          |         | extended |             |              | 
 postal_address_part3             | character varying(200) |           |          |         | extended |             |              | 
 postal_postcode                  | character varying(200) |           |          |         | extended |             |              | 
 postal_postplace                 | character varying(200) |           |          |         | extended |             |              | 
 postal_region_id                 | integer                |           |          |         | plain    |             |              | 
 postal_region_path               | ltree                  |           |          |         | extended |             |              | 
 postal_region_code               | character varying      |           |          |         | extended |             |              | 
 postal_country_id                | integer                |           |          |         | plain    |             |              | 
 postal_country_iso_2             | text                   |           |          |         | extended |             |              | 
 postal_latitude                  | numeric(9,6)           |           |          |         | main     |             |              | 
 postal_longitude                 | numeric(9,6)           |           |          |         | main     |             |              | 
 postal_altitude                  | numeric(6,1)           |           |          |         | main     |             |              | 
 web_address                      | character varying(256) |           |          |         | extended |             |              | 
 email_address                    | character varying(50)  |           |          |         | extended |             |              | 
 phone_number                     | character varying(50)  |           |          |         | extended |             |              | 
 landline                         | character varying(50)  |           |          |         | extended |             |              | 
 mobile_number                    | character varying(50)  |           |          |         | extended |             |              | 
 fax_number                       | character varying(50)  |           |          |         | extended |             |              | 
 status_id                        | integer                |           |          |         | plain    |             |              | 
 status_code                      | character varying      |           |          |         | extended |             |              | 
 include_unit_in_reports          | boolean                |           |          |         | plain    |             |              | 
 invalid_codes                    | jsonb                  |           |          |         | extended |             |              | 
 has_legal_unit                   | boolean                |           |          |         | plain    |             |              | 
 establishment_ids                | integer[]              |           |          |         | extended |             |              | 
 legal_unit_ids                   | integer[]              |           |          |         | extended |             |              | 
 enterprise_ids                   | integer[]              |           |          |         | extended |             |              | 
 stats                            | jsonb                  |           |          |         | extended |             |              | 
 stats_summary                    | jsonb                  |           |          |         | extended |             |              | 
 establishment_count              | integer                |           |          |         | plain    |             |              | 
 legal_unit_count                 | integer                |           |          |         | plain    |             |              | 
 enterprise_count                 | integer                |           |          |         | plain    |             |              | 
 tag_paths                        | ltree[]                |           |          |         | extended |             |              | 
Indexes:
    "idx_gist_statistical_unit_activity_category_paths" gist (activity_category_paths)
    "idx_gist_statistical_unit_external_idents" gin (external_idents jsonb_path_ops)
    "idx_gist_statistical_unit_physical_region_path" gist (physical_region_path)
    "idx_gist_statistical_unit_primary_activity_category_path" gist (primary_activity_category_path)
    "idx_gist_statistical_unit_secondary_activity_category_path" gist (secondary_activity_category_path)
    "idx_gist_statistical_unit_sector_path" gist (sector_path)
    "idx_gist_statistical_unit_tag_paths" gist (tag_paths)
    "idx_statistical_unit_activity_category_paths" btree (activity_category_paths)
    "idx_statistical_unit_data_source_ids" gin (data_source_ids)
    "idx_statistical_unit_establishment_id" btree (unit_id)
    "idx_statistical_unit_external_idents" btree (external_idents)
    "idx_statistical_unit_invalid_codes" gin (invalid_codes)
    "idx_statistical_unit_invalid_codes_exists" btree (invalid_codes) WHERE invalid_codes IS NOT NULL
    "idx_statistical_unit_legal_form_id" btree (legal_form_id)
    "idx_statistical_unit_physical_country_id" btree (physical_country_id)
    "idx_statistical_unit_physical_region_id" btree (physical_region_id)
    "idx_statistical_unit_physical_region_path" btree (physical_region_path)
    "idx_statistical_unit_primary_activity_category_id" btree (primary_activity_category_id)
    "idx_statistical_unit_primary_activity_category_path" btree (primary_activity_category_path)
    "idx_statistical_unit_search" gin (search)
    "idx_statistical_unit_secondary_activity_category_id" btree (secondary_activity_category_id)
    "idx_statistical_unit_secondary_activity_category_path" btree (secondary_activity_category_path)
    "idx_statistical_unit_sector_id" btree (sector_id)
    "idx_statistical_unit_sector_path" btree (sector_path)
    "idx_statistical_unit_tag_paths" btree (tag_paths)
    "idx_statistical_unit_unit_type" btree (unit_type)
    "statistical_unit_key" UNIQUE, btree (valid_from, valid_to, unit_type, unit_id)
    "su_ei_stat_ident_idx" btree ((external_idents ->> 'stat_ident'::text))
    "su_ei_tax_ident_idx" btree ((external_idents ->> 'tax_ident'::text))
    "su_s_employees_idx" btree ((stats ->> 'employees'::text))
    "su_s_turnover_idx" btree ((stats ->> 'turnover'::text))
    "su_ss_employees_count_idx" btree (((stats_summary -> 'employees'::text) ->> 'count'::text))
    "su_ss_employees_sum_idx" btree (((stats_summary -> 'employees'::text) ->> 'sum'::text))
    "su_ss_turnover_count_idx" btree (((stats_summary -> 'turnover'::text) ->> 'count'::text))
    "su_ss_turnover_sum_idx" btree (((stats_summary -> 'turnover'::text) ->> 'sum'::text))
View definition:
 SELECT statistical_unit_def.unit_type,
    statistical_unit_def.unit_id,
    statistical_unit_def.valid_after,
    statistical_unit_def.valid_from,
    statistical_unit_def.valid_to,
    statistical_unit_def.external_idents,
    statistical_unit_def.name,
    statistical_unit_def.birth_date,
    statistical_unit_def.death_date,
    statistical_unit_def.search,
    statistical_unit_def.primary_activity_category_id,
    statistical_unit_def.primary_activity_category_path,
    statistical_unit_def.primary_activity_category_code,
    statistical_unit_def.secondary_activity_category_id,
    statistical_unit_def.secondary_activity_category_path,
    statistical_unit_def.secondary_activity_category_code,
    statistical_unit_def.activity_category_paths,
    statistical_unit_def.sector_id,
    statistical_unit_def.sector_path,
    statistical_unit_def.sector_code,
    statistical_unit_def.sector_name,
    statistical_unit_def.data_source_ids,
    statistical_unit_def.data_source_codes,
    statistical_unit_def.legal_form_id,
    statistical_unit_def.legal_form_code,
    statistical_unit_def.legal_form_name,
    statistical_unit_def.physical_address_part1,
    statistical_unit_def.physical_address_part2,
    statistical_unit_def.physical_address_part3,
    statistical_unit_def.physical_postcode,
    statistical_unit_def.physical_postplace,
    statistical_unit_def.physical_region_id,
    statistical_unit_def.physical_region_path,
    statistical_unit_def.physical_region_code,
    statistical_unit_def.physical_country_id,
    statistical_unit_def.physical_country_iso_2,
    statistical_unit_def.physical_latitude,
    statistical_unit_def.physical_longitude,
    statistical_unit_def.physical_altitude,
    statistical_unit_def.postal_address_part1,
    statistical_unit_def.postal_address_part2,
    statistical_unit_def.postal_address_part3,
    statistical_unit_def.postal_postcode,
    statistical_unit_def.postal_postplace,
    statistical_unit_def.postal_region_id,
    statistical_unit_def.postal_region_path,
    statistical_unit_def.postal_region_code,
    statistical_unit_def.postal_country_id,
    statistical_unit_def.postal_country_iso_2,
    statistical_unit_def.postal_latitude,
    statistical_unit_def.postal_longitude,
    statistical_unit_def.postal_altitude,
    statistical_unit_def.web_address,
    statistical_unit_def.email_address,
    statistical_unit_def.phone_number,
    statistical_unit_def.landline,
    statistical_unit_def.mobile_number,
    statistical_unit_def.fax_number,
    statistical_unit_def.status_id,
    statistical_unit_def.status_code,
    statistical_unit_def.include_unit_in_reports,
    statistical_unit_def.invalid_codes,
    statistical_unit_def.has_legal_unit,
    statistical_unit_def.establishment_ids,
    statistical_unit_def.legal_unit_ids,
    statistical_unit_def.enterprise_ids,
    statistical_unit_def.stats,
    statistical_unit_def.stats_summary,
    statistical_unit_def.establishment_count,
    statistical_unit_def.legal_unit_count,
    statistical_unit_def.enterprise_count,
    statistical_unit_def.tag_paths
   FROM statistical_unit_def;
Access method: heap

```

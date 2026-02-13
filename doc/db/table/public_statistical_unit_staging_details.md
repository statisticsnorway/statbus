```sql
                                                                                     Table "public.statistical_unit_staging"
              Column              |           Type           | Collation | Nullable |                                Default                                | Storage  | Compression | Stats target | Description 
----------------------------------+--------------------------+-----------+----------+-----------------------------------------------------------------------+----------+-------------+--------------+-------------
 unit_type                        | statistical_unit_type    |           | not null |                                                                       | plain    |             |              | 
 unit_id                          | integer                  |           | not null |                                                                       | plain    |             |              | 
 valid_from                       | date                     |           |          |                                                                       | plain    |             |              | 
 valid_to                         | date                     |           |          |                                                                       | plain    |             |              | 
 valid_until                      | date                     |           |          |                                                                       | plain    |             |              | 
 external_idents                  | jsonb                    |           |          |                                                                       | extended |             |              | 
 name                             | character varying        |           |          |                                                                       | extended |             |              | 
 birth_date                       | date                     |           |          |                                                                       | plain    |             |              | 
 death_date                       | date                     |           |          |                                                                       | plain    |             |              | 
 search                           | tsvector                 |           |          |                                                                       | extended |             |              | 
 primary_activity_category_id     | integer                  |           |          |                                                                       | plain    |             |              | 
 primary_activity_category_path   | ltree                    |           |          |                                                                       | extended |             |              | 
 primary_activity_category_code   | character varying        |           |          |                                                                       | extended |             |              | 
 secondary_activity_category_id   | integer                  |           |          |                                                                       | plain    |             |              | 
 secondary_activity_category_path | ltree                    |           |          |                                                                       | extended |             |              | 
 secondary_activity_category_code | character varying        |           |          |                                                                       | extended |             |              | 
 activity_category_paths          | ltree[]                  |           |          |                                                                       | extended |             |              | 
 sector_id                        | integer                  |           |          |                                                                       | plain    |             |              | 
 sector_path                      | ltree                    |           |          |                                                                       | extended |             |              | 
 sector_code                      | character varying        |           |          |                                                                       | extended |             |              | 
 sector_name                      | text                     |           |          |                                                                       | extended |             |              | 
 data_source_ids                  | integer[]                |           |          |                                                                       | extended |             |              | 
 data_source_codes                | text[]                   |           |          |                                                                       | extended |             |              | 
 legal_form_id                    | integer                  |           |          |                                                                       | plain    |             |              | 
 legal_form_code                  | text                     |           |          |                                                                       | extended |             |              | 
 legal_form_name                  | text                     |           |          |                                                                       | extended |             |              | 
 physical_address_part1           | character varying(200)   |           |          |                                                                       | extended |             |              | 
 physical_address_part2           | character varying(200)   |           |          |                                                                       | extended |             |              | 
 physical_address_part3           | character varying(200)   |           |          |                                                                       | extended |             |              | 
 physical_postcode                | character varying(200)   |           |          |                                                                       | extended |             |              | 
 physical_postplace               | character varying(200)   |           |          |                                                                       | extended |             |              | 
 physical_region_id               | integer                  |           |          |                                                                       | plain    |             |              | 
 physical_region_path             | ltree                    |           |          |                                                                       | extended |             |              | 
 physical_region_code             | character varying        |           |          |                                                                       | extended |             |              | 
 physical_country_id              | integer                  |           |          |                                                                       | plain    |             |              | 
 physical_country_iso_2           | text                     |           |          |                                                                       | extended |             |              | 
 physical_latitude                | numeric(9,6)             |           |          |                                                                       | main     |             |              | 
 physical_longitude               | numeric(9,6)             |           |          |                                                                       | main     |             |              | 
 physical_altitude                | numeric(6,1)             |           |          |                                                                       | main     |             |              | 
 domestic                         | boolean                  |           |          |                                                                       | plain    |             |              | 
 postal_address_part1             | character varying(200)   |           |          |                                                                       | extended |             |              | 
 postal_address_part2             | character varying(200)   |           |          |                                                                       | extended |             |              | 
 postal_address_part3             | character varying(200)   |           |          |                                                                       | extended |             |              | 
 postal_postcode                  | character varying(200)   |           |          |                                                                       | extended |             |              | 
 postal_postplace                 | character varying(200)   |           |          |                                                                       | extended |             |              | 
 postal_region_id                 | integer                  |           |          |                                                                       | plain    |             |              | 
 postal_region_path               | ltree                    |           |          |                                                                       | extended |             |              | 
 postal_region_code               | character varying        |           |          |                                                                       | extended |             |              | 
 postal_country_id                | integer                  |           |          |                                                                       | plain    |             |              | 
 postal_country_iso_2             | text                     |           |          |                                                                       | extended |             |              | 
 postal_latitude                  | numeric(9,6)             |           |          |                                                                       | main     |             |              | 
 postal_longitude                 | numeric(9,6)             |           |          |                                                                       | main     |             |              | 
 postal_altitude                  | numeric(6,1)             |           |          |                                                                       | main     |             |              | 
 web_address                      | character varying(256)   |           |          |                                                                       | extended |             |              | 
 email_address                    | character varying(50)    |           |          |                                                                       | extended |             |              | 
 phone_number                     | character varying(50)    |           |          |                                                                       | extended |             |              | 
 landline                         | character varying(50)    |           |          |                                                                       | extended |             |              | 
 mobile_number                    | character varying(50)    |           |          |                                                                       | extended |             |              | 
 fax_number                       | character varying(50)    |           |          |                                                                       | extended |             |              | 
 unit_size_id                     | integer                  |           |          |                                                                       | plain    |             |              | 
 unit_size_code                   | text                     |           |          |                                                                       | extended |             |              | 
 status_id                        | integer                  |           |          |                                                                       | plain    |             |              | 
 status_code                      | character varying        |           |          |                                                                       | extended |             |              | 
 used_for_counting                | boolean                  |           |          |                                                                       | plain    |             |              | 
 last_edit_comment                | character varying(512)   |           |          |                                                                       | extended |             |              | 
 last_edit_by_user_id             | integer                  |           |          |                                                                       | plain    |             |              | 
 last_edit_at                     | timestamp with time zone |           |          |                                                                       | plain    |             |              | 
 invalid_codes                    | jsonb                    |           |          |                                                                       | extended |             |              | 
 has_legal_unit                   | boolean                  |           |          |                                                                       | plain    |             |              | 
 related_establishment_ids        | integer[]                |           |          |                                                                       | extended |             |              | 
 excluded_establishment_ids       | integer[]                |           |          |                                                                       | extended |             |              | 
 included_establishment_ids       | integer[]                |           |          |                                                                       | extended |             |              | 
 related_legal_unit_ids           | integer[]                |           |          |                                                                       | extended |             |              | 
 excluded_legal_unit_ids          | integer[]                |           |          |                                                                       | extended |             |              | 
 included_legal_unit_ids          | integer[]                |           |          |                                                                       | extended |             |              | 
 related_enterprise_ids           | integer[]                |           |          |                                                                       | extended |             |              | 
 excluded_enterprise_ids          | integer[]                |           |          |                                                                       | extended |             |              | 
 included_enterprise_ids          | integer[]                |           |          |                                                                       | extended |             |              | 
 stats                            | jsonb                    |           |          |                                                                       | extended |             |              | 
 stats_summary                    | jsonb                    |           |          |                                                                       | extended |             |              | 
 included_establishment_count     | integer                  |           |          |                                                                       | plain    |             |              | 
 included_legal_unit_count        | integer                  |           |          |                                                                       | plain    |             |              | 
 included_enterprise_count        | integer                  |           |          |                                                                       | plain    |             |              | 
 tag_paths                        | ltree[]                  |           |          |                                                                       | extended |             |              | 
 report_partition_seq             | integer                  |           |          | generated always as (report_partition_seq(unit_type, unit_id)) stored | plain    |             |              | 
Not-null constraints:
    "statistical_unit_unit_type_not_null" NOT NULL "unit_type"
    "statistical_unit_unit_id_not_null" NOT NULL "unit_id"
Access method: heap

```

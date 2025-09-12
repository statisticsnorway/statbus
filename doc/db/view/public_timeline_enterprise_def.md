```sql
                            View "public.timeline_enterprise_def"
              Column              |           Type           | Collation | Nullable | Default 
----------------------------------+--------------------------+-----------+----------+---------
 unit_type                        | statistical_unit_type    |           |          | 
 unit_id                          | integer                  |           |          | 
 valid_from                       | date                     |           |          | 
 valid_to                         | date                     |           |          | 
 valid_until                      | date                     |           |          | 
 name                             | character varying(256)   |           |          | 
 birth_date                       | date                     |           |          | 
 death_date                       | date                     |           |          | 
 search                           | tsvector                 |           |          | 
 primary_activity_category_id     | integer                  |           |          | 
 primary_activity_category_path   | ltree                    |           |          | 
 primary_activity_category_code   | character varying        |           |          | 
 secondary_activity_category_id   | integer                  |           |          | 
 secondary_activity_category_path | ltree                    |           |          | 
 secondary_activity_category_code | character varying        |           |          | 
 activity_category_paths          | ltree[]                  |           |          | 
 sector_id                        | integer                  |           |          | 
 sector_path                      | ltree                    |           |          | 
 sector_code                      | character varying        |           |          | 
 sector_name                      | text                     |           |          | 
 data_source_ids                  | integer[]                |           |          | 
 data_source_codes                | text[]                   |           |          | 
 legal_form_id                    | integer                  |           |          | 
 legal_form_code                  | text                     |           |          | 
 legal_form_name                  | text                     |           |          | 
 physical_address_part1           | character varying(200)   |           |          | 
 physical_address_part2           | character varying(200)   |           |          | 
 physical_address_part3           | character varying(200)   |           |          | 
 physical_postcode                | character varying(200)   |           |          | 
 physical_postplace               | character varying(200)   |           |          | 
 physical_region_id               | integer                  |           |          | 
 physical_region_path             | ltree                    |           |          | 
 physical_region_code             | character varying        |           |          | 
 physical_country_id              | integer                  |           |          | 
 physical_country_iso_2           | text                     |           |          | 
 physical_latitude                | numeric(9,6)             |           |          | 
 physical_longitude               | numeric(9,6)             |           |          | 
 physical_altitude                | numeric(6,1)             |           |          | 
 postal_address_part1             | character varying(200)   |           |          | 
 postal_address_part2             | character varying(200)   |           |          | 
 postal_address_part3             | character varying(200)   |           |          | 
 postal_postcode                  | character varying(200)   |           |          | 
 postal_postplace                 | character varying(200)   |           |          | 
 postal_region_id                 | integer                  |           |          | 
 postal_region_path               | ltree                    |           |          | 
 postal_region_code               | character varying        |           |          | 
 postal_country_id                | integer                  |           |          | 
 postal_country_iso_2             | text                     |           |          | 
 postal_latitude                  | numeric(9,6)             |           |          | 
 postal_longitude                 | numeric(9,6)             |           |          | 
 postal_altitude                  | numeric(6,1)             |           |          | 
 web_address                      | character varying(256)   |           |          | 
 email_address                    | character varying(50)    |           |          | 
 phone_number                     | character varying(50)    |           |          | 
 landline                         | character varying(50)    |           |          | 
 mobile_number                    | character varying(50)    |           |          | 
 fax_number                       | character varying(50)    |           |          | 
 unit_size_id                     | integer                  |           |          | 
 unit_size_code                   | text                     |           |          | 
 status_id                        | integer                  |           |          | 
 status_code                      | character varying        |           |          | 
 include_unit_in_reports          | boolean                  |           |          | 
 last_edit_comment                | character varying(512)   |           |          | 
 last_edit_by_user_id             | integer                  |           |          | 
 last_edit_at                     | timestamp with time zone |           |          | 
 invalid_codes                    | jsonb                    |           |          | 
 has_legal_unit                   | boolean                  |           |          | 
 related_establishment_ids        | integer[]                |           |          | 
 excluded_establishment_ids       | integer[]                |           |          | 
 included_establishment_ids       | integer[]                |           |          | 
 related_legal_unit_ids           | integer[]                |           |          | 
 excluded_legal_unit_ids          | integer[]                |           |          | 
 included_legal_unit_ids          | integer[]                |           |          | 
 related_enterprise_ids           | integer[]                |           |          | 
 excluded_enterprise_ids          | integer[]                |           |          | 
 included_enterprise_ids          | integer[]                |           |          | 
 enterprise_id                    | integer                  |           |          | 
 primary_establishment_id         | integer                  |           |          | 
 primary_legal_unit_id            | integer                  |           |          | 
 stats_summary                    | jsonb                    |           |          | 

```

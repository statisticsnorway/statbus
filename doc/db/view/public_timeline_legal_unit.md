```sql
                             View "public.timeline_legal_unit"
              Column              |          Type          | Collation | Nullable | Default 
----------------------------------+------------------------+-----------+----------+---------
 unit_type                        | statistical_unit_type  |           |          | 
 unit_id                          | integer                |           |          | 
 valid_after                      | date                   |           |          | 
 valid_from                       | date                   |           |          | 
 valid_to                         | date                   |           |          | 
 name                             | character varying(256) |           |          | 
 birth_date                       | date                   |           |          | 
 death_date                       | date                   |           |          | 
 search                           | tsvector               |           |          | 
 primary_activity_category_id     | integer                |           |          | 
 primary_activity_category_path   | ltree                  |           |          | 
 secondary_activity_category_id   | integer                |           |          | 
 secondary_activity_category_path | ltree                  |           |          | 
 activity_category_paths          | ltree[]                |           |          | 
 sector_id                        | integer                |           |          | 
 sector_path                      | ltree                  |           |          | 
 sector_code                      | character varying      |           |          | 
 sector_name                      | text                   |           |          | 
 data_source_ids                  | integer[]              |           |          | 
 data_source_codes                | text[]                 |           |          | 
 legal_form_id                    | integer                |           |          | 
 legal_form_code                  | text                   |           |          | 
 legal_form_name                  | text                   |           |          | 
 physical_address_part1           | character varying(200) |           |          | 
 physical_address_part2           | character varying(200) |           |          | 
 physical_address_part3           | character varying(200) |           |          | 
 physical_postal_code             | character varying(200) |           |          | 
 physical_postal_place            | character varying(200) |           |          | 
 physical_region_id               | integer                |           |          | 
 physical_region_path             | ltree                  |           |          | 
 physical_country_id              | integer                |           |          | 
 physical_country_iso_2           | text                   |           |          | 
 postal_address_part1             | character varying(200) |           |          | 
 postal_address_part2             | character varying(200) |           |          | 
 postal_address_part3             | character varying(200) |           |          | 
 postal_postal_code               | character varying(200) |           |          | 
 postal_postal_place              | character varying(200) |           |          | 
 postal_region_id                 | integer                |           |          | 
 postal_region_path               | ltree                  |           |          | 
 postal_country_id                | integer                |           |          | 
 postal_country_iso_2             | text                   |           |          | 
 invalid_codes                    | jsonb                  |           |          | 
 establishment_ids                | integer[]              |           |          | 
 legal_unit_id                    | integer                |           |          | 
 enterprise_id                    | integer                |           |          | 
 stats                            | jsonb                  |           |          | 
 stats_summary                    | jsonb                  |           |          | 

```

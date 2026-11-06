```sql
                                         View "public.timeline_legal_unit_def"
              Column              |           Type           | Collation | Nullable | Default | Storage  | Description 
----------------------------------+--------------------------+-----------+----------+---------+----------+-------------
 unit_type                        | statistical_unit_type    |           |          |         | plain    | 
 unit_id                          | integer                  |           |          |         | plain    | 
 valid_from                       | date                     |           |          |         | plain    | 
 valid_to                         | date                     |           |          |         | plain    | 
 valid_until                      | date                     |           |          |         | plain    | 
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
 domestic                         | boolean                  |           |          |         | plain    | 
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
 used_for_counting                | boolean                  |           |          |         | plain    | 
 last_edit_comment                | character varying(512)   |           |          |         | extended | 
 last_edit_by_user_id             | integer                  |           |          |         | plain    | 
 last_edit_at                     | timestamp with time zone |           |          |         | plain    | 
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
 legal_unit_id                    | integer                  |           |          |         | plain    | 
 enterprise_id                    | integer                  |           |          |         | plain    | 
 primary_for_enterprise           | boolean                  |           |          |         | plain    | 
 stats                            | jsonb                    |           |          |         | extended | 
 stats_summary                    | jsonb                    |           |          |         | extended | 
View definition:
 SELECT unit_type,
    unit_id,
    valid_from,
    valid_to,
    valid_until,
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
    domestic,
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
    used_for_counting,
    last_edit_comment,
    last_edit_by_user_id,
    last_edit_at,
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
    legal_unit_id,
    enterprise_id,
    primary_for_enterprise,
    stats,
    stats_summary
   FROM timeline_legal_unit_def_for(NULL::integer[]) timeline_legal_unit_def_for(unit_type, unit_id, valid_from, valid_to, valid_until, name, birth_date, death_date, search, primary_activity_category_id, primary_activity_category_path, primary_activity_category_code, secondary_activity_category_id, secondary_activity_category_path, secondary_activity_category_code, activity_category_paths, sector_id, sector_path, sector_code, sector_name, data_source_ids, data_source_codes, legal_form_id, legal_form_code, legal_form_name, physical_address_part1, physical_address_part2, physical_address_part3, physical_postcode, physical_postplace, physical_region_id, physical_region_path, physical_region_code, physical_country_id, physical_country_iso_2, physical_latitude, physical_longitude, physical_altitude, domestic, postal_address_part1, postal_address_part2, postal_address_part3, postal_postcode, postal_postplace, postal_region_id, postal_region_path, postal_region_code, postal_country_id, postal_country_iso_2, postal_latitude, postal_longitude, postal_altitude, web_address, email_address, phone_number, landline, mobile_number, fax_number, unit_size_id, unit_size_code, status_id, status_code, used_for_counting, last_edit_comment, last_edit_by_user_id, last_edit_at, has_legal_unit, related_establishment_ids, excluded_establishment_ids, included_establishment_ids, related_legal_unit_ids, excluded_legal_unit_ids, included_legal_unit_ids, related_enterprise_ids, excluded_enterprise_ids, included_enterprise_ids, legal_unit_id, enterprise_id, primary_for_enterprise, stats, stats_summary);
Options: security_invoker=on

```

**Comment:** Every timeline_legal_unit row, as computed now: timeline_legal_unit_def_for(NULL). The full refresh reads it in ranges of unit ids.

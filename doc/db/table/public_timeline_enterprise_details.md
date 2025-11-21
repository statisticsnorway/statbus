```sql
                                                         Table "public.timeline_enterprise"
              Column              |           Type           | Collation | Nullable | Default | Storage  | Compression | Stats target | Description 
----------------------------------+--------------------------+-----------+----------+---------+----------+-------------+--------------+-------------
 unit_type                        | statistical_unit_type    |           | not null |         | plain    |             |              | 
 unit_id                          | integer                  |           | not null |         | plain    |             |              | 
 valid_from                       | date                     |           | not null |         | plain    |             |              | 
 valid_to                         | date                     |           | not null |         | plain    |             |              | 
 valid_until                      | date                     |           | not null |         | plain    |             |              | 
 name                             | text                     |           |          |         | extended |             |              | 
 birth_date                       | date                     |           |          |         | plain    |             |              | 
 death_date                       | date                     |           |          |         | plain    |             |              | 
 search                           | tsvector                 |           |          |         | extended |             |              | 
 primary_activity_category_id     | integer                  |           |          |         | plain    |             |              | 
 primary_activity_category_path   | ltree                    |           |          |         | extended |             |              | 
 primary_activity_category_code   | character varying        |           |          |         | extended |             |              | 
 secondary_activity_category_id   | integer                  |           |          |         | plain    |             |              | 
 secondary_activity_category_path | ltree                    |           |          |         | extended |             |              | 
 secondary_activity_category_code | character varying        |           |          |         | extended |             |              | 
 activity_category_paths          | ltree[]                  |           |          |         | extended |             |              | 
 sector_id                        | integer                  |           |          |         | plain    |             |              | 
 sector_path                      | ltree                    |           |          |         | extended |             |              | 
 sector_code                      | character varying        |           |          |         | extended |             |              | 
 sector_name                      | text                     |           |          |         | extended |             |              | 
 data_source_ids                  | integer[]                |           |          |         | extended |             |              | 
 data_source_codes                | text[]                   |           |          |         | extended |             |              | 
 legal_form_id                    | integer                  |           |          |         | plain    |             |              | 
 legal_form_code                  | text                     |           |          |         | extended |             |              | 
 legal_form_name                  | text                     |           |          |         | extended |             |              | 
 physical_address_part1           | character varying(200)   |           |          |         | extended |             |              | 
 physical_address_part2           | character varying(200)   |           |          |         | extended |             |              | 
 physical_address_part3           | character varying(200)   |           |          |         | extended |             |              | 
 physical_postcode                | character varying(200)   |           |          |         | extended |             |              | 
 physical_postplace               | character varying(200)   |           |          |         | extended |             |              | 
 physical_region_id               | integer                  |           |          |         | plain    |             |              | 
 physical_region_path             | ltree                    |           |          |         | extended |             |              | 
 physical_region_code             | character varying        |           |          |         | extended |             |              | 
 physical_country_id              | integer                  |           |          |         | plain    |             |              | 
 physical_country_iso_2           | text                     |           |          |         | extended |             |              | 
 physical_latitude                | numeric(9,6)             |           |          |         | main     |             |              | 
 physical_longitude               | numeric(9,6)             |           |          |         | main     |             |              | 
 physical_altitude                | numeric(6,1)             |           |          |         | main     |             |              | 
 domestic                         | boolean                  |           |          |         | plain    |             |              | 
 postal_address_part1             | character varying(200)   |           |          |         | extended |             |              | 
 postal_address_part2             | character varying(200)   |           |          |         | extended |             |              | 
 postal_address_part3             | character varying(200)   |           |          |         | extended |             |              | 
 postal_postcode                  | character varying(200)   |           |          |         | extended |             |              | 
 postal_postplace                 | character varying(200)   |           |          |         | extended |             |              | 
 postal_region_id                 | integer                  |           |          |         | plain    |             |              | 
 postal_region_path               | ltree                    |           |          |         | extended |             |              | 
 postal_region_code               | character varying        |           |          |         | extended |             |              | 
 postal_country_id                | integer                  |           |          |         | plain    |             |              | 
 postal_country_iso_2             | text                     |           |          |         | extended |             |              | 
 postal_latitude                  | numeric(9,6)             |           |          |         | main     |             |              | 
 postal_longitude                 | numeric(9,6)             |           |          |         | main     |             |              | 
 postal_altitude                  | numeric(6,1)             |           |          |         | main     |             |              | 
 web_address                      | character varying(256)   |           |          |         | extended |             |              | 
 email_address                    | character varying(50)    |           |          |         | extended |             |              | 
 phone_number                     | character varying(50)    |           |          |         | extended |             |              | 
 landline                         | character varying(50)    |           |          |         | extended |             |              | 
 mobile_number                    | character varying(50)    |           |          |         | extended |             |              | 
 fax_number                       | character varying(50)    |           |          |         | extended |             |              | 
 unit_size_id                     | integer                  |           |          |         | plain    |             |              | 
 unit_size_code                   | text                     |           |          |         | extended |             |              | 
 status_id                        | integer                  |           |          |         | plain    |             |              | 
 status_code                      | character varying        |           |          |         | extended |             |              | 
 used_for_counting                | boolean                  |           |          |         | plain    |             |              | 
 last_edit_comment                | character varying(512)   |           |          |         | extended |             |              | 
 last_edit_by_user_id             | integer                  |           |          |         | plain    |             |              | 
 last_edit_at                     | timestamp with time zone |           |          |         | plain    |             |              | 
 invalid_codes                    | jsonb                    |           |          |         | extended |             |              | 
 has_legal_unit                   | boolean                  |           |          |         | plain    |             |              | 
 related_establishment_ids        | integer[]                |           |          |         | extended |             |              | 
 excluded_establishment_ids       | integer[]                |           |          |         | extended |             |              | 
 included_establishment_ids       | integer[]                |           |          |         | extended |             |              | 
 related_legal_unit_ids           | integer[]                |           |          |         | extended |             |              | 
 excluded_legal_unit_ids          | integer[]                |           |          |         | extended |             |              | 
 included_legal_unit_ids          | integer[]                |           |          |         | extended |             |              | 
 related_enterprise_ids           | integer[]                |           |          |         | extended |             |              | 
 excluded_enterprise_ids          | integer[]                |           |          |         | extended |             |              | 
 included_enterprise_ids          | integer[]                |           |          |         | extended |             |              | 
 enterprise_id                    | integer                  |           |          |         | plain    |             |              | 
 primary_establishment_id         | integer                  |           |          |         | plain    |             |              | 
 primary_legal_unit_id            | integer                  |           |          |         | plain    |             |              | 
 stats_summary                    | jsonb                    |           |          |         | extended |             |              | 
Indexes:
    "timeline_enterprise_pkey" PRIMARY KEY, btree (unit_type, unit_id, valid_from)
    "idx_timeline_enterprise_related_establishment_ids" gin (related_establishment_ids)
    "idx_timeline_enterprise_related_legal_unit_ids" gin (related_legal_unit_ids)
    "idx_timeline_enterprise_unit_daterange" gist (daterange(valid_from, valid_until, '[)'::text), unit_id)
    "idx_timeline_enterprise_valid_period" btree (valid_from, valid_until)
Policies:
    POLICY "timeline_enterprise_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "timeline_enterprise_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "timeline_enterprise_regular_user_read" FOR SELECT
      TO regular_user
      USING (true)
Not-null constraints:
    "timeline_enterprise_unit_type_not_null" NOT NULL "unit_type"
    "timeline_enterprise_unit_id_not_null" NOT NULL "unit_id"
    "timeline_enterprise_valid_from_not_null" NOT NULL "valid_from"
    "timeline_enterprise_valid_to_not_null" NOT NULL "valid_to"
    "timeline_enterprise_valid_until_not_null" NOT NULL "valid_until"
Access method: heap

```

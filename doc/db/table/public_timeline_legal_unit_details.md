```sql
                                                         Table "public.timeline_legal_unit"
              Column              |           Type           | Collation | Nullable | Default | Storage  | Compression | Stats target | Description 
----------------------------------+--------------------------+-----------+----------+---------+----------+-------------+--------------+-------------
 unit_type                        | statistical_unit_type    |           | not null |         | plain    |             |              | 
 unit_id                          | integer                  |           | not null |         | plain    |             |              | 
 valid_from                       | date                     |           | not null |         | plain    |             |              | 
 valid_to                         | date                     |           | not null |         | plain    |             |              | 
 valid_until                      | date                     |           | not null |         | plain    |             |              | 
 name                             | character varying(256)   |           |          |         | extended |             |              | 
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
 include_unit_in_reports          | boolean                  |           |          |         | plain    |             |              | 
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
 legal_unit_id                    | integer                  |           |          |         | plain    |             |              | 
 enterprise_id                    | integer                  |           |          |         | plain    |             |              | 
 primary_for_enterprise           | boolean                  |           |          |         | plain    |             |              | 
 stats                            | jsonb                    |           |          |         | extended |             |              | 
 stats_summary                    | jsonb                    |           |          |         | extended |             |              | 
Indexes:
    "timeline_legal_unit_pkey" PRIMARY KEY, btree (unit_type, unit_id, valid_from)
    "idx_timeline_legal_unit_daterange" gist (daterange(valid_from, valid_until, '[)'::text))
    "idx_timeline_legal_unit_enterprise_id" btree (enterprise_id)
    "idx_timeline_legal_unit_legal_unit_id" btree (legal_unit_id) WHERE legal_unit_id IS NOT NULL
    "idx_timeline_legal_unit_primary_for_enterprise" btree (primary_for_enterprise) WHERE primary_for_enterprise = true
    "idx_timeline_legal_unit_related_establishment_ids" gin (related_establishment_ids)
    "idx_timeline_legal_unit_valid_period" btree (valid_from, valid_until)
Policies:
    POLICY "timeline_legal_unit_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "timeline_legal_unit_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "timeline_legal_unit_regular_user_read" FOR SELECT
      TO regular_user
      USING (true)
Access method: heap

```

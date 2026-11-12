```sql
                                                                                      Table "public.statistical_unit"
              Column              |           Type           | Collation | Nullable |                             Default                             | Storage  | Compression | Stats target | Description 
----------------------------------+--------------------------+-----------+----------+-----------------------------------------------------------------+----------+-------------+--------------+-------------
 unit_type                        | statistical_unit_type    |           | not null |                                                                 | plain    |             |              | 
 unit_id                          | integer                  |           | not null |                                                                 | plain    |             |              | 
 valid_from                       | date                     |           |          |                                                                 | plain    |             |              | 
 valid_to                         | date                     |           |          |                                                                 | plain    |             |              | 
 valid_until                      | date                     |           |          |                                                                 | plain    |             |              | 
 external_idents                  | jsonb                    |           |          |                                                                 | extended |             |              | 
 name                             | character varying        |           |          |                                                                 | extended |             |              | 
 birth_date                       | date                     |           |          |                                                                 | plain    |             |              | 
 death_date                       | date                     |           |          |                                                                 | plain    |             |              | 
 search                           | tsvector                 |           |          |                                                                 | extended |             |              | 
 primary_activity_category_id     | integer                  |           |          |                                                                 | plain    |             |              | 
 primary_activity_category_path   | ltree                    |           |          |                                                                 | extended |             |              | 
 primary_activity_category_code   | character varying        |           |          |                                                                 | extended |             |              | 
 secondary_activity_category_id   | integer                  |           |          |                                                                 | plain    |             |              | 
 secondary_activity_category_path | ltree                    |           |          |                                                                 | extended |             |              | 
 secondary_activity_category_code | character varying        |           |          |                                                                 | extended |             |              | 
 activity_category_paths          | ltree[]                  |           |          |                                                                 | extended |             |              | 
 sector_id                        | integer                  |           |          |                                                                 | plain    |             |              | 
 sector_path                      | ltree                    |           |          |                                                                 | extended |             |              | 
 sector_code                      | character varying        |           |          |                                                                 | extended |             |              | 
 sector_name                      | text                     |           |          |                                                                 | extended |             |              | 
 data_source_ids                  | integer[]                |           |          |                                                                 | extended |             |              | 
 data_source_codes                | text[]                   |           |          |                                                                 | extended |             |              | 
 legal_form_id                    | integer                  |           |          |                                                                 | plain    |             |              | 
 legal_form_code                  | text                     |           |          |                                                                 | extended |             |              | 
 legal_form_name                  | text                     |           |          |                                                                 | extended |             |              | 
 physical_address_part1           | character varying(200)   |           |          |                                                                 | extended |             |              | 
 physical_address_part2           | character varying(200)   |           |          |                                                                 | extended |             |              | 
 physical_address_part3           | character varying(200)   |           |          |                                                                 | extended |             |              | 
 physical_postcode                | character varying(200)   |           |          |                                                                 | extended |             |              | 
 physical_postplace               | character varying(200)   |           |          |                                                                 | extended |             |              | 
 physical_region_id               | integer                  |           |          |                                                                 | plain    |             |              | 
 physical_region_path             | ltree                    |           |          |                                                                 | extended |             |              | 
 physical_region_code             | character varying        |           |          |                                                                 | extended |             |              | 
 physical_country_id              | integer                  |           |          |                                                                 | plain    |             |              | 
 physical_country_iso_2           | text                     |           |          |                                                                 | extended |             |              | 
 physical_latitude                | numeric(9,6)             |           |          |                                                                 | main     |             |              | 
 physical_longitude               | numeric(9,6)             |           |          |                                                                 | main     |             |              | 
 physical_altitude                | numeric(6,1)             |           |          |                                                                 | main     |             |              | 
 domestic                         | boolean                  |           |          |                                                                 | plain    |             |              | 
 postal_address_part1             | character varying(200)   |           |          |                                                                 | extended |             |              | 
 postal_address_part2             | character varying(200)   |           |          |                                                                 | extended |             |              | 
 postal_address_part3             | character varying(200)   |           |          |                                                                 | extended |             |              | 
 postal_postcode                  | character varying(200)   |           |          |                                                                 | extended |             |              | 
 postal_postplace                 | character varying(200)   |           |          |                                                                 | extended |             |              | 
 postal_region_id                 | integer                  |           |          |                                                                 | plain    |             |              | 
 postal_region_path               | ltree                    |           |          |                                                                 | extended |             |              | 
 postal_region_code               | character varying        |           |          |                                                                 | extended |             |              | 
 postal_country_id                | integer                  |           |          |                                                                 | plain    |             |              | 
 postal_country_iso_2             | text                     |           |          |                                                                 | extended |             |              | 
 postal_latitude                  | numeric(9,6)             |           |          |                                                                 | main     |             |              | 
 postal_longitude                 | numeric(9,6)             |           |          |                                                                 | main     |             |              | 
 postal_altitude                  | numeric(6,1)             |           |          |                                                                 | main     |             |              | 
 web_address                      | character varying(256)   |           |          |                                                                 | extended |             |              | 
 email_address                    | character varying(50)    |           |          |                                                                 | extended |             |              | 
 phone_number                     | character varying(50)    |           |          |                                                                 | extended |             |              | 
 landline                         | character varying(50)    |           |          |                                                                 | extended |             |              | 
 mobile_number                    | character varying(50)    |           |          |                                                                 | extended |             |              | 
 fax_number                       | character varying(50)    |           |          |                                                                 | extended |             |              | 
 unit_size_id                     | integer                  |           |          |                                                                 | plain    |             |              | 
 unit_size_code                   | text                     |           |          |                                                                 | extended |             |              | 
 status_id                        | integer                  |           |          |                                                                 | plain    |             |              | 
 status_code                      | character varying        |           |          |                                                                 | extended |             |              | 
 used_for_counting                | boolean                  |           |          |                                                                 | plain    |             |              | 
 last_edit_comment                | character varying(512)   |           |          |                                                                 | extended |             |              | 
 last_edit_by_user_id             | integer                  |           |          |                                                                 | plain    |             |              | 
 last_edit_at                     | timestamp with time zone |           |          |                                                                 | plain    |             |              | 
 has_legal_unit                   | boolean                  |           |          |                                                                 | plain    |             |              | 
 related_establishment_ids        | integer[]                |           |          |                                                                 | extended |             |              | 
 excluded_establishment_ids       | integer[]                |           |          |                                                                 | extended |             |              | 
 included_establishment_ids       | integer[]                |           |          |                                                                 | extended |             |              | 
 related_legal_unit_ids           | integer[]                |           |          |                                                                 | extended |             |              | 
 excluded_legal_unit_ids          | integer[]                |           |          |                                                                 | extended |             |              | 
 included_legal_unit_ids          | integer[]                |           |          |                                                                 | extended |             |              | 
 related_enterprise_ids           | integer[]                |           |          |                                                                 | extended |             |              | 
 excluded_enterprise_ids          | integer[]                |           |          |                                                                 | extended |             |              | 
 included_enterprise_ids          | integer[]                |           |          |                                                                 | extended |             |              | 
 stats                            | jsonb                    |           |          |                                                                 | extended |             |              | 
 stats_summary                    | jsonb                    |           |          |                                                                 | extended |             |              | 
 included_establishment_count     | integer                  |           |          |                                                                 | plain    |             |              | 
 included_legal_unit_count        | integer                  |           |          |                                                                 | plain    |             |              | 
 included_enterprise_count        | integer                  |           |          |                                                                 | plain    |             |              | 
 tag_paths                        | ltree[]                  |           |          |                                                                 | extended |             |              | 
 valid_range                      | daterange                |           | not null | generated always as (daterange(valid_from, valid_until)) stored | extended |             |              | 
 hash_slot                        | integer                  |           |          |                                                                 | plain    |             |              | 
Indexes:
    "statistical_unit_temporal_pk" PRIMARY KEY (unit_type, unit_id, valid_range WITHOUT OVERLAPS)
    "idx_gist_statistical_unit_external_idents" gin (external_idents jsonb_path_ops)
    "idx_gist_statistical_unit_physical_region_path" gist (physical_region_path)
    "idx_gist_statistical_unit_primary_activity_category_path" gist (primary_activity_category_path)
    "idx_gist_statistical_unit_sector_path" gist (sector_path)
    "idx_gist_statistical_unit_tag_paths" gist (tag_paths)
    "idx_statistical_unit_data_source_ids" gin (data_source_ids)
    "idx_statistical_unit_domestic" btree (domestic)
    "idx_statistical_unit_establishment_id" btree (unit_id)
    "idx_statistical_unit_hash_slot" btree (hash_slot) INCLUDE (unit_type, unit_id, used_for_counting, valid_from, valid_until, birth_date, death_date, physical_region_path, primary_activity_category_path, sector_path, legal_form_id, physical_country_id, status_id, stats_summary)
    "idx_statistical_unit_last_edit_by_user_id" btree (last_edit_by_user_id)
    "idx_statistical_unit_legal_form_id" btree (legal_form_id)
    "idx_statistical_unit_physical_country_id" btree (physical_country_id)
    "idx_statistical_unit_physical_region_id" btree (physical_region_id)
    "idx_statistical_unit_primary_activity_category_id" btree (primary_activity_category_id)
    "idx_statistical_unit_search" gin (search)
    "idx_statistical_unit_secondary_activity_category_id" btree (secondary_activity_category_id)
    "idx_statistical_unit_sector_id" btree (sector_id)
    "idx_statistical_unit_status_code" btree (status_code)
    "idx_statistical_unit_unit_size_code" btree (unit_size_code)
    "idx_statistical_unit_unit_type" btree (unit_type)
    "statistical_unit_unit_idx" btree (unit_type, unit_id)
    "su_ei_stat_ident_idx" btree ((external_idents ->> 'stat_ident'::text))
    "su_ei_tax_ident_idx" btree ((external_idents ->> 'tax_ident'::text))
    "su_sort_birth_date_asc" btree (birth_date, unit_type, unit_id)
    "su_sort_birth_date_desc" btree (birth_date DESC NULLS LAST, unit_type, unit_id)
    "su_sort_death_date_asc" btree (death_date, unit_type, unit_id)
    "su_sort_death_date_desc" btree (death_date DESC NULLS LAST, unit_type, unit_id)
    "su_sort_last_edit_at_asc" btree (last_edit_at, unit_type, unit_id)
    "su_sort_last_edit_at_desc" btree (last_edit_at DESC NULLS LAST, unit_type, unit_id)
    "su_sort_legal_form_code_asc" btree (legal_form_code, unit_type, unit_id)
    "su_sort_legal_form_code_desc" btree (legal_form_code DESC NULLS LAST, unit_type, unit_id)
    "su_sort_name_asc" btree (name, unit_type, unit_id)
    "su_sort_name_desc" btree (name DESC NULLS LAST, unit_type, unit_id)
    "su_sort_physical_region_path_asc" btree (physical_region_path, unit_type, unit_id)
    "su_sort_physical_region_path_desc" btree (physical_region_path DESC NULLS LAST, unit_type, unit_id)
    "su_sort_primary_activity_category_path_asc" btree (primary_activity_category_path, unit_type, unit_id)
    "su_sort_primary_activity_category_path_desc" btree (primary_activity_category_path DESC NULLS LAST, unit_type, unit_id)
    "su_sort_secondary_activity_category_path_asc" btree (secondary_activity_category_path, unit_type, unit_id)
    "su_sort_secondary_activity_category_path_desc" btree (secondary_activity_category_path DESC NULLS LAST, unit_type, unit_id)
    "su_sort_sector_path_asc" btree (sector_path, unit_type, unit_id)
    "su_sort_sector_path_desc" btree (sector_path DESC NULLS LAST, unit_type, unit_id)
    "su_ss_employees_sum_asc_idx" btree (((stats_summary -> 'employees'::text) -> 'sum'::text), unit_type, unit_id)
    "su_ss_employees_sum_desc_idx" btree (((stats_summary -> 'employees'::text) -> 'sum'::text) DESC NULLS LAST, unit_type, unit_id)
    "su_ss_turnover_sum_asc_idx" btree (((stats_summary -> 'turnover'::text) -> 'sum'::text), unit_type, unit_id)
    "su_ss_turnover_sum_desc_idx" btree (((stats_summary -> 'turnover'::text) -> 'sum'::text) DESC NULLS LAST, unit_type, unit_id)
Policies:
    POLICY "statistical_unit_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "statistical_unit_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "statistical_unit_regular_user_read" FOR SELECT
      TO regular_user
      USING (true)
Statistics objects:
    "public.statistical_unit_existence_stat" ON GREATEST(valid_from, birth_date), LEAST(valid_until, death_date) FROM statistical_unit
Not-null constraints:
    "statistical_unit_unit_type_not_null" NOT NULL "unit_type"
    "statistical_unit_unit_id_not_null" NOT NULL "unit_id"
    "statistical_unit_valid_range_not_null" NOT NULL "valid_range"
Triggers:
    trg_set_hash_slot BEFORE INSERT ON statistical_unit FOR EACH ROW EXECUTE FUNCTION set_hash_slot()
Access method: heap

```

**Comment:** One row per unit and period, derived for the search page and reports. Every index on this table serves a named query (its COMMENT says which) and is paid for by every recalculation; a new search filter or sort adds its index in the same change (admin.create_statistical_unit_ui_indices, test/sql/359).

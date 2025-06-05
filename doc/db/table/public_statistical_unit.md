```sql
                               Table "public.statistical_unit"
              Column              |           Type           | Collation | Nullable | Default 
----------------------------------+--------------------------+-----------+----------+---------
 unit_type                        | statistical_unit_type    |           |          | 
 unit_id                          | integer                  |           |          | 
 valid_after                      | date                     |           |          | 
 valid_from                       | date                     |           |          | 
 valid_to                         | date                     |           |          | 
 external_idents                  | jsonb                    |           |          | 
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
 stats                            | jsonb                    |           |          | 
 stats_summary                    | jsonb                    |           |          | 
 included_establishment_count     | integer                  |           |          | 
 included_legal_unit_count        | integer                  |           |          | 
 included_enterprise_count        | integer                  |           |          | 
 tag_paths                        | ltree[]                  |           |          | 
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
    "statistical_unit_after_key" UNIQUE, btree (valid_after, valid_to, unit_type, unit_id)
    "statistical_unit_from_key" UNIQUE, btree (valid_from, valid_to, unit_type, unit_id)
    "statistical_unit_type_id_daterange_excl" EXCLUDE USING gist (unit_type WITH =, unit_id WITH =, daterange(valid_after, valid_to, '(]'::text) WITH &&) DEFERRABLE
    "statistical_unit_upsert_pkey" UNIQUE, btree (unit_type, unit_id, valid_after)
    "su_ei_stat_ident_idx" btree ((external_idents ->> 'stat_ident'::text))
    "su_ei_tax_ident_idx" btree ((external_idents ->> 'tax_ident'::text))
    "su_s_employees_idx" btree ((stats ->> 'employees'::text))
    "su_s_turnover_idx" btree ((stats ->> 'turnover'::text))
    "su_ss_employees_count_idx" btree (((stats_summary -> 'employees'::text) ->> 'count'::text))
    "su_ss_employees_sum_idx" btree (((stats_summary -> 'employees'::text) ->> 'sum'::text))
    "su_ss_turnover_count_idx" btree (((stats_summary -> 'turnover'::text) ->> 'count'::text))
    "su_ss_turnover_sum_idx" btree (((stats_summary -> 'turnover'::text) ->> 'sum'::text))
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

```

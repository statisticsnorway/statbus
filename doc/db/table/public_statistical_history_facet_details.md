```sql
                                                        Table "public.statistical_history_facet"
                  Column                  |         Type          | Collation | Nullable | Default | Storage  | Compression | Stats target | Description 
------------------------------------------+-----------------------+-----------+----------+---------+----------+-------------+--------------+-------------
 resolution                               | history_resolution    |           |          |         | plain    |             |              | 
 year                                     | integer               |           |          |         | plain    |             |              | 
 month                                    | integer               |           |          |         | plain    |             |              | 
 unit_type                                | statistical_unit_type |           |          |         | plain    |             |              | 
 primary_activity_category_path           | ltree                 |           |          |         | extended |             |              | 
 secondary_activity_category_path         | ltree                 |           |          |         | extended |             |              | 
 sector_path                              | ltree                 |           |          |         | extended |             |              | 
 legal_form_id                            | integer               |           |          |         | plain    |             |              | 
 physical_region_path                     | ltree                 |           |          |         | extended |             |              | 
 physical_country_id                      | integer               |           |          |         | plain    |             |              | 
 unit_size_id                             | integer               |           |          |         | plain    |             |              | 
 status_id                                | integer               |           |          |         | plain    |             |              | 
 exists_count                             | integer               |           |          |         | plain    |             |              | 
 exists_change                            | integer               |           |          |         | plain    |             |              | 
 exists_added_count                       | integer               |           |          |         | plain    |             |              | 
 exists_removed_count                     | integer               |           |          |         | plain    |             |              | 
 countable_count                          | integer               |           |          |         | plain    |             |              | 
 countable_change                         | integer               |           |          |         | plain    |             |              | 
 countable_added_count                    | integer               |           |          |         | plain    |             |              | 
 countable_removed_count                  | integer               |           |          |         | plain    |             |              | 
 births                                   | integer               |           |          |         | plain    |             |              | 
 deaths                                   | integer               |           |          |         | plain    |             |              | 
 name_change_count                        | integer               |           |          |         | plain    |             |              | 
 primary_activity_category_change_count   | integer               |           |          |         | plain    |             |              | 
 secondary_activity_category_change_count | integer               |           |          |         | plain    |             |              | 
 sector_change_count                      | integer               |           |          |         | plain    |             |              | 
 legal_form_change_count                  | integer               |           |          |         | plain    |             |              | 
 physical_region_change_count             | integer               |           |          |         | plain    |             |              | 
 physical_country_change_count            | integer               |           |          |         | plain    |             |              | 
 physical_address_change_count            | integer               |           |          |         | plain    |             |              | 
 unit_size_change_count                   | integer               |           |          |         | plain    |             |              | 
 status_change_count                      | integer               |           |          |         | plain    |             |              | 
 stats_summary                            | jsonb                 |           |          |         | extended |             |              | 
Indexes:
    "idx_gist_statistical_history_facet_physical_region_path" gist (physical_region_path)
    "idx_gist_statistical_history_facet_primary_activity_category_pa" gist (primary_activity_category_path)
    "idx_gist_statistical_history_facet_secondary_activity_category_" gist (secondary_activity_category_path)
    "idx_gist_statistical_history_facet_sector_path" gist (sector_path)
    "idx_statistical_history_facet_legal_form_id" btree (legal_form_id)
    "idx_statistical_history_facet_month" btree (month)
    "idx_statistical_history_facet_physical_country_id" btree (physical_country_id)
    "idx_statistical_history_facet_physical_region_path" btree (physical_region_path)
    "idx_statistical_history_facet_primary_activity_category_path" btree (primary_activity_category_path)
    "idx_statistical_history_facet_secondary_activity_category_path" btree (secondary_activity_category_path)
    "idx_statistical_history_facet_sector_path" btree (sector_path)
    "idx_statistical_history_facet_stats_summary" gin (stats_summary jsonb_path_ops)
    "idx_statistical_history_facet_unit_type" btree (unit_type)
    "idx_statistical_history_facet_year" btree (year)
    "statistical_history_facet_month_key" UNIQUE, btree (resolution, year, month, unit_type, primary_activity_category_path, secondary_activity_category_path, sector_path, legal_form_id, physical_region_path, physical_country_id) WHERE resolution = 'year-month'::history_resolution
    "statistical_history_facet_year_key" UNIQUE, btree (year, month, unit_type, primary_activity_category_path, secondary_activity_category_path, sector_path, legal_form_id, physical_region_path, physical_country_id) WHERE resolution = 'year'::history_resolution
Policies:
    POLICY "statistical_history_facet_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "statistical_history_facet_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "statistical_history_facet_regular_user_read" FOR SELECT
      TO regular_user
      USING (true)
Typed table of type: statistical_history_facet_type
Access method: heap

```

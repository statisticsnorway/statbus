```sql
                                Table "public.statistical_history"
                  Column                  |         Type          | Collation | Nullable | Default 
------------------------------------------+-----------------------+-----------+----------+---------
 resolution                               | history_resolution    |           |          | 
 year                                     | integer               |           |          | 
 month                                    | integer               |           |          | 
 unit_type                                | statistical_unit_type |           |          | 
 exists_count                             | integer               |           |          | 
 exists_change                            | integer               |           |          | 
 exists_added_count                       | integer               |           |          | 
 exists_removed_count                     | integer               |           |          | 
 countable_count                          | integer               |           |          | 
 countable_change                         | integer               |           |          | 
 countable_added_count                    | integer               |           |          | 
 countable_removed_count                  | integer               |           |          | 
 births                                   | integer               |           |          | 
 deaths                                   | integer               |           |          | 
 name_change_count                        | integer               |           |          | 
 primary_activity_category_change_count   | integer               |           |          | 
 secondary_activity_category_change_count | integer               |           |          | 
 sector_change_count                      | integer               |           |          | 
 legal_form_change_count                  | integer               |           |          | 
 physical_region_change_count             | integer               |           |          | 
 physical_country_change_count            | integer               |           |          | 
 physical_address_change_count            | integer               |           |          | 
 stats_summary                            | jsonb                 |           |          | 
 hash_partition                           | int4range             |           |          | 
Indexes:
    "idx_history_resolution" btree (resolution) WHERE hash_partition IS NULL
    "idx_statistical_history_hash_partition" btree (hash_partition) WHERE hash_partition IS NOT NULL
    "idx_statistical_history_month" btree (month) WHERE hash_partition IS NULL
    "idx_statistical_history_stats_summary" gin (stats_summary jsonb_path_ops) WHERE hash_partition IS NULL
    "idx_statistical_history_year" btree (year) WHERE hash_partition IS NULL
    "statistical_history_month_key" UNIQUE, btree (resolution, year, month, unit_type) WHERE resolution = 'year-month'::history_resolution AND hash_partition IS NULL
    "statistical_history_partition_month_key" UNIQUE, btree (hash_partition, resolution, year, month, unit_type) WHERE resolution = 'year-month'::history_resolution AND hash_partition IS NOT NULL
    "statistical_history_partition_year_key" UNIQUE, btree (hash_partition, resolution, year, unit_type) WHERE resolution = 'year'::history_resolution AND hash_partition IS NOT NULL
    "statistical_history_year_key" UNIQUE, btree (resolution, year, unit_type) WHERE resolution = 'year'::history_resolution AND hash_partition IS NULL
Policies:
    POLICY "statistical_history_admin_user_manage"
      TO admin_user
      USING ((hash_partition IS NULL))
      WITH CHECK (true)
    POLICY "statistical_history_authenticated_read" FOR SELECT
      TO authenticated
      USING ((hash_partition IS NULL))
    POLICY "statistical_history_regular_user_read" FOR SELECT
      TO regular_user
      USING ((hash_partition IS NULL))
Typed table of type: statistical_history_type

```

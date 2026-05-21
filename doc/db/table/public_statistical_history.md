```sql
                                                           Table "public.statistical_history"
                  Column                  |         Type          | Collation | Nullable | Default | Storage  | Compression | Stats target | Description 
------------------------------------------+-----------------------+-----------+----------+---------+----------+-------------+--------------+-------------
 resolution                               | history_resolution    |           |          |         | plain    |             |              | 
 year                                     | integer               |           |          |         | plain    |             |              | 
 month                                    | integer               |           |          |         | plain    |             |              | 
 unit_type                                | statistical_unit_type |           |          |         | plain    |             |              | 
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
 stats_summary                            | jsonb                 |           |          |         | extended |             |              | 
 hash_partition                           | int4range             |           |          |         | extended |             |              | 
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
Access method: heap

```

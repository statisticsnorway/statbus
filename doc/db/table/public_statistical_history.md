```sql
                                                                                                                                                                                                                                                                                           Table "public.statistical_history"
                  Column                  |         Type          | Collation | Nullable | Default | Storage  | Compression | Stats target |                                                                                                                                                                                                                                 Description                                                                                                                                                                                                                                 
------------------------------------------+-----------------------+-----------+----------+---------+----------+-------------+--------------+-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
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
 hash_partition                           | int4range             |           |          |         | extended |             |              | NULL marks the period total: the row the application reads. A range marks a partition slot, the partial count for units whose hash_slot falls in that range; worker.statistical_history_reduce sums the slots into the total. The row level security policies show application roles only the totals, so a reader running as the caller (statistical_history_highcharts, PostgREST) gets one row per period. Worker code running as the table owner sees the slots as well.
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
Check constraints:
    "statistical_history_hash_partition_is_one_slot" CHECK (hash_partition IS NULL OR upper(hash_partition) = (lower(hash_partition) + 1))
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

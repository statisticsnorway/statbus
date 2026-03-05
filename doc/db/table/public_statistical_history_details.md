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
 partition_seq                            | integer               |           |          |         | plain    |             |              | 
Indexes:
    "idx_history_resolution" btree (resolution) WHERE partition_seq IS NULL
    "idx_statistical_history_month" btree (month) WHERE partition_seq IS NULL
    "idx_statistical_history_partition_seq" btree (partition_seq) WHERE partition_seq IS NOT NULL
    "idx_statistical_history_stats_summary" gin (stats_summary jsonb_path_ops) WHERE partition_seq IS NULL
    "idx_statistical_history_year" btree (year) WHERE partition_seq IS NULL
    "statistical_history_month_key" UNIQUE, btree (resolution, year, month, unit_type) WHERE resolution = 'year-month'::history_resolution AND partition_seq IS NULL
    "statistical_history_partition_month_key" UNIQUE, btree (partition_seq, resolution, year, month, unit_type) WHERE resolution = 'year-month'::history_resolution AND partition_seq IS NOT NULL
    "statistical_history_partition_year_key" UNIQUE, btree (partition_seq, resolution, year, unit_type) WHERE resolution = 'year'::history_resolution AND partition_seq IS NOT NULL
    "statistical_history_year_key" UNIQUE, btree (resolution, year, unit_type) WHERE resolution = 'year'::history_resolution AND partition_seq IS NULL
Policies:
    POLICY "statistical_history_admin_user_manage"
      TO admin_user
      USING ((partition_seq IS NULL))
      WITH CHECK (true)
    POLICY "statistical_history_authenticated_read" FOR SELECT
      TO authenticated
      USING ((partition_seq IS NULL))
    POLICY "statistical_history_regular_user_read" FOR SELECT
      TO regular_user
      USING ((partition_seq IS NULL))
Typed table of type: statistical_history_type
Access method: heap

```

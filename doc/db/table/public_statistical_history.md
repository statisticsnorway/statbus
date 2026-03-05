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
 partition_seq                            | integer               |           |          | 
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

```

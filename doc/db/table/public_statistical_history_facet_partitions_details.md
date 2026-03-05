```sql
                                              Unlogged table "public.statistical_history_facet_partitions"
                  Column                  |         Type          | Collation | Nullable | Default | Storage  | Compression | Stats target | Description 
------------------------------------------+-----------------------+-----------+----------+---------+----------+-------------+--------------+-------------
 partition_seq                            | integer               |           | not null |         | plain    |             |              | 
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
    "idx_shf_partitions_seq" btree (partition_seq)
    "statistical_history_facet_par_partition_seq_resolution_year_key" UNIQUE CONSTRAINT, btree (partition_seq, resolution, year, month, unit_type, primary_activity_category_path, secondary_activity_category_path, sector_path, legal_form_id, physical_region_path, physical_country_id, unit_size_id, status_id) NULLS NOT DISTINCT
Not-null constraints:
    "statistical_history_facet_partitions_partition_seq_not_null" NOT NULL "partition_seq"
Access method: heap

```

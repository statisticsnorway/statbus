```sql
                   Unlogged table "public.statistical_history_facet_partitions"
                  Column                  |         Type          | Collation | Nullable | Default 
------------------------------------------+-----------------------+-----------+----------+---------
 hash_slot                                | integer               |           | not null | 
 resolution                               | history_resolution    |           |          | 
 year                                     | integer               |           |          | 
 month                                    | integer               |           |          | 
 unit_type                                | statistical_unit_type |           |          | 
 primary_activity_category_path           | ltree                 |           |          | 
 secondary_activity_category_path         | ltree                 |           |          | 
 sector_path                              | ltree                 |           |          | 
 legal_form_id                            | integer               |           |          | 
 physical_region_path                     | ltree                 |           |          | 
 physical_country_id                      | integer               |           |          | 
 unit_size_id                             | integer               |           |          | 
 status_id                                | integer               |           |          | 
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
 unit_size_change_count                   | integer               |           |          | 
 status_change_count                      | integer               |           |          | 
 stats_summary                            | jsonb                 |           |          | 
Indexes:
    "idx_shf_partitions_hash_slot" btree (hash_slot)
    "statistical_history_facet_par_hash_slot_resolution_year_key" UNIQUE CONSTRAINT, btree (hash_slot, resolution, year, month, unit_type, primary_activity_category_path, secondary_activity_category_path, sector_path, legal_form_id, physical_region_path, physical_country_id, unit_size_id, status_id) NULLS NOT DISTINCT

```

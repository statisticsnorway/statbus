```sql
                               View "public.statistical_history_def"
                  Column                  |         Type          | Collation | Nullable | Default 
------------------------------------------+-----------------------+-----------+----------+---------
 resolution                               | history_resolution    |           |          | 
 year                                     | integer               |           |          | 
 month                                    | integer               |           |          | 
 unit_type                                | statistical_unit_type |           |          | 
 count                                    | bigint                |           |          | 
 births                                   | bigint                |           |          | 
 deaths                                   | bigint                |           |          | 
 name_change_count                        | bigint                |           |          | 
 primary_activity_category_change_count   | bigint                |           |          | 
 secondary_activity_category_change_count | bigint                |           |          | 
 sector_change_count                      | bigint                |           |          | 
 legal_form_change_count                  | bigint                |           |          | 
 physical_region_change_count             | bigint                |           |          | 
 physical_country_change_count            | bigint                |           |          | 
 physical_address_change_count            | bigint                |           |          | 
 stats_summary                            | jsonb                 |           |          | 

```
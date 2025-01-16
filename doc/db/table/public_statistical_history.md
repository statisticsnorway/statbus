```sql
                          Materialized view "public.statistical_history"
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
Indexes:
    "idx_history_resolution" btree (resolution)
    "idx_statistical_history_births" btree (births)
    "idx_statistical_history_count" btree (count)
    "idx_statistical_history_deaths" btree (deaths)
    "idx_statistical_history_month" btree (month)
    "idx_statistical_history_stats_summary" gin (stats_summary jsonb_path_ops)
    "idx_statistical_history_year" btree (year)
    "statistical_history_month_key" UNIQUE, btree (resolution, year, month, unit_type) WHERE resolution = 'year-month'::history_resolution
    "statistical_history_year_key" UNIQUE, btree (resolution, year, unit_type) WHERE resolution = 'year'::history_resolution

```

```sql
                                                     Materialized view "public.statistical_history"
                  Column                  |         Type          | Collation | Nullable | Default | Storage  | Compression | Stats target | Description 
------------------------------------------+-----------------------+-----------+----------+---------+----------+-------------+--------------+-------------
 resolution                               | history_resolution    |           |          |         | plain    |             |              | 
 year                                     | integer               |           |          |         | plain    |             |              | 
 month                                    | integer               |           |          |         | plain    |             |              | 
 unit_type                                | statistical_unit_type |           |          |         | plain    |             |              | 
 count                                    | bigint                |           |          |         | plain    |             |              | 
 births                                   | bigint                |           |          |         | plain    |             |              | 
 deaths                                   | bigint                |           |          |         | plain    |             |              | 
 name_change_count                        | bigint                |           |          |         | plain    |             |              | 
 primary_activity_category_change_count   | bigint                |           |          |         | plain    |             |              | 
 secondary_activity_category_change_count | bigint                |           |          |         | plain    |             |              | 
 sector_change_count                      | bigint                |           |          |         | plain    |             |              | 
 legal_form_change_count                  | bigint                |           |          |         | plain    |             |              | 
 physical_region_change_count             | bigint                |           |          |         | plain    |             |              | 
 physical_country_change_count            | bigint                |           |          |         | plain    |             |              | 
 physical_address_change_count            | bigint                |           |          |         | plain    |             |              | 
 stats_summary                            | jsonb                 |           |          |         | extended |             |              | 
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
View definition:
 SELECT statistical_history_def.resolution,
    statistical_history_def.year,
    statistical_history_def.month,
    statistical_history_def.unit_type,
    statistical_history_def.count,
    statistical_history_def.births,
    statistical_history_def.deaths,
    statistical_history_def.name_change_count,
    statistical_history_def.primary_activity_category_change_count,
    statistical_history_def.secondary_activity_category_change_count,
    statistical_history_def.sector_change_count,
    statistical_history_def.legal_form_change_count,
    statistical_history_def.physical_region_change_count,
    statistical_history_def.physical_country_change_count,
    statistical_history_def.physical_address_change_count,
    statistical_history_def.stats_summary
   FROM statistical_history_def
  ORDER BY statistical_history_def.year, statistical_history_def.month;
Access method: heap

```

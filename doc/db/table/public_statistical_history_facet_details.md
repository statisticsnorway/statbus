```sql
                                                  Materialized view "public.statistical_history_facet"
                  Column                  |         Type          | Collation | Nullable | Default | Storage  | Compression | Stats target | Description 
------------------------------------------+-----------------------+-----------+----------+---------+----------+-------------+--------------+-------------
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
 status_id                                | integer               |           |          |         | plain    |             |              | 
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
 status_change_count                      | bigint                |           |          |         | plain    |             |              | 
 stats_summary                            | jsonb                 |           |          |         | extended |             |              | 
Indexes:
    "idx_gist_statistical_history_facet_physical_region_path" gist (physical_region_path)
    "idx_gist_statistical_history_facet_primary_activity_category_pa" gist (primary_activity_category_path)
    "idx_gist_statistical_history_facet_secondary_activity_category_" gist (secondary_activity_category_path)
    "idx_gist_statistical_history_facet_sector_path" gist (sector_path)
    "idx_statistical_history_facet_births" btree (births)
    "idx_statistical_history_facet_count" btree (count)
    "idx_statistical_history_facet_deaths" btree (deaths)
    "idx_statistical_history_facet_legal_form_id" btree (legal_form_id)
    "idx_statistical_history_facet_month" btree (month)
    "idx_statistical_history_facet_physical_country_id" btree (physical_country_id)
    "idx_statistical_history_facet_physical_region_path" btree (physical_region_path)
    "idx_statistical_history_facet_primary_activity_category_path" btree (primary_activity_category_path)
    "idx_statistical_history_facet_secondary_activity_category_path" btree (secondary_activity_category_path)
    "idx_statistical_history_facet_sector_path" btree (sector_path)
    "idx_statistical_history_facet_stats_summary" gin (stats_summary jsonb_path_ops)
    "idx_statistical_history_facet_year" btree (year)
    "statistical_history_facet_month_key" UNIQUE, btree (resolution, year, month, unit_type, primary_activity_category_path, secondary_activity_category_path, sector_path, legal_form_id, physical_region_path, physical_country_id) WHERE resolution = 'year-month'::history_resolution
    "statistical_history_facet_year_key" UNIQUE, btree (year, month, unit_type, primary_activity_category_path, secondary_activity_category_path, sector_path, legal_form_id, physical_region_path, physical_country_id) WHERE resolution = 'year'::history_resolution
View definition:
 SELECT statistical_history_facet_def.resolution,
    statistical_history_facet_def.year,
    statistical_history_facet_def.month,
    statistical_history_facet_def.unit_type,
    statistical_history_facet_def.primary_activity_category_path,
    statistical_history_facet_def.secondary_activity_category_path,
    statistical_history_facet_def.sector_path,
    statistical_history_facet_def.legal_form_id,
    statistical_history_facet_def.physical_region_path,
    statistical_history_facet_def.physical_country_id,
    statistical_history_facet_def.status_id,
    statistical_history_facet_def.count,
    statistical_history_facet_def.births,
    statistical_history_facet_def.deaths,
    statistical_history_facet_def.name_change_count,
    statistical_history_facet_def.primary_activity_category_change_count,
    statistical_history_facet_def.secondary_activity_category_change_count,
    statistical_history_facet_def.sector_change_count,
    statistical_history_facet_def.legal_form_change_count,
    statistical_history_facet_def.physical_region_change_count,
    statistical_history_facet_def.physical_country_change_count,
    statistical_history_facet_def.physical_address_change_count,
    statistical_history_facet_def.status_change_count,
    statistical_history_facet_def.stats_summary
   FROM statistical_history_facet_def
  ORDER BY statistical_history_facet_def.year, statistical_history_facet_def.month;
Access method: heap

```

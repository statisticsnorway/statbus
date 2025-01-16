```sql
                                               Materialized view "public.statistical_unit_facet"
             Column             |         Type          | Collation | Nullable | Default | Storage  | Compression | Stats target | Description 
--------------------------------+-----------------------+-----------+----------+---------+----------+-------------+--------------+-------------
 valid_from                     | date                  |           |          |         | plain    |             |              | 
 valid_to                       | date                  |           |          |         | plain    |             |              | 
 unit_type                      | statistical_unit_type |           |          |         | plain    |             |              | 
 physical_region_path           | ltree                 |           |          |         | extended |             |              | 
 primary_activity_category_path | ltree                 |           |          |         | extended |             |              | 
 sector_path                    | ltree                 |           |          |         | extended |             |              | 
 legal_form_id                  | integer               |           |          |         | plain    |             |              | 
 physical_country_id            | integer               |           |          |         | plain    |             |              | 
 count                          | bigint                |           |          |         | plain    |             |              | 
 stats_summary                  | jsonb                 |           |          |         | extended |             |              | 
Indexes:
    "statistical_unit_facet_legal_form_id_btree" btree (legal_form_id)
    "statistical_unit_facet_physical_country_id_btree" btree (physical_country_id)
    "statistical_unit_facet_physical_region_path_btree" btree (physical_region_path)
    "statistical_unit_facet_physical_region_path_gist" gist (physical_region_path)
    "statistical_unit_facet_primary_activity_category_path_btree" btree (primary_activity_category_path)
    "statistical_unit_facet_primary_activity_category_path_gist" gist (primary_activity_category_path)
    "statistical_unit_facet_sector_path_btree" btree (sector_path)
    "statistical_unit_facet_sector_path_gist" gist (sector_path)
    "statistical_unit_facet_unit_type" btree (unit_type)
    "statistical_unit_facet_valid_from" btree (valid_from)
    "statistical_unit_facet_valid_to" btree (valid_to)
View definition:
 SELECT statistical_unit.valid_from,
    statistical_unit.valid_to,
    statistical_unit.unit_type,
    statistical_unit.physical_region_path,
    statistical_unit.primary_activity_category_path,
    statistical_unit.sector_path,
    statistical_unit.legal_form_id,
    statistical_unit.physical_country_id,
    count(*) AS count,
    jsonb_stats_summary_merge_agg(statistical_unit.stats_summary) AS stats_summary
   FROM statistical_unit
  GROUP BY statistical_unit.valid_from, statistical_unit.valid_to, statistical_unit.unit_type, statistical_unit.physical_region_path, statistical_unit.primary_activity_category_path, statistical_unit.sector_path, statistical_unit.legal_form_id, statistical_unit.physical_country_id;
Access method: heap

```

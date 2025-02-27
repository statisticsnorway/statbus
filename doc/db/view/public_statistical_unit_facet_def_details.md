```sql
                                     View "public.statistical_unit_facet_def"
             Column             |         Type          | Collation | Nullable | Default | Storage  | Description 
--------------------------------+-----------------------+-----------+----------+---------+----------+-------------
 valid_from                     | date                  |           |          |         | plain    | 
 valid_to                       | date                  |           |          |         | plain    | 
 unit_type                      | statistical_unit_type |           |          |         | plain    | 
 physical_region_path           | ltree                 |           |          |         | extended | 
 primary_activity_category_path | ltree                 |           |          |         | extended | 
 sector_path                    | ltree                 |           |          |         | extended | 
 legal_form_id                  | integer               |           |          |         | plain    | 
 physical_country_id            | integer               |           |          |         | plain    | 
 status_id                      | integer               |           |          |         | plain    | 
 count                          | bigint                |           |          |         | plain    | 
 stats_summary                  | jsonb                 |           |          |         | extended | 
View definition:
 SELECT statistical_unit.valid_from,
    statistical_unit.valid_to,
    statistical_unit.unit_type,
    statistical_unit.physical_region_path,
    statistical_unit.primary_activity_category_path,
    statistical_unit.sector_path,
    statistical_unit.legal_form_id,
    statistical_unit.physical_country_id,
    statistical_unit.status_id,
    count(*) AS count,
    jsonb_stats_summary_merge_agg(statistical_unit.stats_summary) AS stats_summary
   FROM statistical_unit
  WHERE statistical_unit.include_unit_in_reports
  GROUP BY statistical_unit.valid_from, statistical_unit.valid_to, statistical_unit.unit_type, statistical_unit.physical_region_path, statistical_unit.primary_activity_category_path, statistical_unit.sector_path, statistical_unit.legal_form_id, statistical_unit.physical_country_id, statistical_unit.status_id;

```

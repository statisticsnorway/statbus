```sql
                                     View "public.statistical_unit_facet_def"
             Column             |         Type          | Collation | Nullable | Default | Storage  | Description 
--------------------------------+-----------------------+-----------+----------+---------+----------+-------------
 valid_from                     | date                  |           |          |         | plain    | 
 valid_to                       | date                  |           |          |         | plain    | 
 valid_until                    | date                  |           |          |         | plain    | 
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
 SELECT valid_from,
    valid_to,
    valid_until,
    unit_type,
    physical_region_path,
    primary_activity_category_path,
    sector_path,
    legal_form_id,
    physical_country_id,
    status_id,
    count(*) AS count,
    jsonb_stats_summary_merge_agg(stats_summary) AS stats_summary
   FROM statistical_unit
  WHERE include_unit_in_reports
  GROUP BY valid_from, valid_to, valid_until, unit_type, physical_region_path, primary_activity_category_path, sector_path, legal_form_id, physical_country_id, status_id;

```

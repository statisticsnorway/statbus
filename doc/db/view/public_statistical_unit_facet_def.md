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
 SELECT unit_existence_from(valid_from, birth_date) AS valid_from,
    unit_existence_until(valid_until, death_date) - 1 AS valid_to,
    unit_existence_until(valid_until, death_date) AS valid_until,
    unit_type,
    physical_region_path,
    primary_activity_category_path,
    sector_path,
    legal_form_id,
    physical_country_id,
    status_id,
    count(*) AS count,
    jsonb_stats_merge_agg(stats_summary) AS stats_summary
   FROM statistical_unit
  WHERE used_for_counting AND unit_existence_from(valid_from, birth_date) < unit_existence_until(valid_until, death_date)
  GROUP BY (unit_existence_from(valid_from, birth_date)), (unit_existence_until(valid_until, death_date)), unit_type, physical_region_path, primary_activity_category_path, sector_path, legal_form_id, physical_country_id, status_id;
Options: security_invoker=on

```

**Comment:** STATBUS-475: facet windows are the unit EXISTENCE window within each record (public.unit_existence_from/until), so the Reports drilldown counts existing units, like the dashboard cards and the Units-over-time chart.

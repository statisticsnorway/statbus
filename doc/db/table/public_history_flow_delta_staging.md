```sql
                                               Unlogged table "public.history_flow_delta_staging"
              Column              |         Type          | Collation | Nullable | Default | Storage  | Compression | Stats target | Description 
----------------------------------+-----------------------+-----------+----------+---------+----------+-------------+--------------+-------------
 unit_id                          | integer               |           | not null |         | plain    |             |              | 
 sign                             | smallint              |           | not null |         | plain    |             |              | 
 resolution                       | history_resolution    |           | not null |         | plain    |             |              | 
 year                             | integer               |           | not null |         | plain    |             |              | 
 month                            | integer               |           |          |         | plain    |             |              | 
 unit_type                        | statistical_unit_type |           | not null |         | plain    |             |              | 
 primary_activity_category_path   | ltree                 |           |          |         | extended |             |              | 
 secondary_activity_category_path | ltree                 |           |          |         | extended |             |              | 
 sector_path                      | ltree                 |           |          |         | extended |             |              | 
 legal_form_id                    | integer               |           |          |         | plain    |             |              | 
 physical_region_path             | ltree                 |           |          |         | extended |             |              | 
 physical_country_id              | integer               |           |          |         | plain    |             |              | 
 unit_size_id                     | integer               |           |          |         | plain    |             |              | 
 status_id                        | integer               |           |          |         | plain    |             |              | 
 flows                            | integer[]             |           | not null |         | extended |             |              | 
 stats_ended                      | jsonb                 |           |          |         | extended |             |              | 
Not-null constraints:
    "history_flow_delta_staging_unit_id_not_null" NOT NULL "unit_id"
    "history_flow_delta_staging_sign_not_null" NOT NULL "sign"
    "history_flow_delta_staging_resolution_not_null" NOT NULL "resolution"
    "history_flow_delta_staging_year_not_null" NOT NULL "year"
    "history_flow_delta_staging_unit_type_not_null" NOT NULL "unit_type"
    "history_flow_delta_staging_flows_not_null" NOT NULL "flows"
Access method: heap

```

**Comment:** Signed per-unit rows staged by worker.derive_history_delta_range children for this cycle; worker.history_delta_reduce adds them into history_flow_delta.

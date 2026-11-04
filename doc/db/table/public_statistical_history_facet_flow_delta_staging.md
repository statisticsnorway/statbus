```sql
                                      Unlogged table "public.statistical_history_facet_flow_delta_staging"
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
    "statistical_history_facet_flow_delta_staging_unit_id_not_null" NOT NULL "unit_id"
    "statistical_history_facet_flow_delta_staging_sign_not_null" NOT NULL "sign"
    "statistical_history_facet_flow_delta_stagin_resolution_not_null" NOT NULL "resolution"
    "statistical_history_facet_flow_delta_staging_year_not_null" NOT NULL "year"
    "statistical_history_facet_flow_delta_staging_unit_type_not_null" NOT NULL "unit_type"
    "statistical_history_facet_flow_delta_staging_flows_not_null" NOT NULL "flows"
Access method: heap

```

**Comment:** Signed per-unit rows staged by worker.derive_statistical_history_facet_delta_partition children for this cycle; worker.statistical_history_facet_delta_reduce adds them into statistical_history_facet_flow_delta.

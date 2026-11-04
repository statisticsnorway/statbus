```sql
                                                                                                                                           Table "public.statistical_history_facet_stock_delta_staging"
              Column              |         Type          | Collation | Nullable | Default | Storage  | Compression | Stats target |                                                                                                 Description                                                                                                  
----------------------------------+-----------------------+-----------+----------+---------+----------+-------------+--------------+--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 unit_id                          | integer               |           | not null |         | plain    |             |              | 
 sign                             | smallint              |           | not null |         | plain    |             |              | 
 unit_type                        | statistical_unit_type |           | not null |         | plain    |             |              | 
 primary_activity_category_path   | ltree                 |           |          |         | extended |             |              | 
 secondary_activity_category_path | ltree                 |           |          |         | extended |             |              | 
 sector_path                      | ltree                 |           |          |         | extended |             |              | 
 legal_form_id                    | integer               |           |          |         | plain    |             |              | 
 physical_region_path             | ltree                 |           |          |         | extended |             |              | 
 physical_country_id              | integer               |           |          |         | plain    |             |              | 
 unit_size_id                     | integer               |           |          |         | plain    |             |              | 
 status_id                        | integer               |           |          |         | plain    |             |              | 
 on_month                         | date                  |           | not null |         | plain    |             |              | 
 exists_delta                     | integer               |           | not null |         | plain    |             |              | 
 countable_delta                  | integer               |           | not null |         | plain    |             |              | 
 stats_delta                      | jsonb                 |           |          |         | extended |             |              | 
 generation                       | bigint                |           | not null |         | plain    |             |              | The cycle that staged the row (see worker.statistical_history_facet_delta_state). 0 for rows that are true when they commit: the subtraction of units deleted from statistical_unit in the same transaction.
Not-null constraints:
    "statistical_history_facet_stock_delta_staging_unit_id_not_null" NOT NULL "unit_id"
    "statistical_history_facet_stock_delta_staging_sign_not_null" NOT NULL "sign"
    "statistical_history_facet_stock_delta_stagin_unit_type_not_null" NOT NULL "unit_type"
    "statistical_history_facet_stock_delta_staging_on_month_not_null" NOT NULL "on_month"
    "statistical_history_facet_stock_delta_sta_exists_delta_not_null" NOT NULL "exists_delta"
    "statistical_history_facet_stock_delta__countable_delta_not_null" NOT NULL "countable_delta"
    "statistical_history_facet_stock_delta_stagi_generation_not_null" NOT NULL "generation"
Access method: heap

```

**Comment:** Signed per-unit rows staged by worker.derive_statistical_history_facet_delta_partition children for this cycle; worker.statistical_history_facet_delta_reduce adds them into statistical_history_facet_stock_delta.

```sql
                                               Unlogged table "public.history_stock_delta_staging"
              Column              |         Type          | Collation | Nullable | Default | Storage  | Compression | Stats target | Description 
----------------------------------+-----------------------+-----------+----------+---------+----------+-------------+--------------+-------------
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
Not-null constraints:
    "history_stock_delta_staging_unit_id_not_null" NOT NULL "unit_id"
    "history_stock_delta_staging_sign_not_null" NOT NULL "sign"
    "history_stock_delta_staging_unit_type_not_null" NOT NULL "unit_type"
    "history_stock_delta_staging_on_month_not_null" NOT NULL "on_month"
    "history_stock_delta_staging_exists_delta_not_null" NOT NULL "exists_delta"
    "history_stock_delta_staging_countable_delta_not_null" NOT NULL "countable_delta"
Access method: heap

```

**Comment:** Signed per-unit rows staged by worker.derive_history_delta_range children for this cycle; worker.history_delta_reduce adds them into history_stock_delta.

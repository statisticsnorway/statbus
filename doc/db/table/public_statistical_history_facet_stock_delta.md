```sql
                                                                                                                                                                                                                                                  Table "public.statistical_history_facet_stock_delta"
              Column              |         Type          | Collation | Nullable | Default | Storage  | Compression | Stats target |                                                                                                                                                                                                     Description                                                                                                                                                                                                     
----------------------------------+-----------------------+-----------+----------+---------+----------+-------------+--------------+---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 unit_type                        | statistical_unit_type |           | not null |         | plain    |             |              | 
 primary_activity_category_path   | ltree                 |           |          |         | extended |             |              | 
 secondary_activity_category_path | ltree                 |           |          |         | extended |             |              | 
 sector_path                      | ltree                 |           |          |         | extended |             |              | 
 legal_form_id                    | integer               |           |          |         | plain    |             |              | 
 physical_region_path             | ltree                 |           |          |         | extended |             |              | 
 physical_country_id              | integer               |           |          |         | plain    |             |              | 
 unit_size_id                     | integer               |           |          |         | plain    |             |              | 
 status_id                        | integer               |           |          |         | plain    |             |              | 
 on_month                         | date                  |           | not null |         | plain    |             |              | First day of the month in which the change takes effect. Every report period ends on a month end, and a change on any day of a month is in the stock at that month's end, so bucketing by month gives the same stock at every period end as the exact dates. It keeps one row per cell and month however many changes fall inside the month, and a unit's changes that undo each other within a month leave no row.
 exists_delta                     | integer               |           | not null |         | plain    |             |              | 
 countable_delta                  | integer               |           | not null |         | plain    |             |              | 
 stats_delta                      | jsonb                 |           |          |         | extended |             |              | 
 unit_ids                         | integer[]             |           | not null |         | extended |             |              | Units contributing to this row, sorted. A unit leaves when its contribution is removed; the row is deleted when no unit remains.
Indexes:
    "statistical_history_facet_stock_delta_key" UNIQUE, btree (unit_type, primary_activity_category_path, secondary_activity_category_path, sector_path, legal_form_id, physical_region_path, physical_country_id, unit_size_id, status_id, on_month) NULLS NOT DISTINCT
    "statistical_history_facet_stock_delta_unit_type_on_month_idx" btree (unit_type, on_month)
Policies:
    POLICY "statistical_history_facet_stock_delta_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "statistical_history_facet_stock_delta_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "statistical_history_facet_stock_delta_regular_user_read" FOR SELECT
      TO regular_user
      USING (true)
Not-null constraints:
    "statistical_history_facet_stock_delta_unit_type_not_null" NOT NULL "unit_type"
    "statistical_history_facet_stock_delta_on_month_not_null" NOT NULL "on_month"
    "statistical_history_facet_stock_delta_exists_delta_not_null" NOT NULL "exists_delta"
    "statistical_history_facet_stock_delta_countable_delta_not_null" NOT NULL "countable_delta"
    "statistical_history_facet_stock_delta_unit_ids_not_null" NOT NULL "unit_ids"
Access method: heap

```

**Comment:** Stock changes per cell and month (on_month): +1/-1 when a unit enters/leaves the cell (exists_delta; countable_delta when it is used for counting) and the stats of counted versions entering and leaving (stats_delta, jsonb_stats stats_delta). The stock at a month end is the sum up to it. unit_ids lists the units contributing to the row. Maintained by worker.derive_statistical_history_facet_delta and worker.statistical_history_facet_delta_reduce.

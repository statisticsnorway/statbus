```sql
                                             Table "public.history_period"
   Column   |        Type        | Collation | Nullable | Default | Storage | Compression | Stats target | Description 
------------+--------------------+-----------+----------+---------+---------+-------------+--------------+-------------
 resolution | history_resolution |           | not null |         | plain   |             |              | 
 year       | integer            |           | not null |         | plain   |             |              | 
 month      | integer            |           |          |         | plain   |             |              | 
 prev_stop  | date               |           | not null |         | plain   |             |              | 
 curr_start | date               |           | not null |         | plain   |             |              | 
 curr_stop  | date               |           | not null |         | plain   |             |              | 
Indexes:
    "history_period_key" UNIQUE, btree (resolution, year, month) NULLS NOT DISTINCT
Policies:
    POLICY "history_period_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "history_period_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "history_period_regular_user_read" FOR SELECT
      TO regular_user
      USING (true)
Not-null constraints:
    "history_period_resolution_not_null" NOT NULL "resolution"
    "history_period_year_not_null" NOT NULL "year"
    "history_period_prev_stop_not_null" NOT NULL "prev_stop"
    "history_period_curr_start_not_null" NOT NULL "curr_start"
    "history_period_curr_stop_not_null" NOT NULL "curr_stop"
Access method: heap

```

**Comment:** The periods statistical_history and statistical_history_facet show: get_statistical_history_periods() for the current data, refreshed by worker.history_delta_reduce.

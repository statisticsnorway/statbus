```sql
                                                Table "public.timesegments"
   Column    |         Type          | Collation | Nullable | Default | Storage | Compression | Stats target | Description 
-------------+-----------------------+-----------+----------+---------+---------+-------------+--------------+-------------
 unit_type   | statistical_unit_type |           | not null |         | plain   |             |              | 
 unit_id     | integer               |           | not null |         | plain   |             |              | 
 valid_after | date                  |           | not null |         | plain   |             |              | 
 valid_to    | date                  |           | not null |         | plain   |             |              | 
Indexes:
    "timesegments_pkey" PRIMARY KEY, btree (unit_type, unit_id, valid_after)
    "idx_timesegments_daterange" gist (daterange(valid_after, valid_to, '(]'::text))
    "idx_timesegments_unit_type" btree (unit_type)
    "idx_timesegments_unit_type_id_period" btree (unit_type, unit_id, valid_after, valid_to)
    "idx_timesegments_unit_type_id_valid_after" btree (unit_type, unit_id, valid_after)
    "idx_timesegments_unit_type_unit_id" btree (unit_type, unit_id)
Policies:
    POLICY "timesegments_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "timesegments_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "timesegments_regular_user_read" FOR SELECT
      TO regular_user
      USING (true)
Access method: heap

```

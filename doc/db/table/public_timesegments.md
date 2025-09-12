```sql
                     Table "public.timesegments"
   Column    |         Type          | Collation | Nullable | Default 
-------------+-----------------------+-----------+----------+---------
 unit_type   | statistical_unit_type |           | not null | 
 unit_id     | integer               |           | not null | 
 valid_from  | date                  |           | not null | 
 valid_until | date                  |           | not null | 
Indexes:
    "timesegments_pkey" PRIMARY KEY, btree (unit_type, unit_id, valid_from)
    "idx_timesegments_daterange" gist (daterange(valid_from, valid_until, '[)'::text))
    "idx_timesegments_unit_type" btree (unit_type)
    "idx_timesegments_unit_type_id_period" btree (unit_type, unit_id, valid_from, valid_until)
    "idx_timesegments_unit_type_id_valid_from" btree (unit_type, unit_id, valid_from)
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

```

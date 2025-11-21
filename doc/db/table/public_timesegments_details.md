```sql
                                                Table "public.timesegments"
   Column    |         Type          | Collation | Nullable | Default | Storage | Compression | Stats target | Description 
-------------+-----------------------+-----------+----------+---------+---------+-------------+--------------+-------------
 unit_type   | statistical_unit_type |           | not null |         | plain   |             |              | 
 unit_id     | integer               |           | not null |         | plain   |             |              | 
 valid_from  | date                  |           | not null |         | plain   |             |              | 
 valid_until | date                  |           | not null |         | plain   |             |              | 
Indexes:
    "timesegments_pkey" PRIMARY KEY, btree (unit_type, unit_id, valid_from)
    "idx_timesegments_unit_daterange" gist (daterange(valid_from, valid_until, '[)'::text), unit_type, unit_id)
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
Not-null constraints:
    "timesegments_unit_type_not_null" NOT NULL "unit_type"
    "timesegments_unit_id_not_null" NOT NULL "unit_id"
    "timesegments_valid_from_not_null" NOT NULL "valid_from"
    "timesegments_valid_until_not_null" NOT NULL "valid_until"
Access method: heap

```

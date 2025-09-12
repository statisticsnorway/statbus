```sql
                     Table "public.timepoints"
  Column   |         Type          | Collation | Nullable | Default 
-----------+-----------------------+-----------+----------+---------
 unit_type | statistical_unit_type |           | not null | 
 unit_id   | integer               |           | not null | 
 timepoint | date                  |           | not null | 
Indexes:
    "timepoints_pkey" PRIMARY KEY, btree (unit_type, unit_id, timepoint)
    "ix_timepoints_unit" btree (unit_type, unit_id)
Policies:
    POLICY "timepoints_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "timepoints_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "timepoints_regular_user_read" FOR SELECT
      TO regular_user
      USING (true)

```

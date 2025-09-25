```sql
         Table "public.timesegments_years"
 Column |  Type   | Collation | Nullable | Default 
--------+---------+-----------+----------+---------
 year   | integer |           | not null | 
Indexes:
    "timesegments_years_pkey" PRIMARY KEY, btree (year)
Policies:
    POLICY "timesegments_years_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "timesegments_years_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "timesegments_years_regular_user_read" FOR SELECT
      TO regular_user
      USING (true)

```

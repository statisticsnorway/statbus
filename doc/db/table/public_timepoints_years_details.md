```sql
                                    Table "public.timepoints_years"
 Column |  Type   | Collation | Nullable | Default | Storage | Compression | Stats target | Description 
--------+---------+-----------+----------+---------+---------+-------------+--------------+-------------
 year   | integer |           | not null |         | plain   |             |              | 
Indexes:
    "timepoints_years_pkey" PRIMARY KEY, btree (year)
Policies:
    POLICY "timepoints_years_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "timepoints_years_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "timepoints_years_regular_user_read" FOR SELECT
      TO regular_user
      USING (true)
Access method: heap

```

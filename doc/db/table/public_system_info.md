```sql
                            Table "public.system_info"
   Column   |           Type           | Collation | Nullable |      Default      
------------+--------------------------+-----------+----------+-------------------
 key        | text                     |           | not null | 
 value      | text                     |           | not null | 
 updated_at | timestamp with time zone |           | not null | clock_timestamp()
Indexes:
    "system_info_pkey" PRIMARY KEY, btree (key)
Policies:
    POLICY "system_info_admin_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "system_info_authenticated_view" FOR SELECT
      TO authenticated
      USING (true)

```

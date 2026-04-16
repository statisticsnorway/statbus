```sql
                 Table "public.upgrade_retention_caps"
     Column     |        Type         | Collation | Nullable | Default 
----------------+---------------------+-----------+----------+---------
 release_status | release_status_type |           | not null | 
 state          | upgrade_state       |           | not null | 
 time_cap       | interval            |           |          | 
 count_cap      | integer             |           |          | 
 install_purge  | boolean             |           | not null | false
Indexes:
    "upgrade_retention_caps_pkey" PRIMARY KEY, btree (release_status, state)
Policies:
    POLICY "upgrade_retention_caps_admin_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "upgrade_retention_caps_authenticated_view" FOR SELECT
      TO authenticated
      USING (true)

```

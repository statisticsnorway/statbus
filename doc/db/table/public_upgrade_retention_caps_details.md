```sql
                                           Table "public.upgrade_retention_caps"
     Column     |        Type         | Collation | Nullable | Default | Storage | Compression | Stats target | Description 
----------------+---------------------+-----------+----------+---------+---------+-------------+--------------+-------------
 release_status | release_status_type |           | not null |         | plain   |             |              | 
 state          | upgrade_state       |           | not null |         | plain   |             |              | 
 time_cap       | interval            |           |          |         | plain   |             |              | 
 count_cap      | integer             |           |          |         | plain   |             |              | 
 install_purge  | boolean             |           | not null | false   | plain   |             |              | 
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
Not-null constraints:
    "upgrade_retention_caps_release_status_not_null" NOT NULL "release_status"
    "upgrade_retention_caps_state_not_null" NOT NULL "state"
    "upgrade_retention_caps_install_purge_not_null" NOT NULL "install_purge"
Access method: heap

```

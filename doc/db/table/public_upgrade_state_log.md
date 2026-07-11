```sql
                                                            Table "public.upgrade_state_log"
      Column      |           Type           | Collation | Nullable |           Default            | Storage  | Compression | Stats target | Description 
------------------+--------------------------+-----------+----------+------------------------------+----------+-------------+--------------+-------------
 id               | bigint                   |           | not null | generated always as identity | plain    |             |              | 
 upgrade_id       | integer                  |           | not null |                              | plain    |             |              | 
 old_state        | upgrade_state            |           |          |                              | plain    |             |              | 
 new_state        | upgrade_state            |           |          |                              | plain    |             |              | 
 old_parked_at    | timestamp with time zone |           |          |                              | plain    |             |              | 
 new_parked_at    | timestamp with time zone |           |          |                              | plain    |             |              | 
 application_name | text                     |           |          |                              | extended |             |              | 
 query            | text                     |           |          |                              | extended |             |              | 
 backend_pid      | integer                  |           |          |                              | plain    |             |              | 
 logged_at        | timestamp with time zone |           | not null | clock_timestamp()            | plain    |             |              | 
Indexes:
    "upgrade_state_log_pkey" PRIMARY KEY, btree (id)
Policies:
    POLICY "upgrade_state_log_admin_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "upgrade_state_log_authenticated_view" FOR SELECT
      TO authenticated
      USING (true)
Not-null constraints:
    "upgrade_state_log_id_not_null" NOT NULL "id"
    "upgrade_state_log_upgrade_id_not_null" NOT NULL "upgrade_id"
    "upgrade_state_log_logged_at_not_null" NOT NULL "logged_at"
Access method: heap

```

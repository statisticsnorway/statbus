```sql
                                                                                                                                Table "public.upgrade_state_log"
           Column           |           Type           | Collation | Nullable |           Default            | Storage  | Compression | Stats target |                                                                Description                                                                
----------------------------+--------------------------+-----------+----------+------------------------------+----------+-------------+--------------+-------------------------------------------------------------------------------------------------------------------------------------------
 id                         | bigint                   |           | not null | generated always as identity | plain    |             |              | 
 upgrade_id                 | integer                  |           | not null |                              | plain    |             |              | 
 old_state                  | upgrade_state            |           |          |                              | plain    |             |              | 
 new_state                  | upgrade_state            |           |          |                              | plain    |             |              | 
 old_parked_at              | timestamp with time zone |           |          |                              | plain    |             |              | 
 new_parked_at              | timestamp with time zone |           |          |                              | plain    |             |              | 
 application_name           | text                     |           |          |                              | extended |             |              | 
 query                      | text                     |           |          |                              | extended |             |              | 
 backend_pid                | integer                  |           |          |                              | plain    |             |              | 
 logged_at                  | timestamp with time zone |           | not null | clock_timestamp()            | plain    |             |              | 
 actor                      | text                     |           |          |                              | extended |             |              | 
 actor_source               | upgrade_actor_source     |           |          |                              | plain    |             |              | 
 old_error                  | text                     |           |          |                              | extended |             |              | Error text from the upgrade row before this state or park transition.
 old_log_relative_file_path | text                     |           |          |                              | extended |             |              | Upgrade log basename from the upgrade row before this state or park transition.
 old_backup_path            | text                     |           |          |                              | extended |             |              | Backup path recorded on the upgrade row before this state or park transition. Historical metadata only; backup contents may later change.
 old_recovery_parked_reason | text                     |           |          |                              | extended |             |              | Recovery park reason from the upgrade row before this state or park transition.
 old_recovery_attempts      | integer                  |           |          |                              | plain    |             |              | Recovery attempt count from the upgrade row before this state or park transition.
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

**Comment:** STATBUS-154 diagnostic append-only log: one row per public.upgrade UPDATE that changes state or recovery_parked_at, tagged with the writing connection identity (application_name / backend_pid / current_query). Ops-plane only.

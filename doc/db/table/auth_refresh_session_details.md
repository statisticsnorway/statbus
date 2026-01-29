```sql
                                                              Table "auth.refresh_session"
     Column      |           Type           | Collation | Nullable |           Default            | Storage  | Compression | Stats target | Description 
-----------------+--------------------------+-----------+----------+------------------------------+----------+-------------+--------------+-------------
 id              | integer                  |           | not null | generated always as identity | plain    |             |              | 
 jti             | uuid                     |           | not null | uuidv7()                     | plain    |             |              | 
 user_id         | integer                  |           | not null |                              | plain    |             |              | 
 refresh_version | integer                  |           | not null | 0                            | plain    |             |              | 
 created_at      | timestamp with time zone |           | not null | now()                        | plain    |             |              | 
 last_used_at    | timestamp with time zone |           | not null | now()                        | plain    |             |              | 
 expires_at      | timestamp with time zone |           | not null |                              | plain    |             |              | 
 user_agent      | text                     |           |          |                              | extended |             |              | 
 ip_address      | inet                     |           |          |                              | main     |             |              | 
Indexes:
    "refresh_session_pkey" PRIMARY KEY, btree (id)
    "refresh_session_expires_at_idx" btree (expires_at)
    "refresh_session_jti_key" UNIQUE CONSTRAINT, btree (jti)
    "refresh_session_user_id_idx" btree (user_id)
Foreign-key constraints:
    "refresh_session_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth."user"(id) ON DELETE CASCADE
Policies:
    POLICY "admin_all_refresh_sessions"
      USING (pg_has_role(CURRENT_USER, 'admin_user'::name, 'MEMBER'::text))
      WITH CHECK (pg_has_role(CURRENT_USER, 'admin_user'::name, 'MEMBER'::text))
    POLICY "delete_own_refresh_sessions" FOR DELETE
      USING ((user_id = auth.uid()))
    POLICY "insert_own_refresh_sessions" FOR INSERT
      WITH CHECK ((user_id = auth.uid()))
    POLICY "select_own_refresh_sessions" FOR SELECT
      USING ((user_id = auth.uid()))
    POLICY "update_own_refresh_sessions" FOR UPDATE
      USING ((user_id = auth.uid()))
      WITH CHECK ((user_id = auth.uid()))
Not-null constraints:
    "refresh_session_id_not_null" NOT NULL "id"
    "refresh_session_jti_not_null" NOT NULL "jti"
    "refresh_session_user_id_not_null" NOT NULL "user_id"
    "refresh_session_refresh_version_not_null" NOT NULL "refresh_version"
    "refresh_session_created_at_not_null" NOT NULL "created_at"
    "refresh_session_last_used_at_not_null" NOT NULL "last_used_at"
    "refresh_session_expires_at_not_null" NOT NULL "expires_at"
Access method: heap

```

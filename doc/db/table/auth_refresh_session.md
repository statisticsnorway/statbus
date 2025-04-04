```sql
                                   Table "auth.refresh_session"
     Column      |           Type           | Collation | Nullable |           Default            
-----------------+--------------------------+-----------+----------+------------------------------
 id              | integer                  |           | not null | generated always as identity
 jti             | uuid                     |           | not null | gen_random_uuid()
 user_id         | integer                  |           | not null | 
 refresh_version | integer                  |           | not null | 0
 created_at      | timestamp with time zone |           | not null | now()
 last_used_at    | timestamp with time zone |           | not null | now()
 expires_at      | timestamp with time zone |           | not null | 
 user_agent      | text                     |           |          | 
 ip_address      | inet                     |           |          | 
Indexes:
    "refresh_session_pkey" PRIMARY KEY, btree (id)
    "refresh_session_expires_at_idx" btree (expires_at)
    "refresh_session_jti_key" UNIQUE CONSTRAINT, btree (jti)
    "refresh_session_user_id_idx" btree (user_id)
Foreign-key constraints:
    "refresh_session_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth."user"(id) ON DELETE CASCADE

```

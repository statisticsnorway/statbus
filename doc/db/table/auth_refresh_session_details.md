```sql
                                                              Table "auth.refresh_session"
     Column      |           Type           | Collation | Nullable |           Default            | Storage  | Compression | Stats target | Description 
-----------------+--------------------------+-----------+----------+------------------------------+----------+-------------+--------------+-------------
 id              | integer                  |           | not null | generated always as identity | plain    |             |              | 
 jti             | uuid                     |           | not null | gen_random_uuid()            | plain    |             |              | 
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
Access method: heap

```

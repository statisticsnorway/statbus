```sql
                                                                                                            Table "auth.sessions"
    Column    |            Type             | Collation | Nullable | Default | Storage  | Compression | Stats target |                                                      Description                                                      
--------------+-----------------------------+-----------+----------+---------+----------+-------------+--------------+-----------------------------------------------------------------------------------------------------------------------
 id           | uuid                        |           | not null |         | plain    |             |              | 
 user_id      | uuid                        |           | not null |         | plain    |             |              | 
 created_at   | timestamp with time zone    |           |          |         | plain    |             |              | 
 updated_at   | timestamp with time zone    |           |          |         | plain    |             |              | 
 factor_id    | uuid                        |           |          |         | plain    |             |              | 
 aal          | auth.aal_level              |           |          |         | plain    |             |              | 
 not_after    | timestamp with time zone    |           |          |         | plain    |             |              | Auth: Not after is a nullable column that contains a timestamp after which the session should be regarded as expired.
 refreshed_at | timestamp without time zone |           |          |         | plain    |             |              | 
 user_agent   | text                        |           |          |         | extended |             |              | 
 ip           | inet                        |           |          |         | main     |             |              | 
 tag          | text                        |           |          |         | extended |             |              | 
Indexes:
    "sessions_pkey" PRIMARY KEY, btree (id)
    "sessions_not_after_idx" btree (not_after DESC)
    "sessions_user_id_idx" btree (user_id)
    "user_id_created_at_idx" btree (user_id, created_at)
Foreign-key constraints:
    "sessions_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
Referenced by:
    TABLE "auth.mfa_amr_claims" CONSTRAINT "mfa_amr_claims_session_id_fkey" FOREIGN KEY (session_id) REFERENCES auth.sessions(id) ON DELETE CASCADE
    TABLE "auth.refresh_tokens" CONSTRAINT "refresh_tokens_session_id_fkey" FOREIGN KEY (session_id) REFERENCES auth.sessions(id) ON DELETE CASCADE
Policies (row security enabled): (none)
Access method: heap

```

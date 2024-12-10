```sql
                                                                      Table "auth.refresh_tokens"
   Column    |           Type           | Collation | Nullable |                     Default                     | Storage  | Compression | Stats target | Description 
-------------+--------------------------+-----------+----------+-------------------------------------------------+----------+-------------+--------------+-------------
 instance_id | uuid                     |           |          |                                                 | plain    |             |              | 
 id          | bigint                   |           | not null | nextval('auth.refresh_tokens_id_seq'::regclass) | plain    |             |              | 
 token       | character varying(255)   |           |          |                                                 | extended |             |              | 
 user_id     | character varying(255)   |           |          |                                                 | extended |             |              | 
 revoked     | boolean                  |           |          |                                                 | plain    |             |              | 
 created_at  | timestamp with time zone |           |          |                                                 | plain    |             |              | 
 updated_at  | timestamp with time zone |           |          |                                                 | plain    |             |              | 
 parent      | character varying(255)   |           |          |                                                 | extended |             |              | 
 session_id  | uuid                     |           |          |                                                 | plain    |             |              | 
Indexes:
    "refresh_tokens_pkey" PRIMARY KEY, btree (id)
    "refresh_tokens_instance_id_idx" btree (instance_id)
    "refresh_tokens_instance_id_user_id_idx" btree (instance_id, user_id)
    "refresh_tokens_parent_idx" btree (parent)
    "refresh_tokens_session_id_revoked_idx" btree (session_id, revoked)
    "refresh_tokens_token_unique" UNIQUE CONSTRAINT, btree (token)
    "refresh_tokens_updated_at_idx" btree (updated_at DESC)
Foreign-key constraints:
    "refresh_tokens_session_id_fkey" FOREIGN KEY (session_id) REFERENCES auth.sessions(id) ON DELETE CASCADE
Policies (row security enabled): (none)
Access method: heap

```

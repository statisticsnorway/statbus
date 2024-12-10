```sql
                                                                                                                               Table "auth.identities"
     Column      |           Type           | Collation | Nullable |                               Default                               | Storage  | Compression | Stats target |                                            Description                                             
-----------------+--------------------------+-----------+----------+---------------------------------------------------------------------+----------+-------------+--------------+----------------------------------------------------------------------------------------------------
 provider_id     | text                     |           | not null |                                                                     | extended |             |              | 
 user_id         | uuid                     |           | not null |                                                                     | plain    |             |              | 
 identity_data   | jsonb                    |           | not null |                                                                     | extended |             |              | 
 provider        | text                     |           | not null |                                                                     | extended |             |              | 
 last_sign_in_at | timestamp with time zone |           |          |                                                                     | plain    |             |              | 
 created_at      | timestamp with time zone |           |          |                                                                     | plain    |             |              | 
 updated_at      | timestamp with time zone |           |          |                                                                     | plain    |             |              | 
 email           | text                     |           |          | generated always as (lower(identity_data ->> 'email'::text)) stored | extended |             |              | Auth: Email is a generated column that references the optional email property in the identity_data
 id              | uuid                     |           | not null | gen_random_uuid()                                                   | plain    |             |              | 
Indexes:
    "identities_pkey" PRIMARY KEY, btree (id)
    "identities_email_idx" btree (email text_pattern_ops)
    "identities_provider_id_provider_unique" UNIQUE CONSTRAINT, btree (provider_id, provider)
    "identities_user_id_idx" btree (user_id)
Foreign-key constraints:
    "identities_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
Policies (row security enabled): (none)
Access method: heap

```

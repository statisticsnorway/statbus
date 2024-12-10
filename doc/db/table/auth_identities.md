```sql
                                                         Table "auth.identities"
     Column      |           Type           | Collation | Nullable |                               Default                               
-----------------+--------------------------+-----------+----------+---------------------------------------------------------------------
 provider_id     | text                     |           | not null | 
 user_id         | uuid                     |           | not null | 
 identity_data   | jsonb                    |           | not null | 
 provider        | text                     |           | not null | 
 last_sign_in_at | timestamp with time zone |           |          | 
 created_at      | timestamp with time zone |           |          | 
 updated_at      | timestamp with time zone |           |          | 
 email           | text                     |           |          | generated always as (lower(identity_data ->> 'email'::text)) stored
 id              | uuid                     |           | not null | gen_random_uuid()
Indexes:
    "identities_pkey" PRIMARY KEY, btree (id)
    "identities_email_idx" btree (email text_pattern_ops)
    "identities_provider_id_provider_unique" UNIQUE CONSTRAINT, btree (provider_id, provider)
    "identities_user_id_idx" btree (user_id)
Foreign-key constraints:
    "identities_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
Policies (row security enabled): (none)

```

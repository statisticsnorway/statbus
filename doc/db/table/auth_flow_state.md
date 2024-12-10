```sql
                               Table "auth.flow_state"
         Column         |            Type            | Collation | Nullable | Default 
------------------------+----------------------------+-----------+----------+---------
 id                     | uuid                       |           | not null | 
 user_id                | uuid                       |           |          | 
 auth_code              | text                       |           | not null | 
 code_challenge_method  | auth.code_challenge_method |           | not null | 
 code_challenge         | text                       |           | not null | 
 provider_type          | text                       |           | not null | 
 provider_access_token  | text                       |           |          | 
 provider_refresh_token | text                       |           |          | 
 created_at             | timestamp with time zone   |           |          | 
 updated_at             | timestamp with time zone   |           |          | 
 authentication_method  | text                       |           | not null | 
 auth_code_issued_at    | timestamp with time zone   |           |          | 
Indexes:
    "flow_state_pkey" PRIMARY KEY, btree (id)
    "flow_state_created_at_idx" btree (created_at DESC)
    "idx_auth_code" btree (auth_code)
    "idx_user_id_auth_method" btree (user_id, authentication_method)
Referenced by:
    TABLE "auth.saml_relay_states" CONSTRAINT "saml_relay_states_flow_state_id_fkey" FOREIGN KEY (flow_state_id) REFERENCES auth.flow_state(id) ON DELETE CASCADE
Policies (row security enabled): (none)

```

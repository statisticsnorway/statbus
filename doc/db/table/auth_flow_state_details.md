```sql
                                                          Table "auth.flow_state"
         Column         |            Type            | Collation | Nullable | Default | Storage  | Compression | Stats target | Description 
------------------------+----------------------------+-----------+----------+---------+----------+-------------+--------------+-------------
 id                     | uuid                       |           | not null |         | plain    |             |              | 
 user_id                | uuid                       |           |          |         | plain    |             |              | 
 auth_code              | text                       |           | not null |         | extended |             |              | 
 code_challenge_method  | auth.code_challenge_method |           | not null |         | plain    |             |              | 
 code_challenge         | text                       |           | not null |         | extended |             |              | 
 provider_type          | text                       |           | not null |         | extended |             |              | 
 provider_access_token  | text                       |           |          |         | extended |             |              | 
 provider_refresh_token | text                       |           |          |         | extended |             |              | 
 created_at             | timestamp with time zone   |           |          |         | plain    |             |              | 
 updated_at             | timestamp with time zone   |           |          |         | plain    |             |              | 
 authentication_method  | text                       |           | not null |         | extended |             |              | 
 auth_code_issued_at    | timestamp with time zone   |           |          |         | plain    |             |              | 
Indexes:
    "flow_state_pkey" PRIMARY KEY, btree (id)
    "flow_state_created_at_idx" btree (created_at DESC)
    "idx_auth_code" btree (auth_code)
    "idx_user_id_auth_method" btree (user_id, authentication_method)
Referenced by:
    TABLE "auth.saml_relay_states" CONSTRAINT "saml_relay_states_flow_state_id_fkey" FOREIGN KEY (flow_state_id) REFERENCES auth.flow_state(id) ON DELETE CASCADE
Policies (row security enabled): (none)
Access method: heap

```

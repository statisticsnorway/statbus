```sql
                       Table "auth.saml_relay_states"
     Column      |           Type           | Collation | Nullable | Default 
-----------------+--------------------------+-----------+----------+---------
 id              | uuid                     |           | not null | 
 sso_provider_id | uuid                     |           | not null | 
 request_id      | text                     |           | not null | 
 for_email       | text                     |           |          | 
 redirect_to     | text                     |           |          | 
 created_at      | timestamp with time zone |           |          | 
 updated_at      | timestamp with time zone |           |          | 
 flow_state_id   | uuid                     |           |          | 
Indexes:
    "saml_relay_states_pkey" PRIMARY KEY, btree (id)
    "saml_relay_states_created_at_idx" btree (created_at DESC)
    "saml_relay_states_for_email_idx" btree (for_email)
    "saml_relay_states_sso_provider_id_idx" btree (sso_provider_id)
Check constraints:
    "request_id not empty" CHECK (char_length(request_id) > 0)
Foreign-key constraints:
    "saml_relay_states_flow_state_id_fkey" FOREIGN KEY (flow_state_id) REFERENCES auth.flow_state(id) ON DELETE CASCADE
    "saml_relay_states_sso_provider_id_fkey" FOREIGN KEY (sso_provider_id) REFERENCES auth.sso_providers(id) ON DELETE CASCADE
Policies (row security enabled): (none)

```

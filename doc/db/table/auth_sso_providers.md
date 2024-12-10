```sql
                       Table "auth.sso_providers"
   Column    |           Type           | Collation | Nullable | Default 
-------------+--------------------------+-----------+----------+---------
 id          | uuid                     |           | not null | 
 resource_id | text                     |           |          | 
 created_at  | timestamp with time zone |           |          | 
 updated_at  | timestamp with time zone |           |          | 
Indexes:
    "sso_providers_pkey" PRIMARY KEY, btree (id)
    "sso_providers_resource_id_idx" UNIQUE, btree (lower(resource_id))
Check constraints:
    "resource_id not empty" CHECK (resource_id = NULL::text OR char_length(resource_id) > 0)
Referenced by:
    TABLE "auth.saml_providers" CONSTRAINT "saml_providers_sso_provider_id_fkey" FOREIGN KEY (sso_provider_id) REFERENCES auth.sso_providers(id) ON DELETE CASCADE
    TABLE "auth.saml_relay_states" CONSTRAINT "saml_relay_states_sso_provider_id_fkey" FOREIGN KEY (sso_provider_id) REFERENCES auth.sso_providers(id) ON DELETE CASCADE
    TABLE "auth.sso_domains" CONSTRAINT "sso_domains_sso_provider_id_fkey" FOREIGN KEY (sso_provider_id) REFERENCES auth.sso_providers(id) ON DELETE CASCADE
Policies (row security enabled): (none)

```

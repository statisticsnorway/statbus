```sql
                          Table "auth.saml_providers"
      Column       |           Type           | Collation | Nullable | Default 
-------------------+--------------------------+-----------+----------+---------
 id                | uuid                     |           | not null | 
 sso_provider_id   | uuid                     |           | not null | 
 entity_id         | text                     |           | not null | 
 metadata_xml      | text                     |           | not null | 
 metadata_url      | text                     |           |          | 
 attribute_mapping | jsonb                    |           |          | 
 created_at        | timestamp with time zone |           |          | 
 updated_at        | timestamp with time zone |           |          | 
 name_id_format    | text                     |           |          | 
Indexes:
    "saml_providers_pkey" PRIMARY KEY, btree (id)
    "saml_providers_entity_id_key" UNIQUE CONSTRAINT, btree (entity_id)
    "saml_providers_sso_provider_id_idx" btree (sso_provider_id)
Check constraints:
    "entity_id not empty" CHECK (char_length(entity_id) > 0)
    "metadata_url not empty" CHECK (metadata_url = NULL::text OR char_length(metadata_url) > 0)
    "metadata_xml not empty" CHECK (char_length(metadata_xml) > 0)
Foreign-key constraints:
    "saml_providers_sso_provider_id_fkey" FOREIGN KEY (sso_provider_id) REFERENCES auth.sso_providers(id) ON DELETE CASCADE
Policies (row security enabled): (none)

```

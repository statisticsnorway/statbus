```sql
                                                     Table "auth.sso_domains"
     Column      |           Type           | Collation | Nullable | Default | Storage  | Compression | Stats target | Description 
-----------------+--------------------------+-----------+----------+---------+----------+-------------+--------------+-------------
 id              | uuid                     |           | not null |         | plain    |             |              | 
 sso_provider_id | uuid                     |           | not null |         | plain    |             |              | 
 domain          | text                     |           | not null |         | extended |             |              | 
 created_at      | timestamp with time zone |           |          |         | plain    |             |              | 
 updated_at      | timestamp with time zone |           |          |         | plain    |             |              | 
Indexes:
    "sso_domains_pkey" PRIMARY KEY, btree (id)
    "sso_domains_domain_idx" UNIQUE, btree (lower(domain))
    "sso_domains_sso_provider_id_idx" btree (sso_provider_id)
Check constraints:
    "domain not empty" CHECK (char_length(domain) > 0)
Foreign-key constraints:
    "sso_domains_sso_provider_id_fkey" FOREIGN KEY (sso_provider_id) REFERENCES auth.sso_providers(id) ON DELETE CASCADE
Policies (row security enabled): (none)
Access method: heap

```

```sql
                        Table "admin.migrations"
   Column    |           Type           | Collation | Nullable | Default 
-------------+--------------------------+-----------+----------+---------
 version     | text                     |           | not null | 
 filename    | text                     |           | not null | 
 sha256_hash | text                     |           | not null | 
 applied_at  | timestamp with time zone |           | not null | now()
 duration_ms | integer                  |           | not null | 
Indexes:
    "migrations_pkey" PRIMARY KEY, btree (version)
    "migrations_sha256_hash_idx" btree (sha256_hash)
Policies:
    POLICY "migrations_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)

```

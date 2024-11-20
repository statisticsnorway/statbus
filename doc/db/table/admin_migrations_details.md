```sql
                                                   Table "admin.migrations"
   Column    |           Type           | Collation | Nullable | Default | Storage  | Compression | Stats target | Description 
-------------+--------------------------+-----------+----------+---------+----------+-------------+--------------+-------------
 version     | text                     |           | not null |         | extended |             |              | 
 filename    | text                     |           | not null |         | extended |             |              | 
 sha256_hash | text                     |           | not null |         | extended |             |              | 
 applied_at  | timestamp with time zone |           | not null | now()   | plain    |             |              | 
 duration_ms | integer                  |           | not null |         | plain    |             |              | 
Indexes:
    "migrations_pkey" PRIMARY KEY, btree (version)
    "migrations_sha256_hash_idx" btree (sha256_hash)
Policies:
    POLICY "migrations_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
Access method: heap

```

```sql
                                              Table "db.migration"
      Column       |           Type           | Collation | Nullable |                 Default                  
-------------------+--------------------------+-----------+----------+------------------------------------------
 id                | integer                  |           | not null | nextval('db.migration_id_seq'::regclass)
 major_version     | text                     |           | not null | 
 minor_version     | text                     |           |          | 
 filename          | text                     |           | not null | 
 sha256_hash       | text                     |           | not null | 
 applied_at        | timestamp with time zone |           | not null | now()
 duration_ms       | integer                  |           | not null | 
 major_description | text                     |           | not null | 
 minor_description | text                     |           |          | 
Indexes:
    "migration_pkey" PRIMARY KEY, btree (id)
    "migration_major_version_idx" btree (major_version)
    "migration_minor_version_idx" btree (minor_version)
    "migration_sha256_hash_idx" btree (sha256_hash)
Check constraints:
    "major and minor consistency" CHECK (minor_version IS NULL AND minor_description IS NULL OR minor_version IS NOT NULL AND minor_description IS NOT NULL)
Policies:
    POLICY "migration_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)

```

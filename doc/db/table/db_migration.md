```sql
                                           Table "db.migration"
   Column    |           Type           | Collation | Nullable |                 Default                  
-------------+--------------------------+-----------+----------+------------------------------------------
 id          | integer                  |           | not null | nextval('db.migration_id_seq'::regclass)
 version     | bigint                   |           | not null | 
 filename    | text                     |           | not null | 
 description | text                     |           | not null | 
 applied_at  | timestamp with time zone |           | not null | now()
 duration_ms | integer                  |           | not null | 
Indexes:
    "migration_pkey" PRIMARY KEY, btree (id)
    "migration_version_idx" btree (version)
Policies:
    POLICY "migration_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)

```

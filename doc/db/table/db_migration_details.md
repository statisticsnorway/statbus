```sql
                                                                      Table "db.migration"
   Column    |           Type           | Collation | Nullable |                 Default                  | Storage  | Compression | Stats target | Description 
-------------+--------------------------+-----------+----------+------------------------------------------+----------+-------------+--------------+-------------
 id          | integer                  |           | not null | nextval('db.migration_id_seq'::regclass) | plain    |             |              | 
 version     | text                     |           | not null |                                          | extended |             |              | 
 filename    | text                     |           | not null |                                          | extended |             |              | 
 description | text                     |           | not null |                                          | extended |             |              | 
 applied_at  | timestamp with time zone |           | not null | now()                                    | plain    |             |              | 
 duration_ms | integer                  |           | not null |                                          | plain    |             |              | 
Indexes:
    "migration_pkey" PRIMARY KEY, btree (id)
    "migration_version_idx" btree (version)
Policies:
    POLICY "migration_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
Access method: heap

```

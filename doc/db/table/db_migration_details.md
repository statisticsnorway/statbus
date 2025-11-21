```sql
                                                                      Table "db.migration"
   Column    |           Type           | Collation | Nullable |                 Default                  | Storage  | Compression | Stats target | Description 
-------------+--------------------------+-----------+----------+------------------------------------------+----------+-------------+--------------+-------------
 id          | integer                  |           | not null | nextval('db.migration_id_seq'::regclass) | plain    |             |              | 
 version     | bigint                   |           | not null |                                          | plain    |             |              | 
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
Not-null constraints:
    "migration_id_not_null" NOT NULL "id"
    "migration_version_not_null" NOT NULL "version"
    "migration_filename_not_null" NOT NULL "filename"
    "migration_description_not_null" NOT NULL "description"
    "migration_applied_at_not_null" NOT NULL "applied_at"
    "migration_duration_ms_not_null" NOT NULL "duration_ms"
Access method: heap

```

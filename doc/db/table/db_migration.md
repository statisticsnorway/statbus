```sql
                                                                                                                                                                                                                                                                                                                                        Table "db.migration"
    Column    |           Type           | Collation | Nullable |                 Default                  | Storage  | Compression | Stats target |                                                                                                                                                                                                                                                                  Description                                                                                                                                                                                                                                                                   
--------------+--------------------------+-----------+----------+------------------------------------------+----------+-------------+--------------+------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 id           | integer                  |           | not null | nextval('db.migration_id_seq'::regclass) | plain    |             |              | 
 version      | bigint                   |           | not null |                                          | plain    |             |              | 
 filename     | text                     |           | not null |                                          | extended |             |              | 
 description  | text                     |           | not null |                                          | extended |             |              | 
 applied_at   | timestamp with time zone |           | not null | now()                                    | plain    |             |              | 
 duration_ms  | integer                  |           | not null |                                          | plain    |             |              | 
 content_hash | text                     |           | not null |                                          | extended |             |              | sha256 of the migration file bytes at apply time. Backfilled at column-add via hardcoded UPDATE statements in this migration; stamped by the runner on every subsequent INSERT (apply, redo). Mismatch detection fires before the pending-only filter on every `./sb migrate up` — a stored hash that no longer matches the live file is either an immutability violation (released migration edited) or a WIP edit recoverable via `./sb migrate redo <version>`. NOT NULL: silent NULL is structurally impossible. Per plan-rc.66 section R.
Indexes:
    "migration_pkey" PRIMARY KEY, btree (id)
    "migration_version_idx" btree (version)
    "migration_version_unique" UNIQUE CONSTRAINT, btree (version)
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
    "migration_content_hash_not_null" NOT NULL "content_hash"
Access method: heap

```

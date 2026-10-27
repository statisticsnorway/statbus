```sql
                                                                                                         Table "db.extension_upgrade"
    Column    |           Type           | Collation | Nullable |           Default            | Storage  | Compression | Stats target |                                              Description                                              
--------------+--------------------------+-----------+----------+------------------------------+----------+-------------+--------------+-------------------------------------------------------------------------------------------------------
 id           | integer                  |           | not null | generated always as identity | plain    |             |              | 
 extension    | text                     |           | not null |                              | extended |             |              | Extension name (pg_extension.extname).
 from_version | text                     |           |          |                              | extended |             |              | Installed version before the event; NULL when the event created the extension.
 to_version   | text                     |           | not null |                              | extended |             |              | Version after the event: always the database image default (pg_available_extensions.default_version).
 applied_at   | timestamp with time zone |           | not null | now()                        | plain    |             |              | When the runner applied the event.
Indexes:
    "extension_upgrade_pkey" PRIMARY KEY, btree (id)
Policies:
    POLICY "extension_upgrade_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
Not-null constraints:
    "extension_upgrade_id_not_null" NOT NULL "id"
    "extension_upgrade_extension_not_null" NOT NULL "extension"
    "extension_upgrade_to_version_not_null" NOT NULL "to_version"
    "extension_upgrade_applied_at_not_null" NOT NULL "applied_at"
Access method: heap

```

**Comment:** Audit receipt for the migrate runner extension lifecycle step (STATBUS-533): one row per extension create/update event on this database, written before pending migrations are computed. Never lists retired migration IDs; db.migration records schema migrations only.

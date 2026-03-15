```sql
                                                           Table "public.region_version"
   Column    |           Type           | Collation | Nullable |           Default            | Storage  | Compression | Stats target | Description 
-------------+--------------------------+-----------+----------+------------------------------+----------+-------------+--------------+-------------
 id          | integer                  |           | not null | generated always as identity | plain    |             |              | 
 code        | text                     |           | not null |                              | extended |             |              | 
 name        | text                     |           | not null |                              | extended |             |              | 
 description | text                     |           |          |                              | extended |             |              | 
 lasts_to    | date                     |           |          |                              | plain    |             |              | 
 enabled     | boolean                  |           | not null | true                         | plain    |             |              | 
 custom      | boolean                  |           | not null | false                        | plain    |             |              | 
 created_at  | timestamp with time zone |           | not null | statement_timestamp()        | plain    |             |              | 
 updated_at  | timestamp with time zone |           | not null | statement_timestamp()        | plain    |             |              | 
Indexes:
    "region_version_pkey" PRIMARY KEY, btree (id)
    "ix_region_version_enabled_code" UNIQUE, btree (enabled, code)
    "region_version_code_key" UNIQUE CONSTRAINT, btree (code)
    "region_version_enabled_lasts_to_key" UNIQUE, btree (lasts_to) NULLS NOT DISTINCT WHERE enabled
    "region_version_id_enabled_key" UNIQUE, btree (id, enabled)
Referenced by:
    TABLE "location" CONSTRAINT "location_region_version_id_fkey" FOREIGN KEY (region_version_id) REFERENCES region_version(id)
    TABLE "region" CONSTRAINT "region_version_id_fkey" FOREIGN KEY (version_id) REFERENCES region_version(id)
    TABLE "settings" CONSTRAINT "settings_region_version_enabled_fk" FOREIGN KEY (region_version_id, required_to_be_enabled) REFERENCES region_version(id, enabled)
    TABLE "settings" CONSTRAINT "settings_region_version_id_fkey" FOREIGN KEY (region_version_id) REFERENCES region_version(id)
Policies:
    POLICY "region_version_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "region_version_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "region_version_regular_user_read" FOR SELECT
      TO regular_user
      USING (true)
Not-null constraints:
    "region_version_id_not_null" NOT NULL "id"
    "region_version_code_not_null" NOT NULL "code"
    "region_version_name_not_null" NOT NULL "name"
    "region_version_enabled_not_null" NOT NULL "enabled"
    "region_version_custom_not_null" NOT NULL "custom"
    "region_version_created_at_not_null" NOT NULL "created_at"
    "region_version_updated_at_not_null" NOT NULL "updated_at"
Access method: heap

```

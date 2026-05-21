```sql
                                                                                                        Table "public.sector"
   Column    |           Type           | Collation | Nullable |                                                    Default                                                     | Storage  | Compression | Stats target | Description 
-------------+--------------------------+-----------+----------+----------------------------------------------------------------------------------------------------------------+----------+-------------+--------------+-------------
 id          | integer                  |           | not null | generated always as identity                                                                                   | plain    |             |              | 
 path        | ltree                    |           | not null |                                                                                                                | extended |             |              | 
 parent_id   | integer                  |           |          |                                                                                                                | plain    |             |              | 
 label       | character varying        |           | not null | generated always as (replace(path::text, '.'::text, ''::text)) stored                                          | extended |             |              | 
 code        | character varying        |           |          | generated always as (NULLIF(regexp_replace(path::text, '[^0-9]'::text, ''::text, 'g'::text), ''::text)) stored | extended |             |              | 
 name        | text                     |           | not null |                                                                                                                | extended |             |              | 
 description | text                     |           |          |                                                                                                                | extended |             |              | 
 enabled     | boolean                  |           | not null |                                                                                                                | plain    |             |              | 
 custom      | boolean                  |           | not null |                                                                                                                | plain    |             |              | 
 created_at  | timestamp with time zone |           | not null | statement_timestamp()                                                                                          | plain    |             |              | 
 updated_at  | timestamp with time zone |           | not null | statement_timestamp()                                                                                          | plain    |             |              | 
Indexes:
    "sector_pkey" PRIMARY KEY, btree (id)
    "ix_sector_enabled" btree (enabled)
    "ix_sector_enabled_path" UNIQUE, btree (enabled, path)
    "sector_code_enabled_key" UNIQUE, btree (code) WHERE enabled
    "sector_parent_id_idx" btree (parent_id)
    "sector_path_enabled_custom_key" UNIQUE CONSTRAINT, btree (path, enabled, custom)
    "sector_path_key" UNIQUE CONSTRAINT, btree (path)
Referenced by:
    TABLE "establishment" CONSTRAINT "establishment_sector_id_fkey" FOREIGN KEY (sector_id) REFERENCES sector(id) ON DELETE RESTRICT
    TABLE "legal_unit" CONSTRAINT "legal_unit_sector_id_fkey" FOREIGN KEY (sector_id) REFERENCES sector(id) ON DELETE RESTRICT
Policies:
    POLICY "sector_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "sector_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "sector_regular_user_read" FOR SELECT
      TO regular_user
      USING (true)
Not-null constraints:
    "sector_id_not_null" NOT NULL "id"
    "sector_path_not_null" NOT NULL "path"
    "sector_label_not_null" NOT NULL "label"
    "sector_name_not_null" NOT NULL "name"
    "sector_enabled_not_null" NOT NULL "enabled"
    "sector_custom_not_null" NOT NULL "custom"
    "sector_created_at_not_null" NOT NULL "created_at"
    "sector_updated_at_not_null" NOT NULL "updated_at"
Triggers:
    trigger_prevent_sector_id_update BEFORE UPDATE OF id ON sector FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()
Access method: heap

```

```sql
                                                                             Table "public.sector"
   Column    |           Type           | Collation | Nullable |                                                    Default                                                     
-------------+--------------------------+-----------+----------+----------------------------------------------------------------------------------------------------------------
 id          | integer                  |           | not null | generated always as identity
 path        | ltree                    |           | not null | 
 parent_id   | integer                  |           |          | 
 label       | character varying        |           | not null | generated always as (replace(path::text, '.'::text, ''::text)) stored
 code        | character varying        |           |          | generated always as (NULLIF(regexp_replace(path::text, '[^0-9]'::text, ''::text, 'g'::text), ''::text)) stored
 name        | text                     |           | not null | 
 description | text                     |           |          | 
 enabled     | boolean                  |           | not null | 
 custom      | boolean                  |           | not null | 
 created_at  | timestamp with time zone |           | not null | statement_timestamp()
 updated_at  | timestamp with time zone |           | not null | statement_timestamp()
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
Triggers:
    trigger_prevent_sector_id_update BEFORE UPDATE OF id ON sector FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()

```

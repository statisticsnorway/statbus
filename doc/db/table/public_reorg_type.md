```sql
                                  Table "public.reorg_type"
   Column    |           Type           | Collation | Nullable |           Default            
-------------+--------------------------+-----------+----------+------------------------------
 id          | integer                  |           | not null | generated always as identity
 code        | text                     |           | not null | 
 name        | text                     |           | not null | 
 description | text                     |           | not null | 
 enabled     | boolean                  |           | not null | 
 custom      | boolean                  |           | not null | 
 created_at  | timestamp with time zone |           | not null | statement_timestamp()
 updated_at  | timestamp with time zone |           | not null | statement_timestamp()
Indexes:
    "reorg_type_pkey" PRIMARY KEY, btree (id)
    "ix_reorg_type_code" UNIQUE, btree (code) WHERE enabled
    "ix_reorg_type_enabled" btree (enabled)
    "ix_reorg_type_enabled_code" UNIQUE, btree (enabled, code)
    "reorg_type_code_key" UNIQUE CONSTRAINT, btree (code)
Referenced by:
    TABLE "enterprise_group" CONSTRAINT "enterprise_group_reorg_type_id_fkey" FOREIGN KEY (reorg_type_id) REFERENCES reorg_type(id)
Policies:
    POLICY "reorg_type_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "reorg_type_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "reorg_type_regular_user_read" FOR SELECT
      TO regular_user
      USING (true)
Triggers:
    trigger_prevent_reorg_type_id_update BEFORE UPDATE OF id ON reorg_type FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()

```

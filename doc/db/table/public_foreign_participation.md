```sql
                            Table "public.foreign_participation"
   Column   |           Type           | Collation | Nullable |           Default            
------------+--------------------------+-----------+----------+------------------------------
 id         | integer                  |           | not null | generated always as identity
 code       | text                     |           | not null | 
 name       | text                     |           | not null | 
 enabled    | boolean                  |           | not null | 
 custom     | boolean                  |           | not null | 
 created_at | timestamp with time zone |           | not null | statement_timestamp()
 updated_at | timestamp with time zone |           | not null | statement_timestamp()
Indexes:
    "foreign_participation_pkey" PRIMARY KEY, btree (id)
    "ix_foreign_participation_code" UNIQUE, btree (code) WHERE enabled
    "ix_foreign_participation_enabled" btree (enabled)
    "ix_foreign_participation_enabled_code" UNIQUE, btree (enabled, code)
    "ix_status_code" UNIQUE, btree (code) WHERE enabled
Referenced by:
    TABLE "enterprise_group" CONSTRAINT "enterprise_group_foreign_participation_id_fkey" FOREIGN KEY (foreign_participation_id) REFERENCES foreign_participation(id)
    TABLE "legal_unit" CONSTRAINT "legal_unit_foreign_participation_id_fkey" FOREIGN KEY (foreign_participation_id) REFERENCES foreign_participation(id)
Policies:
    POLICY "foreign_participation_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "foreign_participation_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "foreign_participation_regular_user_read" FOR SELECT
      TO regular_user
      USING (true)
Triggers:
    trigger_prevent_foreign_participation_id_update BEFORE UPDATE OF id ON foreign_participation FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()

```

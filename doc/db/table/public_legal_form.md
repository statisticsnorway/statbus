```sql
                                  Table "public.legal_form"
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
    "legal_form_pkey" PRIMARY KEY, btree (id)
    "ix_legal_form_code" UNIQUE, btree (code) WHERE enabled
    "ix_legal_form_enabled" btree (enabled)
    "ix_legal_form_enabled_code" UNIQUE, btree (enabled, code)
    "legal_form_code_enabled_custom_key" UNIQUE CONSTRAINT, btree (code, enabled, custom)
Referenced by:
    TABLE "legal_unit" CONSTRAINT "legal_unit_legal_form_id_fkey" FOREIGN KEY (legal_form_id) REFERENCES legal_form(id)
Policies:
    POLICY "legal_form_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "legal_form_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "legal_form_regular_user_read" FOR SELECT
      TO regular_user
      USING (true)
Triggers:
    trigger_prevent_legal_form_id_update BEFORE UPDATE OF id ON legal_form FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()

```

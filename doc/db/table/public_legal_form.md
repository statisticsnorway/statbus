```sql
                                  Table "public.legal_form"
   Column   |           Type           | Collation | Nullable |           Default            
------------+--------------------------+-----------+----------+------------------------------
 id         | integer                  |           | not null | generated always as identity
 code       | text                     |           | not null | 
 name       | text                     |           | not null | 
 active     | boolean                  |           | not null | 
 custom     | boolean                  |           | not null | 
 updated_at | timestamp with time zone |           | not null | statement_timestamp()
Indexes:
    "legal_form_pkey" PRIMARY KEY, btree (id)
    "ix_legal_form_active_code" UNIQUE, btree (active, code)
    "ix_legal_form_code" UNIQUE, btree (code) WHERE active
    "legal_form_code_active_custom_key" UNIQUE CONSTRAINT, btree (code, active, custom)
Referenced by:
    TABLE "legal_unit" CONSTRAINT "legal_unit_legal_form_id_fkey" FOREIGN KEY (legal_form_id) REFERENCES legal_form(id)
Policies:
    POLICY "legal_form_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "legal_form_regular_user_read" FOR SELECT
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'regular_user'::statbus_role_type))
    POLICY "legal_form_super_user_manage"
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'super_user'::statbus_role_type))
      WITH CHECK (auth.has_statbus_role(auth.uid(), 'super_user'::statbus_role_type))
Triggers:
    trigger_prevent_legal_form_id_update BEFORE UPDATE OF id ON legal_form FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()

```

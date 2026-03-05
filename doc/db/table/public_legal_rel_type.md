```sql
                                      Table "public.legal_rel_type"
         Column          |           Type           | Collation | Nullable |           Default            
-------------------------+--------------------------+-----------+----------+------------------------------
 id                      | integer                  |           | not null | generated always as identity
 code                    | text                     |           | not null | 
 name                    | text                     |           | not null | 
 description             | text                     |           |          | 
 primary_influencer_only | boolean                  |           | not null | false
 enabled                 | boolean                  |           | not null | true
 custom                  | boolean                  |           | not null | false
 created_at              | timestamp with time zone |           | not null | statement_timestamp()
 updated_at              | timestamp with time zone |           | not null | statement_timestamp()
Indexes:
    "legal_rel_type_pkey" PRIMARY KEY, btree (id)
    "ix_legal_rel_type_code" UNIQUE, btree (code) WHERE enabled
    "ix_legal_rel_type_enabled" btree (enabled)
    "ix_legal_rel_type_enabled_code" UNIQUE, btree (enabled, code)
    "legal_rel_type_code_key" UNIQUE CONSTRAINT, btree (code)
    "legal_rel_type_id_primary_influencer_only_key" UNIQUE CONSTRAINT, btree (id, primary_influencer_only)
Referenced by:
    TABLE "legal_relationship" CONSTRAINT "legal_relationship_type_id_fkey" FOREIGN KEY (type_id) REFERENCES legal_rel_type(id) ON DELETE RESTRICT
    TABLE "legal_relationship" CONSTRAINT "legal_relationship_type_id_primary_influencer_only_fkey" FOREIGN KEY (type_id, primary_influencer_only) REFERENCES legal_rel_type(id, primary_influencer_only) ON UPDATE CASCADE
Policies:
    POLICY "legal_rel_type_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "legal_rel_type_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "legal_rel_type_regular_user_read" FOR SELECT
      TO regular_user
      USING (true)
Triggers:
    trigger_prevent_legal_rel_type_id_update BEFORE UPDATE OF id ON legal_rel_type FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()

```

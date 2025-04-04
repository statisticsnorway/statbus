```sql
                             Table "public.external_ident_type"
   Column    |          Type          | Collation | Nullable |           Default            
-------------+------------------------+-----------+----------+------------------------------
 id          | integer                |           | not null | generated always as identity
 code        | character varying(128) |           | not null | 
 name        | character varying(50)  |           |          | 
 by_tag_id   | integer                |           |          | 
 description | text                   |           |          | 
 priority    | integer                |           |          | 
 archived    | boolean                |           | not null | false
Indexes:
    "external_ident_type_pkey" PRIMARY KEY, btree (id)
    "external_ident_type_by_tag_id_key" UNIQUE CONSTRAINT, btree (by_tag_id)
    "external_ident_type_code_key" UNIQUE CONSTRAINT, btree (code)
    "external_ident_type_priority_key" UNIQUE CONSTRAINT, btree (priority)
Foreign-key constraints:
    "external_ident_type_by_tag_id_fkey" FOREIGN KEY (by_tag_id) REFERENCES tag(id) ON DELETE RESTRICT
Referenced by:
    TABLE "external_ident" CONSTRAINT "external_ident_type_id_fkey" FOREIGN KEY (type_id) REFERENCES external_ident_type(id) ON DELETE RESTRICT
Policies:
    POLICY "external_ident_type_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "external_ident_type_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "external_ident_type_regular_user_read" FOR SELECT
      TO regular_user
      USING (true)
Triggers:
    external_ident_type_derive_code_and_name_from_by_tag_id_insert BEFORE INSERT ON external_ident_type FOR EACH ROW WHEN (new.by_tag_id IS NOT NULL) EXECUTE FUNCTION external_ident_type_derive_code_and_name_from_by_tag_id()
    external_ident_type_derive_code_and_name_from_by_tag_id_update BEFORE UPDATE ON external_ident_type FOR EACH ROW WHEN (new.by_tag_id IS NOT NULL AND new.by_tag_id IS DISTINCT FROM old.by_tag_id) EXECUTE FUNCTION external_ident_type_derive_code_and_name_from_by_tag_id()
    external_ident_type_lifecycle_callbacks_after_delete AFTER DELETE ON external_ident_type FOR EACH STATEMENT EXECUTE FUNCTION lifecycle_callbacks.cleanup_and_generate()
    external_ident_type_lifecycle_callbacks_after_insert AFTER INSERT ON external_ident_type FOR EACH STATEMENT EXECUTE FUNCTION lifecycle_callbacks.cleanup_and_generate()
    external_ident_type_lifecycle_callbacks_after_update AFTER UPDATE ON external_ident_type FOR EACH STATEMENT EXECUTE FUNCTION lifecycle_callbacks.cleanup_and_generate()
    trigger_prevent_external_ident_type_id_update BEFORE UPDATE OF id ON external_ident_type FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()

```

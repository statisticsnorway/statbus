```sql
                              Table "public.external_ident_type"
   Column    |          Type          | Collation | Nullable |             Default             
-------------+------------------------+-----------+----------+---------------------------------
 id          | integer                |           | not null | generated always as identity
 code        | character varying(128) |           | not null | 
 name        | character varying(50)  |           |          | 
 shape       | external_ident_shape   |           | not null | 'regular'::external_ident_shape
 labels      | ltree                  |           |          | 
 description | text                   |           |          | 
 priority    | integer                |           |          | 
 enabled     | boolean                |           | not null | true
Indexes:
    "external_ident_type_pkey" PRIMARY KEY, btree (id)
    "external_ident_type_code_key" UNIQUE CONSTRAINT, btree (code)
    "external_ident_type_priority_key" UNIQUE CONSTRAINT, btree (priority)
Check constraints:
    "shape_labels_consistency" CHECK (shape = 'regular'::external_ident_shape AND labels IS NULL OR shape = 'hierarchical'::external_ident_shape AND labels IS NOT NULL)
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
    external_ident_type_lifecycle_callbacks_after_delete AFTER DELETE ON external_ident_type FOR EACH STATEMENT EXECUTE FUNCTION lifecycle_callbacks.cleanup_and_generate()
    external_ident_type_lifecycle_callbacks_after_insert AFTER INSERT ON external_ident_type FOR EACH STATEMENT EXECUTE FUNCTION lifecycle_callbacks.cleanup_and_generate()
    external_ident_type_lifecycle_callbacks_after_update AFTER UPDATE ON external_ident_type FOR EACH STATEMENT EXECUTE FUNCTION lifecycle_callbacks.cleanup_and_generate()
    trigger_prevent_external_ident_type_id_update BEFORE UPDATE OF id ON external_ident_type FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()

```

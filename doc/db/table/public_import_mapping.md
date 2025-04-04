```sql
                         Table "public.import_mapping"
      Column       |           Type           | Collation | Nullable | Default 
-------------------+--------------------------+-----------+----------+---------
 definition_id     | integer                  |           | not null | 
 source_column_id  | integer                  |           |          | 
 source_value      | text                     |           |          | 
 source_expression | import_source_expression |           |          | 
 target_column_id  | integer                  |           |          | 
 created_at        | timestamp with time zone |           | not null | now()
 updated_at        | timestamp with time zone |           | not null | now()
Indexes:
    "unique_source_column_mapping" UNIQUE CONSTRAINT, btree (definition_id, source_column_id)
    "unique_target_column_mapping" UNIQUE CONSTRAINT, btree (definition_id, target_column_id)
Check constraints:
    "at_least_one_column_must_be_defined" CHECK (source_column_id IS NOT NULL OR target_column_id IS NOT NULL)
    "only_one_source_can_be_defined" CHECK (source_column_id IS NOT NULL AND source_value IS NULL AND source_expression IS NULL OR source_column_id IS NULL AND source_value IS NOT NULL AND source_expression IS NULL OR source_column_id IS NULL AND source_value IS NULL AND source_expression IS NOT NULL)
Foreign-key constraints:
    "import_mapping_definition_id_fkey" FOREIGN KEY (definition_id) REFERENCES import_definition(id) ON DELETE CASCADE
    "import_mapping_source_column_id_fkey" FOREIGN KEY (source_column_id) REFERENCES import_source_column(id) ON DELETE CASCADE
    "import_mapping_target_column_id_fkey" FOREIGN KEY (target_column_id) REFERENCES import_target_column(id) ON DELETE CASCADE
Policies:
    POLICY "import_mapping_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "import_mapping_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "import_mapping_regular_user_read" FOR SELECT
      TO regular_user
      USING (true)
Triggers:
    prevent_non_draft_mapping_changes BEFORE INSERT OR DELETE OR UPDATE ON import_mapping FOR EACH ROW EXECUTE FUNCTION admin.prevent_changes_to_non_draft_definition()

```

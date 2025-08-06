```sql
                                                                                                                                  Table "public.import_mapping"
           Column           |            Type            | Collation | Nullable |           Default            | Storage  | Compression | Stats target |                                                               Description                                                                
----------------------------+----------------------------+-----------+----------+------------------------------+----------+-------------+--------------+------------------------------------------------------------------------------------------------------------------------------------------
 id                         | integer                    |           | not null | generated always as identity | plain    |             |              | 
 definition_id              | integer                    |           | not null |                              | plain    |             |              | 
 source_column_id           | integer                    |           |          |                              | plain    |             |              | 
 source_value               | text                       |           |          |                              | extended |             |              | 
 source_expression          | import_source_expression   |           |          |                              | plain    |             |              | 
 target_data_column_id      | integer                    |           |          |                              | plain    |             |              | The target column in the _data table. NULL if is_ignored is true.
 is_ignored                 | boolean                    |           | not null | false                        | plain    |             |              | If true, the source_column_id is explicitly marked as ignored for this import definition, and no target_data_column should be specified.
 target_data_column_purpose | import_data_column_purpose |           |          |                              | plain    |             |              | The purpose of the target data column. Must be 'source_input' if not ignored, NULL if ignored.
 created_at                 | timestamp with time zone   |           | not null | now()                        | plain    |             |              | 
 updated_at                 | timestamp with time zone   |           | not null | now()                        | plain    |             |              | 
Indexes:
    "import_mapping_pkey" PRIMARY KEY, btree (id)
    "idx_unique_target_mapping_when_not_ignored" UNIQUE, btree (definition_id, target_data_column_id) WHERE is_ignored = false
    "unique_source_to_target_mapping" UNIQUE CONSTRAINT, btree (definition_id, source_column_id, target_data_column_id)
Check constraints:
    "mapping_logic" CHECK (is_ignored IS TRUE AND source_column_id IS NOT NULL AND source_value IS NULL AND source_expression IS NULL AND target_data_column_id IS NULL AND target_data_column_purpose IS NULL OR is_ignored IS FALSE AND target_data_column_id IS NOT NULL AND target_data_column_purpose = 'source_input'::import_data_column_purpose AND (source_column_id IS NOT NULL AND source_value IS NULL AND source_expression IS NULL OR source_column_id IS NULL AND source_value IS NOT NULL AND source_expression IS NULL OR source_column_id IS NULL AND source_value IS NULL AND source_expression IS NOT NULL))
Foreign-key constraints:
    "import_mapping_definition_id_fkey" FOREIGN KEY (definition_id) REFERENCES import_definition(id) ON DELETE CASCADE
    "import_mapping_source_column_id_fkey" FOREIGN KEY (source_column_id) REFERENCES import_source_column(id) ON DELETE CASCADE
    "import_mapping_target_data_column_id_fkey" FOREIGN KEY (target_data_column_id) REFERENCES import_data_column(id) ON DELETE CASCADE
    "import_mapping_target_data_column_id_target_data_column_pu_fkey" FOREIGN KEY (target_data_column_id, target_data_column_purpose) REFERENCES import_data_column(id, purpose)
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
    trg_validate_import_mapping_after_change AFTER INSERT OR DELETE OR UPDATE ON import_mapping FOR EACH ROW EXECUTE FUNCTION admin.trigger_validate_import_definition()
Access method: heap

```

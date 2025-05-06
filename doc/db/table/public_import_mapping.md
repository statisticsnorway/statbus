```sql
                                                Table "public.import_mapping"
           Column           |            Type            | Collation | Nullable |                  Default                   
----------------------------+----------------------------+-----------+----------+--------------------------------------------
 id                         | integer                    |           | not null | generated always as identity
 definition_id              | integer                    |           | not null | 
 source_column_id           | integer                    |           |          | 
 source_value               | text                       |           |          | 
 source_expression          | import_source_expression   |           |          | 
 target_data_column_id      | integer                    |           |          | 
 target_data_column_purpose | import_data_column_purpose |           | not null | 'source_input'::import_data_column_purpose
 created_at                 | timestamp with time zone   |           | not null | now()
 updated_at                 | timestamp with time zone   |           | not null | now()
Indexes:
    "import_mapping_pkey" PRIMARY KEY, btree (id)
    "unique_target_data_column_mapping" UNIQUE CONSTRAINT, btree (definition_id, target_data_column_id)
Check constraints:
    "only_one_source_can_be_defined" CHECK (source_column_id IS NOT NULL AND source_value IS NULL AND source_expression IS NULL OR source_column_id IS NULL AND source_value IS NOT NULL AND source_expression IS NULL OR source_column_id IS NULL AND source_value IS NULL AND source_expression IS NOT NULL)
    "target_data_column_must_be_defined" CHECK (target_data_column_id IS NOT NULL)
    "target_data_column_purpose_must_be_source_input" CHECK (target_data_column_purpose = 'source_input'::import_data_column_purpose)
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

```

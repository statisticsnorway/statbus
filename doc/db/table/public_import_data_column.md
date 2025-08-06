```sql
                                     Table "public.import_data_column"
         Column          |            Type            | Collation | Nullable |           Default            
-------------------------+----------------------------+-----------+----------+------------------------------
 id                      | integer                    |           | not null | generated always as identity
 step_id                 | integer                    |           | not null | 
 priority                | integer                    |           |          | 
 column_name             | text                       |           | not null | 
 column_type             | text                       |           | not null | 
 purpose                 | import_data_column_purpose |           | not null | 
 is_nullable             | boolean                    |           | not null | true
 default_value           | text                       |           |          | 
 is_uniquely_identifying | boolean                    |           | not null | false
 created_at              | timestamp with time zone   |           | not null | now()
 updated_at              | timestamp with time zone   |           | not null | now()
Indexes:
    "import_data_column_pkey" PRIMARY KEY, btree (id)
    "import_data_column_id_purpose_key" UNIQUE CONSTRAINT, btree (id, purpose)
    "import_data_column_step_id_column_name_key" UNIQUE CONSTRAINT, btree (step_id, column_name)
Check constraints:
    "unique_identifying_only_for_source_input" CHECK (NOT is_uniquely_identifying OR purpose = 'source_input'::import_data_column_purpose)
Foreign-key constraints:
    "import_data_column_step_id_fkey" FOREIGN KEY (step_id) REFERENCES import_step(id) ON DELETE CASCADE
Referenced by:
    TABLE "import_mapping" CONSTRAINT "import_mapping_target_data_column_id_fkey" FOREIGN KEY (target_data_column_id) REFERENCES import_data_column(id) ON DELETE CASCADE
    TABLE "import_mapping" CONSTRAINT "import_mapping_target_data_column_id_target_data_column_pu_fkey" FOREIGN KEY (target_data_column_id, target_data_column_purpose) REFERENCES import_data_column(id, purpose)
Policies:
    POLICY "import_data_column_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "import_data_column_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "import_data_column_regular_user_read" FOR SELECT
      TO regular_user
      USING (true)
Triggers:
    trg_validate_import_data_column_after_change AFTER INSERT OR DELETE OR UPDATE ON import_data_column FOR EACH ROW EXECUTE FUNCTION admin.trigger_validate_import_definition()

```

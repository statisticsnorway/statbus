```sql
                                                                                                                                        Table "public.import_data_column"
         Column          |            Type            | Collation | Nullable |           Default            | Storage  | Compression | Stats target |                                                                        Description                                                                         
-------------------------+----------------------------+-----------+----------+------------------------------+----------+-------------+--------------+------------------------------------------------------------------------------------------------------------------------------------------------------------
 id                      | integer                    |           | not null | generated always as identity | plain    |             |              | 
 step_id                 | integer                    |           | not null |                              | plain    |             |              | The import step this column is associated with (NULL for global metadata columns like state, error).
 priority                | integer                    |           |          |                              | plain    |             |              | 
 column_name             | text                       |           | not null |                              | extended |             |              | 
 column_type             | text                       |           | not null |                              | extended |             |              | 
 purpose                 | import_data_column_purpose |           | not null |                              | plain    |             |              | Role of the column in the _data table (source_input, internal, pk_id, metadata).
 is_nullable             | boolean                    |           | not null | true                         | plain    |             |              | Whether the column in the _data table can be NULL.
 default_value           | text                       |           |          |                              | extended |             |              | SQL default value expression for the column in the _data table.
 is_uniquely_identifying | boolean                    |           | not null | false                        | plain    |             |              | Indicates if this data column (must have purpose=source_input) contributes to the unique identification of a row for UPSERT logic during the prepare step.
 created_at              | timestamp with time zone   |           | not null | now()                        | plain    |             |              | 
 updated_at              | timestamp with time zone   |           | not null | now()                        | plain    |             |              | 
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
Not-null constraints:
    "import_data_column_id_not_null" NOT NULL "id"
    "import_data_column_step_id_not_null" NOT NULL "step_id"
    "import_data_column_column_name_not_null" NOT NULL "column_name"
    "import_data_column_column_type_not_null" NOT NULL "column_type"
    "import_data_column_purpose_not_null" NOT NULL "purpose"
    "import_data_column_is_nullable_not_null" NOT NULL "is_nullable"
    "import_data_column_is_uniquely_identifying_not_null" NOT NULL "is_uniquely_identifying"
    "import_data_column_created_at_not_null" NOT NULL "created_at"
    "import_data_column_updated_at_not_null" NOT NULL "updated_at"
Triggers:
    trg_validate_import_data_column_after_change AFTER INSERT OR DELETE OR UPDATE ON import_data_column FOR EACH ROW EXECUTE FUNCTION admin.trigger_validate_import_definition()
Access method: heap

```

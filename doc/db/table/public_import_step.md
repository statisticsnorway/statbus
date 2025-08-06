```sql
                                     Table "public.import_step"
      Column       |           Type           | Collation | Nullable |           Default            
-------------------+--------------------------+-----------+----------+------------------------------
 id                | integer                  |           | not null | generated always as identity
 code              | text                     |           | not null | 
 name              | text                     |           | not null | 
 priority          | integer                  |           | not null | 
 analyse_procedure | regproc                  |           |          | 
 process_procedure | regproc                  |           |          | 
 created_at        | timestamp with time zone |           | not null | now()
 updated_at        | timestamp with time zone |           | not null | now()
Indexes:
    "import_step_pkey" PRIMARY KEY, btree (id)
    "import_step_code_key" UNIQUE CONSTRAINT, btree (code)
Referenced by:
    TABLE "import_data_column" CONSTRAINT "import_data_column_step_id_fkey" FOREIGN KEY (step_id) REFERENCES import_step(id) ON DELETE CASCADE
    TABLE "import_definition_step" CONSTRAINT "import_definition_step_step_id_fkey" FOREIGN KEY (step_id) REFERENCES import_step(id) ON DELETE CASCADE
Policies:
    POLICY "import_step_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "import_step_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "import_step_regular_user_read" FOR SELECT
      TO regular_user
      USING (true)
Triggers:
    trg_validate_import_step_after_change AFTER INSERT OR DELETE OR UPDATE ON import_step FOR EACH ROW EXECUTE FUNCTION admin.trigger_validate_import_definition()

```

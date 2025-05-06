```sql
                                                                                                                               Table "public.import_step"
      Column       |           Type           | Collation | Nullable |           Default            | Storage  | Compression | Stats target |                                                                Description                                                                
-------------------+--------------------------+-----------+----------+------------------------------+----------+-------------+--------------+-------------------------------------------------------------------------------------------------------------------------------------------
 id                | integer                  |           | not null | generated always as identity | plain    |             |              | 
 code              | text                     |           | not null |                              | extended |             |              | Unique code identifier for the step (snake_case).
 name              | text                     |           | not null |                              | extended |             |              | Human-readable name for UI display.
 priority          | integer                  |           | not null |                              | plain    |             |              | Execution order for the step (lower runs first).
 analyse_procedure | regproc                  |           |          |                              | plain    |             |              | Optional procedure to run during the analysis phase for this step.
 process_procedure | regproc                  |           |          |                              | plain    |             |              | Optional procedure to run during the final operation (insert/update/upsert) phase for this step. Must respect import_definition.strategy.
 created_at        | timestamp with time zone |           | not null | now()                        | plain    |             |              | 
 updated_at        | timestamp with time zone |           | not null | now()                        | plain    |             |              | 
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
Access method: heap

```

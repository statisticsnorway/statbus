```sql
                                                                                                                                                  Table "public.import_step"
      Column       |           Type           | Collation | Nullable |           Default            | Storage  | Compression | Stats target |                                                                                   Description                                                                                    
-------------------+--------------------------+-----------+----------+------------------------------+----------+-------------+--------------+----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 id                | integer                  |           | not null | generated always as identity | plain    |             |              | 
 code              | text                     |           | not null |                              | extended |             |              | Unique code identifier for the step (snake_case).
 name              | text                     |           | not null |                              | extended |             |              | Human-readable name for UI display.
 priority          | integer                  |           | not null |                              | plain    |             |              | Execution order for the step (lower runs first).
 analyse_procedure | regproc                  |           |          |                              | plain    |             |              | Optional procedure to run during the analysis phase for this step.
 process_procedure | regproc                  |           |          |                              | plain    |             |              | Optional procedure to run during the final operation (insert/update/upsert) phase for this step. Must respect import_definition.strategy.
 is_holistic       | boolean                  |           | not null |                              | plain    |             |              | If true, the step's procedure is called once for the entire dataset, not in concurrent batches. Use for steps requiring a complete view of the data, like cross-row validations.
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
Not-null constraints:
    "import_step_id_not_null" NOT NULL "id"
    "import_step_code_not_null" NOT NULL "code"
    "import_step_name_not_null" NOT NULL "name"
    "import_step_priority_not_null" NOT NULL "priority"
    "import_step_is_holistic_not_null" NOT NULL "is_holistic"
    "import_step_created_at_not_null" NOT NULL "created_at"
    "import_step_updated_at_not_null" NOT NULL "updated_at"
Triggers:
    trg_validate_import_step_after_change AFTER INSERT OR DELETE OR UPDATE ON import_step FOR EACH ROW EXECUTE FUNCTION admin.trigger_validate_import_definition()
Access method: heap

```

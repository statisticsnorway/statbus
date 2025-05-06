```sql
                                  Table "public.import_definition"
       Column       |           Type           | Collation | Nullable |           Default            
--------------------+--------------------------+-----------+----------+------------------------------
 id                 | integer                  |           | not null | generated always as identity
 slug               | text                     |           | not null | 
 name               | text                     |           | not null | 
 note               | text                     |           |          | 
 data_source_id     | integer                  |           |          | 
 time_context_ident | text                     |           |          | 
 strategy           | import_strategy          |           | not null | 'upsert'::import_strategy
 user_id            | integer                  |           |          | 
 valid              | boolean                  |           | not null | false
 validation_error   | text                     |           |          | 
 created_at         | timestamp with time zone |           | not null | now()
 updated_at         | timestamp with time zone |           | not null | now()
Indexes:
    "import_definition_pkey" PRIMARY KEY, btree (id)
    "import_definition_name_key" UNIQUE CONSTRAINT, btree (name)
    "import_definition_slug_key" UNIQUE CONSTRAINT, btree (slug)
    "ix_import_data_source_id" btree (data_source_id)
    "ix_import_user_id" btree (user_id)
Foreign-key constraints:
    "import_definition_data_source_id_fkey" FOREIGN KEY (data_source_id) REFERENCES data_source(id) ON DELETE RESTRICT
    "import_definition_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth."user"(id) ON DELETE SET NULL
Referenced by:
    TABLE "import_definition_step" CONSTRAINT "import_definition_step_definition_id_fkey" FOREIGN KEY (definition_id) REFERENCES import_definition(id) ON DELETE CASCADE
    TABLE "import_job" CONSTRAINT "import_job_definition_id_fkey" FOREIGN KEY (definition_id) REFERENCES import_definition(id) ON DELETE CASCADE
    TABLE "import_mapping" CONSTRAINT "import_mapping_definition_id_fkey" FOREIGN KEY (definition_id) REFERENCES import_definition(id) ON DELETE CASCADE
    TABLE "import_source_column" CONSTRAINT "import_source_column_definition_id_fkey" FOREIGN KEY (definition_id) REFERENCES import_definition(id) ON DELETE CASCADE
Policies:
    POLICY "import_definition_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "import_definition_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "import_definition_regular_user_read" FOR SELECT
      TO regular_user
      USING (true)

```

```sql
                                                                                                                                       Table "public.import_definition"
          Column          |           Type           | Collation | Nullable |               Default                | Storage  | Compression | Stats target |                                                                   Description                                                                    
--------------------------+--------------------------+-----------+----------+--------------------------------------+----------+-------------+--------------+--------------------------------------------------------------------------------------------------------------------------------------------------
 id                       | integer                  |           | not null | generated always as identity         | plain    |             |              | 
 slug                     | text                     |           | not null |                                      | extended |             |              | 
 name                     | text                     |           | not null |                                      | extended |             |              | 
 note                     | text                     |           |          |                                      | extended |             |              | 
 data_source_id           | integer                  |           |          |                                      | plain    |             |              | 
 time_context_ident       | text                     |           |          |                                      | extended |             |              | 
 strategy                 | import_strategy          |           | not null | 'insert_or_replace'::import_strategy | plain    |             |              | Defines the strategy (insert_or_replace, insert_only, replace_only, insert_or_update, update_only) for the final insertion step.
 mode                     | import_mode              |           |          |                                      | plain    |             |              | Defines the structural mode of the import, e.g., if an establishment is linked to a legal unit (formal) or directly to an enterprise (informal).
 user_id                  | integer                  |           |          |                                      | plain    |             |              | 
 valid                    | boolean                  |           | not null | false                                | plain    |             |              | Indicates if the definition passes validation checks.
 validation_error         | text                     |           |          |                                      | extended |             |              | Stores validation error messages if not valid.
 default_retention_period | interval                 |           | not null | '1 year 6 mons'::interval            | plain    |             |              | Default period after which related job data (job record, _upload, _data tables) can be cleaned up. Calculated from job creation time.
 created_at               | timestamp with time zone |           | not null | now()                                | plain    |             |              | 
 updated_at               | timestamp with time zone |           | not null | now()                                | plain    |             |              | 
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
Access method: heap

```

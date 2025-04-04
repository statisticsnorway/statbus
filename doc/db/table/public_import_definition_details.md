```sql
                                                             Table "public.import_definition"
       Column       |           Type           | Collation | Nullable |           Default            | Storage  | Compression | Stats target | Description 
--------------------+--------------------------+-----------+----------+------------------------------+----------+-------------+--------------+-------------
 id                 | integer                  |           | not null | generated always as identity | plain    |             |              | 
 slug               | text                     |           | not null |                              | extended |             |              | 
 name               | text                     |           | not null |                              | extended |             |              | 
 target_id          | integer                  |           |          |                              | plain    |             |              | 
 note               | text                     |           |          |                              | extended |             |              | 
 data_source_id     | integer                  |           |          |                              | plain    |             |              | 
 time_context_ident | text                     |           |          |                              | extended |             |              | 
 user_id            | integer                  |           |          |                              | plain    |             |              | 
 draft              | boolean                  |           | not null | true                         | plain    |             |              | 
 valid              | boolean                  |           | not null | false                        | plain    |             |              | 
 validation_error   | text                     |           |          |                              | extended |             |              | 
 created_at         | timestamp with time zone |           | not null | now()                        | plain    |             |              | 
 updated_at         | timestamp with time zone |           | not null | now()                        | plain    |             |              | 
Indexes:
    "import_definition_pkey" PRIMARY KEY, btree (id)
    "import_definition_name_key" UNIQUE CONSTRAINT, btree (name)
    "import_definition_slug_key" UNIQUE CONSTRAINT, btree (slug)
    "ix_import_data_source_id" btree (data_source_id)
    "ix_import_user_id" btree (user_id)
Check constraints:
    "draft_valid_error_states" CHECK (
CASE
    WHEN draft THEN NOT valid
    WHEN NOT draft THEN valid AND validation_error IS NULL
    ELSE false
END)
Foreign-key constraints:
    "import_definition_data_source_id_fkey" FOREIGN KEY (data_source_id) REFERENCES data_source(id) ON DELETE RESTRICT
    "import_definition_target_id_fkey" FOREIGN KEY (target_id) REFERENCES import_target(id) ON DELETE CASCADE
    "import_definition_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth."user"(id) ON DELETE SET NULL
Referenced by:
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
Triggers:
    prevent_non_draft_changes BEFORE UPDATE ON import_definition FOR EACH ROW EXECUTE FUNCTION admin.prevent_changes_to_non_draft_definition()
    validate_on_draft_change BEFORE UPDATE OF draft ON import_definition FOR EACH ROW WHEN (old.draft = true AND new.draft = false) EXECUTE FUNCTION admin.import_definition_validate_before()
    validate_time_context_ident_trigger BEFORE INSERT OR UPDATE OF time_context_ident ON import_definition FOR EACH ROW EXECUTE FUNCTION admin.validate_time_context_ident()
Access method: heap

```

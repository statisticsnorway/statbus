```sql
                                                                                                                                                                              Table "public.import_job"
          Column          |           Type           | Collation | Nullable |                Default                 | Storage  | Compression | Stats target |                                                                                                      Description                                                                                                       
--------------------------+--------------------------+-----------+----------+----------------------------------------+----------+-------------+--------------+------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 id                       | integer                  |           | not null | generated always as identity           | plain    |             |              | 
 slug                     | text                     |           | not null |                                        | extended |             |              | 
 description              | text                     |           |          |                                        | extended |             |              | 
 note                     | text                     |           |          |                                        | extended |             |              | 
 created_at               | timestamp with time zone |           | not null | now()                                  | plain    |             |              | 
 updated_at               | timestamp with time zone |           | not null | now()                                  | plain    |             |              | 
 time_context_ident       | text                     |           |          |                                        | extended |             |              | 
 default_valid_from       | date                     |           |          |                                        | plain    |             |              | 
 default_valid_to         | date                     |           |          |                                        | plain    |             |              | 
 default_data_source_code | text                     |           |          |                                        | extended |             |              | 
 upload_table_name        | text                     |           | not null |                                        | extended |             |              | 
 data_table_name          | text                     |           | not null |                                        | extended |             |              | 
 priority                 | integer                  |           |          |                                        | plain    |             |              | 
 definition_snapshot      | jsonb                    |           |          |                                        | extended |             |              | Captures the complete state of an `import_definition` and its related entities at job creation. This ensures immutable processing. The structure is a JSONB object with keys corresponding to the source tables/views:+
                          |                          |           |          |                                        |          |             |              | - `import_definition`: A JSON representation of the `public.import_definition` row.                                                                                                                                   +
                          |                          |           |          |                                        |          |             |              | - `time_context` (optional): If `valid_time_from = 'time_context'`, a JSON representation of the `public.time_context` row.                                                                                           +
                          |                          |           |          |                                        |          |             |              | - `import_step_list`: An array of `public.import_step` JSON objects for the definition.                                                                                                                               +
                          |                          |           |          |                                        |          |             |              | - `import_data_column_list`: An array of `public.import_data_column` JSON objects for the definition's steps.                                                                                                         +
                          |                          |           |          |                                        |          |             |              | - `import_source_column_list`: An array of `public.import_source_column` JSON objects for the definition.                                                                                                             +
                          |                          |           |          |                                        |          |             |              | - `import_mapping_list`: An array of enriched mapping objects, each containing the mapping, source column, and target data column records.
 preparing_data_at        | timestamp with time zone |           |          |                                        | plain    |             |              | 
 analysis_start_at        | timestamp with time zone |           |          |                                        | plain    |             |              | 
 analysis_stop_at         | timestamp with time zone |           |          |                                        | plain    |             |              | 
 changes_approved_at      | timestamp with time zone |           |          |                                        | plain    |             |              | 
 changes_rejected_at      | timestamp with time zone |           |          |                                        | plain    |             |              | 
 processing_start_at      | timestamp with time zone |           |          |                                        | plain    |             |              | 
 processing_stop_at       | timestamp with time zone |           |          |                                        | plain    |             |              | 
 total_rows               | integer                  |           |          |                                        | plain    |             |              | 
 imported_rows            | integer                  |           |          | 0                                      | plain    |             |              | 
 import_completed_pct     | numeric(5,2)             |           |          | 0                                      | main     |             |              | 
 import_rows_per_sec      | numeric(10,2)            |           |          |                                        | main     |             |              | 
 last_progress_update     | timestamp with time zone |           |          |                                        | plain    |             |              | 
 state                    | import_job_state         |           | not null | 'waiting_for_upload'::import_job_state | plain    |             |              | 
 error                    | text                     |           |          |                                        | extended |             |              | 
 review                   | boolean                  |           | not null | false                                  | plain    |             |              | 
 edit_comment             | text                     |           |          |                                        | extended |             |              | Default edit comment to be applied to records processed by this job.
 expires_at               | timestamp with time zone |           | not null |                                        | plain    |             |              | Timestamp when the job and its associated data (_upload, _data tables) are eligible for cleanup. Calculated as created_at + import_definition.default_retention_period.
 definition_id            | integer                  |           | not null |                                        | plain    |             |              | 
 user_id                  | integer                  |           |          |                                        | plain    |             |              | 
Indexes:
    "import_job_pkey" PRIMARY KEY, btree (id)
    "import_job_slug_key" UNIQUE CONSTRAINT, btree (slug)
    "ix_import_job_definition_id" btree (definition_id)
    "ix_import_job_expires_at" btree (expires_at)
    "ix_import_job_user_id" btree (user_id)
Check constraints:
    "import_job_default_valid_from_to_consistency_check" CHECK (default_valid_from IS NULL AND default_valid_to IS NULL OR default_valid_from IS NOT NULL AND default_valid_to IS NOT NULL AND default_valid_from <= default_valid_to)
    "job_parameters_must_match_valid_time_from_mode" CHECK (
CASE (definition_snapshot -> 'import_definition'::text) ->> 'valid_time_from'::text
    WHEN 'job_provided'::text THEN default_valid_from IS NOT NULL AND default_valid_to IS NOT NULL
    WHEN 'source_columns'::text THEN time_context_ident IS NULL AND default_valid_from IS NULL AND default_valid_to IS NULL
    ELSE true
END)
    "snapshot_has_import_data_column_list" CHECK (definition_snapshot ? 'import_data_column_list'::text)
    "snapshot_has_import_definition" CHECK (definition_snapshot ? 'import_definition'::text)
    "snapshot_has_import_mapping_list" CHECK (definition_snapshot ? 'import_mapping_list'::text)
    "snapshot_has_import_source_column_list" CHECK (definition_snapshot ? 'import_source_column_list'::text)
    "snapshot_has_import_step_list" CHECK (definition_snapshot ? 'import_step_list'::text)
    "snapshot_has_time_context_conditionally" CHECK (((definition_snapshot -> 'import_definition'::text) ->> 'valid_time_from'::text) = 'time_context'::text AND definition_snapshot ? 'time_context'::text OR ((definition_snapshot -> 'import_definition'::text) ->> 'valid_time_from'::text) <> 'time_context'::text)
Foreign-key constraints:
    "import_job_definition_id_fkey" FOREIGN KEY (definition_id) REFERENCES import_definition(id) ON DELETE CASCADE
    "import_job_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth."user"(id) ON DELETE SET NULL
Policies:
    POLICY "import_job_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "import_job_authenticated_select_all" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "import_job_regular_user_delete_own" FOR DELETE
      TO regular_user
      USING ((user_id = auth.uid()))
    POLICY "import_job_regular_user_insert_own" FOR INSERT
      TO regular_user
      WITH CHECK ((user_id = auth.uid()))
    POLICY "import_job_regular_user_update_own" FOR UPDATE
      TO regular_user
      USING ((user_id = auth.uid()))
      WITH CHECK ((user_id = auth.uid()))
Triggers:
    import_job_cleanup BEFORE DELETE OR UPDATE OF upload_table_name, data_table_name ON import_job FOR EACH ROW EXECUTE FUNCTION admin.import_job_cleanup()
    import_job_derive_trigger BEFORE INSERT ON import_job FOR EACH ROW EXECUTE FUNCTION admin.import_job_derive()
    import_job_generate AFTER INSERT OR UPDATE OF upload_table_name, data_table_name ON import_job FOR EACH ROW EXECUTE FUNCTION admin.import_job_generate()
    import_job_notify_trigger AFTER INSERT OR DELETE OR UPDATE ON import_job FOR EACH ROW EXECUTE FUNCTION admin.import_job_notify()
    import_job_progress_notify_trigger AFTER UPDATE OF imported_rows, state ON import_job FOR EACH ROW EXECUTE FUNCTION admin.import_job_progress_notify()
    import_job_progress_update_trigger BEFORE UPDATE OF imported_rows ON import_job FOR EACH ROW EXECUTE FUNCTION admin.import_job_progress_update()
    import_job_state_change_after_trigger AFTER UPDATE OF state ON import_job FOR EACH ROW EXECUTE FUNCTION admin.import_job_state_change_after()
    import_job_state_change_before_trigger BEFORE UPDATE OF state ON import_job FOR EACH ROW EXECUTE FUNCTION admin.import_job_state_change_before()
Access method: heap

```

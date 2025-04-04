```sql
                                                     Table "public.import_job"
                 Column                 |           Type           | Collation | Nullable |                Default                 
----------------------------------------+--------------------------+-----------+----------+----------------------------------------
 id                                     | integer                  |           | not null | generated always as identity
 slug                                   | text                     |           | not null | 
 description                            | text                     |           |          | 
 note                                   | text                     |           |          | 
 default_valid_from                     | date                     |           |          | 
 default_valid_to                       | date                     |           |          | 
 default_data_source_code               | text                     |           |          | 
 upload_table_name                      | text                     |           | not null | 
 data_table_name                        | text                     |           | not null | 
 target_table_name                      | text                     |           | not null | 
 target_schema_name                     | text                     |           | not null | 
 priority                               | integer                  |           |          | 
 import_information_snapshot_table_name | text                     |           | not null | 
 analysis_start_at                      | timestamp with time zone |           |          | 
 analysis_stop_at                       | timestamp with time zone |           |          | 
 preparing_data_at                      | timestamp with time zone |           |          | 
 changes_approved_at                    | timestamp with time zone |           |          | 
 changes_rejected_at                    | timestamp with time zone |           |          | 
 import_start_at                        | timestamp with time zone |           |          | 
 import_stop_at                         | timestamp with time zone |           |          | 
 total_rows                             | integer                  |           |          | 
 imported_rows                          | integer                  |           |          | 0
 import_completed_pct                   | numeric(5,2)             |           |          | 0
 import_rows_per_sec                    | numeric(10,2)            |           |          | 
 last_progress_update                   | timestamp with time zone |           |          | 
 state                                  | import_job_state         |           | not null | 'waiting_for_upload'::import_job_state
 error                                  | text                     |           |          | 
 review                                 | boolean                  |           | not null | false
 definition_id                          | integer                  |           | not null | 
 user_id                                | integer                  |           |          | 
Indexes:
    "import_job_pkey" PRIMARY KEY, btree (id)
    "import_job_slug_key" UNIQUE CONSTRAINT, btree (slug)
    "ix_import_job_definition_id" btree (definition_id)
    "ix_import_job_user_id" btree (user_id)
Foreign-key constraints:
    "import_job_definition_id_fkey" FOREIGN KEY (definition_id) REFERENCES import_definition(id) ON DELETE CASCADE
    "import_job_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth."user"(id) ON DELETE SET NULL
Policies:
    POLICY "import_job_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "import_job_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "import_job_regular_user_manage"
      TO regular_user
      USING (true)
      WITH CHECK (true)
Triggers:
    import_job_cleanup BEFORE DELETE OR UPDATE OF upload_table_name, data_table_name ON import_job FOR EACH ROW EXECUTE FUNCTION admin.import_job_cleanup()
    import_job_derive_trigger BEFORE INSERT ON import_job FOR EACH ROW EXECUTE FUNCTION admin.import_job_derive()
    import_job_generate AFTER INSERT OR UPDATE OF upload_table_name, data_table_name ON import_job FOR EACH ROW EXECUTE FUNCTION admin.import_job_generate()
    import_job_progress_notify_trigger AFTER UPDATE OF imported_rows, state ON import_job FOR EACH ROW EXECUTE FUNCTION admin.import_job_progress_notify()
    import_job_progress_update_trigger BEFORE UPDATE OF imported_rows ON import_job FOR EACH ROW EXECUTE FUNCTION admin.import_job_progress_update()
    import_job_state_change_after_trigger AFTER UPDATE OF state ON import_job FOR EACH ROW EXECUTE FUNCTION admin.import_job_state_change_after()
    import_job_state_change_before_trigger BEFORE UPDATE OF state ON import_job FOR EACH ROW EXECUTE FUNCTION admin.import_job_state_change_before()

```

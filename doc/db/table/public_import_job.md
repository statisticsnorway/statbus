```sql
                                              Table "public.import_job"
          Column          |           Type           | Collation | Nullable |                Default                 
--------------------------+--------------------------+-----------+----------+----------------------------------------
 id                       | integer                  |           | not null | generated always as identity
 slug                     | text                     |           | not null | 
 description              | text                     |           |          | 
 note                     | text                     |           |          | 
 created_at               | timestamp with time zone |           | not null | now()
 updated_at               | timestamp with time zone |           | not null | now()
 default_valid_from       | date                     |           |          | 
 default_valid_to         | date                     |           |          | 
 default_data_source_code | text                     |           |          | 
 upload_table_name        | text                     |           | not null | 
 data_table_name          | text                     |           | not null | 
 priority                 | integer                  |           |          | 
 definition_snapshot      | jsonb                    |           |          | 
 preparing_data_at        | timestamp with time zone |           |          | 
 analysis_start_at        | timestamp with time zone |           |          | 
 analysis_stop_at         | timestamp with time zone |           |          | 
 changes_approved_at      | timestamp with time zone |           |          | 
 changes_rejected_at      | timestamp with time zone |           |          | 
 processing_start_at      | timestamp with time zone |           |          | 
 processing_stop_at       | timestamp with time zone |           |          | 
 total_rows               | integer                  |           |          | 
 imported_rows            | integer                  |           |          | 0
 import_completed_pct     | numeric(5,2)             |           |          | 0
 import_rows_per_sec      | numeric(10,2)            |           |          | 
 last_progress_update     | timestamp with time zone |           |          | 
 state                    | import_job_state         |           | not null | 'waiting_for_upload'::import_job_state
 error                    | text                     |           |          | 
 review                   | boolean                  |           | not null | false
 edit_comment             | text                     |           |          | 
 expires_at               | timestamp with time zone |           | not null | 
 definition_id            | integer                  |           | not null | 
 user_id                  | integer                  |           |          | 
Indexes:
    "import_job_pkey" PRIMARY KEY, btree (id)
    "import_job_slug_key" UNIQUE CONSTRAINT, btree (slug)
    "ix_import_job_definition_id" btree (definition_id)
    "ix_import_job_expires_at" btree (expires_at)
    "ix_import_job_user_id" btree (user_id)
Foreign-key constraints:
    "import_job_definition_id_fkey" FOREIGN KEY (definition_id) REFERENCES import_definition(id) ON DELETE CASCADE
    "import_job_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth."user"(id) ON DELETE SET NULL
Policies:
    POLICY "import_job_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "import_job_authenticated_select_own" FOR SELECT
      TO authenticated
      USING ((user_id = auth.uid()))
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

```

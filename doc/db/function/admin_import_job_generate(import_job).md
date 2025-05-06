```sql
CREATE OR REPLACE FUNCTION admin.import_job_generate(job import_job)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    create_upload_table_stmt text;
    create_data_table_stmt text;
    -- snapshot table variables removed
    add_separator BOOLEAN := FALSE;
    col_rec RECORD;
    source_col_rec RECORD;
BEGIN
  -- Snapshot table creation/population is now handled in import_job_derive trigger
  RAISE DEBUG '[Job %] Generating tables: %, %', job.id, job.upload_table_name, job.data_table_name;

  -- 1. Create Upload Table
  RAISE DEBUG '[Job %] Generating upload table %', job.id, job.upload_table_name;
  create_upload_table_stmt := format('CREATE TABLE public.%I (', job.upload_table_name);
  add_separator := FALSE;
  FOR source_col_rec IN
      SELECT column_name FROM public.import_source_column
      WHERE definition_id = job.definition_id
      ORDER BY priority
  LOOP
    IF add_separator THEN
        create_upload_table_stmt := create_upload_table_stmt || ', ';
    END IF;
    create_upload_table_stmt := create_upload_table_stmt || format('%I TEXT', source_col_rec.column_name);
    add_separator := TRUE;
  END LOOP;
  create_upload_table_stmt := create_upload_table_stmt || ');';

  RAISE DEBUG '[Job %] Upload table DDL: %', job.id, create_upload_table_stmt;
  EXECUTE create_upload_table_stmt;

  -- Add triggers to upload table
  EXECUTE format('
      CREATE TRIGGER %I_check_state_before_insert
      BEFORE INSERT ON public.%I FOR EACH STATEMENT
      EXECUTE FUNCTION admin.check_import_job_state_for_insert(%L);',
      job.upload_table_name, job.upload_table_name, job.slug);
  EXECUTE format('
      CREATE TRIGGER %I_update_state_after_insert
      AFTER INSERT ON public.%I FOR EACH STATEMENT
      EXECUTE FUNCTION admin.update_import_job_state_after_insert(%L);',
      job.upload_table_name, job.upload_table_name, job.slug);
  RAISE DEBUG '[Job %] Added triggers to upload table %', job.id, job.upload_table_name;

  -- 2. Create Data Table
  RAISE DEBUG '[Job %] Generating data table %', job.id, job.data_table_name;
  create_data_table_stmt := format('CREATE TABLE public.%I (', job.data_table_name);
  add_separator := FALSE;

  -- Add columns based on import_data_column records associated with the steps linked to this job's definition
  FOR col_rec IN
      SELECT dc.column_name, dc.column_type, dc.is_nullable, dc.default_value
      FROM public.import_definition_step ds
      JOIN public.import_step s ON ds.step_id = s.id
      JOIN public.import_data_column dc ON dc.step_id = s.id -- Join data columns via step_id
      WHERE ds.definition_id = job.definition_id
      ORDER BY s.priority, dc.priority
  LOOP
    IF add_separator THEN
        create_data_table_stmt := create_data_table_stmt || ', ';
    END IF;
    create_data_table_stmt := create_data_table_stmt || format('%I %s', col_rec.column_name, col_rec.column_type);
    IF NOT col_rec.is_nullable THEN
        create_data_table_stmt := create_data_table_stmt || ' NOT NULL';
    END IF;
    IF col_rec.default_value IS NOT NULL THEN
        create_data_table_stmt := create_data_table_stmt || format(' DEFAULT %s', col_rec.default_value);
    END IF;
    add_separator := TRUE;
  END LOOP;

  -- Metadata columns (state, last_completed_priority, error) are now added declaratively
  -- through the 'metadata' import_step and its associated import_data_column entries,
  -- which are included in the loop above if 'metadata' step is part of the definition.
  create_data_table_stmt := create_data_table_stmt || ');';

  RAISE DEBUG '[Job %] Data table DDL: %', job.id, create_data_table_stmt;
  EXECUTE create_data_table_stmt;

  -- Create index on state and priority for efficient processing
  EXECUTE format('CREATE INDEX ON public.%I (state, last_completed_priority)', job.data_table_name);
  RAISE DEBUG '[Job %] Added index to data table %', job.id, job.data_table_name;

  -- Grant direct permissions to the job owner on the upload table to allow COPY FROM
  DECLARE
      job_user_role_name TEXT;
  BEGIN
      SELECT u.email INTO job_user_role_name
      FROM auth.user u
      WHERE u.id = job.user_id;

      IF job_user_role_name IS NOT NULL THEN
          EXECUTE format('GRANT ALL ON TABLE public.%I TO %I', job.upload_table_name, job_user_role_name);
          RAISE DEBUG '[Job %] Granted ALL on % to role %', job.id, job.upload_table_name, job_user_role_name;
      ELSE
          RAISE WARNING '[Job %] Could not find user role for user_id %, cannot grant permissions on %',
                        job.id, job.user_id, job.upload_table_name;
      END IF;
  END;

  -- Apply standard RLS to the data table
  PERFORM admin.add_rls_regular_user_can_edit(job.data_table_name::regclass);
  RAISE DEBUG '[Job %] Applied RLS to data table %', job.id, job.data_table_name;

  -- Ensure the new tables are available through PostgREST
  NOTIFY pgrst, 'reload schema';
  RAISE DEBUG '[Job %] Notified PostgREST to reload schema', job.id;
END;
$function$
```

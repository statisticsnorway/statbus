```sql
CREATE OR REPLACE FUNCTION admin.import_job_generate(job import_job)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    create_upload_table_stmt text;
    create_data_table_stmt text;
    create_data_indices_stmt text;
    create_snapshot_table_stmt text;
    add_separator BOOLEAN := FALSE;
    info RECORD;
BEGIN
  RAISE DEBUG 'Creating snapshot table %', job.import_information_snapshot_table_name;
  -- Create a snapshot of import_information for this job
  create_snapshot_table_stmt := format(
    'CREATE TABLE public.%I AS
     SELECT * FROM public.import_information
     WHERE job_id = %L',
    job.import_information_snapshot_table_name, job.id
  );

  EXECUTE create_snapshot_table_stmt;

  -- Add indexes to the snapshot table for better performance
  EXECUTE format(
    'CREATE INDEX ON public.%I (source_column_priority)',
    job.import_information_snapshot_table_name
  );

  -- Apply RLS to the snapshot table
  PERFORM admin.add_rls_regular_user_can_read(job.import_information_snapshot_table_name::regclass);

  RAISE DEBUG 'Generating %', job.upload_table_name;
  -- Build the sql to create a table for this import job with target columns
  create_upload_table_stmt := format('CREATE TABLE public.%I (', job.upload_table_name);

  -- Add columns from target table definition
  FOR info IN
      EXECUTE format($$
        SELECT *
        FROM public.%I AS ii
        WHERE source_column IS NOT NULL
      $$, job.import_information_snapshot_table_name)
  LOOP
    IF NOT add_separator THEN
        add_separator := true;
    ELSE
      -- Adds a comma after every line but the first.
        create_upload_table_stmt := create_upload_table_stmt || ',';
    END IF;

    create_upload_table_stmt := create_upload_table_stmt || format($format$
  %I TEXT$format$, info.source_column);
  END LOOP;
  create_upload_table_stmt := create_upload_table_stmt ||$EOS$
  );$EOS$;

  RAISE DEBUG '%', create_upload_table_stmt;
  EXECUTE create_upload_table_stmt;

  -- Create a trigger to check state before INSERT
  -- Using job.slug instead of job.id ensures trigger names are stable across test runs
  -- since slugs are deterministic while job IDs may vary between test runs
  EXECUTE format('
      CREATE TRIGGER %I_check_state_before_insert
      BEFORE INSERT ON public.%I
      FOR EACH STATEMENT
      EXECUTE FUNCTION admin.check_import_job_state_for_insert(%L);
  ',
  job.upload_table_name, job.upload_table_name, job.slug);

  -- Create a trigger to update state after INSERT
  -- Using job.slug instead of job.id ensures trigger names are stable across test runs
  -- since slugs are deterministic while job IDs may vary between test runs
  EXECUTE format('
      CREATE TRIGGER %I_update_state_after_insert
      AFTER INSERT ON public.%I
      FOR EACH STATEMENT
      EXECUTE FUNCTION admin.update_import_job_state_after_insert(%L);
  ',
  job.upload_table_name, job.upload_table_name, job.slug);

  RAISE DEBUG 'Generating %', job.data_table_name;
  -- Build the sql to create a table for this import job with target columns
  create_data_table_stmt := format('CREATE TABLE public.%I (', job.data_table_name);

  -- Add columns from target table definition
  add_separator := false;
  FOR info IN
      EXECUTE format($$
        SELECT *
        FROM public.%I AS ii
        WHERE target_column IS NOT NULL
      $$, job.import_information_snapshot_table_name)
  LOOP
    IF NOT add_separator THEN
        add_separator := true;
    ELSE
      -- Adds a comma after every line but the first.
        create_data_table_stmt := create_data_table_stmt || ',';
    END IF;

    create_data_table_stmt := create_data_table_stmt || format($format$
  %I %I$format$, info.target_column, info.target_type);
  END LOOP;

  -- Add import state tracking column
  create_data_table_stmt := create_data_table_stmt || format($format$,
  state public.import_data_state NOT NULL DEFAULT 'pending'$format$);

  create_data_table_stmt := create_data_table_stmt ||$EOS$
  );$EOS$;

  RAISE DEBUG '%', create_data_table_stmt;
  EXECUTE create_data_table_stmt;

  -- Create index on state for efficient filtering
  EXECUTE format('CREATE INDEX ON public.%I (state)', job.data_table_name);

  -- Add unique constraint on uniquely identifying columns
  create_data_indices_stmt := format('ALTER TABLE public.%I ADD CONSTRAINT %I_unique_key UNIQUE (',
    job.data_table_name,
    job.data_table_name
  );

  -- Add columns to unique constraint
  add_separator := false;
  FOR info IN
      EXECUTE format($$
        SELECT *
        FROM public.%I AS ii
        WHERE uniquely_identifying = TRUE
          AND target_column IS NOT NULL
      $$, job.import_information_snapshot_table_name)
  LOOP
    IF NOT add_separator THEN
        add_separator := true;
    ELSE
        create_data_indices_stmt := create_data_indices_stmt || ', ';
    END IF;

    create_data_indices_stmt := create_data_indices_stmt || format('%I', info.target_column);
  END LOOP;

  create_data_indices_stmt := create_data_indices_stmt || ');';

  RAISE DEBUG '%', create_data_indices_stmt;
  EXECUTE create_data_indices_stmt;

  PERFORM admin.add_rls_regular_user_can_edit(job.upload_table_name::regclass);
  PERFORM admin.add_rls_regular_user_can_edit(job.data_table_name::regclass);

END;
$function$
```

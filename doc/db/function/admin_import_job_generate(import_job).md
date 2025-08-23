```sql
CREATE OR REPLACE FUNCTION admin.import_job_generate(job import_job)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    create_upload_table_stmt text;
    create_data_table_stmt text;
    add_separator BOOLEAN := FALSE;
    col_rec RECORD;
    source_col_rec RECORD;
BEGIN
    RAISE DEBUG '[Job %] Generating tables: %, %', job.id, job.upload_table_name, job.data_table_name;

    -- 1. Create Upload Table using job.definition_snapshot as the single source of truth
    RAISE DEBUG '[Job %] Generating upload table % from snapshot', job.id, job.upload_table_name;
    create_upload_table_stmt := format('CREATE TABLE public.%I (', job.upload_table_name);
    add_separator := FALSE;

    FOR source_col_rec IN
        SELECT * FROM jsonb_to_recordset(job.definition_snapshot->'import_source_column_list')
            AS x(id int, definition_id int, column_name text, priority int, created_at timestamptz, updated_at timestamptz)
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
    EXECUTE format($$
        CREATE TRIGGER %I
        BEFORE INSERT ON public.%I FOR EACH STATEMENT
        EXECUTE FUNCTION admin.check_import_job_state_for_insert(%L);$$,
        job.upload_table_name || '_check_state_before_insert', job.upload_table_name, job.slug);
    EXECUTE format($$
        CREATE TRIGGER %I
        AFTER INSERT ON public.%I FOR EACH STATEMENT
        EXECUTE FUNCTION admin.update_import_job_state_after_insert(%L);$$,
        job.upload_table_name || '_update_state_after_insert', job.upload_table_name, job.slug);
    RAISE DEBUG '[Job %] Added triggers to upload table %', job.id, job.upload_table_name;

    -- 2. Create Data Table using job.definition_snapshot as the single source of truth
    RAISE DEBUG '[Job %] Generating data table % from snapshot', job.id, job.data_table_name;
    -- Add row_id as the first column and primary key
    create_data_table_stmt := format('CREATE TABLE public.%I (row_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY, ', job.data_table_name);
    add_separator := FALSE; -- Reset for data table columns

    -- Add columns based on import_data_column records from the job's definition snapshot.
    -- The snapshot list is already correctly ordered by step priority then column priority.
    FOR col_rec IN
        SELECT *
        FROM jsonb_to_recordset(job.definition_snapshot->'import_data_column_list') AS x(
            id integer,
            step_id int,
            priority int,
            column_name text,
            column_type text,
            purpose public.import_data_column_purpose,
            is_nullable boolean,
            default_value text,
            is_uniquely_identifying boolean,
            created_at timestamptz,
            updated_at timestamptz
        )
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

    create_data_table_stmt := create_data_table_stmt || ');';

    RAISE DEBUG '[Job %] Data table DDL: %', job.id, create_data_table_stmt;
    EXECUTE create_data_table_stmt;


  -- Create composite index (state, last_completed_priority, row_id) for efficient batch selection and in-index ordering
  EXECUTE format($$CREATE INDEX ON public.%1$I (state, last_completed_priority, row_id)$$, job.data_table_name /* %1$I */);
  RAISE DEBUG '[Job %] Added composite index to data table %', job.id, job.data_table_name;

  -- Create indexes on uniquely identifying source_input columns to speed up lookups within analysis steps.
  FOR col_rec IN
      SELECT (x->>'column_name')::TEXT as column_name
      FROM jsonb_array_elements(job.definition_snapshot->'import_data_column_list') x
      WHERE x->>'purpose' = 'source_input' AND (x->>'is_uniquely_identifying')::boolean IS TRUE
  LOOP
      RAISE DEBUG '[Job %] Adding index on uniquely identifying source column: %', job.id, col_rec.column_name;
      EXECUTE format('CREATE INDEX ON public.%I (%I)', job.data_table_name, col_rec.column_name);
  END LOOP;

  -- Add recommended performance indexes for processing phase and founding_row_id lookups.
  BEGIN
      DECLARE
          v_has_founding_row_id_col BOOLEAN;
      BEGIN
          -- Check if the 'founding_row_id' column is defined for this job's data table
          SELECT EXISTS (
              SELECT 1 FROM jsonb_array_elements(job.definition_snapshot->'import_data_column_list') elem
              WHERE elem->>'column_name' = 'founding_row_id'
          ) INTO v_has_founding_row_id_col;

          -- Add processing phase index
          EXECUTE format($$ CREATE INDEX ON public.%1$I (action, row_id) WHERE state = 'processing' AND error IS NULL $$, job.data_table_name);
          RAISE DEBUG '[Job %] Added processing phase index to data table %.', job.id, job.data_table_name;

          -- Add founding_row_id index if the column exists
          IF v_has_founding_row_id_col THEN
              EXECUTE format($$ CREATE INDEX ON public.%1$I (founding_row_id) WHERE founding_row_id IS NOT NULL $$, job.data_table_name);
              RAISE DEBUG '[Job %] Added founding_row_id index to data table %.', job.id, job.data_table_name;
          ELSE
              RAISE DEBUG '[Job %] Skipping founding_row_id index as column is not present in data table %.', job.id, job.data_table_name;
          END IF;
      END;
  END;

  -- Grant direct permissions to the job owner on the upload table to allow COPY FROM
  DECLARE
      job_user_role_name TEXT;
  BEGIN
      SELECT u.email INTO job_user_role_name
      FROM auth.user u
      WHERE u.id = job.user_id;

      IF job_user_role_name IS NOT NULL THEN
          EXECUTE format($$GRANT ALL ON TABLE public.%I TO %I$$, job.upload_table_name, job_user_role_name);
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

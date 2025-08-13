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

  -- Add a UNIQUE index on expressions for columns marked as uniquely identifying,
  -- including validity period. This is required for the ON CONFLICT clause in the prepare step
  -- to handle temporal idempotency and NULLs in identifier columns.
  DECLARE
      uniquely_identifying_cols TEXT[];
      conflict_expressions TEXT[];
      constraint_stmt TEXT;
      col_name TEXT;
  BEGIN
      -- Find uniquely identifying columns THAT ARE ACTUALLY MAPPED for this job by inspecting the snapshot
      SELECT array_agg(DISTINCT idc.column_name ORDER BY idc.column_name)
      INTO uniquely_identifying_cols
      FROM
          jsonb_to_recordset(job.definition_snapshot->'import_mapping_list') AS item(mapping JSONB, source_column JSONB, target_data_column JSONB),
          jsonb_to_record(item.target_data_column) AS idc(column_name TEXT, is_uniquely_identifying BOOLEAN, purpose TEXT)
      WHERE
          idc.is_uniquely_identifying IS TRUE AND
          idc.purpose = 'source_input';

      IF array_length(uniquely_identifying_cols, 1) > 0 THEN
          FOREACH col_name IN ARRAY uniquely_identifying_cols
          LOOP
              -- Use COALESCE to treat NULL as an empty string for uniqueness on identifiers
              conflict_expressions := array_append(conflict_expressions, format('COALESCE(%I, %L)', col_name, ''));
          END LOOP;

          -- Add validity columns to the expressions for the unique index.
          -- They are NOT coalesced, so rows with NULL validity periods are treated as distinct by the index.
          conflict_expressions := conflict_expressions || ARRAY[format('%I', 'valid_from'), format('%I', 'valid_to')];

          constraint_stmt := format('CREATE UNIQUE INDEX %I ON public.%I (%s)',
                                    job.data_table_name || '_unique_ident_key',
                                    job.data_table_name,
                                    array_to_string(conflict_expressions, ', '));
          RAISE DEBUG '[Job %] Adding unique index on expressions to data table %: %', job.id, job.data_table_name, constraint_stmt;
          EXECUTE constraint_stmt;
      END IF;
  END;

  -- Create composite index (state, last_completed_priority, row_id) for efficient batch selection and in-index ordering
  EXECUTE format($$CREATE INDEX ON public.%1$I (state, last_completed_priority, row_id)$$, job.data_table_name /* %1$I */);
  RAISE DEBUG '[Job %] Added composite index to data table %', job.id, job.data_table_name;

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

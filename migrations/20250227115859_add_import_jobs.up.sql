-- Migration 20250227115859: add import jobs
BEGIN;

CREATE TABLE public.import_target(
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    schema_name text NOT NULL,
    table_name text,
    name text UNIQUE NOT NULL,
    created_at timestamp with time zone NOT NULL DEFAULT NOW(),
    updated_at timestamp with time zone NOT NULL DEFAULT NOW(),
    UNIQUE (schema_name, table_name)
);
INSERT INTO public.import_target (schema_name,table_name, name)
VALUES
    ('public','import_legal_unit_era', 'Legal Unit')
    ,('public','import_establishment_era_for_legal_unit', 'Formal Establishment for Legal Unit')
    ,('public','import_establishment_era_without_legal_unit', 'Informal Establishment without Legal Unit')
   ;

CREATE TABLE public.import_target_column(
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    target_id int REFERENCES public.import_target(id),
    column_name text NOT NULL,
    column_type text NOT NULL,
    uniquely_identifying boolean NOT NULL,
    created_at timestamp with time zone NOT NULL DEFAULT NOW(),
    updated_at timestamp with time zone NOT NULL DEFAULT NOW()
);
WITH cols AS (
     SELECT it.id AS target_id
          , column_name
          , data_type AS column_type
          , is_nullable
          , EXISTS (SELECT * FROM public.external_ident_type WHERE code = column_name) AS uniquely_identifying
          , ROW_NUMBER() OVER (PARTITION BY it.id ORDER BY ordinal_position) AS priority
      FROM information_schema.columns AS c
      JOIN public.import_target AS it
        ON c.table_schema = it.schema_name
        AND c.table_name = it.table_name
      ORDER BY target_id, ordinal_position
) INSERT INTO public.import_target_column(target_id, column_name, column_type, uniquely_identifying)
  SELECT target_id, column_name, column_type, uniquely_identifying
  FROM cols
  ;

SELECT it.schema_name || '.' || it.table_name AS target_table_name
     , itc.column_name
     , itc.column_type
     , itc.uniquely_identifying
FROM public.import_target_column itc
JOIN public.import_target it ON it.id = itc.target_id
ORDER BY it.id, it.table_name, itc.column_name;

CREATE TABLE public.import_definition(
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    slug text UNIQUE NOT NULL,
    name text UNIQUE NOT NULL,
    target_id int REFERENCES public.import_target(id),
    note text,
    data_source_id integer REFERENCES public.data_source(id) ON DELETE RESTRICT,
    time_context_ident TEXT, -- For lookup in public.time_context(ident) to get computed valid_from/valid_to
    user_id integer REFERENCES public.statbus_user(id) ON DELETE SET NULL,
    draft boolean NOT NULL DEFAULT true,
    valid boolean NOT NULL DEFAULT false,
    validation_error text,
    created_at timestamp with time zone NOT NULL DEFAULT NOW(),
    updated_at timestamp with time zone NOT NULL DEFAULT NOW(),
    CONSTRAINT draft_valid_error_states CHECK (
        CASE WHEN draft THEN NOT valid
            WHEN NOT draft THEN valid AND validation_error IS NULL
            ELSE false                             -- All other combinations forbidden
        END
    )
);
CREATE INDEX ix_import_user_id ON public.import_definition USING btree (user_id);
CREATE INDEX ix_import_data_source_id ON public.import_definition USING btree (data_source_id);


CREATE FUNCTION admin.import_definition_validate_before()
RETURNS TRIGGER LANGUAGE plpgsql AS $import_definition_validate_before$
DECLARE
    target_has_temporal boolean;
    missing_temporal text[];
BEGIN
    -- Skip validation if in draft mode
    IF NEW.draft THEN
        RETURN NEW;
    END IF;

    -- Check if target table has temporal columns
    SELECT EXISTS (
        SELECT 1 FROM public.import_target_column
        WHERE target_id = NEW.target_id
        AND column_name IN ('valid_from', 'valid_to')
    ) INTO target_has_temporal;

    IF NOT target_has_temporal THEN
        -- No temporal columns needed, validation passes
        NEW.valid := true;
        NEW.validation_error := NULL;
        RETURN NEW;
    END IF;

    -- Check which temporal columns are missing mappings
    SELECT array_agg(column_name)
    FROM public.import_target_column itc
    WHERE itc.target_id = NEW.target_id
    AND itc.column_name IN ('valid_from', 'valid_to')
    AND NOT EXISTS (
        SELECT 1 FROM public.import_mapping im
        WHERE im.target_column_id = itc.id
        AND im.definition_id = NEW.id
        AND (
            im.source_column_id IS NOT NULL OR
            im.source_expression = 'default'::public.import_source_expression OR
            im.source_value IS NOT NULL
        )
    ) INTO missing_temporal;

    -- Set validation results on NEW record
    NEW.valid := (missing_temporal IS NULL);
    NEW.validation_error := CASE
        WHEN missing_temporal IS NULL THEN NULL
        ELSE format(
            'Missing required mappings for temporal columns: %s. Either map source columns or use ''default'' expression',
            array_to_string(missing_temporal, ', ')
        )
    END;
    NEW.draft := CASE
        WHEN missing_temporal IS NULL THEN false
        ELSE true
    END;

    RETURN NEW;
END;
$import_definition_validate_before$;

-- Register import_job_process command in the worker system
INSERT INTO worker.queue_registry (queue, concurrent, description)
VALUES ('import', true, 'Concurrent queue for processing import jobs');

INSERT INTO worker.command_registry (queue, command, handler_function, description)
VALUES
( 'import',
  'import_job_process',
  'admin.import_job_process',
  'Process an import job through all stages'
);

-- Create function to enqueue an import job for processing
CREATE FUNCTION admin.enqueue_import_job_process(
  p_job_id INTEGER
) RETURNS BIGINT
LANGUAGE plpgsql
AS $function$
DECLARE
  v_task_id BIGINT;
  v_payload JSONB;
BEGIN
  -- Validate job exists
  IF NOT EXISTS (SELECT 1 FROM public.import_job WHERE id = p_job_id) THEN
    RAISE EXCEPTION 'Import job % not found', p_job_id;
  END IF;

  -- Create payload
  v_payload := jsonb_build_object('job_id', p_job_id);

  -- Insert task with payload
  INSERT INTO worker.tasks (
    command,
    payload
  ) VALUES (
    'import_job_process',
    v_payload
  )
  RETURNING id INTO v_task_id;

  -- Notify worker of new task with queue information
  PERFORM pg_notify('worker_tasks', 'import');

  RETURN v_task_id;
END;
$function$;


CREATE FUNCTION admin.validate_time_context_ident()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.time_context_ident IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM public.time_context WHERE ident = NEW.time_context_ident) THEN
        RAISE EXCEPTION 'Invalid time_context_ident: %', NEW.time_context_ident;
    END IF;
    RETURN NEW;
END;
$$;


CREATE TRIGGER validate_time_context_ident_trigger
    BEFORE INSERT OR UPDATE OF time_context_ident ON public.import_definition
    FOR EACH ROW
    EXECUTE FUNCTION admin.validate_time_context_ident();

CREATE TRIGGER validate_on_draft_change
    BEFORE UPDATE OF draft ON public.import_definition
    FOR EACH ROW
    WHEN (OLD.draft = true AND NEW.draft = false)
    EXECUTE FUNCTION admin.import_definition_validate_before();

CREATE FUNCTION admin.prevent_changes_to_non_draft_definition()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    def public.import_definition;
BEGIN
    IF TG_TABLE_NAME = 'import_definition' THEN
        -- For direct changes to import_definition
        IF NOT NEW.draft AND OLD.draft = NEW.draft THEN
            RAISE EXCEPTION 'Can only modify import definition % when in draft mode', OLD.id;
        END IF;
    ELSE
        -- For changes to related tables (mapping, source_column)
        SELECT * INTO def FROM public.import_definition WHERE id =
            CASE TG_TABLE_NAME
                WHEN 'import_mapping' THEN
                    CASE TG_OP
                        WHEN 'DELETE' THEN OLD.definition_id
                        ELSE NEW.definition_id
                    END
                WHEN 'import_source_column' THEN NEW.definition_id
            END;

        IF NOT def.draft THEN
            RAISE EXCEPTION 'Can only modify % for import definition % when in draft mode',
                TG_TABLE_NAME, def.id;
        END IF;
    END IF;
    RETURN CASE TG_OP WHEN 'DELETE' THEN OLD ELSE NEW END;
END;
$$;

CREATE TRIGGER prevent_non_draft_changes
    BEFORE UPDATE ON public.import_definition
    FOR EACH ROW
    EXECUTE FUNCTION admin.prevent_changes_to_non_draft_definition();

CREATE TABLE public.import_source_column(
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    definition_id int REFERENCES public.import_definition(id),
    column_name text NOT NULL,
    priority int NOT NULL,
    created_at timestamp with time zone NOT NULL DEFAULT NOW(),
    updated_at timestamp with time zone NOT NULL DEFAULT NOW()
);
COMMENT ON COLUMN public.import_source_column.priority IS 'The ordering of the columns in the CSV file.';

CREATE TRIGGER prevent_non_draft_source_column_changes
    BEFORE INSERT OR UPDATE OR DELETE ON public.import_source_column
    FOR EACH ROW
    EXECUTE FUNCTION admin.prevent_changes_to_non_draft_definition();


CREATE TYPE public.import_source_expression AS ENUM ('now', 'default');

CREATE TABLE public.import_mapping(
    definition_id int NOT NULL REFERENCES public.import_definition(id),
    source_column_id int REFERENCES public.import_source_column(id),
    CONSTRAINT unique_source_column_mapping UNIQUE (definition_id, source_column_id),
    source_value TEXT,
    source_expression public.import_source_expression,
    target_column_id int REFERENCES public.import_target_column(id),
    CONSTRAINT unique_target_column_mapping UNIQUE (definition_id, target_column_id),
    CONSTRAINT "only_one_source_can_be_defined"
    CHECK( source_column_id IS NOT NULL AND source_value IS     NULL AND source_expression IS     NULL
        OR source_column_id IS     NULL AND source_value IS NOT NULL AND source_expression IS     NULL
        OR source_column_id IS     NULL AND source_value IS     NULL AND source_expression IS NOT NULL
        ),
    CONSTRAINT "at_least_one_column_must_be_defined" CHECK(
      source_column_id IS NOT NULL OR target_column_id IS NOT NULL
    ),
    created_at timestamp with time zone NOT NULL DEFAULT NOW(),
    updated_at timestamp with time zone NOT NULL DEFAULT NOW()
);

CREATE TRIGGER prevent_non_draft_mapping_changes
    BEFORE INSERT OR UPDATE OR DELETE ON public.import_mapping
    FOR EACH ROW
    EXECUTE FUNCTION admin.prevent_changes_to_non_draft_definition();

CREATE TYPE public.import_job_status AS ENUM (
    'waiting_for_upload',  -- Initial state: User must upload data into table, then change state to upload_completed
    'upload_completed',    -- Triggers worker notification to begin processing
    'preparing_data',      -- Moving from custom names in upload table to standard names in data table
    'analysing_data',      -- Worker is analyzing the uploaded data
    'waiting_for_review',  -- Analysis complete, waiting for user to approve or reject
    'approved',            -- User approved changes, triggers worker to continue processing
    'rejected',            -- User rejected changes, no further processing
    'importing_data',      -- Worker is importing data into target table
    'finished'             -- Import process completed successfully
);

CREATE TABLE public.import_job (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    slug varchar,
    description text,
    note text,
    default_valid_from DATE,
    default_valid_to DATE,
    default_data_source_code text,
    upload_table_name text NOT NULL,
    data_table_name text NOT NULL,
    target_table_name text NOT NULL,
    target_schema_name text NOT NULL,
    import_information_snapshot_table_name text NOT NULL,
    analysis_start_at timestamp with time zone,
    analysis_stop_at timestamp with time zone,
    preparing_data_at timestamp with time zone,
    changes_approved_at timestamp with time zone,
    changes_rejected_at timestamp with time zone,
    import_start_at timestamp with time zone,
    import_stop_at timestamp with time zone,
    status public.import_job_status NOT NULL DEFAULT 'waiting_for_upload',
    review boolean NOT NULL DEFAULT false,
    definition_id integer NOT NULL REFERENCES public.import_definition(id) ON DELETE CASCADE,
    user_id integer REFERENCES public.statbus_user(id) ON DELETE SET NULL
);
CREATE INDEX ix_import_job_definition_id ON public.import_job USING btree (definition_id);
CREATE INDEX ix_import_job_user_id ON public.import_job USING btree (user_id);

-- Create function to set default slug
CREATE FUNCTION admin.import_job_derive()
RETURNS TRIGGER LANGUAGE plpgsql AS $import_job_derive$
DECLARE
    definition public.import_definition;
BEGIN
    SELECT * INTO definition
    FROM public.import_definition
    WHERE id = NEW.definition_id;

    IF NOT definition.valid THEN
        RAISE EXCEPTION 'Cannot create import job for invalid import_definition % (%): %',
            definition.id, definition.name, COALESCE(definition.validation_error,'Is still draft');
    END IF;

    IF NEW.slug IS NULL THEN
        NEW.slug := format('import_job_%s', NEW.id);
    END IF;

    NEW.upload_table_name := format('%s_upload', NEW.slug);
    NEW.data_table_name := format('%s_data', NEW.slug);
    NEW.import_information_snapshot_table_name := format('%s_import_information', NEW.slug);

    -- Set target table name and schema from import definition
    SELECT it.table_name, it.schema_name
    INTO NEW.target_table_name, NEW.target_schema_name
    FROM public.import_definition id
    JOIN public.import_target it ON it.id = id.target_id
    WHERE id.id = NEW.definition_id;

    -- Set default validity dates from time context if available and not already set
    IF NEW.default_valid_from IS NULL OR NEW.default_valid_to IS NULL THEN
        SELECT tc.valid_from, tc.valid_to
        INTO NEW.default_valid_from, NEW.default_valid_to
        FROM public.import_definition id
        LEFT JOIN public.time_context tc ON tc.ident = id.time_context_ident
        WHERE id.id = NEW.definition_id;
    END IF;

    IF NEW.default_data_source_code IS NULL THEN
        SELECT ds.code
        INTO NEW.default_data_source_code
        FROM public.import_definition id
        JOIN public.data_source ds ON ds.id = id.default_data_source_id
        WHERE id.id = NEW.definition_id;
    END IF;

    -- Set the user_id from the current authenticated user
    IF NEW.user_id IS NULL AND auth.uid() IS NOT NULL THEN
        SELECT id INTO NEW.user_id
        FROM public.statbus_user
        WHERE uuid = auth.uid();
    END IF;

    RETURN NEW;
END;
$import_job_derive$;

-- Create trigger to set slug before insert
CREATE TRIGGER import_job_derive_trigger
    BEFORE INSERT ON public.import_job
    FOR EACH ROW
    EXECUTE FUNCTION admin.import_job_derive();

-- Create functions to manage import job tables and views
CREATE FUNCTION admin.import_job_generate()
RETURNS TRIGGER LANGUAGE plpgsql AS $import_job_generate$
BEGIN
    PERFORM admin.import_job_generate(NEW);
    RETURN NEW;
END;
$import_job_generate$;

-- Create trigger to create objects when job is inserted
CREATE TRIGGER import_job_generate
    AFTER INSERT OR UPDATE OF upload_table_name, data_table_name ON public.import_job
    FOR EACH ROW
    EXECUTE FUNCTION admin.import_job_generate();

-- Function to clean up job objects
CREATE FUNCTION admin.import_job_cleanup()
RETURNS TRIGGER SECURITY DEFINER LANGUAGE plpgsql AS $import_job_cleanup$
BEGIN
    -- Drop the snapshot table
    EXECUTE format('DROP TABLE IF EXISTS public.%I', OLD.import_information_snapshot_table_name);

    -- Drop the upload and data tables
    EXECUTE format('DROP TABLE IF EXISTS public.%I', OLD.upload_table_name);
    EXECUTE format('DROP TABLE IF EXISTS public.%I', OLD.data_table_name);


    RETURN OLD;
END;
$import_job_cleanup$;

-- Create trigger to clean up objects when job is deleted
CREATE TRIGGER import_job_cleanup
    BEFORE UPDATE OF upload_table_name, data_table_name OR DELETE ON public.import_job
    FOR EACH ROW
    EXECUTE FUNCTION admin.import_job_cleanup();


-- Create trigger to automatically process import jobs when status changes to upload_completed
CREATE FUNCTION admin.import_job_status_change()
RETURNS TRIGGER LANGUAGE plpgsql AS $import_job_status_change$
DECLARE
    v_timestamp TIMESTAMPTZ := now();
BEGIN
    -- Record timestamps for status changes if not already recorded
    UPDATE public.import_job SET
        analysis_start_at = CASE WHEN NEW.status = 'analysing_data' AND analysis_start_at IS NULL THEN v_timestamp ELSE analysis_start_at END,
        preparing_data_at = CASE WHEN NEW.status = 'preparing_data' AND preparing_data_at IS NULL THEN v_timestamp ELSE preparing_data_at END,
        analysis_stop_at = CASE WHEN NEW.status = 'waiting_for_review' AND analysis_stop_at IS NULL THEN v_timestamp ELSE analysis_stop_at END,
        changes_approved_at = CASE WHEN NEW.status = 'approved' AND changes_approved_at IS NULL THEN v_timestamp ELSE changes_approved_at END,
        changes_rejected_at = CASE WHEN NEW.status = 'rejected' AND changes_rejected_at IS NULL THEN v_timestamp ELSE changes_rejected_at END,
        import_start_at = CASE WHEN NEW.status = 'importing_data' AND import_start_at IS NULL THEN v_timestamp ELSE import_start_at END,
        import_stop_at = CASE WHEN NEW.status = 'finished' AND import_stop_at IS NULL THEN v_timestamp ELSE import_stop_at END
    WHERE id = NEW.id;

    -- Only enqueue for processing when transitioning from user action states
    IF (OLD.status = 'waiting_for_upload' AND NEW.status = 'upload_completed') OR
       (OLD.status = 'waiting_for_review' AND NEW.status = 'approved') THEN
        PERFORM admin.enqueue_import_job_process(NEW.id);
    END IF;

    RETURN NEW;
END;
$import_job_status_change$;

CREATE TRIGGER import_job_status_change_trigger
    AFTER INSERT OR UPDATE OF status ON public.import_job
    FOR EACH ROW
    EXECUTE FUNCTION admin.import_job_status_change();

SELECT admin.add_rls_regular_user_can_read('public.import_target'::regclass);
SELECT admin.add_rls_regular_user_can_read('public.import_target_column'::regclass);
SELECT admin.add_rls_regular_user_can_read('public.import_definition'::regclass);
SELECT admin.add_rls_regular_user_can_read('public.import_source_column'::regclass);
SELECT admin.add_rls_regular_user_can_read('public.import_mapping'::regclass);
SELECT admin.add_rls_regular_user_can_edit('public.import_job'::regclass);

CREATE VIEW public.import_information WITH (security_barrier = true) AS
    SELECT ij.id AS job_id
    , id.id AS definition_id
    , ij.slug AS import_job_slug
    , id.slug AS import_definition_slug
    , id.name AS import_name
    , id.note AS import_note
    , it.schema_name AS target_schema_name
    , ij.upload_table_name AS upload_table_name
    , ij.data_table_name AS data_table_name
    , isc.column_name AS source_column
    , im.source_value AS source_value
    , im.source_expression AS source_expression
    , itc.column_name AS target_column
    , itc.column_type AS target_type
    , itc.uniquely_identifying AS uniquely_identifying
    , isc.priority AS source_column_priority
    FROM public.import_job ij
    JOIN public.import_definition id ON ij.definition_id = id.id
    JOIN public.import_target it ON id.target_id = it.id
    JOIN public.import_mapping im ON id.id = im.definition_id
    LEFT OUTER JOIN public.import_source_column isc ON im.source_column_id = isc.id
    LEFT OUTER JOIN public.import_target_column itc ON im.target_column_id = itc.id
    ORDER BY id.id ASC
           , ij.id ASC
           , isc.priority ASC NULLS LAST
           , isc.id ASC
           , itc.id ASC
;


/*
Each import operates on it's on table.
The table is unlogged for good performance on insert.
There is a view that maps from the columns names of the upload to the column names of the table.
*/
CREATE FUNCTION admin.import_job_generate(job public.import_job)
RETURNS void SECURITY DEFINER LANGUAGE plpgsql AS $import_job_generate$
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
    'CREATE UNLOGGED TABLE public.%I AS
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
  create_upload_table_stmt := format('CREATE UNLOGGED TABLE public.%I (', job.upload_table_name);

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

  RAISE DEBUG 'Generating %', job.data_table_name;
  -- Build the sql to create a table for this import job with target columns
  create_data_table_stmt := format('CREATE UNLOGGED TABLE public.%I (', job.data_table_name);

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
  create_data_table_stmt := create_data_table_stmt ||$EOS$
  );$EOS$;

  RAISE DEBUG '%', create_data_table_stmt;
  EXECUTE create_data_table_stmt;

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
$import_job_generate$;



-- Simple dispatcher for import_job_process
CREATE FUNCTION admin.import_job_process(payload JSONB)
RETURNS void LANGUAGE plpgsql AS $import_job_process$
DECLARE
    job_id INTEGER;
BEGIN
    -- Extract job_id from payload and call the implementation function
    job_id := (payload->>'job_id')::INTEGER;

    -- Call the implementation function
    PERFORM admin.import_job_process(job_id);
END;
$import_job_process$;


-- Function to update import job status and return the updated record
CREATE FUNCTION admin.import_job_set_status(
    job public.import_job,
    new_status public.import_job_status
) RETURNS public.import_job
LANGUAGE plpgsql AS $import_job_set_status$
DECLARE
    updated_job public.import_job;
BEGIN
    -- Update the status in the database
    UPDATE public.import_job
    SET status = new_status
    WHERE id = job.id
    RETURNING * INTO updated_job;

    -- Return the updated record
    RETURN updated_job;
END;
$import_job_set_status$;

-- Function to calculate the next state based on the current state
CREATE FUNCTION admin.import_job_next_state(job public.import_job)
RETURNS public.import_job_status
LANGUAGE plpgsql AS $import_job_next_state$
BEGIN
    CASE job.status
        WHEN 'waiting_for_upload' THEN
            RETURN job.status; -- No automatic transition, requires user action

        WHEN 'upload_completed' THEN
            RETURN 'preparing_data';

        WHEN 'preparing_data' THEN
            RETURN 'analysing_data';

        WHEN 'analysing_data' THEN
            IF job.review THEN
                RETURN 'waiting_for_review';
            ELSE
                RETURN 'importing_data';
            END IF;

        WHEN 'waiting_for_review' THEN
          RETURN job.status; -- No automatic transition, requires user action

        WHEN 'approved' THEN
            RETURN 'importing_data';

        WHEN 'rejected' THEN
            RETURN 'finished';

        WHEN 'importing_data' THEN
            RETURN 'finished';

        WHEN 'finished' THEN
            RETURN job.status; -- Terminal state

        ELSE
            RAISE EXCEPTION 'Unknown import job status: %', job.status;
    END CASE;
END;
$import_job_next_state$;


-- Function to set user context for import job processing
CREATE FUNCTION admin.set_import_job_user_context(job_id integer)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $set_import_job_user_context$
DECLARE
    v_user_uuid uuid;
    v_original_user_id text;
BEGIN
    -- Save the current user context if any
    v_original_user_id := current_setting('request.jwt.claim.sub', true);

    -- Get the user UUID from the job
    SELECT su.uuid INTO v_user_uuid
    FROM public.import_job ij
    JOIN public.statbus_user su ON ij.user_id = su.id
    WHERE ij.id = job_id;

    IF v_user_uuid IS NOT NULL THEN
        -- Set the user context
        PERFORM set_config('request.jwt.claim.sub', v_user_uuid::text, true);
        RAISE DEBUG 'Set user context to % for import job %', v_user_uuid, job_id;
    ELSE
        RAISE DEBUG 'No user found for import job %, using current context', job_id;
    END IF;

    -- Store the original user ID for reset
    PERFORM set_config('admin.original_user_id', COALESCE(v_original_user_id, ''), true);
END;
$set_import_job_user_context$;

-- Function to reset user context after import job processing
CREATE FUNCTION admin.reset_import_job_user_context()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $reset_import_job_user_context$
DECLARE
    v_original_user_id text;
BEGIN
    -- Get the original user context
    v_original_user_id := current_setting('admin.original_user_id', true);

    IF v_original_user_id != '' THEN
        -- Reset to the original user context
        PERFORM set_config('request.jwt.claim.sub', v_original_user_id, true);
        RAISE DEBUG 'Reset user context to original user %', v_original_user_id;
    ELSE
        -- Clear the user context
        PERFORM set_config('request.jwt.claim.sub', '', true);
        RAISE DEBUG 'Cleared user context (no original user)';
    END IF;
END;
$reset_import_job_user_context$;

-- Grant execute permissions on the user context functions
GRANT EXECUTE ON FUNCTION admin.set_import_job_user_context TO authenticated;
GRANT EXECUTE ON FUNCTION admin.reset_import_job_user_context TO authenticated;

CREATE FUNCTION admin.import_job_process(job_id integer)
RETURNS void LANGUAGE plpgsql AS $import_job_process$
DECLARE
    job public.import_job;
    next_status public.import_job_status;
BEGIN
    -- Get the job details
    SELECT * INTO job FROM public.import_job WHERE id = job_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Import job % not found', job_id;
    END IF;

    -- Set the user context to the job creator
    PERFORM admin.set_import_job_user_context(job_id);

    BEGIN
        -- Process the job based on its current status
        LOOP
            -- Get the next status
            next_status := admin.import_job_next_state(job);

            -- If status doesn't change, we're either at a terminal state or waiting for user action
            IF next_status = job.status THEN
                IF job.status = 'waiting_for_review' AND job.review THEN
                    RAISE DEBUG 'Import job % is now waiting for review', job_id;
                ELSIF job.status = 'finished' THEN
                    RAISE DEBUG 'Import job % completed successfully', job_id;
                END IF;
                EXIT; -- Exit the loop
            END IF;

            -- Update the job status
            job := admin.import_job_set_status(job, next_status);

            -- Perform the appropriate action for the new status
            CASE job.status
                WHEN 'preparing_data' THEN
                    PERFORM admin.import_job_prepare(job);

                WHEN 'analysing_data' THEN
                    PERFORM admin.import_job_analyse(job);

                WHEN 'importing_data' THEN
                    PERFORM admin.import_job_insert(job);

                ELSE
                    -- Other states don't require specific actions
                    NULL;
            END CASE;
        END LOOP;
    EXCEPTION
        WHEN OTHERS THEN
            -- Reset user context before re-raising the exception
            PERFORM admin.reset_import_job_user_context();
            RAISE;
    END;

    -- Reset the user context when done
    PERFORM admin.reset_import_job_user_context();
END;
$import_job_process$;


-- Function to prepare import job by moving data from upload table to data table
CREATE FUNCTION admin.import_job_prepare(job public.import_job)
RETURNS void LANGUAGE plpgsql AS $import_job_prepare$
DECLARE
    merge_stmt text;
    add_separator BOOLEAN := FALSE;
    info RECORD;
    v_timestamp TIMESTAMPTZ;
BEGIN
    -- This function will move data from the upload table to the data table
    -- with appropriate transformations based on the import definition
    RAISE DEBUG 'Preparing import job % by moving data from % to %',
                 job.id, job.upload_table_name, job.data_table_name;

    /*
    -- Example of generated merge statement:
    INSERT INTO public.import_job_123_data_table (
      tax_ident, name, legal_form_code, primary_activity_category_code
    ) SELECT
      tax_ident, name, legal_form_code, primary_activity_category_code
    FROM public.import_job_123_upload_table
    ON CONFLICT (tax_ident) DO UPDATE SET
      name = EXCLUDED.name,
      legal_form_code = EXCLUDED.legal_form_code,
      primary_activity_category_code = EXCLUDED.primary_activity_category_code;
    */

    -- Build dynamic INSERT statement with ON CONFLICT handling
    merge_stmt := format('INSERT INTO public.%I (', job.data_table_name);

    -- Add target columns
    add_separator := FALSE;
    FOR info IN
        SELECT * FROM public.import_information AS ii
        WHERE ii.job_id = job.id
          AND target_column IS NOT NULL
    LOOP
        IF NOT add_separator THEN
            add_separator := true;
        ELSE
            merge_stmt := merge_stmt || ', ';
        END IF;

        merge_stmt := merge_stmt || format('%I', info.target_column);
    END LOOP;

    merge_stmt := merge_stmt || format(') SELECT ');

    -- Add source columns, values and expressions
    add_separator := FALSE;
    FOR info IN
        SELECT *
        FROM public.import_information AS ii
        WHERE ii.job_id = job.id
          AND target_column IS NOT NULL
          AND (source_column IS NOT NULL
              OR source_value IS NOT NULL
              OR source_expression IS NOT NULL)
    LOOP
        IF NOT add_separator THEN
            add_separator := true;
        ELSE
            merge_stmt := merge_stmt || ', ';
        END IF;

        CASE
            WHEN info.source_value IS NOT NULL THEN
                merge_stmt := merge_stmt || quote_literal(info.source_value);
            WHEN info.source_expression IS NOT NULL THEN
                merge_stmt := merge_stmt || CASE info.source_expression
                    WHEN 'now' THEN 'statement_timestamp()'
                    WHEN 'default' THEN
                        CASE info.target_column
                            WHEN 'valid_from' THEN quote_literal(job.default_valid_from)
                            WHEN 'valid_to' THEN quote_literal(job.default_valid_to)
                            WHEN 'data_source_code' THEN quote_literal(job.default_valid_data_source_code)
                            ELSE 'NULL'
                        END
                    ELSE 'NULL'
                    END;
            WHEN info.source_column IS NOT NULL THEN
                merge_stmt := merge_stmt || CASE info.target_column
                    WHEN 'valid_from' THEN format('COALESCE(NULLIF(%I,%L), %L)', info.source_column, '', job.default_valid_from)
                    WHEN 'valid_to' THEN format('COALESCE(NULLIF(%I,%L), %L)', info.source_column, '', job.default_valid_to)
                    ELSE format('NULLIF(%I,%L)', info.source_column, '')
                    END;
            ELSE
                RAISE EXCEPTION 'No valid source (column/value/expression) found for job %', job_id;
        END CASE;
    END LOOP;

    merge_stmt := merge_stmt || format(' FROM public.%I ', job.upload_table_name);

    -- Add ON CONFLICT clause using uniquely identifying columns
    merge_stmt := merge_stmt || ' ON CONFLICT (';

    add_separator := FALSE;
    FOR info IN
        SELECT *
        FROM public.import_information AS ii
        WHERE ii.job_id = job.id
          AND uniquely_identifying = TRUE
          AND target_column IS NOT NULL
    LOOP
        IF NOT add_separator THEN
            add_separator := true;
        ELSE
            merge_stmt := merge_stmt || ', ';
        END IF;

        merge_stmt := merge_stmt || format('%I', info.target_column);
    END LOOP;

    merge_stmt := merge_stmt || ') DO UPDATE SET ';

    -- Add update assignments
    add_separator := FALSE;
    FOR info IN
        SELECT *
        FROM public.import_information AS ii
        WHERE ii.job_id = job.id
          AND source_column IS NOT NULL
          AND target_column IS NOT NULL
          AND NOT uniquely_identifying
    LOOP
        IF NOT add_separator THEN
            add_separator := true;
        ELSE
            merge_stmt := merge_stmt || ', ';
        END IF;

        merge_stmt := merge_stmt || format('%I = EXCLUDED.%I',
                                        info.target_column,
                                        info.target_column);
    END LOOP;

    -- Execute the insert
    RAISE DEBUG 'Executing upsert: %', merge_stmt;
    EXECUTE merge_stmt;

    DECLARE
      data_table_count INT;
    BEGIN
      EXECUTE format('SELECT count(*) FROM public.%I', job.data_table_name) INTO data_table_count;
      RAISE DEBUG 'There are % rows in %', data_table_count, job.data_table_name;
    END;
END;
$import_job_prepare$;

-- Function to analyze import data before actual import
CREATE FUNCTION admin.import_job_analyse(job public.import_job)
RETURNS void LANGUAGE plpgsql AS $import_job_analyse$
BEGIN
    -- This function will analyze the data in the data table
    -- to identify potential issues before importing
    RAISE DEBUG 'Analyzing data for import job %', job.id;

    -- Validate the data table using the standardised column names
    -- Placeholder for implementation (NOOP for now)
    NULL;
END;
$import_job_analyse$;

-- Function to insert data from the data table to the target table
CREATE FUNCTION admin.import_job_insert(job public.import_job)
RETURNS void LANGUAGE plpgsql AS $import_job_insert$
BEGIN
    -- This function will copy data from the data table to the target table
    RAISE DEBUG 'Inserting data from % to %.%',
                 job.data_table_name, job.target_schema_name, job.target_table_name;

    -- Insert validated data into target table
    DECLARE
      target RECORD;
      target_columns TEXT;
      insert_stmt TEXT;
    BEGIN
        -- Get target columns from the snapshot table
        EXECUTE format(
            'SELECT string_agg(quote_ident(target_column), '','')
            FROM public.%I
            WHERE target_column IS NOT NULL',
            job.import_information_snapshot_table_name
        ) INTO target_columns;

        insert_stmt := format($format$
          INSERT INTO %I.%I (%s)
          SELECT %s FROM public.%I;
        $format$
        , job.target_schema_name
        , job.target_table_name
        , target_columns
        , target_columns
        , job.data_table_name
        );

        RAISE DEBUG 'Executing %', insert_stmt;
        EXECUTE insert_stmt;
    END;

END;
$import_job_insert$;



-- Create default import definitions for all target tables

-- 1. Legal unit with time_context for current year
WITH legal_unit_target AS (
    SELECT * FROM public.import_target
    WHERE schema_name = 'public'
      AND table_name = 'import_legal_unit_era'
), legal_unit_current_def AS (
    INSERT INTO public.import_definition
        ( target_id
        , slug
        , name
        , note
        , time_context_ident
        )
    SELECT legal_unit_target.id
        , 'legal_unit_current_year'
        , 'Legal Unit - Current Year'
        , 'Import legal units with validity period set to current year'
        , 'r_year_curr'
    FROM legal_unit_target
    RETURNING *
), legal_unit_current_source_columns AS (
    INSERT INTO public.import_source_column (definition_id, column_name, priority)
    SELECT legal_unit_current_def.id, itc.column_name, ROW_NUMBER() OVER (ORDER BY itc.id)
    FROM legal_unit_current_def
    JOIN public.import_target_column itc ON itc.target_id = legal_unit_current_def.target_id
    WHERE itc.column_name NOT IN ('valid_from', 'valid_to')
    RETURNING *
), legal_unit_current_mappings AS (
    -- Map source columns to target columns with same name
    INSERT INTO public.import_mapping (definition_id, source_column_id, target_column_id, source_value, source_expression)
    SELECT legal_unit_current_def.id, sc.id, tc.id, NULL, NULL
    FROM legal_unit_current_def
    JOIN legal_unit_current_source_columns sc ON sc.definition_id = legal_unit_current_def.id
    JOIN public.import_target_column tc ON tc.target_id = legal_unit_current_def.target_id AND tc.column_name = sc.column_name

    UNION ALL

    -- Add default mappings for valid_from and valid_to
    SELECT legal_unit_current_def.id, NULL, tc.id, NULL, 'default'::public.import_source_expression
    FROM legal_unit_current_def
    JOIN public.import_target_column tc ON tc.target_id = legal_unit_current_def.target_id
    WHERE tc.column_name IN ('valid_from', 'valid_to')
    RETURNING *
),

-- 2. Legal unit with explicit valid_from/valid_to
legal_unit_explicit_def AS (
    INSERT INTO public.import_definition
        ( target_id
        , slug
        , name
        , note
        )
    SELECT legal_unit_target.id
        , 'legal_unit_explicit_dates'
        , 'Legal Unit - Explicit Dates'
        , 'Import legal units with explicit valid_from and valid_to columns'
    FROM legal_unit_target
    RETURNING *
), legal_unit_explicit_source_columns AS (
    INSERT INTO public.import_source_column (definition_id, column_name, priority)
    SELECT legal_unit_explicit_def.id, itc.column_name, ROW_NUMBER() OVER (ORDER BY itc.id)
    FROM legal_unit_explicit_def
    JOIN public.import_target_column itc ON itc.target_id = legal_unit_explicit_def.target_id
    RETURNING *
), legal_unit_explicit_mappings AS (
    -- Map all source columns to target columns with same name
    INSERT INTO public.import_mapping (definition_id, source_column_id, target_column_id, source_value, source_expression)
    SELECT legal_unit_explicit_def.id, sc.id, tc.id, NULL, NULL
    FROM legal_unit_explicit_def
    JOIN legal_unit_explicit_source_columns sc ON sc.definition_id = legal_unit_explicit_def.id
    JOIN public.import_target_column tc ON tc.target_id = legal_unit_explicit_def.target_id AND tc.column_name = sc.column_name
    RETURNING *
),

-- 3. Establishment for legal unit with time_context for current year
establishment_for_lu_target AS (
    SELECT * FROM public.import_target
    WHERE schema_name = 'public'
      AND table_name = 'import_establishment_era_for_legal_unit'
), establishment_for_lu_current_def AS (
    INSERT INTO public.import_definition
        ( target_id
        , slug
        , name
        , note
        , time_context_ident
        )
    SELECT establishment_for_lu_target.id
        , 'establishment_for_lu_current_year'
        , 'Establishment for Legal Unit - Current Year'
        , 'Import establishments linked to legal units with validity period set to current year'
        , 'r_year_curr'
    FROM establishment_for_lu_target
    RETURNING *
), establishment_for_lu_current_source_columns AS (
    INSERT INTO public.import_source_column (definition_id, column_name, priority)
    SELECT establishment_for_lu_current_def.id, itc.column_name, ROW_NUMBER() OVER (ORDER BY itc.id)
    FROM establishment_for_lu_current_def
    JOIN public.import_target_column itc ON itc.target_id = establishment_for_lu_current_def.target_id
    WHERE itc.column_name NOT IN ('valid_from', 'valid_to')
    RETURNING *
), establishment_for_lu_current_mappings AS (
    -- Map source columns to target columns with same name
    INSERT INTO public.import_mapping (definition_id, source_column_id, target_column_id, source_value, source_expression)
    SELECT establishment_for_lu_current_def.id, sc.id, tc.id, NULL, NULL
    FROM establishment_for_lu_current_def
    JOIN establishment_for_lu_current_source_columns sc ON sc.definition_id = establishment_for_lu_current_def.id
    JOIN public.import_target_column tc ON tc.target_id = establishment_for_lu_current_def.target_id AND tc.column_name = sc.column_name

    UNION ALL

    -- Add default mappings for valid_from and valid_to
    SELECT establishment_for_lu_current_def.id, NULL, tc.id, NULL, 'default'::public.import_source_expression
    FROM establishment_for_lu_current_def
    JOIN public.import_target_column tc ON tc.target_id = establishment_for_lu_current_def.target_id
    WHERE tc.column_name IN ('valid_from', 'valid_to')
    RETURNING *
),

-- 4. Establishment for legal unit with explicit valid_from/valid_to
establishment_for_lu_explicit_def AS (
    INSERT INTO public.import_definition
        ( target_id
        , slug
        , name
        , note
        )
    SELECT establishment_for_lu_target.id
        , 'establishment_for_lu_explicit_dates'
        , 'Establishment for Legal Unit - Explicit Dates'
        , 'Import establishments linked to legal units with explicit valid_from and valid_to columns'
    FROM establishment_for_lu_target
    RETURNING *
), establishment_for_lu_explicit_source_columns AS (
    INSERT INTO public.import_source_column (definition_id, column_name, priority)
    SELECT establishment_for_lu_explicit_def.id, itc.column_name, ROW_NUMBER() OVER (ORDER BY itc.id)
    FROM establishment_for_lu_explicit_def
    JOIN public.import_target_column itc ON itc.target_id = establishment_for_lu_explicit_def.target_id
    RETURNING *
), establishment_for_lu_explicit_mappings AS (
    -- Map all source columns to target columns with same name
    INSERT INTO public.import_mapping (definition_id, source_column_id, target_column_id, source_value, source_expression)
    SELECT establishment_for_lu_explicit_def.id, sc.id, tc.id, NULL, NULL
    FROM establishment_for_lu_explicit_def
    JOIN establishment_for_lu_explicit_source_columns sc ON sc.definition_id = establishment_for_lu_explicit_def.id
    JOIN public.import_target_column tc ON tc.target_id = establishment_for_lu_explicit_def.target_id AND tc.column_name = sc.column_name
    RETURNING *
),

-- 5. Establishment without legal unit with time_context for current year
establishment_without_lu_target AS (
    SELECT * FROM public.import_target
    WHERE schema_name = 'public'
      AND table_name = 'import_establishment_era_without_legal_unit'
), establishment_without_lu_current_def AS (
    INSERT INTO public.import_definition
        ( target_id
        , slug
        , name
        , note
        , time_context_ident
        )
    SELECT establishment_without_lu_target.id
        , 'establishment_without_lu_current_year'
        , 'Establishment without Legal Unit - Current Year'
        , 'Import standalone establishments with validity period set to current year'
        , 'r_year_curr'
    FROM establishment_without_lu_target
    RETURNING *
), establishment_without_lu_current_source_columns AS (
    INSERT INTO public.import_source_column (definition_id, column_name, priority)
    SELECT establishment_without_lu_current_def.id, itc.column_name, ROW_NUMBER() OVER (ORDER BY itc.id)
    FROM establishment_without_lu_current_def
    JOIN public.import_target_column itc ON itc.target_id = establishment_without_lu_current_def.target_id
    WHERE itc.column_name NOT IN ('valid_from', 'valid_to')
    RETURNING *
), establishment_without_lu_current_mappings AS (
    -- Map source columns to target columns with same name
    INSERT INTO public.import_mapping (definition_id, source_column_id, target_column_id, source_value, source_expression)
    SELECT establishment_without_lu_current_def.id, sc.id, tc.id, NULL, NULL
    FROM establishment_without_lu_current_def
    JOIN establishment_without_lu_current_source_columns sc ON sc.definition_id = establishment_without_lu_current_def.id
    JOIN public.import_target_column tc ON tc.target_id = establishment_without_lu_current_def.target_id AND tc.column_name = sc.column_name

    UNION ALL

    -- Add default mappings for valid_from and valid_to
    SELECT establishment_without_lu_current_def.id, NULL, tc.id, NULL, 'default'::public.import_source_expression
    FROM establishment_without_lu_current_def
    JOIN public.import_target_column tc ON tc.target_id = establishment_without_lu_current_def.target_id
    WHERE tc.column_name IN ('valid_from', 'valid_to')
    RETURNING *
),

-- 6. Establishment without legal unit with explicit valid_from/valid_to
establishment_without_lu_explicit_def AS (
    INSERT INTO public.import_definition
        ( target_id
        , slug
        , name
        , note
        )
    SELECT establishment_without_lu_target.id
        , 'establishment_without_lu_explicit_dates'
        , 'Establishment without Legal Unit - Explicit Dates'
        , 'Import standalone establishments with explicit valid_from and valid_to columns'
    FROM establishment_without_lu_target
    RETURNING *
), establishment_without_lu_explicit_source_columns AS (
    INSERT INTO public.import_source_column (definition_id, column_name, priority)
    SELECT establishment_without_lu_explicit_def.id, itc.column_name, ROW_NUMBER() OVER (ORDER BY itc.id)
    FROM establishment_without_lu_explicit_def
    JOIN public.import_target_column itc ON itc.target_id = establishment_without_lu_explicit_def.target_id
    RETURNING *
), establishment_without_lu_explicit_mappings AS (
    -- Map all source columns to target columns with same name
    INSERT INTO public.import_mapping (definition_id, source_column_id, target_column_id, source_value, source_expression)
    SELECT establishment_without_lu_explicit_def.id, sc.id, tc.id, NULL, NULL
    FROM establishment_without_lu_explicit_def
    JOIN establishment_without_lu_explicit_source_columns sc ON sc.definition_id = establishment_without_lu_explicit_def.id
    JOIN public.import_target_column tc ON tc.target_id = establishment_without_lu_explicit_def.target_id AND tc.column_name = sc.column_name
    RETURNING *
)
SELECT 1;

-- Set all import definitions to non-draft mode
UPDATE public.import_definition
SET draft = false
WHERE draft
RETURNING *;

END;

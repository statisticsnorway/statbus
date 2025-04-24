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
    target_id int REFERENCES public.import_target(id) ON DELETE CASCADE,
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
    target_id int REFERENCES public.import_target(id) ON DELETE CASCADE,
    note text,
    data_source_id integer REFERENCES public.data_source(id) ON DELETE RESTRICT,
    time_context_ident TEXT, -- For lookup in public.time_context(ident) to get computed valid_from/valid_to
    user_id integer REFERENCES auth.user(id) ON DELETE SET NULL,
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

-- Procedure to notify about import_job_process status check
CREATE PROCEDURE worker.notify_check_is_importing()
LANGUAGE plpgsql
AS $procedure$
BEGIN
  PERFORM pg_notify('check', 'is_importing');
END;
$procedure$;

-- Register import_job_process command in the worker system
INSERT INTO worker.queue_registry (queue, concurrent, description)
VALUES ('import', true, 'Concurrent queue for processing import jobs');

INSERT INTO worker.command_registry (queue, command, handler_procedure, before_procedure, after_procedure, description)
VALUES
( 'import',
  'import_job_process',
  'admin.import_job_process',
  'worker.notify_check_is_importing', -- Before hook
  'worker.notify_check_is_importing', -- After hook
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
  v_priority INTEGER;
BEGIN
  -- Validate job exists and get priority
  SELECT priority INTO v_priority
  FROM public.import_job
  WHERE id = p_job_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Import job % not found', p_job_id;
  END IF;

  -- Create payload
  v_payload := jsonb_build_object('job_id', p_job_id);

  -- Insert task with payload and priority
  -- Use job priority if available, otherwise fall back to job ID
  -- This ensures jobs are processed in order of upload timestamp
  INSERT INTO worker.tasks (
    command,
    payload,
    priority
  ) VALUES (
    'import_job_process',
    v_payload,
    COALESCE(v_priority, p_job_id)
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
    definition_id int REFERENCES public.import_definition(id) ON DELETE CASCADE,
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
    definition_id int NOT NULL REFERENCES public.import_definition(id) ON DELETE CASCADE,
    source_column_id int REFERENCES public.import_source_column(id) ON DELETE CASCADE,
    CONSTRAINT unique_source_column_mapping UNIQUE (definition_id, source_column_id),
    source_value TEXT,
    source_expression public.import_source_expression,
    target_column_id int REFERENCES public.import_target_column(id) ON DELETE CASCADE,
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

CREATE TYPE public.import_job_state AS ENUM (
    'waiting_for_upload',  -- Initial state: User must upload data into table, then change state to upload_completed
    'upload_completed',    -- Triggers worker notification to begin processing
    'preparing_data',      -- Moving from custom names in upload table to standard names in data table
    'analysing_data',      -- Worker is analyzing the uploaded data
    'waiting_for_review',  -- Analysis complete, waiting for user to approve or reject
    'approved',            -- User approved changes, triggers worker to continue processing
    'rejected',            -- User rejected changes, no further processing
    'importing_data',      -- Worker is importing data into target table
    'finished'             -- Import process completed.
);

-- Create enum type for row-level import state tracking
CREATE TYPE public.import_data_state AS ENUM (
    'pending',     -- Initial state.
--    'analysing',   -- Row is currently being analysed
--    'analysed',    -- Row has been analysed
    'importing',   -- Row is currently being imported
    'imported',    -- Row has been successfully imported
    'error'        -- Error occurred
);

CREATE TABLE public.import_job (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    slug text UNIQUE NOT NULL,
    description text,
    note text,
    created_at timestamp with time zone NOT NULL DEFAULT NOW(),
    updated_at timestamp with time zone NOT NULL DEFAULT NOW(),
    default_valid_from DATE,
    default_valid_to DATE,
    default_data_source_code text,
    upload_table_name text NOT NULL,
    data_table_name text NOT NULL,
    target_table_name text NOT NULL,
    target_schema_name text NOT NULL,
    priority integer,
    import_information_snapshot_table_name text NOT NULL,
    analysis_start_at timestamp with time zone,
    analysis_stop_at timestamp with time zone,
    preparing_data_at timestamp with time zone,
    changes_approved_at timestamp with time zone,
    changes_rejected_at timestamp with time zone,
    import_start_at timestamp with time zone,
    import_stop_at timestamp with time zone,
    total_rows integer,
    imported_rows integer DEFAULT 0,
    import_completed_pct numeric(5,2) DEFAULT 0,
    import_rows_per_sec numeric(10,2),
    last_progress_update timestamp with time zone,
    state public.import_job_state NOT NULL DEFAULT 'waiting_for_upload',
    error TEXT,
    review boolean NOT NULL DEFAULT false,
    definition_id integer NOT NULL REFERENCES public.import_definition(id) ON DELETE CASCADE,
    user_id integer REFERENCES auth.user(id) ON DELETE SET NULL
);
CREATE INDEX ix_import_job_definition_id ON public.import_job USING btree (definition_id);
CREATE INDEX ix_import_job_user_id ON public.import_job USING btree (user_id);

-- Function to check if import job is in WAITING_FOR_UPLOAD state
CREATE FUNCTION admin.check_import_job_state_for_insert()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    job_state public.import_job_state;
    job_slug text;
    job_id integer;
BEGIN
    -- Extract job_slug from trigger name (format: tablename_check_state_before_insert)
    -- Using job_slug instead of job_id ensures trigger names are stable across test runs
    -- since slugs are deterministic while job_ids may vary between test runs
    job_slug := TG_ARGV[0]::text;

    SELECT id, state INTO job_id, job_state
    FROM public.import_job
    WHERE slug = job_slug;

    IF job_state != 'waiting_for_upload' THEN
        RAISE EXCEPTION 'Cannot insert data: import job % (slug: %) is not in waiting_for_upload state', job_id, job_slug;
    END IF;

    RETURN NULL; -- For BEFORE triggers with FOR EACH STATEMENT
END;
$$;

-- Function to update import job state after INSERT
CREATE FUNCTION admin.update_import_job_state_after_insert()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    row_count INTEGER;
    job_slug text;
BEGIN
    -- Extract job_slug from trigger arguments
    -- Using job_slug instead of job_id ensures trigger names are stable across test runs
    -- since slugs are deterministic while job_ids may vary between test runs
    job_slug := TG_ARGV[0]::text;

    -- Count rows in the table
    EXECUTE format('SELECT COUNT(*) FROM %s', TG_TABLE_NAME) INTO row_count;

    -- Only update state if rows were actually inserted
    IF row_count > 0 THEN
        UPDATE public.import_job
        SET state = 'upload_completed'
        WHERE slug = job_slug
        AND state = 'waiting_for_upload';
    END IF;

    RETURN NULL; -- For AFTER triggers with FOR EACH STATEMENT
END;
$$;

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
        JOIN public.data_source ds ON ds.id = id.data_source_id
        WHERE id.id = NEW.definition_id;
    END IF;

    -- Set the user_id from the current authenticated user
    IF NEW.user_id IS NULL THEN
        NEW.user_id := auth.uid();
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

-- Create trigger to notify on import job changes
CREATE FUNCTION admin.import_job_notify()
RETURNS TRIGGER LANGUAGE plpgsql AS $import_job_notify$
BEGIN
    IF TG_OP = 'DELETE' THEN
        PERFORM pg_notify('import_job', json_build_object('verb', TG_OP, 'id', OLD.id)::text);
        RETURN OLD;
    ELSE
        PERFORM pg_notify('import_job', json_build_object('verb', TG_OP, 'id', NEW.id)::text);
        RETURN NEW;
    END IF;
END;
$import_job_notify$;

CREATE TRIGGER import_job_notify_trigger
    AFTER INSERT OR UPDATE OR DELETE ON public.import_job
    FOR EACH ROW
    EXECUTE FUNCTION admin.import_job_notify();
    
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


-- Create sequence for import job priorities
CREATE SEQUENCE IF NOT EXISTS public.import_job_priority_seq;

-- Create trigger to automatically set timestamps when state changes
CREATE FUNCTION admin.import_job_state_change_before()
RETURNS TRIGGER LANGUAGE plpgsql AS $import_job_state_change_before$
DECLARE
    v_timestamp TIMESTAMPTZ := now();
    v_row_count INTEGER;
BEGIN
    -- Record timestamps for state changes if not already recorded
    IF NEW.state = 'analysing_data' AND NEW.analysis_start_at IS NULL THEN
        NEW.analysis_start_at := v_timestamp;
    END IF;

    IF NEW.state = 'preparing_data' AND NEW.preparing_data_at IS NULL THEN
        NEW.preparing_data_at := v_timestamp;
    END IF;

    IF NEW.state = 'waiting_for_review' AND NEW.analysis_stop_at IS NULL THEN
        NEW.analysis_stop_at := v_timestamp;
    END IF;

    IF NEW.state = 'approved' AND NEW.changes_approved_at IS NULL THEN
        NEW.changes_approved_at := v_timestamp;
    END IF;

    IF NEW.state = 'rejected' AND NEW.changes_rejected_at IS NULL THEN
        NEW.changes_rejected_at := v_timestamp;
    END IF;

    IF NEW.state = 'importing_data' AND NEW.import_start_at IS NULL THEN
        NEW.import_start_at := v_timestamp;
    END IF;

    IF NEW.state = 'finished' AND NEW.import_stop_at IS NULL THEN
        NEW.import_stop_at := v_timestamp;
    END IF;

    -- Derive total_rows when state changes to upload_completed
    IF OLD.state = 'waiting_for_upload' AND NEW.state = 'upload_completed' THEN
        -- Count rows in the upload table
        EXECUTE format('SELECT COUNT(*) FROM public.%I', NEW.upload_table_name) INTO v_row_count;
        NEW.total_rows := v_row_count;

        -- Set priority using the dedicated sequence
        -- Lower values = higher priority, so earlier jobs get lower sequence values
        -- This ensures jobs are processed in the order they were created
        NEW.priority := nextval('public.import_job_priority_seq')::integer;

        RAISE DEBUG 'Set total_rows to % for import job %', v_row_count, NEW.id;
    END IF;

    RETURN NEW;
END;
$import_job_state_change_before$;

CREATE TRIGGER import_job_state_change_before_trigger
    BEFORE UPDATE OF state ON public.import_job
    FOR EACH ROW
    EXECUTE FUNCTION admin.import_job_state_change_before();

-- Create trigger to enqueue processing after state changes
CREATE FUNCTION admin.import_job_state_change_after()
RETURNS TRIGGER LANGUAGE plpgsql AS $import_job_state_change_after$
BEGIN
    -- Only enqueue for processing when transitioning from user action states
    -- or when a state change happens that requires further processing
    IF (OLD.state = 'waiting_for_upload' AND NEW.state = 'upload_completed') OR
       (OLD.state = 'waiting_for_review' AND NEW.state = 'approved') THEN
        PERFORM admin.enqueue_import_job_process(NEW.id);
    END IF;

    RETURN NEW;
END;
$import_job_state_change_after$;

CREATE TRIGGER import_job_state_change_after_trigger
    AFTER UPDATE OF state ON public.import_job
    FOR EACH ROW
    EXECUTE FUNCTION admin.import_job_state_change_after();

/*
TRANSACTION VISIBILITY RATIONALE:

The import job processing system has been designed to process work in small,
discrete transactions rather than one large transaction. This approach offers
several important benefits:

1. Progress Visibility: By committing after each state change or batch, the
   progress becomes immediately visible to other database sessions. This allows
   users and monitoring systems to track the import progress in real-time.

2. Reduced Lock Contention: Smaller transactions hold locks for shorter periods,
   reducing the chance of blocking other database operations.

3. Transaction Safety: If an error occurs during processing, only the current
   batch is affected, not the entire import job. Previously processed batches
   remain committed.

4. Resource Management: Breaking the work into smaller chunks prevents transaction
   logs from growing too large and reduces memory usage.

5. Resumability: If the process is interrupted (server restart, etc.), it can
   resume from the last committed point rather than starting over.

The implementation uses a rescheduling mechanism where each transaction schedules
the next one via the worker queue system. This ensures that even if there's an
error in one transaction, the next one can still be scheduled and executed.
*/

-- Create trigger to update last_progress_update timestamp
CREATE FUNCTION admin.import_job_progress_update()
RETURNS TRIGGER LANGUAGE plpgsql AS $import_job_progress_update$
BEGIN
    -- Update last_progress_update timestamp when imported_rows changes
    IF OLD.imported_rows IS DISTINCT FROM NEW.imported_rows THEN
        NEW.last_progress_update := clock_timestamp();
    END IF;

    -- Calculate import_completed_pct
    IF NEW.total_rows IS NULL OR NEW.total_rows = 0 THEN
        NEW.import_completed_pct := 0;
    ELSE
        NEW.import_completed_pct := ROUND((NEW.imported_rows::numeric / NEW.total_rows::numeric) * 100, 2);
    END IF;

    -- Calculate import_rows_per_sec
    IF NEW.imported_rows = 0 OR NEW.import_start_at IS NULL THEN
        NEW.import_rows_per_sec := 0;
    ELSIF NEW.state = 'finished' AND NEW.import_stop_at IS NOT NULL THEN
        NEW.import_rows_per_sec := CASE
            WHEN EXTRACT(EPOCH FROM (NEW.import_stop_at - NEW.import_start_at)) <= 0 THEN 0
            ELSE ROUND((NEW.imported_rows::numeric / EXTRACT(EPOCH FROM (NEW.import_stop_at - NEW.import_start_at))), 2)
        END;
    ELSE
        NEW.import_rows_per_sec := CASE
            WHEN EXTRACT(EPOCH FROM (COALESCE(NEW.last_progress_update, clock_timestamp()) - NEW.import_start_at)) <= 0 THEN 0
            ELSE ROUND((NEW.imported_rows::numeric / EXTRACT(EPOCH FROM (COALESCE(NEW.last_progress_update, clock_timestamp()) - NEW.import_start_at))), 2)
        END;
    END IF;

    RETURN NEW;
END;
$import_job_progress_update$;

CREATE TRIGGER import_job_progress_update_trigger
    BEFORE UPDATE OF imported_rows ON public.import_job
    FOR EACH ROW
    EXECUTE FUNCTION admin.import_job_progress_update();

-- Create trigger for progress notifications
CREATE FUNCTION admin.import_job_progress_notify()
RETURNS TRIGGER LANGUAGE plpgsql AS $import_job_progress_notify$
BEGIN
    -- Notify clients about progress update
    PERFORM pg_notify(
        'import_job_progress',
        json_build_object(
            'job_id', NEW.id,
            'total_rows', NEW.total_rows,
            'imported_rows', NEW.imported_rows,
            'import_completed_pct', NEW.import_completed_pct,
            'import_rows_per_sec', NEW.import_rows_per_sec,
            'state', NEW.state
        )::text
    );
    RETURN NEW;
END;
$import_job_progress_notify$;

CREATE TRIGGER import_job_progress_notify_trigger
    AFTER UPDATE OF imported_rows, state ON public.import_job
    FOR EACH ROW
    EXECUTE FUNCTION admin.import_job_progress_notify();

-- Create function to get import job progress details including row states
CREATE FUNCTION public.get_import_job_progress(job_id integer)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER AS $get_import_job_progress$
DECLARE
    job public.import_job;
    row_states json;
BEGIN
    -- Get the job details
    SELECT * INTO job FROM public.import_job WHERE id = job_id;
    IF NOT FOUND THEN
        RETURN json_build_object('error', format('Import job %s not found', job_id));
    END IF;

    -- Get row state counts
    EXECUTE format(
        'SELECT json_build_object(
            ''pending'', COUNT(*) FILTER (WHERE state = ''pending''),
            ''importing'', COUNT(*) FILTER (WHERE state = ''importing''),
            ''imported'', COUNT(*) FILTER (WHERE state = ''imported''),
            ''error'', COUNT(*) FILTER (WHERE state = ''error'')
        ) FROM public.%I',
        job.data_table_name
    ) INTO row_states;

    -- Return detailed progress information
    RETURN json_build_object(
        'job_id', job.id,
        'state', job.state,
        'total_rows', job.total_rows,
        'imported_rows', job.imported_rows,
        'import_completed_pct', job.import_completed_pct,
        'import_rows_per_sec', job.import_rows_per_sec,
        'last_progress_update', job.last_progress_update,
        'row_states', row_states
    );
END;
$get_import_job_progress$;

GRANT EXECUTE ON FUNCTION public.get_import_job_progress TO authenticated;

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

-- Grant SELECT on the view to authenticated
GRANT SELECT ON public.import_information TO authenticated;

/*
Each import operates on it's on table.
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
$import_job_generate$;



-- Simple dispatcher for import_job_process
CREATE PROCEDURE admin.import_job_process(payload JSONB)
LANGUAGE plpgsql AS $import_job_process$
DECLARE
    job_id INTEGER;
BEGIN
    -- Extract job_id from payload and call the implementation procedure
    job_id := (payload->>'job_id')::INTEGER;

    -- Call the implementation procedure
    CALL admin.import_job_process(job_id);
END;
$import_job_process$;

-- Function to reschedule an import job for processing
-- This is used to ensure transaction visibility of progress
CREATE FUNCTION admin.reschedule_import_job_process(
  p_job_id INTEGER
) RETURNS BIGINT
LANGUAGE plpgsql
AS $function$
DECLARE
  v_task_id BIGINT;
  v_payload JSONB;
  v_job public.import_job;
BEGIN
  -- Get the job details to check if it should be rescheduled
  SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;

  -- Only reschedule if the job is in a state that requires further processing
  IF v_job.state IN ('upload_completed', 'preparing_data', 'analysing_data', 'approved', 'importing_data') THEN
    -- Create payload
    v_payload := jsonb_build_object('job_id', p_job_id);

    -- Insert task with payload and priority
    INSERT INTO worker.tasks (
      command,
      payload,
      priority
    ) VALUES (
      'import_job_process',
      v_payload,
      v_job.priority
    )
    RETURNING id INTO v_task_id;
    RAISE DEBUG 'Rescheduled Task ID: %', v_task_id;

    -- Notify worker of new task with queue information
    PERFORM pg_notify('worker_tasks', 'import');

    RETURN v_task_id;
  END IF;

  RETURN NULL;
END;
$function$;


-- Function to update import job state and return the updated record
CREATE FUNCTION admin.import_job_set_state(
    job public.import_job,
    new_state public.import_job_state
) RETURNS public.import_job
LANGUAGE plpgsql AS $import_job_set_state$
DECLARE
    updated_job public.import_job;
BEGIN
    -- Update the state in the database
    UPDATE public.import_job
    SET state = new_state
    WHERE id = job.id
    RETURNING * INTO updated_job;

    -- Return the updated record
    RETURN updated_job;
END;
$import_job_set_state$;

-- Function to calculate the next state based on the current state
CREATE FUNCTION admin.import_job_next_state(job public.import_job)
RETURNS public.import_job_state
LANGUAGE plpgsql AS $import_job_next_state$
BEGIN
    CASE job.state
        WHEN 'waiting_for_upload' THEN
            RETURN job.state; -- No automatic transition, requires user action

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
          RETURN job.state; -- No automatic transition, requires user action

        WHEN 'approved' THEN
            RETURN 'importing_data';

        WHEN 'rejected' THEN
            RETURN 'finished';

        WHEN 'importing_data' THEN
            RETURN job.state; -- Transition done by batch job as it completes.

        WHEN 'finished' THEN
            RETURN job.state; -- Terminal state

        ELSE
            RAISE EXCEPTION 'Unknown import job state: %', job.state;
    END CASE;
END;
$import_job_next_state$;


-- Function to set user context for import job processing
CREATE FUNCTION admin.set_import_job_user_context(job_id integer)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $set_import_job_user_context$
DECLARE
    v_email text;
    v_original_claims jsonb;
BEGIN
    -- Save the current user context if any
    v_original_claims := COALESCE(
        nullif(current_setting('request.jwt.claims', true), '')::jsonb,
        '{}'::jsonb
    );
    
    -- Store the original claims for reset
    PERFORM set_config('admin.original_claims', v_original_claims::text, true);

    -- Get the user email from the job
    SELECT u.email INTO v_email
    FROM public.import_job ij
    JOIN auth.user u ON ij.user_id = u.id
    WHERE ij.id = job_id;

    IF v_email IS NOT NULL THEN
        -- Set the user context
        PERFORM auth.set_user_context_from_email(v_email);
        RAISE DEBUG 'Set user context to % for import job %', v_email, job_id;
    ELSE
        RAISE DEBUG 'No user found for import job %, using current context', job_id;
    END IF;
END;
$set_import_job_user_context$;

-- Function to reset user context after import job processing
CREATE FUNCTION admin.reset_import_job_user_context()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $reset_import_job_user_context$
DECLARE
    v_original_claims jsonb;
BEGIN
    -- Get the original claims
    v_original_claims := COALESCE(
        nullif(current_setting('admin.original_claims', true), '')::jsonb,
        '{}'::jsonb
    );

    IF v_original_claims != '{}'::jsonb THEN
        -- Reset to the original claims
        PERFORM auth.use_jwt_claims_in_session(v_original_claims);
        RAISE DEBUG 'Reset user context to original claims';
    ELSE
        -- Clear the user context
        PERFORM auth.reset_session_context();
        RAISE DEBUG 'Cleared user context (no original claims)';
    END IF;
END;
$reset_import_job_user_context$;

-- Grant execute permissions on the user context functions
GRANT EXECUTE ON FUNCTION admin.set_import_job_user_context TO authenticated;
GRANT EXECUTE ON FUNCTION admin.reset_import_job_user_context TO authenticated;

CREATE PROCEDURE admin.import_job_process(job_id integer)
LANGUAGE plpgsql AS $import_job_process$
DECLARE
    job public.import_job;
    next_state public.import_job_state;
    should_reschedule BOOLEAN := FALSE;
BEGIN
    -- Get the job details
    SELECT * INTO job FROM public.import_job WHERE id = job_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Import job % not found', job_id;
    END IF;

    -- Set the user context to the job creator, for recording edit_by_user_id
    PERFORM admin.set_import_job_user_context(job_id);

    -- Process the job based on its current state
    -- We'll only process one state transition per transaction to ensure visibility

    -- Perform the appropriate action for the current state
    CASE job.state
    WHEN 'waiting_for_upload' THEN
        RAISE DEBUG 'Import job % is waiting for upload', job_id;
        should_reschedule := FALSE;

    WHEN 'upload_completed' THEN
        RAISE DEBUG 'Import job % is ready for preparing data', job_id;
        should_reschedule := TRUE;

    WHEN 'preparing_data' THEN
        PERFORM admin.import_job_prepare(job);
        should_reschedule := TRUE;

    WHEN 'analysing_data' THEN
        PERFORM admin.import_job_analyse(job);
        should_reschedule := TRUE;

    WHEN 'waiting_for_review' THEN
        RAISE DEBUG 'Import job % is waiting for review', job_id;
        should_reschedule := FALSE;

    WHEN 'approved' THEN
        RAISE DEBUG 'Import job % is approved for importing', job_id;
        should_reschedule := TRUE;

    WHEN 'rejected' THEN
        RAISE DEBUG 'Import job % was rejected', job_id;
        should_reschedule := FALSE;

    WHEN 'importing_data' THEN
        -- For importing, we'll handle batches in the import_job_insert function
        PERFORM admin.import_job_insert(job);

        -- Check if we need to reschedule (not finished yet)
        SELECT state = 'importing_data' INTO should_reschedule
        FROM public.import_job WHERE id = job_id;

    WHEN 'finished' THEN
        RAISE DEBUG 'Import job % completed successfully', job_id;
        should_reschedule := FALSE;

    ELSE
        RAISE WARNING 'Unknown import job state: %', job.state;
        should_reschedule := FALSE;
    END CASE;

    -- After processing the current state, calculate and set the next state
    -- Only transition if the job is still in the same state (it might have changed during processing)
    SELECT * INTO job FROM public.import_job WHERE id = job_id;
    next_state := admin.import_job_next_state(job);

    IF next_state <> job.state THEN
        -- Update the job state for the next run
        job := admin.import_job_set_state(job, next_state);
        RAISE DEBUG 'Updated import job % state from % to %', job_id, job.state, next_state;

        -- Always reschedule after a state change
        should_reschedule := TRUE;
    END IF;

    -- Reset the user context when done
    PERFORM admin.reset_import_job_user_context();

    -- Reschedule if needed
    IF should_reschedule THEN
        PERFORM admin.reschedule_import_job_process(job_id);
        RAISE DEBUG 'Rescheduled import job % for further processing', job_id;
    END IF;
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
    error_message TEXT;
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
                            WHEN 'data_source_code' THEN quote_literal(job.default_data_source_code)
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
    BEGIN
        RAISE DEBUG 'Executing upsert: %', merge_stmt;
        EXECUTE merge_stmt;

        DECLARE
          data_table_count INT;
        BEGIN
          EXECUTE format('SELECT count(*) FROM public.%I', job.data_table_name) INTO data_table_count;
          RAISE DEBUG 'There are % rows in %', data_table_count, job.data_table_name;
        END;
    EXCEPTION
        WHEN OTHERS THEN
            error_message := SQLERRM;
            RAISE DEBUG 'Error in import_job_prepare: %', error_message;

            -- Update the job with the error
            UPDATE public.import_job
            SET error = format('Error preparing data: %s', error_message)
            WHERE id = job.id;

            RAISE EXCEPTION 'Error preparing data: %', error_message;
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
DECLARE
    target_columns TEXT;
    batch_size INTEGER := 1000; -- Process 1000 rows at a time
    pending_count INTEGER;
    imported_count INTEGER := 0;
    error_count INTEGER := 0;
    batch_insert_stmt TEXT;
    batch_count INTEGER;
    uniquely_identifying_columns TEXT;
    should_continue BOOLEAN := TRUE;
    max_batches_per_transaction INTEGER := 1; -- Only process one batch per transaction
    current_batch INTEGER := 0;
BEGIN
    -- This function will copy data from the data table to the target table
    RAISE DEBUG 'IMPORT_JOB_INSERT: Starting import from % to %.%',
                 job.data_table_name, job.target_schema_name, job.target_table_name;

    -- Get target columns from the snapshot table (excluding state)
    EXECUTE format(
        'SELECT string_agg(quote_ident(target_column), '','')
        FROM public.%I
        WHERE target_column IS NOT NULL',
        job.import_information_snapshot_table_name
    ) INTO target_columns;

    RAISE DEBUG 'IMPORT_JOB_INSERT: Target columns: %', target_columns;

    -- Get uniquely identifying columns for the WHERE clause in batch processing
    EXECUTE format(
        'SELECT string_agg(quote_ident(target_column), '','')
        FROM public.%I
        WHERE uniquely_identifying = TRUE
          AND target_column IS NOT NULL',
        job.import_information_snapshot_table_name
    ) INTO uniquely_identifying_columns;

    RAISE DEBUG 'IMPORT_JOB_INSERT: Uniquely identifying columns: %', uniquely_identifying_columns;

    -- Count rows in different states
    DECLARE
        pending_count INTEGER;
        importing_count INTEGER;
        error_count INTEGER;
    BEGIN
        -- Get counts for all states in a single query using window functions
        EXECUTE format('
            WITH counts AS (
                SELECT
                    COUNT(*) FILTER (WHERE state = ''pending'') AS pending,
                    COUNT(*) FILTER (WHERE state = ''importing'') AS importing,
                    COUNT(*) FILTER (WHERE state = ''imported'') AS imported,
                    COUNT(*) FILTER (WHERE state = ''error'') AS error
                FROM public.%I
            )
            SELECT pending, importing, imported, error FROM counts',
            job.data_table_name
        ) INTO pending_count, importing_count, imported_count, error_count;

        RAISE DEBUG 'IMPORT_JOB_INSERT: Initial state - Pending: %, Processing: %, Imported: %, Error: %',
                    pending_count, importing_count, imported_count, error_count;

        -- If there are rows stuck in processing state, mark them as pending to retry
        IF importing_count > 0 THEN
            EXECUTE format('UPDATE public.%I SET state = ''pending'' WHERE state = ''importing''',
                          job.data_table_name);
            RAISE DEBUG 'IMPORT_JOB_INSERT: Reset % rows from processing to pending state', importing_count;
            pending_count := pending_count + importing_count;
        END IF;

        -- Update job with already imported rows (for resumability)
        -- Note: total_rows is set once when state changes to upload_completed and never changes
        -- import_completed_pct is now a generated column
        -- last_progress_update is set by the trigger
        UPDATE public.import_job
        SET imported_rows = imported_count
        WHERE id = job.id
        RETURNING * INTO job;
    END;

    -- Process in batches until all pending rows are processed
    DECLARE
        remaining_count INTEGER;
    BEGIN
        -- Initialize remaining count from pending rows
        EXECUTE format('SELECT COUNT(*) FROM public.%I WHERE state = ''pending''',
                      job.data_table_name) INTO remaining_count;

        RAISE DEBUG 'IMPORT_JOB_INSERT: Starting batch processing with % pending rows', remaining_count;

        -- Process until no pending rows remain or we've reached our batch limit
        WHILE remaining_count > 0 AND current_batch < max_batches_per_transaction LOOP
            -- Increment batch counter
            current_batch := current_batch + 1;
        BEGIN
            RAISE DEBUG 'IMPORT_JOB_INSERT: Starting new batch, remaining rows: %', remaining_count;

            -- Mark batch as processing (with row locking)
            DECLARE
                mark_batch_sql TEXT;
                marked_count INTEGER;
            BEGIN
                mark_batch_sql := format($format$
                    UPDATE public.%I
                    SET state = 'importing'
                    WHERE state = 'pending'
                    AND ctid IN (
                        SELECT ctid
                        FROM public.%I
                        WHERE state = 'pending'
                        ORDER BY %s
                        LIMIT %s
                    );
                $format$,
                job.data_table_name,
                job.data_table_name,
                COALESCE(uniquely_identifying_columns, 'ctid'),
                batch_size);

                RAISE DEBUG 'IMPORT_JOB_INSERT: Marking batch SQL: %', mark_batch_sql;
                EXECUTE mark_batch_sql;

                GET DIAGNOSTICS marked_count = ROW_COUNT;
                RAISE DEBUG 'IMPORT_JOB_INSERT: Marked % rows as processing', marked_count;

                -- If no rows were marked as processing, exit the loop
                IF marked_count = 0 THEN
                    RAISE DEBUG 'IMPORT_JOB_INSERT: No rows marked as processing, exiting loop';
                    EXIT;
                ELSE
                    batch_count := marked_count;
                END IF;
            END;

            -- Create batch insert statement for rows marked as processing
            batch_insert_stmt := format($format$
                WITH batch AS (
                    SELECT %s, ctid AS source_ctid
                    FROM public.%I
                    WHERE state = 'importing'
                    ORDER BY %s
                    FOR UPDATE
                ),
                inserted AS (
                    INSERT INTO %I.%I (%s)
                    SELECT %s FROM batch
                    RETURNING 1 AS inserted_row
                )
                SELECT COUNT(*) FROM inserted;
            $format$,
            target_columns,
            job.data_table_name,
            COALESCE(uniquely_identifying_columns, 'ctid'),
            job.target_schema_name,
            job.target_table_name,
            target_columns,
            target_columns
            );

            RAISE DEBUG 'IMPORT_JOB_INSERT: Batch insert SQL: %', batch_insert_stmt;

            -- Execute batch insert
            -- Execute and capture actual inserted count
            DECLARE
                reported_inserted INTEGER;
                is_view BOOLEAN;
                v_error TEXT;
            BEGIN
                -- Execute with error handling
                BEGIN
                    EXECUTE batch_insert_stmt INTO reported_inserted;
                EXCEPTION WHEN OTHERS THEN
                    -- Capture the specific error for this statement with enhanced diagnostics
                    DECLARE
                        v_detail TEXT;
                        v_context TEXT;
                        v_hint TEXT;
                        v_state TEXT;
                        v_message TEXT;
                        v_column_name TEXT;
                        v_constraint_name TEXT;
                        v_table_name TEXT;
                        v_schema_name TEXT;
                    BEGIN
                        GET STACKED DIAGNOSTICS
                            v_state = RETURNED_SQLSTATE,
                            v_message = MESSAGE_TEXT,
                            v_detail = PG_EXCEPTION_DETAIL,
                            v_hint = PG_EXCEPTION_HINT,
                            v_context = PG_EXCEPTION_CONTEXT,
                            v_column_name = COLUMN_NAME,
                            v_constraint_name = CONSTRAINT_NAME,
                            v_table_name = TABLE_NAME,
                            v_schema_name = SCHEMA_NAME;

                        RAISE DEBUG 'IMPORT_JOB_INSERT: Error executing batch insert: %', v_message;
                        RAISE DEBUG 'IMPORT_JOB_INSERT: Error details: %, Hint: %', v_detail, v_hint;
                        RAISE DEBUG 'IMPORT_JOB_INSERT: Error state: %, Context: %', v_state, v_context;
                        RAISE DEBUG 'IMPORT_JOB_INSERT: Related objects - Table: %.%, Column: %, Constraint: %',
                                    v_schema_name, v_table_name, v_column_name, v_constraint_name;

                        -- Format the error message while all variables are in scope
                        v_error := format('Import failed: %s. Details: %s. Hint: %s. Related to: %s.%s%s%s',
                                      v_message,
                                      v_detail,
                                      v_hint,
                                      COALESCE(v_schema_name, ''),
                                      COALESCE(v_table_name, ''),
                                      CASE WHEN v_column_name IS NOT NULL THEN '.' || v_column_name ELSE '' END,
                                      CASE WHEN v_constraint_name IS NOT NULL THEN ' (constraint: ' || v_constraint_name || ')' ELSE '' END);
                    END;

                    -- Mark rows with error - this won't be rolled back since it's outside the exception block
                    EXECUTE format($format$
                        UPDATE public.%I
                        SET state = 'error'
                        WHERE state = 'importing';
                    $format$, job.data_table_name);

                    -- Count error rows
                    EXECUTE format('SELECT COUNT(*) FROM public.%I WHERE state = ''error''',
                                  job.data_table_name) INTO error_count;

                    -- Log the error
                    RAISE WARNING 'Error importing batch: %. % rows marked as error.', SQLERRM, error_count;

                    -- Get the actual count of successfully imported rows
                    DECLARE
                        actual_imported_count INTEGER;
                    BEGIN
                        EXECUTE format('SELECT COUNT(*) FROM public.%I WHERE state = ''imported''',
                                      job.data_table_name) INTO actual_imported_count;

                        -- Update the job with the error, mark as finished, and set correct imported_rows count
                        UPDATE public.import_job
                        SET state = 'finished',
                            error = v_error,
                            imported_rows = actual_imported_count
                        WHERE id = job.id;

                        RAISE DEBUG 'IMPORT_JOB_INSERT: Import job marked as finished due to error with % imported rows', actual_imported_count;
                    END;

                    -- Prevent further processing, since the job is already marked as finished.
                    RETURN;
                END;

                -- If rows were inserted successfully, use that count
                IF reported_inserted > 0 THEN
                    RAISE DEBUG 'IMPORT_JOB_INSERT: Inserted % rows in this batch (reported by INSERT)', reported_inserted;
                    batch_count := reported_inserted;
                ELSE
                    -- Check if the target is a view
                    EXECUTE format(
                        'SELECT EXISTS (
                            SELECT 1 FROM information_schema.views
                            WHERE table_schema = %L AND table_name = %L
                        )',
                        job.target_schema_name, job.target_table_name
                    ) INTO is_view;

                    IF is_view THEN
                        -- For views, we can't rely on the INSERT returning count
                        -- so we'll preserve the batch_count set in the marking phase.
                        RAISE DEBUG 'IMPORT_JOB_INSERT: Target is a view, assuming all marked rows were processed successfully';
                    ELSE
                        -- For tables, if nothing was inserted, that's an error
                        RAISE EXCEPTION 'Failed to insert any rows into table %.%', job.target_schema_name, job.target_table_name;
                    END IF;
                END IF;
            END;

            -- Mark processed rows as imported
            DECLARE
                mark_imported_sql TEXT;
                marked_count INTEGER;
            BEGIN
                mark_imported_sql := format($format$
                    UPDATE public.%I
                    SET state = 'imported'
                    WHERE state = 'importing';
                $format$, job.data_table_name);

                RAISE DEBUG 'IMPORT_JOB_INSERT: Marking as imported SQL: %', mark_imported_sql;
                EXECUTE mark_imported_sql;

                GET DIAGNOSTICS marked_count = ROW_COUNT;
                RAISE DEBUG 'IMPORT_JOB_INSERT: Marked % rows as imported', marked_count;

                -- Update the imported_rows count immediately after marking rows as imported
                -- This ensures we don't lose track of progress between batches
                IF marked_count > 0 THEN
                    UPDATE public.import_job
                    SET imported_rows = imported_rows + marked_count
                    WHERE id = job.id;
                    RAISE DEBUG 'IMPORT_JOB_INSERT: Updated imported_rows count by adding % rows', marked_count;
                END IF;
            END;

            -- Update imported count
            imported_count := imported_count + batch_count;

            -- Recalculate remaining count directly from database
            EXECUTE format('SELECT COUNT(*) FROM public.%I WHERE state = ''pending''',
                          job.data_table_name) INTO remaining_count;

            RAISE DEBUG 'IMPORT_JOB_INSERT: Updated counts - imported: %, remaining: %', imported_count, remaining_count;

            -- Update progress in job table
            DECLARE
                current_progress numeric(5,2);
                imported_count INTEGER;
            BEGIN
                -- Get the actual count of imported rows from the data table
                EXECUTE format('SELECT COUNT(*) FROM public.%I WHERE state = ''imported''',
                              job.data_table_name) INTO imported_count;

                UPDATE public.import_job
                SET imported_rows = imported_count
                WHERE id = job.id
                RETURNING import_completed_pct INTO current_progress;

                RAISE DEBUG 'IMPORT_JOB_INSERT: Updated job progress to % complete', current_progress;
            END;

        END;
    END LOOP;

    -- Do a final count to ensure we have the correct numbers
    EXECUTE format('
        WITH counts AS (
            SELECT
                COUNT(*) FILTER (WHERE state = ''pending'') AS pending,
                COUNT(*) FILTER (WHERE state = ''imported'') AS imported,
                COUNT(*) FILTER (WHERE state = ''error'') AS error
            FROM public.%I
        )
        SELECT pending, imported, error FROM counts',
        job.data_table_name
    ) INTO pending_count, imported_count, error_count;

    RAISE DEBUG 'IMPORT_JOB_INSERT: Batches processed. Counts - Pending: %, Imported: %, Errors: %',
                pending_count, imported_count, error_count;

    -- Update job with current counts - ensure we use the actual count from the data table
    -- This is critical for ensuring the final count is accurate
    UPDATE public.import_job
    SET imported_rows = imported_count
    WHERE id = job.id;

    RAISE DEBUG 'IMPORT_JOB_INSERT: Final update of imported_rows to %', imported_count;

    -- Check if there were any errors during processing
    IF error_count > 0 THEN
        -- We've already marked the job as finished with an error in the exception handler
        RAISE DEBUG 'IMPORT_JOB_INSERT: Import failed with % errors', error_count;
    -- If there are still pending rows, we need to continue in the next transaction
    ELSIF pending_count > 0 THEN
        RAISE DEBUG 'IMPORT_JOB_INSERT: Still have % rows to import, will continue in next transaction', pending_count;
    ELSE
        -- No more pending rows and no errors, we're done successfully
        -- Update job state to finished and ensure the imported_rows count is accurate
        EXECUTE format('
            WITH counts AS (
                SELECT COUNT(*) FILTER (WHERE state = ''imported'') AS imported
                FROM public.%I
            )
            UPDATE public.import_job
            SET state = ''finished'',
                imported_rows = (SELECT imported FROM counts)
            WHERE id = %L',
            job.data_table_name,
            job.id
        );

        RAISE DEBUG 'IMPORT_JOB_INSERT: Set state to finished and ensured final imported_rows count is accurate';
        RAISE DEBUG 'IMPORT_JOB_INSERT: Import completed successfully';
    END IF;
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

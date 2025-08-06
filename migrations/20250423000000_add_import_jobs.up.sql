-- Migration 20250227115859: add import jobs
BEGIN;


-- Create a separate schema for all the import related functions that are used internally
-- by the import job system, but not available through the API.
CREATE SCHEMA import;
GRANT USAGE ON SCHEMA import TO authenticated;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA import TO authenticated;


-- Represents a logical component or processing stage within an import definition.
-- Steps are ordered by priority to manage dependencies.
CREATE TABLE public.import_step(
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code text UNIQUE NOT NULL, -- Unique code identifier for the step (snake_case)
    name text NOT NULL,        -- Human-readable name for UI
    priority integer NOT NULL,
    analyse_procedure regproc, -- Procedure for analysis phase (optional)
    process_procedure regproc, -- Procedure for the final operation (insert/update/upsert) phase (optional)
    created_at timestamp with time zone NOT NULL DEFAULT NOW(),
    updated_at timestamp with time zone NOT NULL DEFAULT NOW()
);
COMMENT ON TABLE public.import_step IS 'Logical processing step within an import definition (e.g., external_ident, legal_unit, physical_location). Ordered by priority.';
COMMENT ON COLUMN public.import_step.code IS 'Unique code identifier for the step (snake_case).';
COMMENT ON COLUMN public.import_step.name IS 'Human-readable name for UI display.';
COMMENT ON COLUMN public.import_step.priority IS 'Execution order for the step (lower runs first).';
COMMENT ON COLUMN public.import_step.analyse_procedure IS 'Optional procedure to run during the analysis phase for this step.';
COMMENT ON COLUMN public.import_step.process_procedure IS 'Optional procedure to run during the final operation (insert/update/upsert) phase for this step. Must respect import_definition.strategy.';

-- Enum to control the final insertion behavior
CREATE TYPE public.import_strategy AS ENUM ('insert_or_replace', 'insert_only', 'replace_only', 'insert_or_update', 'update_only');
COMMENT ON TYPE public.import_strategy IS
'Defines the strategy when inserting data into the final target table(s):
- insert_or_replace: Insert new rows, or replace existing rows (temporal data is handled by replacing overlapping periods).
- insert_only: Only insert new rows, skip or error on existing rows.
- replace_only: Only replace existing rows, skip rows that do not already exist.
- insert_or_update: Insert new rows, or update existing rows with non-null values from source, handling temporal aspects by splitting/adjusting eras.
- update_only: Only update existing rows, skip or error on new rows.';

-- Enum to define the structural mode of the import, particularly for establishments
CREATE TYPE public.import_mode AS ENUM (
    'legal_unit',        -- Standard import for legal units (implies formal economy context for linked establishments)
    'establishment_formal', -- Establishment linked to a legal unit
    'establishment_informal', -- Establishment linked directly to an enterprise (informal economy)
    'generic_unit'       -- For operations that apply to any unit type (e.g., stats updates)
);
COMMENT ON TYPE public.import_mode IS
'Defines the structural mode of the import, especially relevant for establishments:
- legal_unit: Standard import for legal units. Establishments linked to these are implicitly formal.
- establishment_formal: Establishment is linked to a Legal Unit (typical formal economy).
- establishment_informal: Establishment is linked directly to an Enterprise (typical informal economy).
- generic_unit: For operations that apply to any pre-existing unit type, like statistical variable updates.';

CREATE TYPE public.import_valid_time_from AS ENUM (
    'job_provided',   -- Validity is derived from parameters provided on the import job (either a time_context or explicit dates).
    'source_columns'  -- Validity is derived from 'valid_from'/'valid_to' columns in the source data.
);
COMMENT ON TYPE public.import_valid_time_from IS
'Defines how the validity period for imported records is determined:
- job_provided: The import job must be created with either a `time_context_ident` or explicit `default_valid_from`/`to` dates.
- source_columns: The source data file must contain columns that map to valid_from and valid_to for each record.';

CREATE TYPE public.import_row_operation_type AS ENUM (
    'insert',  -- Row represents a new unit/record to be inserted (no existing unit found).
    'replace', -- Row represents an existing unit/record to be replaced (existing unit found, strategy implies replacement).
    'update'   -- Row represents an existing unit/record to be updated (existing unit found, strategy implies update).
);
COMMENT ON TYPE public.import_row_operation_type IS
'Specifies the intended high-level operation for an import data row after initial analysis of identifiers:
- insert: No existing unit found; a new record is intended.
- replace: An existing unit was found, and the strategy implies a replacement-style modification.
- update: An existing unit was found, and the strategy implies an update-style modification.';

CREATE TYPE public.import_row_action_type AS ENUM (
    'insert',  -- Row represents a new unit/record to be inserted.
    'replace', -- Row represents an existing unit/record to be updated/replaced (using batch upsert logic, effectively replacing the temporal slice).
    'update',  -- Row represents an existing unit/record to be updated (merging non-null values into the existing temporal slice).
    'skip'     -- Row should be skipped due to strategy mismatch or other reasons identified during analysis.
);

COMMENT ON TYPE public.import_row_action_type IS
'Specifies the intended action for an import data row after analysis:
- insert: Create a new record.
- replace: Replace an existing record (temporal data is handled by replacing overlapping periods).
- update: Update an existing record (temporal data is handled by merging data into overlapping periods, potentially splitting/adjusting eras).
- skip: Do not process this row further due to strategy mismatch or errors.';


CREATE TABLE public.import_definition(
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    slug text UNIQUE NOT NULL,
    name text UNIQUE NOT NULL,
    note text,
    data_source_id integer REFERENCES public.data_source(id) ON DELETE RESTRICT,
    strategy public.import_strategy NOT NULL DEFAULT 'insert_or_replace'::public.import_strategy,
    mode public.import_mode NOT NULL, -- Defines the structural mode (e.g., for establishment imports)
    valid_time_from public.import_valid_time_from NOT NULL, -- Declarative method for time validity.
    user_id integer REFERENCES auth.user(id) ON DELETE SET NULL,
    active boolean NOT NULL DEFAULT true, -- Whether the definition is active and usable
    custom boolean NOT NULL DEFAULT true, -- True if system-provided default, false if user-created/customized.
    valid boolean NOT NULL DEFAULT false, -- Indicates if the definition passes validation checks
    validation_error text,                -- Stores validation error messages if not valid
    default_retention_period INTERVAL NOT NULL DEFAULT '18 months'::INTERVAL, -- Default period after which related job data can be cleaned up
    created_at timestamp with time zone NOT NULL DEFAULT NOW(),
    updated_at timestamp with time zone NOT NULL DEFAULT NOW()
    -- Removed draft column and draft_valid_error_states constraint
);
CREATE INDEX ix_import_user_id ON public.import_definition USING btree (user_id);
CREATE INDEX ix_import_data_source_id ON public.import_definition USING btree (data_source_id);

COMMENT ON COLUMN public.import_definition.strategy IS 'Defines the strategy (insert_or_replace, insert_only, replace_only, insert_or_update, update_only) for the final insertion step.';
COMMENT ON COLUMN public.import_definition.mode IS 'Defines the structural mode of the import, e.g., if an establishment is linked to a legal unit (formal) or directly to an enterprise (informal).';
COMMENT ON COLUMN public.import_definition.valid_time_from IS 'Declaratively defines how the validity period for imported records is determined (from a job-level time context or from columns in the source file).';
COMMENT ON COLUMN public.import_definition.valid IS 'Indicates if the definition passes validation checks.';
COMMENT ON COLUMN public.import_definition.validation_error IS 'Stores validation error messages if not valid.';
COMMENT ON COLUMN public.import_definition.default_retention_period IS 'Default period after which related job data (job record, _upload, _data tables) can be cleaned up. Calculated from job creation time.';

-- Removed import_definition_validate_before function and trigger
-- Validation logic should be consolidated or handled differently if needed beyond job creation check.

-- Enum defining the purpose of a column in the intermediate _data table
CREATE TYPE public.import_data_column_purpose AS ENUM (
    'source_input',      -- Raw data mapped directly from the source file
    'internal',          -- Result of lookups/calculations during analysis phase
    'pk_id',             -- ID of the record inserted into a final table by this target
    'metadata'           -- Internal status/error tracking columns (state, error, last_completed_priority)
);
COMMENT ON TYPE public.import_data_column_purpose IS
'Defines the role of a column within the job-specific _data table:
- source_input: Raw data mapped directly from the source file (always TEXT).
- internal: Intermediate results from analysis (lookups, type casting, calculations).
- pk_id: Primary key of the record inserted/updated in a final Statbus table by a process step.
- metadata: Internal columns for tracking row state and errors.';

-- Defines the data columns required or produced by a specific import step.
-- The schema of a job's _data table is derived from the columns associated with the steps linked to its definition.
CREATE TABLE public.import_data_column (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    -- definition_id removed - columns are now defined per step
    step_id int NOT NULL REFERENCES public.import_step(id) ON DELETE CASCADE, -- Step this column belongs to (NULL for global metadata like state, error)
    priority int, -- Defines column order within a step or for metadata columns. Metadata columns (step_id IS NULL) use this. Step columns order by step.priority then this. Can be NULL for step columns.
    column_name text NOT NULL,
    column_type text NOT NULL,
    purpose public.import_data_column_purpose NOT NULL,
    is_nullable boolean NOT NULL DEFAULT true,
    default_value text, -- Default value expression (e.g., 'now()', '0')
    is_uniquely_identifying boolean NOT NULL DEFAULT false, -- Used for ON CONFLICT in prepare step
    created_at timestamp with time zone NOT NULL DEFAULT NOW(),
    updated_at timestamp with time zone NOT NULL DEFAULT NOW(),
    UNIQUE (step_id, column_name), -- Unique column name within a step (or globally if step_id is NULL)
    UNIQUE (id, purpose), -- Added for FK constraint from import_mapping
    CONSTRAINT unique_identifying_only_for_source_input CHECK (NOT is_uniquely_identifying OR purpose = 'source_input')
);
COMMENT ON TABLE public.import_data_column IS 'Defines data columns required or produced by import steps. The schema of a job''s _data table is derived from these based on the steps linked to the job''s definition.';
COMMENT ON COLUMN public.import_data_column.step_id IS 'The import step this column is associated with (NULL for global metadata columns like state, error).';
COMMENT ON COLUMN public.import_data_column.purpose IS 'Role of the column in the _data table (source_input, internal, pk_id, metadata).';
COMMENT ON COLUMN public.import_data_column.is_nullable IS 'Whether the column in the _data table can be NULL.';
COMMENT ON COLUMN public.import_data_column.default_value IS 'SQL default value expression for the column in the _data table.';
COMMENT ON COLUMN public.import_data_column.is_uniquely_identifying IS 'Indicates if this data column (must have purpose=source_input) contributes to the unique identification of a row for UPSERT logic during the prepare step.';

-- Removed admin.prevent_changes_to_non_draft_definition function and related triggers
-- Changes are now allowed regardless of the 'valid' status. Validation occurs at job creation.

-- Linking table between import definitions and the steps they include.
CREATE TABLE public.import_definition_step (
    definition_id INT NOT NULL REFERENCES public.import_definition(id) ON DELETE CASCADE,
    step_id INT NOT NULL REFERENCES public.import_step(id) ON DELETE CASCADE,
    PRIMARY KEY (definition_id, step_id)
);
COMMENT ON TABLE public.import_definition_step IS 'Connects an import definition to the specific import steps it utilizes.';

-- Removed trigger prevent_non_draft_definition_step_changes

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

-- Removed validate_time_context_ident function and trigger prevent_non_draft_changes_and_validate
-- Time context validation can happen within admin.import_job_derive if needed, or a separate validation function.

CREATE TABLE public.import_source_column(
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    definition_id int NOT NULL REFERENCES public.import_definition(id) ON DELETE CASCADE, -- Made NOT NULL
    column_name text NOT NULL,
    priority int NOT NULL,
    created_at timestamp with time zone NOT NULL DEFAULT NOW(),
    updated_at timestamp with time zone NOT NULL DEFAULT NOW(),
    UNIQUE (definition_id, column_name),
    UNIQUE (definition_id, priority)
);
COMMENT ON COLUMN public.import_source_column.priority IS 'The 1-based ordering of the columns in the source file.';

-- Removed trigger prevent_non_draft_source_column_changes

CREATE TYPE public.import_source_expression AS ENUM ('now', 'default');

CREATE TABLE public.import_mapping(
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    definition_id int NOT NULL REFERENCES public.import_definition(id) ON DELETE CASCADE,
    source_column_id int REFERENCES public.import_source_column(id) ON DELETE CASCADE,
    -- Removed unique constraint unique_source_column_mapping as it might be too strict if multiple sources map to one target initially? Revisit if needed.
    source_value TEXT,
    source_expression public.import_source_expression,
    target_data_column_id int REFERENCES public.import_data_column(id) ON DELETE CASCADE, -- FK to import_data_column
    is_ignored BOOLEAN NOT NULL DEFAULT false, -- If true, this source_column is explicitly ignored
    target_data_column_purpose public.import_data_column_purpose, -- Nullable, no default. Value constrained by "mapping_logic"
    -- Old constraints unique_target_data_column_mapping, only_one_source_can_be_defined,
    -- target_data_column_must_be_defined, and target_data_column_purpose_must_be_source_input
    -- are replaced by the "mapping_logic" CHECK constraint and a partial unique index.

    CONSTRAINT unique_source_to_target_mapping UNIQUE (definition_id, source_column_id, target_data_column_id), -- Ensure a source maps to a target only once per definition (applies to non-ignored)

    CONSTRAINT "mapping_logic" CHECK (
        (
            is_ignored IS TRUE AND
            source_column_id IS NOT NULL AND -- Must specify which source column is ignored
            source_value IS NULL AND
            source_expression IS NULL AND
            target_data_column_id IS NULL AND -- No target when ignored
            target_data_column_purpose IS NULL    -- No target purpose when ignored
        ) OR (
            is_ignored IS FALSE AND
            target_data_column_id IS NOT NULL AND -- Must have a target when not ignored
            target_data_column_purpose = 'source_input'::public.import_data_column_purpose AND -- Target purpose must be source_input
            ( -- Exactly one source type must be defined
                (source_column_id IS NOT NULL AND source_value IS NULL AND source_expression IS NULL) OR
                (source_column_id IS NULL AND source_value IS NOT NULL AND source_expression IS NULL) OR
                (source_column_id IS NULL AND source_value IS NULL AND source_expression IS NOT NULL)
            )
        )
    ),
    FOREIGN KEY (target_data_column_id, target_data_column_purpose) REFERENCES public.import_data_column(id, purpose), -- Applies when target_data_column_id is not null
    created_at timestamp with time zone NOT NULL DEFAULT NOW(),
    updated_at timestamp with time zone NOT NULL DEFAULT NOW()
);
-- Partial unique index to ensure target_data_column_id is unique per definition only for non-ignored mappings
CREATE UNIQUE INDEX idx_unique_target_mapping_when_not_ignored
ON public.import_mapping (definition_id, target_data_column_id)
WHERE is_ignored = false;

COMMENT ON COLUMN public.import_mapping.is_ignored IS 'If true, the source_column_id is explicitly marked as ignored for this import definition, and no target_data_column should be specified.';
COMMENT ON COLUMN public.import_mapping.target_data_column_id IS 'The target column in the _data table. NULL if is_ignored is true.';
COMMENT ON COLUMN public.import_mapping.target_data_column_purpose IS 'The purpose of the target data column. Must be ''source_input'' if not ignored, NULL if ignored.';

-- Removed trigger prevent_non_draft_mapping_changes

-- Function to validate import_definition
CREATE OR REPLACE FUNCTION admin.validate_import_definition(p_definition_id INT)
RETURNS void LANGUAGE plpgsql AS $validate_import_definition$
DECLARE
    v_definition public.import_definition;
    v_error_messages TEXT[] := ARRAY[]::TEXT[];
    v_is_valid BOOLEAN := true;
    v_step_codes TEXT[];
    v_has_time_from_context_step BOOLEAN;
    v_has_time_from_source_step BOOLEAN;
    v_has_valid_from_mapping BOOLEAN := false;
    v_has_valid_to_mapping BOOLEAN := false;
    v_source_col_rec RECORD;
    v_mapping_rec RECORD;
    v_temp_text TEXT;
BEGIN
    SELECT * INTO v_definition FROM public.import_definition WHERE id = p_definition_id;
    IF NOT FOUND THEN
        RAISE DEBUG 'validate_import_definition: Definition ID % not found. Skipping validation.', p_definition_id;
        RETURN;
    END IF;

    -- 1. Time Validity Method Check
    -- All definitions must include the 'valid_time' step to ensure uniform processing.
    IF NOT EXISTS (SELECT 1 FROM public.import_definition_step ids JOIN public.import_step s ON s.id = ids.step_id WHERE ids.definition_id = p_definition_id AND s.code = 'valid_time') THEN
        v_is_valid := false;
        v_error_messages := array_append(v_error_messages, 'All import definitions must include the "valid_time" step.');
    END IF;

    -- The following checks ensure the mappings for 'valid_from' and 'valid_to' are consistent with the chosen time validity mode.
    IF v_definition.valid_time_from = 'source_columns' THEN
        -- Check that 'valid_from' and 'valid_to' are mapped from source columns.
        SELECT EXISTS (
            SELECT 1 FROM public.import_mapping im
            JOIN public.import_data_column idc ON im.target_data_column_id = idc.id JOIN public.import_step s ON idc.step_id = s.id
            WHERE im.definition_id = p_definition_id AND s.code = 'valid_time' AND idc.column_name = 'valid_from' AND im.source_column_id IS NOT NULL AND im.is_ignored = FALSE
        ) INTO v_has_valid_from_mapping;
        SELECT EXISTS (
            SELECT 1 FROM public.import_mapping im
            JOIN public.import_data_column idc ON im.target_data_column_id = idc.id JOIN public.import_step s ON idc.step_id = s.id
            WHERE im.definition_id = p_definition_id AND s.code = 'valid_time' AND idc.column_name = 'valid_to' AND im.source_column_id IS NOT NULL AND im.is_ignored = FALSE
        ) INTO v_has_valid_to_mapping;

        IF NOT (v_has_valid_from_mapping AND v_has_valid_to_mapping) THEN
            v_is_valid := false;
            v_error_messages := array_append(v_error_messages, 'When valid_time_from="source_columns", mappings for both "valid_from" and "valid_to" from source columns are required.');
        END IF;

    ELSIF v_definition.valid_time_from = 'job_provided' THEN
        -- If validity is derived from job-level parameters, the definition must map 'valid_from'
        -- and 'valid_to' to the 'default' source expression. This allows the `import_job_prepare`
        -- function to populate these columns from the job's `default_valid_from`/`to` fields.
        SELECT EXISTS (
            SELECT 1 FROM public.import_mapping im
            JOIN public.import_data_column idc ON im.target_data_column_id = idc.id JOIN public.import_step s ON idc.step_id = s.id
            WHERE im.definition_id = p_definition_id AND s.code = 'valid_time' AND idc.column_name = 'valid_from' AND im.source_expression = 'default' AND im.is_ignored = FALSE
        ) INTO v_has_valid_from_mapping;
        SELECT EXISTS (
            SELECT 1 FROM public.import_mapping im
            JOIN public.import_data_column idc ON im.target_data_column_id = idc.id JOIN public.import_step s ON idc.step_id = s.id
            WHERE im.definition_id = p_definition_id AND s.code = 'valid_time' AND idc.column_name = 'valid_to' AND im.source_expression = 'default' AND im.is_ignored = FALSE
        ) INTO v_has_valid_to_mapping;

        IF NOT (v_has_valid_from_mapping AND v_has_valid_to_mapping) THEN
            v_is_valid := false;
            v_error_messages := array_append(v_error_messages, 'When valid_time_from="job_provided", mappings for both "valid_from" and "valid_to" using source_expression="default" are required.');
        END IF;

    ELSE
      v_is_valid := false;
      v_error_messages := array_append(v_error_messages, 'valid_time_from is NULL or has an unhandled value.');
    END IF;

    -- 2. Mode-specific step checks
    SELECT array_agg(s.code) INTO v_step_codes
    FROM public.import_definition_step ids
    JOIN public.import_step s ON ids.step_id = s.id
    WHERE ids.definition_id = p_definition_id;
    v_step_codes := COALESCE(v_step_codes, ARRAY[]::TEXT[]);

    IF v_definition.mode = 'legal_unit' THEN
        IF NOT ('legal_unit' = ANY(v_step_codes)) THEN
            v_is_valid := false;
            v_error_messages := array_append(v_error_messages, 'Mode "legal_unit" requires the "legal_unit" step.');
        END IF;
        IF NOT ('enterprise_link_for_legal_unit' = ANY(v_step_codes)) THEN
            v_is_valid := false;
            v_error_messages := array_append(v_error_messages, 'Mode "legal_unit" requires the "enterprise_link_for_legal_unit" step.');
        END IF;
    ELSIF v_definition.mode = 'establishment_formal' THEN
        IF NOT ('establishment' = ANY(v_step_codes)) THEN
            v_is_valid := false;
            v_error_messages := array_append(v_error_messages, 'Mode "establishment_formal" requires the "establishment" step.');
        END IF;
        IF NOT ('link_establishment_to_legal_unit' = ANY(v_step_codes)) THEN
            v_is_valid := false;
            v_error_messages := array_append(v_error_messages, 'Mode "establishment_formal" requires the "link_establishment_to_legal_unit" step.');
        END IF;
    ELSIF v_definition.mode = 'establishment_informal' THEN
        IF NOT ('establishment' = ANY(v_step_codes)) THEN
            v_is_valid := false;
            v_error_messages := array_append(v_error_messages, 'Mode "establishment_informal" requires the "establishment" step.');
        END IF;
        IF NOT ('enterprise_link_for_establishment' = ANY(v_step_codes)) THEN
            v_is_valid := false;
            v_error_messages := array_append(v_error_messages, 'Mode "establishment_informal" requires the "enterprise_link_for_establishment" step.');
        END IF;
    ELSIF v_definition.mode = 'generic_unit' THEN
        -- Generic unit mode might have fewer structural step requirements.
        -- It still needs external_idents to find the unit, and likely statistical_variables if that's its purpose.
        -- For now, no specific structural checks beyond the global mandatory ones.
        RAISE DEBUG '[Validate Def ID %] Mode is generic_unit, skipping LU/ES specific step checks.', p_definition_id;
    ELSE
        -- This case should ideally not be reached if the mode enum is exhaustive and NOT NULL
        v_is_valid := false;
        v_error_messages := array_append(v_error_messages, format('Unknown or unhandled import mode: %L.', v_definition.mode));
    END IF;

    -- 3. Check for mandatory steps
    IF NOT ('external_idents' = ANY(v_step_codes)) THEN
        v_is_valid := false;
        v_error_messages := array_append(v_error_messages, 'The "external_idents" step is mandatory.');
    END IF;
    IF NOT ('edit_info' = ANY(v_step_codes)) THEN
        v_is_valid := false;
        v_error_messages := array_append(v_error_messages, 'The "edit_info" step is mandatory.');
    END IF;
    IF NOT ('metadata' = ANY(v_step_codes)) THEN
        v_is_valid := false;
        v_error_messages := array_append(v_error_messages, 'The "metadata" step is mandatory.');
    END IF;

    -- 4. Source Column and Mapping Consistency

    -- Specific check for 'external_idents' step:
    -- If 'external_idents' step is included, at least one of its 'source_input' data columns must be mapped.
    IF 'external_idents' = ANY(v_step_codes) THEN
        DECLARE
            v_has_mapped_external_ident BOOLEAN;
        BEGIN
            SELECT EXISTS (
                SELECT 1 FROM public.import_mapping im
                JOIN public.import_data_column idc ON im.target_data_column_id = idc.id
                JOIN public.import_step s ON idc.step_id = s.id
                WHERE im.definition_id = p_definition_id
                  AND s.code = 'external_idents'
                  AND idc.purpose = 'source_input'
                  AND im.is_ignored = FALSE
            ) INTO v_has_mapped_external_ident;

            IF NOT v_has_mapped_external_ident THEN
                v_is_valid := false;
                v_error_messages := array_append(v_error_messages, 'At least one external identifier column (e.g., tax_ident, stat_ident) must be mapped for the "external_idents" step.');
            END IF;
        END;
    END IF;

    -- Specific check for 'status' step removed, as status_code mapping is now optional.
    -- The analyse_status procedure will handle defaults, and analyse_legal_unit/_establishment
    -- will error if status_id is ultimately not resolved.

    -- Conditional check for 'data_source_code' mapping:
    -- If import_definition.data_source_id is NULL, a mapping for 'data_source_code' is required.
    IF v_definition.data_source_id IS NULL THEN
        DECLARE
            v_data_source_code_mapped BOOLEAN;
            v_data_source_code_data_column_exists BOOLEAN;
        BEGIN
            -- Check if a data_source_code data column even exists for any of the definition's steps
            SELECT EXISTS (
                SELECT 1
                FROM public.import_definition_step ids
                JOIN public.import_data_column idc ON ids.step_id = idc.step_id
                WHERE ids.definition_id = p_definition_id
                  AND idc.column_name = 'data_source_code'
                  AND idc.purpose = 'source_input'
            ) INTO v_data_source_code_data_column_exists;

            IF v_data_source_code_data_column_exists THEN
                -- If the data column exists, check if it's mapped
                SELECT EXISTS (
                    SELECT 1 FROM public.import_mapping im
                    JOIN public.import_data_column idc ON im.target_data_column_id = idc.id
                    WHERE im.definition_id = p_definition_id
                      AND idc.column_name = 'data_source_code'
                      AND idc.purpose = 'source_input'
                      AND im.is_ignored = FALSE
                ) INTO v_data_source_code_mapped;

                IF NOT v_data_source_code_mapped THEN
                    v_is_valid := false;
                    v_error_messages := array_append(v_error_messages, 'If import_definition.data_source_id is NULL and a "data_source_code" source_input data column is available for the definition''s steps, it must be mapped.');
                END IF;
            ELSE
                -- If data_source_id is NULL and no data_source_code data column is available from steps, it's an error.
                v_is_valid := false;
                v_error_messages := array_append(v_error_messages, 'If import_definition.data_source_id is NULL, a "data_source_code" source_input data column must be available via one of the definition''s steps and mapped. None found.');
            END IF;
        END;
    END IF;

    -- The old generic loop checking all source_input columns for mapping is removed.
    -- Only specific, critical mappings are checked above.

    FOR v_source_col_rec IN
        SELECT isc.column_name
        FROM public.import_source_column isc
        WHERE isc.definition_id = p_definition_id
          AND NOT EXISTS (
            SELECT 1 FROM public.import_mapping im
            WHERE im.definition_id = p_definition_id AND im.source_column_id = isc.id
          )
    LOOP
        v_is_valid := false;
        v_error_messages := array_append(v_error_messages, format('Unused import_source_column: "%s". It is defined but not used in any mapping.', v_source_col_rec.column_name));
    END LOOP;

    FOR v_mapping_rec IN
        SELECT im.id as mapping_id, idc.column_name as target_col_name, s.code as target_step_code
        FROM public.import_mapping im
        JOIN public.import_data_column idc ON im.target_data_column_id = idc.id -- This JOIN implies target_data_column_id IS NOT NULL
        JOIN public.import_step s ON idc.step_id = s.id
        WHERE im.definition_id = p_definition_id
          AND im.is_ignored = FALSE -- Only validate non-ignored mappings for this check
          AND NOT EXISTS (
            SELECT 1 FROM public.import_definition_step ids
            WHERE ids.definition_id = p_definition_id AND ids.step_id = s.id
          )
    LOOP
        v_is_valid := false;
        v_error_messages := array_append(v_error_messages, format('Mapping ID %s targets data column "%s" in step "%s", but this step is not part of the definition.', v_mapping_rec.mapping_id, v_mapping_rec.target_col_name, v_mapping_rec.target_step_code));
    END LOOP;

    -- Final Update
    IF v_is_valid THEN
        UPDATE public.import_definition
        SET valid = true, validation_error = NULL
        WHERE id = p_definition_id;
    ELSE
        -- Concatenate unique error messages
        SELECT string_agg(DISTINCT error_msg, '; ') INTO v_temp_text FROM unnest(v_error_messages) AS error_msg;
        UPDATE public.import_definition
        SET valid = false, validation_error = v_temp_text
        WHERE id = p_definition_id;
    END IF;

END;
$validate_import_definition$;

-- Trigger function for import_definition validation
CREATE OR REPLACE FUNCTION admin.trigger_validate_import_definition()
RETURNS TRIGGER LANGUAGE plpgsql AS $trigger_validate_import_definition$
DECLARE
    v_definition_id INT;
    v_step_id INT;
BEGIN
    IF TG_OP = 'DELETE' THEN
        IF TG_TABLE_NAME = 'import_definition' THEN
            RETURN OLD; -- No need to validate a definition that is being deleted
        ELSIF TG_TABLE_NAME IN ('import_definition_step', 'import_source_column', 'import_mapping') THEN
            v_definition_id := OLD.definition_id;
        ELSIF TG_TABLE_NAME = 'import_data_column' THEN
            v_step_id := OLD.step_id;
        ELSIF TG_TABLE_NAME = 'import_step' THEN
            v_step_id := OLD.id;
        END IF;
    ELSE -- INSERT or UPDATE
        IF TG_TABLE_NAME = 'import_definition' THEN
            IF TG_OP = 'UPDATE' THEN
                -- If any core configuration field changed, validation is needed.
                -- Otherwise, skip to prevent recursion if only valid/validation_error or non-core fields changed.
                IF NEW.slug IS DISTINCT FROM OLD.slug OR
                   NEW.data_source_id IS DISTINCT FROM OLD.data_source_id OR
                   NEW.strategy IS DISTINCT FROM OLD.strategy OR
                   NEW.mode IS DISTINCT FROM OLD.mode OR
                   NEW.valid_time_from IS DISTINCT FROM OLD.valid_time_from OR
                   NEW.default_retention_period IS DISTINCT FROM OLD.default_retention_period
                THEN
                    RAISE DEBUG '[% Trigger on %] Core field changed for import_definition ID %, proceeding with validation.', TG_OP, TG_TABLE_NAME, NEW.id;
                    v_definition_id := NEW.id;
                ELSE
                    RAISE DEBUG '[% Trigger on %] Skipping validation for import_definition ID % as no core configuration fields changed in this UPDATE.', TG_OP, TG_TABLE_NAME, NEW.id;
                    RETURN NEW; -- Skip validation
                END IF;
            ELSE -- TG_OP = 'INSERT'
                v_definition_id := NEW.id; -- Always validate on INSERT
            END IF;
        ELSIF TG_TABLE_NAME IN ('import_definition_step', 'import_source_column', 'import_mapping') THEN
            v_definition_id := NEW.definition_id;
        ELSIF TG_TABLE_NAME = 'import_data_column' THEN
            v_step_id := NEW.step_id;
        ELSIF TG_TABLE_NAME = 'import_step' THEN
            v_step_id := NEW.id;
        END IF;
    END IF;

    IF v_definition_id IS NOT NULL THEN
        PERFORM admin.validate_import_definition(v_definition_id);
    ELSIF v_step_id IS NOT NULL THEN
        -- Re-validate all definitions using this step
        FOR v_definition_id IN
            SELECT DISTINCT definition_id
            FROM public.import_definition_step
            WHERE step_id = v_step_id
        LOOP
            PERFORM admin.validate_import_definition(v_definition_id);
        END LOOP;
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$trigger_validate_import_definition$;

-- Triggers for import_definition validation
CREATE TRIGGER trg_validate_import_definition_after_change
    AFTER INSERT OR UPDATE OF slug, data_source_id, strategy, mode, valid_time_from, default_retention_period OR DELETE ON public.import_definition
    FOR EACH ROW EXECUTE FUNCTION admin.trigger_validate_import_definition();

CREATE TRIGGER trg_validate_import_definition_step_after_change
    AFTER INSERT OR UPDATE OR DELETE ON public.import_definition_step
    FOR EACH ROW EXECUTE FUNCTION admin.trigger_validate_import_definition();

CREATE TRIGGER trg_validate_import_source_column_after_change
    AFTER INSERT OR UPDATE OR DELETE ON public.import_source_column
    FOR EACH ROW EXECUTE FUNCTION admin.trigger_validate_import_definition();

CREATE TRIGGER trg_validate_import_mapping_after_change
    AFTER INSERT OR UPDATE OR DELETE ON public.import_mapping
    FOR EACH ROW EXECUTE FUNCTION admin.trigger_validate_import_definition();

CREATE TRIGGER trg_validate_import_data_column_after_change
    AFTER INSERT OR UPDATE OR DELETE ON public.import_data_column
    FOR EACH ROW EXECUTE FUNCTION admin.trigger_validate_import_definition();

CREATE TRIGGER trg_validate_import_step_after_change
    AFTER INSERT OR UPDATE OR DELETE ON public.import_step -- Consider UPDATE OF analyse_procedure, process_procedure if more granular control is needed
    FOR EACH ROW EXECUTE FUNCTION admin.trigger_validate_import_definition();


CREATE TYPE public.import_job_state AS ENUM (
    'waiting_for_upload',  -- Initial state: User must upload data into table, then change state to upload_completed
    'upload_completed',    -- Triggers worker notification to begin processing (and sets total_rows)
    'preparing_data',      -- Moving from custom names in upload table to standard names in data table
    'analysing_data',      -- Worker is analyzing the uploaded data
    'waiting_for_review',  -- Analysis complete, waiting for user to approve or reject
    'approved',            -- User approved changes, triggers worker to continue processing
    'rejected',            -- User rejected changes, no further processing
    'processing_data',      -- Worker is importing data into target table
    'finished'             -- Import process completed.
);

-- Create enum type for row-level import state tracking
CREATE TYPE public.import_data_state AS ENUM (
    'pending',     -- Initial state.
    'analysing',   -- Row is currently being analysed
    'analysed',    -- Row has been analysed
    'processing',   -- Row is currently being imported
    'processed',    -- Row has been successfully imported
    'error'        -- Error occurred
);

CREATE TABLE public.import_job(
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    slug text UNIQUE NOT NULL,
    description text,
    note text,
    created_at timestamp with time zone NOT NULL DEFAULT NOW(),
    updated_at timestamp with time zone NOT NULL DEFAULT NOW(),
    time_context_ident TEXT, -- FK not possible as time_context is a view. Validated in a trigger.
    default_valid_from DATE,
    default_valid_to DATE,
    default_data_source_code text,
    upload_table_name text NOT NULL, -- Name of the table holding raw uploaded data
    data_table_name text NOT NULL,   -- Name of the table holding processed/intermediate data
    priority integer,                -- Priority for worker queue processing
    definition_snapshot JSONB,       -- Snapshot of definition metadata at job creation time
    preparing_data_at timestamp with time zone,
    analysis_start_at timestamp with time zone, -- Timestamp analysis phase started
    analysis_stop_at timestamp with time zone,  -- Timestamp analysis phase finished
    changes_approved_at timestamp with time zone,
    changes_rejected_at timestamp with time zone,
    processing_start_at timestamp with time zone,
    processing_stop_at timestamp with time zone,
    total_rows integer,
    imported_rows integer DEFAULT 0,
    import_completed_pct numeric(5,2) DEFAULT 0,
    import_rows_per_sec numeric(10,2),
    last_progress_update timestamp with time zone,
    state public.import_job_state NOT NULL DEFAULT 'waiting_for_upload',
    error TEXT,
    review boolean NOT NULL DEFAULT false,
    edit_comment TEXT, -- Job-level default edit comment
    expires_at TIMESTAMPTZ NOT NULL, -- Timestamp when the job and its associated data are eligible for cleanup
    definition_id integer NOT NULL REFERENCES public.import_definition(id) ON DELETE CASCADE,
    user_id integer REFERENCES auth.user(id) ON DELETE SET NULL,
    CONSTRAINT import_job_default_valid_from_to_consistency_check CHECK (
        (default_valid_from IS NULL AND default_valid_to IS NULL) OR
        (default_valid_from IS NOT NULL AND default_valid_to IS NOT NULL AND default_valid_from <= default_valid_to)
    ),
    CONSTRAINT snapshot_has_import_definition CHECK (definition_snapshot ? 'import_definition'),
    CONSTRAINT snapshot_has_import_step_list CHECK (definition_snapshot ? 'import_step_list'),
    CONSTRAINT snapshot_has_import_data_column_list CHECK (definition_snapshot ? 'import_data_column_list'),
    CONSTRAINT snapshot_has_import_source_column_list CHECK (definition_snapshot ? 'import_source_column_list'),
    CONSTRAINT snapshot_has_import_mapping_list CHECK (definition_snapshot ? 'import_mapping_list'),
    CONSTRAINT snapshot_has_time_context_conditionally CHECK (
        -- This check ensures that if the definition requires a time context, the snapshot contains one.
        -- The expression evaluates to NULL (passing the check) if `definition_snapshot` or its `import_definition` key is null.
        -- The presence of `import_definition` key is enforced by the `snapshot_has_import_definition` constraint.
        (
            -- Case 1: The definition requires a time context, so the snapshot must have the time_context key.
            (definition_snapshot->'import_definition'->>'valid_time_from' = 'time_context' AND definition_snapshot ? 'time_context')
        ) OR
        (
            -- Case 2: The definition does not require a time context.
            (definition_snapshot->'import_definition'->>'valid_time_from' != 'time_context')
        )
    ),
    -- This constraint validates that the job's parameters are consistent with the `valid_time_from` mode specified in its definition snapshot.
    CONSTRAINT job_parameters_must_match_valid_time_from_mode CHECK (
        CASE definition_snapshot->'import_definition'->>'valid_time_from'
            WHEN 'job_provided' THEN
                (default_valid_from IS NOT NULL AND default_valid_to IS NOT NULL) -- This state must be reached either directly or via derivation from time_context.
            WHEN 'source_columns' THEN
                (time_context_ident IS NULL AND default_valid_from IS NULL AND default_valid_to IS NULL)
            ELSE
                -- This path is taken if the `valid_time_from` key is missing or has an unknown value.
                -- `snapshot_has_import_definition` and the NOT NULL ENUM on the source table make this unlikely.
                -- Returning true allows rows where snapshot is not yet populated to pass.
                true
        END
    )
);
COMMENT ON COLUMN public.import_job.edit_comment IS 'Default edit comment to be applied to records processed by this job.';
COMMENT ON COLUMN public.import_job.definition_snapshot IS 'Captures the complete state of an `import_definition` and its related entities at job creation. This ensures immutable processing. The structure is a JSONB object with keys corresponding to the source tables/views:
- `import_definition`: A JSON representation of the `public.import_definition` row.
- `time_context` (optional): If `valid_time_from = ''time_context''`, a JSON representation of the `public.time_context` row.
- `import_step_list`: An array of `public.import_step` JSON objects for the definition.
- `import_data_column_list`: An array of `public.import_data_column` JSON objects for the definition''s steps.
- `import_source_column_list`: An array of `public.import_source_column` JSON objects for the definition.
- `import_mapping_list`: An array of enriched mapping objects, each containing the mapping, source column, and target data column records.';
COMMENT ON COLUMN public.import_job.expires_at IS 'Timestamp when the job and its associated data (_upload, _data tables) are eligible for cleanup. Calculated as created_at + import_definition.default_retention_period.';
CREATE INDEX ix_import_job_definition_id ON public.import_job USING btree (definition_id);
CREATE INDEX ix_import_job_user_id ON public.import_job USING btree (user_id);
CREATE INDEX ix_import_job_expires_at ON public.import_job USING btree (expires_at);

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
    v_snapshot JSONB;
BEGIN
    SELECT * INTO definition
    FROM public.import_definition
    WHERE id = NEW.definition_id;

    -- Check if definition exists and is marked as valid
    IF NOT FOUND OR NOT definition.valid THEN
        RAISE EXCEPTION 'Cannot create import job: Import definition % (%) is not valid. Error: %',
            NEW.definition_id, COALESCE(definition.name, 'N/A'), COALESCE(definition.validation_error, 'Definition not found or not marked valid');
    END IF;

    -- Validate time_context_ident if provided on the job
    IF NEW.time_context_ident IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.time_context WHERE ident = NEW.time_context_ident) THEN
        RAISE EXCEPTION 'Cannot create import job: Invalid time_context_ident % provided for the job does not exist in public.time_context.', NEW.time_context_ident;
    END IF;

    IF NEW.slug IS NULL THEN
        NEW.slug := format('import_job_%s', NEW.id);
    END IF;

    NEW.upload_table_name := format('%I', NEW.slug || '_upload');
    NEW.data_table_name := format('%I', NEW.slug || '_data');

    -- Populate the definition_snapshot JSONB with explicit keys matching table names
    SELECT jsonb_build_object(
        'import_definition', (SELECT row_to_json(d) FROM public.import_definition d WHERE d.id = NEW.definition_id),
        'import_step_list', (SELECT jsonb_agg(row_to_json(s) ORDER BY s.priority) FROM public.import_step s JOIN public.import_definition_step ds_link ON s.id = ds_link.step_id WHERE ds_link.definition_id = NEW.definition_id),
        'import_data_column_list', (
            SELECT jsonb_agg(row_to_json(dc) ORDER BY s_link.priority, dc.priority, dc.column_name)
            FROM public.import_data_column dc
            JOIN public.import_step s_link ON dc.step_id = s_link.id
            JOIN public.import_definition_step ds_link ON s_link.id = ds_link.step_id
            WHERE ds_link.definition_id = NEW.definition_id
        ),
        'import_source_column_list', (SELECT jsonb_agg(row_to_json(sc_list) ORDER BY sc_list.priority) FROM public.import_source_column sc_list WHERE sc_list.definition_id = NEW.definition_id),
        'import_mapping_list', (
            SELECT jsonb_agg(
                jsonb_build_object(
                    'mapping', row_to_json(m_map),
                    'source_column', row_to_json(sc_map),
                    'target_data_column', row_to_json(dc_map)
                ) ORDER BY s_link.priority, dc_map.priority, dc_map.column_name, m_map.id
            )
            FROM public.import_mapping m_map
            LEFT JOIN public.import_source_column sc_map ON m_map.source_column_id = sc_map.id AND sc_map.definition_id = m_map.definition_id -- Ensure source_column is for the same definition
            JOIN public.import_data_column dc_map ON m_map.target_data_column_id = dc_map.id
            JOIN public.import_step s_link ON dc_map.step_id = s_link.id
            JOIN public.import_definition_step ds_map_link ON s_link.id = ds_map_link.step_id AND ds_map_link.definition_id = m_map.definition_id -- Ensure data_column's step is linked to this definition
            WHERE m_map.definition_id = NEW.definition_id
        )
    ) INTO v_snapshot;

    IF v_snapshot IS NULL OR NOT (
        v_snapshot ? 'import_definition' AND
        v_snapshot ? 'import_step_list' AND
        v_snapshot ? 'import_data_column_list' AND
        v_snapshot ? 'import_source_column_list' AND
        v_snapshot ? 'import_mapping_list'
    ) THEN
         RAISE EXCEPTION 'Failed to generate a complete definition snapshot for definition_id %. It is missing one or more required keys: import_definition, import_step_list, import_data_column_list, import_source_column_list, import_mapping_list.', NEW.definition_id;
    END IF;

    -- Validate and set default validity dates based on the definition's declarative valid_time_from
    IF definition.valid_time_from = 'job_provided' THEN
        -- Case A: The definition requires job-level dates. The user must provide EITHER a time_context_ident OR explicit dates, but not both.
        IF NEW.time_context_ident IS NOT NULL AND (NEW.default_valid_from IS NOT NULL OR NEW.default_valid_to IS NOT NULL) THEN
            RAISE EXCEPTION 'Cannot specify both a time_context_ident and explicit default_valid_from/to dates for a job with definition %.', definition.name;
        END IF;
        IF NEW.time_context_ident IS NULL AND (NEW.default_valid_from IS NULL OR NEW.default_valid_to IS NULL) THEN
            RAISE EXCEPTION 'Must specify either a time_context_ident or explicit default_valid_from/to dates for a job with definition %.', definition.name;
        END IF;

        -- If time_context_ident is provided, derive the default dates.
        IF NEW.time_context_ident IS NOT NULL THEN
            -- Stage 1 of 2 for time_context handling:
            -- Derive from the job's time_context_ident and populate the job's own default_valid_from/to columns.
            -- Stage 2 happens in `import_job_prepare`, where these job-level defaults are used to populate the
            -- `_data` table's `valid_from`/`to` columns for every row via the `source_expression='default'` mapping.
            SELECT tc.valid_from, tc.valid_to
            INTO NEW.default_valid_from, NEW.default_valid_to
            FROM public.time_context tc
            WHERE tc.ident = NEW.time_context_ident;

            -- Also, add the time_context record itself to the snapshot for immutable processing
            SELECT v_snapshot || jsonb_build_object('time_context', row_to_json(tc))
            INTO v_snapshot
            FROM public.time_context tc WHERE tc.ident = NEW.time_context_ident;
        END IF;
        -- If explicit dates were provided, they are already on NEW and will be used.

    ELSIF definition.valid_time_from = 'source_columns' THEN
        -- Case C: The definition uses dates from the source file. The job MUST NOT provide a time_context_ident or explicit dates.
        IF NEW.time_context_ident IS NOT NULL THEN
            RAISE EXCEPTION 'Cannot specify a time_context_ident for an import job when its definition (%) has valid_time_from="source_columns".', definition.name;
        END IF;
        IF NEW.default_valid_from IS NOT NULL OR NEW.default_valid_to IS NOT NULL THEN
            RAISE EXCEPTION 'Cannot specify default_valid_from/to for an import job when its definition (%) has valid_time_from="source_columns".', definition.name;
        END IF;
    END IF;

    IF NEW.default_data_source_code IS NULL AND definition.data_source_id IS NOT NULL THEN
        SELECT ds.code
        INTO NEW.default_data_source_code
        FROM public.data_source ds
        WHERE ds.id = definition.data_source_id;
    END IF;

    -- Set the user_id from the current authenticated user
    IF NEW.user_id IS NULL THEN
        NEW.user_id := auth.uid();
    END IF;

    -- Set expires_at based on created_at and definition's retention period
    -- NEW.created_at is populated by its DEFAULT NOW() before this trigger runs for an INSERT.
    NEW.expires_at := NEW.created_at + COALESCE(definition.default_retention_period, '18 months'::INTERVAL);

    NEW.definition_snapshot := v_snapshot;
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
    RAISE DEBUG '[Job %] Cleaning up tables: %, %', OLD.id, OLD.upload_table_name, OLD.data_table_name;
    -- Snapshot table is removed automatically when the job row is deleted or updated

    -- Drop the upload and data tables
    EXECUTE format('DROP TABLE IF EXISTS public.%I CASCADE', OLD.upload_table_name);
    EXECUTE format('DROP TABLE IF EXISTS public.%I CASCADE', OLD.data_table_name);

    -- Ensure the new tables are removed from PostgREST
    NOTIFY pgrst, 'reload schema';
    RAISE DEBUG '[Job %] Cleanup complete, notified PostgREST', OLD.id;

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
    IF NEW.state = 'preparing_data' AND NEW.preparing_data_at IS NULL THEN
        NEW.preparing_data_at := v_timestamp;
    END IF;

    IF NEW.state = 'analysing_data' AND NEW.analysis_start_at IS NULL THEN
        NEW.analysis_start_at := v_timestamp;
    END IF;

    -- Set stop timestamps when transitioning *out* of a processing state
    IF OLD.state = 'analysing_data' AND NEW.state != OLD.state AND NEW.analysis_stop_at IS NULL THEN
        NEW.analysis_stop_at := v_timestamp;
    END IF;

    IF OLD.state = 'processing_data' AND NEW.state != OLD.state AND NEW.processing_stop_at IS NULL THEN
        NEW.processing_stop_at := v_timestamp;
    END IF;

    -- Record timestamps for approval/rejection states
    IF NEW.state = 'approved' AND NEW.changes_approved_at IS NULL THEN
        NEW.changes_approved_at := v_timestamp;
    END IF;

    IF NEW.state = 'rejected' AND NEW.changes_rejected_at IS NULL THEN
        NEW.changes_rejected_at := v_timestamp;
    END IF;

    -- Record start timestamp for processing_data state
    IF NEW.state = 'processing_data' AND NEW.processing_start_at IS NULL THEN
        NEW.processing_start_at := v_timestamp;
    END IF;

    -- Derive total_rows when state changes from waiting_for_upload to upload_completed
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
    IF NEW.imported_rows = 0 OR NEW.processing_start_at IS NULL THEN
        NEW.import_rows_per_sec := 0;
    ELSIF NEW.state = 'finished' AND NEW.processing_stop_at IS NOT NULL THEN
        NEW.import_rows_per_sec := CASE
            WHEN EXTRACT(EPOCH FROM (NEW.processing_stop_at - NEW.processing_start_at)) <= 0 THEN 0
            ELSE ROUND((NEW.imported_rows::numeric / EXTRACT(EPOCH FROM (NEW.processing_stop_at - NEW.processing_start_at))), 2)
        END;
    ELSE
        NEW.import_rows_per_sec := CASE
            WHEN EXTRACT(EPOCH FROM (COALESCE(NEW.last_progress_update, clock_timestamp()) - NEW.processing_start_at)) <= 0 THEN 0
            ELSE ROUND((NEW.imported_rows::numeric / EXTRACT(EPOCH FROM (COALESCE(NEW.last_progress_update, clock_timestamp()) - NEW.processing_start_at))), 2)
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

    -- Get row state counts including analysis states
    EXECUTE format(
        'SELECT json_build_object(
            ''pending'', COUNT(*) FILTER (WHERE state = ''pending''),
            ''analysing'', COUNT(*) FILTER (WHERE state = ''analysing''),
            ''analysed'', COUNT(*) FILTER (WHERE state = ''analysed''),
            ''processing'', COUNT(*) FILTER (WHERE state = ''processing''),
            ''processed'', COUNT(*) FILTER (WHERE state = ''processed''),
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

SELECT admin.add_rls_regular_user_can_read('public.import_step'::regclass);
SELECT admin.add_rls_regular_user_can_read('public.import_data_column'::regclass);
SELECT admin.add_rls_regular_user_can_read('public.import_definition'::regclass);
SELECT admin.add_rls_regular_user_can_read('public.import_source_column'::regclass);
SELECT admin.add_rls_regular_user_can_read('public.import_mapping'::regclass);
SELECT admin.add_rls_regular_user_can_read('public.import_definition_step'::regclass); -- Allow read for regular users

-- Apply custom RLS policies for import_job
ALTER TABLE public.import_job ENABLE ROW LEVEL SECURITY;

-- Grant base permissions
GRANT SELECT, INSERT, UPDATE, DELETE ON public.import_job TO regular_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.import_job TO admin_user;
GRANT SELECT ON public.import_job TO authenticated; -- Grant SELECT for authenticated users

-- Policies for import_job
-- Admin user has full access
CREATE POLICY import_job_admin_user_manage ON public.import_job
    FOR ALL
    TO admin_user
    USING (true)
    WITH CHECK (true);

-- Any authenticated user can select any import job
CREATE POLICY import_job_authenticated_select_all ON public.import_job
    FOR SELECT
    TO authenticated
    USING (true); -- Allows selection of all rows

-- Regular users can insert jobs only for themselves
CREATE POLICY import_job_regular_user_insert_own ON public.import_job
    FOR INSERT
    TO regular_user
    WITH CHECK (user_id = auth.uid());

-- Regular users can update their own jobs
CREATE POLICY import_job_regular_user_update_own ON public.import_job
    FOR UPDATE
    TO regular_user
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid()); -- Ensure they can't change the owner

-- Regular users can delete their own jobs
CREATE POLICY import_job_regular_user_delete_own ON public.import_job
    FOR DELETE
    TO regular_user
    USING (user_id = auth.uid());

/*
Each import job operates on its own set of tables:
- _upload: Holds raw data from the uploaded file.
- _data: Holds processed/intermediate data, structured according to import_data_column.
- _snapshot: Holds a snapshot of the relevant import definition metadata at job creation time.
*/
CREATE FUNCTION admin.import_job_generate(job public.import_job)
RETURNS void SECURITY DEFINER LANGUAGE plpgsql AS $import_job_generate$
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

  -- 2. Create Data Table
  RAISE DEBUG '[Job %] Generating data table %', job.id, job.data_table_name;
  -- Add row_id as the first column and primary key
  create_data_table_stmt := format('CREATE TABLE public.%I (row_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, ', job.data_table_name);
  add_separator := FALSE; -- Reset for data table columns

  -- Add columns based on import_data_column records associated with the steps linked to this job's definition
  FOR col_rec IN
      SELECT dc.column_name, dc.column_type, dc.is_nullable, dc.default_value
      FROM public.import_definition_step ds
      JOIN public.import_step s ON ds.step_id = s.id
      JOIN public.import_data_column dc ON dc.step_id = s.id -- Join data columns via step_id
      WHERE ds.definition_id = job.definition_id
      ORDER BY s.priority, dc.priority, dc.column_name
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

  -- Create index on state and priority for efficient processing
  EXECUTE format($$CREATE INDEX ON public.%I (state, last_completed_priority)$$, job.data_table_name);
  RAISE DEBUG '[Job %] Added index to data table %', job.id, job.data_table_name;

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
  IF v_job.state IN ('upload_completed', 'preparing_data', 'analysing_data', 'approved', 'processing_data') THEN
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
            RETURN job.state; -- Transition done by batch job as it completes.

        WHEN 'analysing_data' THEN
            RETURN job.state; -- Transition done by batch job as it completes.

        WHEN 'waiting_for_review' THEN
          RETURN job.state; -- No automatic transition, requires user action

        WHEN 'approved' THEN
            RETURN 'processing_data';

        WHEN 'rejected' THEN
            RETURN 'finished';

        WHEN 'processing_data' THEN
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

-- Helper function to safely cast text to ltree
CREATE OR REPLACE FUNCTION import.safe_cast_to_ltree(
    IN p_text_ltree TEXT,
    OUT p_value public.LTREE,
    OUT p_error_message TEXT
) LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
    p_value := NULL;
    p_error_message := NULL;

    IF p_text_ltree IS NULL OR p_text_ltree = '' THEN
        RETURN; -- p_value and p_error_message remain NULL, indicating successful cast of empty/null to NULL
    END IF;

    BEGIN
        p_value := p_text_ltree::public.LTREE;
    EXCEPTION
        WHEN invalid_text_representation THEN
            p_error_message := 'Invalid ltree format (invalid_text_representation): ''' || p_text_ltree || '''. SQLSTATE: ' || SQLSTATE;
            RAISE DEBUG '%', p_error_message;
        WHEN OTHERS THEN
            p_error_message := 'Failed to cast ''' || p_text_ltree || ''' to ltree. SQLSTATE: ' || SQLSTATE || ', SQLERRM: ' || SQLERRM;
            RAISE DEBUG '%', p_error_message;
    END;
END;
$$;


CREATE PROCEDURE admin.import_job_process(job_id integer)
LANGUAGE plpgsql AS $import_job_process$
DECLARE
    job public.import_job;
    next_state public.import_job_state;
    should_reschedule BOOLEAN := FALSE;
    v_processed_count INTEGER; -- Moved declaration here
BEGIN
    -- Get the job details
    SELECT * INTO job FROM public.import_job WHERE id = job_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Import job % not found', job_id;
    END IF;

    -- Set the user context to the job creator
    PERFORM admin.set_import_job_user_context(job_id);

    RAISE DEBUG '[Job %] Processing job in state: %', job_id, job.state;

    -- Process based on current state
    CASE job.state
        WHEN 'waiting_for_upload' THEN
            RAISE DEBUG '[Job %] Waiting for upload.', job_id;
            should_reschedule := FALSE;

        WHEN 'upload_completed' THEN
            RAISE DEBUG '[Job %] Transitioning to preparing_data.', job_id;
            job := admin.import_job_set_state(job, 'preparing_data');
            should_reschedule := TRUE; -- Reschedule immediately to start prepare

        WHEN 'preparing_data' THEN
            RAISE DEBUG '[Job %] Calling import_job_prepare.', job_id;
            PERFORM admin.import_job_prepare(job);
            -- Transition rows in _data table from 'pending' to 'analysing'
            RAISE DEBUG '[Job %] Updating data rows from pending to analysing in table %', job_id, job.data_table_name;
            EXECUTE format($$UPDATE public.%I SET state = %L WHERE state = %L$$, job.data_table_name, 'analysing'::public.import_data_state, 'pending'::public.import_data_state);
            job := admin.import_job_set_state(job, 'analysing_data');
            should_reschedule := TRUE; -- Reschedule immediately to start analysis

        WHEN 'analysing_data' THEN
            RAISE DEBUG '[Job %] Starting analysis phase.', job_id;
            should_reschedule := admin.import_job_process_phase(job, 'analyse'::public.import_step_phase);
            
            -- Refresh job record to see if an error was set by the phase
            SELECT * INTO job FROM public.import_job WHERE id = job_id;

            IF job.error IS NOT NULL THEN
                RAISE WARNING '[Job %] Error detected during analysis phase: %. Transitioning to finished.', job_id, job.error;
                job := admin.import_job_set_state(job, 'finished');
                should_reschedule := FALSE;
            ELSIF NOT should_reschedule THEN -- No error, and phase reported no more work
                IF job.review THEN
                    -- Transition rows from 'analysing' to 'analysed' if review is required
                    -- Rows in 'analysing' state here have completed all analysis steps.
                    -- The 'error' field might be populated with non-fatal errors (e.g., for legal_unit activity codes).
                    RAISE DEBUG '[Job %] Updating data rows from analysing to analysed in table % for review', job_id, job.data_table_name;
                    EXECUTE format($$UPDATE public.%I SET state = %L WHERE state = %L$$, job.data_table_name, 'analysed'::public.import_data_state, 'analysing'::public.import_data_state);
                    job := admin.import_job_set_state(job, 'waiting_for_review');
                    RAISE DEBUG '[Job %] Analysis complete, waiting for review.', job_id;
                    -- should_reschedule remains FALSE as it's waiting for user action
                ELSE
                    -- Transition rows from 'analysing' to 'processing' if no review
                    -- Rows in 'analysing' state here have completed all analysis steps.
                    RAISE DEBUG '[Job %] Updating data rows from analysing to processing and resetting LCP in table %', job_id, job.data_table_name;
                    EXECUTE format($$UPDATE public.%I SET state = %L, last_completed_priority = 0 WHERE state = %L$$, job.data_table_name, 'processing'::public.import_data_state, 'analysing'::public.import_data_state);
                    job := admin.import_job_set_state(job, 'processing_data');
                    RAISE DEBUG '[Job %] Analysis complete, proceeding to processing.', job_id;
                    should_reschedule := TRUE; -- Reschedule to start processing
                END IF;
            END IF;
            -- If should_reschedule is TRUE from the phase function (and no error), it will be rescheduled.

        WHEN 'waiting_for_review' THEN
            RAISE DEBUG '[Job %] Waiting for user review.', job_id;
            should_reschedule := FALSE;

        WHEN 'approved' THEN
            RAISE DEBUG '[Job %] Approved, transitioning to processing_data.', job_id;
            -- Transition rows in _data table from 'analysed' to 'processing' and reset LCP
            RAISE DEBUG '[Job %] Updating data rows from analysed to processing and resetting LCP in table % after approval', job_id, job.data_table_name;
            EXECUTE format($$UPDATE public.%I SET state = %L, last_completed_priority = 0 WHERE state = %L AND error IS NULL$$, job.data_table_name, 'processing'::public.import_data_state, 'analysed'::public.import_data_state);
            job := admin.import_job_set_state(job, 'processing_data');
            should_reschedule := TRUE; -- Reschedule immediately to start import

        WHEN 'rejected' THEN
            RAISE DEBUG '[Job %] Rejected, transitioning to finished.', job_id;
            job := admin.import_job_set_state(job, 'finished');
            should_reschedule := FALSE;

        WHEN 'processing_data' THEN
            RAISE DEBUG '[Job %] Starting process phase.', job_id;
            should_reschedule := admin.import_job_process_phase(job, 'process'::public.import_step_phase);

            -- Refresh job record to see if an error was set by the phase
            SELECT * INTO job FROM public.import_job WHERE id = job_id;

            IF job.error IS NOT NULL THEN
                RAISE WARNING '[Job %] Error detected during processing phase: %. Transitioning to finished.', job_id, job.error;
                job := admin.import_job_set_state(job, 'finished');
                should_reschedule := FALSE;
            ELSIF NOT should_reschedule THEN -- No error, and phase reported no more work
                -- Update data rows to 'processed'
                RAISE DEBUG '[Job %] Finalizing processed rows in table %', job_id, job.data_table_name;
                EXECUTE format($$UPDATE public.%I SET state = %L WHERE state = %L AND error IS NULL$$, job.data_table_name, 'processed'::public.import_data_state, 'processing'::public.import_data_state);

                -- Update imported_rows count on the job
                -- DECLARE v_processed_count INTEGER; -- Declaration moved to the top of the procedure
                EXECUTE format($$SELECT count(*) FROM public.%I WHERE state = %L$$, job.data_table_name, 'processed'::public.import_data_state) INTO v_processed_count;
                UPDATE public.import_job SET imported_rows = v_processed_count WHERE id = job.id;
                RAISE DEBUG '[Job %] Updated imported_rows to %', job_id, v_processed_count;

                job := admin.import_job_set_state(job, 'finished');
                RAISE DEBUG '[Job %] Processing complete, transitioning to finished.', job_id;
                -- should_reschedule remains FALSE
            END IF;
            -- If should_reschedule is TRUE from the phase function (and no error), it will be rescheduled.

        WHEN 'finished' THEN
            RAISE DEBUG '[Job %] Already finished.', job_id;
            should_reschedule := FALSE;

        ELSE
            RAISE EXCEPTION '[Job %] Unknown import job state: %', job.id, job.state;
    END CASE;

    -- Reset the user context
    PERFORM admin.reset_import_job_user_context();

    -- Reschedule if work remains for the current phase or if transitioned to a processing state
    IF should_reschedule THEN
        PERFORM admin.reschedule_import_job_process(job_id);
        RAISE DEBUG '[Job %] Rescheduled for further processing.', job_id;
    END IF;

EXCEPTION WHEN OTHERS THEN
    -- Ensure context is reset even on error
    PERFORM admin.reset_import_job_user_context();
    RAISE; -- Re-raise the original error
END;
$import_job_process$;


-- Enum defining the processing phase for import steps
CREATE TYPE public.import_step_phase AS ENUM ('analyse', 'process');
COMMENT ON TYPE public.import_step_phase IS 'Defines the processing phase for import steps: analyse (validation, lookups) or process (final database operation).';

-- Helper function to process a phase (analyse or process) in batches
CREATE FUNCTION admin.import_job_process_phase(
    job public.import_job,
    phase public.import_step_phase -- Use the new enum type
) RETURNS BOOLEAN -- Returns TRUE if more work remains for this phase
LANGUAGE plpgsql AS $import_job_process_phase$
DECLARE
    batch_size INTEGER := 1000; -- Process up to 1000 rows per target step in one transaction
    targets JSONB;
    target_rec RECORD;
    proc_to_call REGPROC;
    rows_processed_in_tx INTEGER := 0;
    work_still_exists_for_phase BOOLEAN := FALSE; -- Indicates if rows for this phase still exist after processing
    batch_row_ids BIGINT[]; -- Changed from TID[] to BIGINT[]
    error_message TEXT;
    current_phase_data_state public.import_data_state;
    v_sql TEXT; -- Added declaration for v_sql
BEGIN
    RAISE DEBUG '[Job %] Processing phase: %', job.id, phase;

    -- Determine the data state corresponding to the current phase
    IF phase = 'analyse'::public.import_step_phase THEN
        current_phase_data_state := 'analysing'::public.import_data_state;
    ELSIF phase = 'process'::public.import_step_phase THEN
        current_phase_data_state := 'processing'::public.import_data_state;
    ELSE
        RAISE EXCEPTION '[Job %] Invalid phase specified: %', job.id, phase;
    END IF;

    -- Load steps from the job's snapshot
    targets := job.definition_snapshot->'import_step_list';
    IF targets IS NULL OR jsonb_typeof(targets) != 'array' THEN
        RAISE EXCEPTION '[Job %] Failed to load valid import_step_list array from definition_snapshot', job.id;
    END IF;

    -- Loop through steps (targets) in priority order
    FOR target_rec IN SELECT * FROM jsonb_to_recordset(targets) AS x(
                            id int, code text, name text, priority int, analyse_procedure regproc, process_procedure regproc) -- Added 'code'
                      ORDER BY priority
    LOOP
        -- Determine which procedure to call for this phase
        IF phase = 'analyse'::public.import_step_phase THEN
            proc_to_call := target_rec.analyse_procedure;
        ELSE -- 'process' phase
            proc_to_call := target_rec.process_procedure;
        END IF;

        -- Skip if no procedure defined for this target/phase
        IF proc_to_call IS NULL THEN
            RAISE DEBUG '[Job %] Skipping target % (priority %) for phase % - no procedure defined.', job.id, target_rec.name, target_rec.priority, phase;
            CONTINUE;
        END IF;

        RAISE DEBUG '[Job %] Checking target % (priority %) for phase % using procedure %', job.id, target_rec.name, target_rec.priority, phase, proc_to_call;

        -- Find one batch of rows ready for this target's phase
        EXECUTE format(
            $$SELECT array_agg(row_id) FROM (
                SELECT row_id FROM public.%I
                WHERE state = %L AND last_completed_priority < %L
                ORDER BY row_id -- Ensure consistent batching using row_id
                LIMIT %L
                FOR UPDATE SKIP LOCKED -- Avoid waiting for locked rows
             ) AS batch$$,
            job.data_table_name,
            current_phase_data_state,
            target_rec.priority,
            batch_size
        ) INTO batch_row_ids;

        -- If no rows found for this target, move to the next target
        IF batch_row_ids IS NULL OR array_length(batch_row_ids, 1) = 0 THEN
            RAISE DEBUG '[Job %] No rows found for target % (priority %) in state % with priority < %.',
                        job.id, target_rec.name, target_rec.priority,
                        current_phase_data_state, target_rec.priority;
            CONTINUE; -- Move to the next target in the FOR loop
        END IF;

        RAISE DEBUG '[Job %] Found batch of % rows for target % (priority %), calling %',
                    job.id, array_length(batch_row_ids, 1), target_rec.name, target_rec.priority, proc_to_call;

        -- Call the target-specific procedure
        BEGIN
            -- Always pass the step_code as the third argument
            EXECUTE format('CALL %s($1, $2, $3)', proc_to_call) USING job.id, batch_row_ids, target_rec.code;
            rows_processed_in_tx := rows_processed_in_tx + array_length(batch_row_ids, 1);
        EXCEPTION WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
            RAISE WARNING '[Job %] Programming error suspected in procedure % for target % (code: %): %', job.id, proc_to_call, target_rec.name, target_rec.code, error_message;
            -- Log the job error before re-raising
            UPDATE public.import_job SET error = jsonb_build_object('programming_error_in_step_procedure', format('Error during %s phase, target %s (code: %s, proc: %s): %s', phase, target_rec.name, target_rec.code, proc_to_call::text, error_message))
            WHERE id = job.id;
            RAISE; -- Re-raise the original exception to halt and indicate a programming error
        END;
        -- After processing one batch for a target, continue to the next target.
        -- The function will determine if overall work remains for the phase at the end.
    END LOOP; -- End target loop

    -- After attempting to process one batch for all applicable targets,
    -- check if there are still any rows in the current phase's state that can be processed by any step in this phase.
    -- This determines if the calling procedure should reschedule.
    v_sql := 'SELECT EXISTS (SELECT 1 FROM public.%I dt JOIN jsonb_to_recordset(%L::JSONB) AS s(id int, code text, name text, priority int, analyse_procedure regproc, process_procedure regproc) ON TRUE WHERE dt.state = %L AND dt.last_completed_priority < s.priority AND CASE %L::public.import_step_phase WHEN ''analyse'' THEN s.analyse_procedure IS NOT NULL WHEN ''process'' THEN s.process_procedure IS NOT NULL ELSE FALSE END)';
    EXECUTE format(v_sql, job.data_table_name, job.definition_snapshot->'import_step_list', current_phase_data_state, phase)
    INTO work_still_exists_for_phase;

    RAISE DEBUG '[Job %] Phase % processing pass complete for this transaction. Rows processed in tx: %. Work still exists for phase (final check): %',
                job.id, phase, rows_processed_in_tx, work_still_exists_for_phase;

    RETURN work_still_exists_for_phase;
END;
$import_job_process_phase$;


-- Function to prepare import job by moving data from upload table to data table
CREATE FUNCTION admin.import_job_prepare(job public.import_job)
RETURNS void LANGUAGE plpgsql AS $import_job_prepare$
DECLARE
    upsert_stmt TEXT;
    insert_columns_list TEXT[] := ARRAY[]::TEXT[];
    select_expressions_list TEXT[] := ARRAY[]::TEXT[];
    conflict_key_columns_list TEXT[] := ARRAY[]::TEXT[];
    update_set_expressions_list TEXT[] := ARRAY[]::TEXT[];

    insert_columns TEXT;
    select_clause TEXT;
    conflict_columns_text TEXT;
    update_set_clause TEXT;

    item_rec RECORD; -- Will hold {mapping, source_column, target_data_column}
    current_mapping JSONB;
    current_source_column JSONB;
    current_target_data_column JSONB;
    
    error_message TEXT;
    snapshot JSONB := job.definition_snapshot;
BEGIN
    RAISE DEBUG '[Job %] Preparing data: Moving from % to %', job.id, job.upload_table_name, job.data_table_name;

    IF snapshot IS NULL OR snapshot->'import_mapping_list' IS NULL THEN
        RAISE EXCEPTION '[Job %] Invalid or missing import_mapping_list in definition_snapshot', job.id;
    END IF;

    -- Iterate through mappings to build INSERT columns and SELECT expressions in a consistent order
    FOR item_rec IN 
        SELECT * 
        FROM jsonb_to_recordset(COALESCE(snapshot->'import_mapping_list', '[]'::jsonb)) 
            AS item(mapping JSONB, source_column JSONB, target_data_column JSONB)
        ORDER BY (item.mapping->>'id')::integer -- Order by mapping ID for consistency
    LOOP
        current_mapping := item_rec.mapping;
        current_source_column := item_rec.source_column;
        current_target_data_column := item_rec.target_data_column;

        IF current_target_data_column IS NULL OR current_target_data_column = 'null'::jsonb THEN
            RAISE EXCEPTION '[Job %] Mapping ID % refers to non-existent target_data_column.', job.id, current_mapping->>'id';
        END IF;

        -- Only process mappings that target 'source_input' columns for the prepare step
        IF current_target_data_column->>'purpose' != 'source_input' THEN
            RAISE DEBUG '[Job %] Skipping mapping ID % because target data column % (ID: %) is not for ''source_input''. Purpose: %', 
                        job.id, current_mapping->>'id', current_target_data_column->>'column_name', current_target_data_column->>'id', current_target_data_column->>'purpose';
            CONTINUE;
        END IF;

        insert_columns_list := array_append(insert_columns_list, format('%I', current_target_data_column->>'column_name'));

        -- Generate SELECT expression based on mapping type
        IF current_mapping->>'source_value' IS NOT NULL THEN
            select_expressions_list := array_append(select_expressions_list, format('%L', current_mapping->>'source_value'));
        ELSIF current_mapping->>'source_expression' IS NOT NULL THEN
            select_expressions_list := array_append(select_expressions_list,
                CASE current_mapping->>'source_expression'
                    WHEN 'now' THEN 'statement_timestamp()'
                    WHEN 'default' THEN
                        CASE current_target_data_column->>'column_name'
                            WHEN 'valid_from' THEN format('%L', job.default_valid_from)
                            WHEN 'valid_to' THEN format('%L', job.default_valid_to)
                            WHEN 'data_source_code' THEN format('%L', job.default_data_source_code)
                            ELSE 'NULL' 
                        END
                    ELSE 'NULL'
                END
            );
        ELSIF current_mapping->>'source_column_id' IS NOT NULL THEN
            IF current_source_column IS NULL OR current_source_column = 'null'::jsonb THEN
                 RAISE EXCEPTION '[Job %] Could not find source column details for source_column_id % in mapping ID %.', job.id, current_mapping->>'source_column_id', current_mapping->>'id';
            END IF;
            select_expressions_list := array_append(select_expressions_list, format($$NULLIF(%I, '')$$, current_source_column->>'column_name'));
        ELSE
            -- This case should be prevented by the CHECK constraint on import_mapping table
            RAISE EXCEPTION '[Job %] Mapping ID % for target data column % (ID: %) has no valid source (column/value/expression). This should not happen.', job.id, current_mapping->>'id', current_target_data_column->>'column_name', current_target_data_column->>'id';
        END IF;
        
        -- If this target data column is part of the unique key, add it to conflict_key_columns_list
        IF (current_target_data_column->>'is_uniquely_identifying')::boolean THEN
            -- We collect the raw, unquoted column names to ensure consistent expression generation with import_job_generate
            conflict_key_columns_list := array_append(conflict_key_columns_list, current_target_data_column->>'column_name');
        END IF;
    END LOOP;

    IF array_length(insert_columns_list, 1) = 0 THEN
        RAISE DEBUG '[Job %] No mapped source_input columns found to insert. Skipping prepare.', job.id;
        RETURN;
    END IF;

    insert_columns := array_to_string(insert_columns_list, ', ');
    select_clause := array_to_string(select_expressions_list, ', ');

    DECLARE
        conflict_key_expressions_list TEXT[];
        col_name TEXT;
    BEGIN
        IF array_length(conflict_key_columns_list, 1) > 0 THEN
            -- Build COALESCE expressions for the ON CONFLICT clause to handle NULLs in identifiers.
            -- Using %I on raw column names to match the index creation logic exactly.
            FOREACH col_name IN ARRAY conflict_key_columns_list
            LOOP
                conflict_key_expressions_list := array_append(conflict_key_expressions_list, format('COALESCE(%I, %L)', col_name, ''));
            END LOOP;

            -- Also include validity period in conflict key expressions for temporal idempotency.
            -- They are NOT coalesced to allow multiple rows with same identifiers but NULL validity periods.
            conflict_key_expressions_list := conflict_key_expressions_list || ARRAY[format('%I', 'valid_from'), format('%I', 'valid_to')];
            conflict_columns_text := array_to_string(conflict_key_expressions_list, ', ');
            RAISE DEBUG '[Job %] ON CONFLICT expressions: %', job.id, conflict_columns_text;

            -- Also add validity columns to the list of key columns so they are not updated ON CONFLICT.
            -- The list now has raw names, so we must quote them before appending the already-quoted validity columns.
            DECLARE
                quoted_conflict_key_columns_list TEXT[] := ARRAY[]::text[];
            BEGIN
                FOREACH col_name IN ARRAY conflict_key_columns_list
                LOOP
                    quoted_conflict_key_columns_list := array_append(quoted_conflict_key_columns_list, format('%I', col_name));
                END LOOP;
                conflict_key_columns_list := quoted_conflict_key_columns_list || ARRAY[format('%I', 'valid_from'), format('%I', 'valid_to')];
            END;
        END IF;
    END;

    -- Build UPDATE SET clause: update all inserted columns that are NOT part of the conflict key
    FOR i IN 1 .. array_length(insert_columns_list, 1) LOOP
        IF NOT (insert_columns_list[i] = ANY(COALESCE(conflict_key_columns_list, ARRAY[]::TEXT[]))) THEN
            update_set_expressions_list := array_append(update_set_expressions_list, format('%s = EXCLUDED.%s', insert_columns_list[i], insert_columns_list[i]));
        END IF;
    END LOOP;
    update_set_clause := array_to_string(update_set_expressions_list, ', ');

    -- Assemble the final UPSERT statement
    -- The ON CONFLICT targets a unique index on expressions (COALESCE(col, '')) to handle NULLs correctly.
    IF conflict_columns_text IS NULL OR conflict_columns_text = '' OR update_set_clause = '' THEN
        -- If no conflict columns defined, or no columns to update, just do INSERT
        upsert_stmt := format($$INSERT INTO public.%I (%s) SELECT %s FROM public.%I$$,
                              job.data_table_name, insert_columns, select_clause, job.upload_table_name);
    ELSE
        upsert_stmt := format($$INSERT INTO public.%I (%s) SELECT %s FROM public.%I ON CONFLICT (%s) DO UPDATE SET %s$$,
                              job.data_table_name, insert_columns, select_clause, job.upload_table_name, conflict_columns_text, update_set_clause);
    END IF;

    BEGIN
        RAISE DEBUG '[Job %] Executing prepare upsert: %', job.id, upsert_stmt;
        EXECUTE upsert_stmt;

        DECLARE data_table_count INT;
        BEGIN
            EXECUTE format($$SELECT count(*) FROM public.%I$$, job.data_table_name) INTO data_table_count;
            RAISE DEBUG '[Job %] Rows in data table % after prepare: %', job.id, job.data_table_name, data_table_count;
        END;
    EXCEPTION
        WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
            RAISE WARNING '[Job %] Error preparing data: %', job.id, error_message;
            UPDATE public.import_job SET error = jsonb_build_object('prepare_error', error_message), state = 'finished' WHERE id = job.id;
            RAISE; -- Re-raise the exception
    END;

    -- Set initial state for all rows in data table (redundant if table is new, safe if resuming)
    EXECUTE format($$UPDATE public.%I SET state = %L, last_completed_priority = 0 WHERE state IS NULL OR state != %L$$,
                   job.data_table_name, 'pending', 'error');

END;
$import_job_prepare$;


END;

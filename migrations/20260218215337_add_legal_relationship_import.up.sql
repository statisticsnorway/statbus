-- Migration: Add legal_relationship import mode, step, procedures, and default definitions
-- Enables importing ownership/control relationships between legal units via the standard import pipeline.

BEGIN;

--------------------------------------------------------------------------------
-- PART 1: Add import_mode enum value
--------------------------------------------------------------------------------

ALTER TYPE public.import_mode ADD VALUE IF NOT EXISTS 'legal_relationship';

COMMIT;

-- Must be in separate transaction after ADD VALUE
BEGIN;

--------------------------------------------------------------------------------
-- PART 2: Create analyse and process procedures
-- (Must exist before PART 3 which casts them to regproc)
--------------------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE import.analyse_legal_relationship(p_job_id INT, p_batch_seq INTEGER, p_step_code TEXT)
LANGUAGE plpgsql AS $analyse_legal_relationship$
DECLARE
    v_job public.import_job;
    v_step public.import_step;
    v_data_table_name TEXT;
    v_error_count INT := 0;
    v_update_count INT := 0;
    v_sql TEXT;
    v_error_keys_to_clear_arr TEXT[] := ARRAY[
        'missing_influencing_tax_ident',
        'unknown_influencing_tax_ident',
        'missing_influenced_tax_ident',
        'unknown_influenced_tax_ident',
        'missing_rel_type_code',
        'unknown_rel_type_code',
        'invalid_percentage'
    ];
    v_invalid_code_keys_arr TEXT[] := ARRAY['rel_type_code'];
BEGIN
    RAISE DEBUG '[Job %] analyse_legal_relationship (Batch): Starting analysis for batch_seq %', p_job_id, p_batch_seq;

    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;

    SELECT * INTO v_step
    FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list')
    WHERE code = 'legal_relationship';
    IF NOT FOUND THEN RAISE EXCEPTION '[Job %] legal_relationship target step not found in snapshot', p_job_id; END IF;

    -- STEP 1: Materialize batch data into temp table
    IF to_regclass('pg_temp.t_lr_batch_data') IS NOT NULL THEN DROP TABLE t_lr_batch_data; END IF;
    v_sql := format($$
        CREATE TEMP TABLE t_lr_batch_data ON COMMIT DROP AS
        SELECT dt.row_id,
               dt.influencing_tax_ident_raw,
               dt.influenced_tax_ident_raw,
               dt.rel_type_code_raw,
               dt.percentage_raw
        FROM %I dt
        WHERE dt.batch_seq = $1
          AND dt.action IS DISTINCT FROM 'skip';
    $$, v_data_table_name);
    EXECUTE v_sql USING p_batch_seq;
    ANALYZE t_lr_batch_data;

    -- STEP 2: Resolve distinct tax_idents to legal_unit IDs
    IF to_regclass('pg_temp.t_lr_influencing_ids') IS NOT NULL THEN DROP TABLE t_lr_influencing_ids; END IF;
    CREATE TEMP TABLE t_lr_influencing_ids ON COMMIT DROP AS
    WITH distinct_idents AS (
        SELECT DISTINCT NULLIF(TRIM(influencing_tax_ident_raw), '') AS tax_ident
        FROM t_lr_batch_data
        WHERE NULLIF(TRIM(influencing_tax_ident_raw), '') IS NOT NULL
    )
    SELECT
        di.tax_ident,
        lu.id AS legal_unit_id
    FROM distinct_idents AS di
    LEFT JOIN public.external_ident AS ei
        ON ei.ident = di.tax_ident
        AND ei.type_id = (SELECT id FROM public.external_ident_type WHERE code = 'tax_ident')
    LEFT JOIN public.legal_unit AS lu
        ON lu.id = ei.legal_unit_id
        AND lu.valid_range @> CURRENT_DATE;
    ANALYZE t_lr_influencing_ids;

    IF to_regclass('pg_temp.t_lr_influenced_ids') IS NOT NULL THEN DROP TABLE t_lr_influenced_ids; END IF;
    CREATE TEMP TABLE t_lr_influenced_ids ON COMMIT DROP AS
    WITH distinct_idents AS (
        SELECT DISTINCT NULLIF(TRIM(influenced_tax_ident_raw), '') AS tax_ident
        FROM t_lr_batch_data
        WHERE NULLIF(TRIM(influenced_tax_ident_raw), '') IS NOT NULL
    )
    SELECT
        di.tax_ident,
        lu.id AS legal_unit_id
    FROM distinct_idents AS di
    LEFT JOIN public.external_ident AS ei
        ON ei.ident = di.tax_ident
        AND ei.type_id = (SELECT id FROM public.external_ident_type WHERE code = 'tax_ident')
    LEFT JOIN public.legal_unit AS lu
        ON lu.id = ei.legal_unit_id
        AND lu.valid_range @> CURRENT_DATE;
    ANALYZE t_lr_influenced_ids;

    -- Resolve rel_type codes
    IF to_regclass('pg_temp.t_lr_type_ids') IS NOT NULL THEN DROP TABLE t_lr_type_ids; END IF;
    CREATE TEMP TABLE t_lr_type_ids ON COMMIT DROP AS
    WITH distinct_codes AS (
        SELECT DISTINCT NULLIF(TRIM(rel_type_code_raw), '') AS code
        FROM t_lr_batch_data
        WHERE NULLIF(TRIM(rel_type_code_raw), '') IS NOT NULL
    )
    SELECT
        dc.code,
        lrt.id AS type_id
    FROM distinct_codes AS dc
    LEFT JOIN public.legal_rel_type AS lrt ON lrt.code = dc.code AND lrt.enabled;
    ANALYZE t_lr_type_ids;

    -- STEP 3: Main update with resolved values
    v_sql := format($SQL$
        WITH lookups AS (
            SELECT
                bd.row_id AS data_row_id,
                infl.legal_unit_id AS influencing_id,
                infld.legal_unit_id AS influenced_id,
                tp.type_id,
                CASE
                    WHEN NULLIF(TRIM(bd.percentage_raw), '') IS NOT NULL THEN
                        CASE
                            WHEN bd.percentage_raw ~ '^\s*[0-9]+(\.[0-9]+)?\s*$' THEN
                                TRIM(bd.percentage_raw)::numeric(5,2)
                            ELSE NULL
                        END
                    ELSE NULL
                END AS percentage,
                NULLIF(TRIM(bd.influencing_tax_ident_raw), '') IS NULL AS missing_influencing,
                NULLIF(TRIM(bd.influenced_tax_ident_raw), '') IS NULL AS missing_influenced,
                NULLIF(TRIM(bd.rel_type_code_raw), '') IS NULL AS missing_rel_type,
                NULLIF(TRIM(bd.influencing_tax_ident_raw), '') IS NOT NULL AND infl.legal_unit_id IS NULL AS unknown_influencing,
                NULLIF(TRIM(bd.influenced_tax_ident_raw), '') IS NOT NULL AND infld.legal_unit_id IS NULL AS unknown_influenced,
                NULLIF(TRIM(bd.rel_type_code_raw), '') IS NOT NULL AND tp.type_id IS NULL AS unknown_rel_type,
                NULLIF(TRIM(bd.percentage_raw), '') IS NOT NULL
                    AND NOT (bd.percentage_raw ~ '^\s*[0-9]+(\.[0-9]+)?\s*$')
                    AS invalid_percentage
            FROM t_lr_batch_data AS bd
            LEFT JOIN t_lr_influencing_ids AS infl ON infl.tax_ident = NULLIF(TRIM(bd.influencing_tax_ident_raw), '')
            LEFT JOIN t_lr_influenced_ids AS infld ON infld.tax_ident = NULLIF(TRIM(bd.influenced_tax_ident_raw), '')
            LEFT JOIN t_lr_type_ids AS tp ON tp.code = NULLIF(TRIM(bd.rel_type_code_raw), '')
        )
        UPDATE public.%1$I dt SET
            influencing_id = l.influencing_id,
            influenced_id = l.influenced_id,
            type_id = l.type_id,
            percentage = l.percentage,
            state = CASE
                WHEN l.missing_influencing OR l.unknown_influencing
                  OR l.missing_influenced OR l.unknown_influenced
                  OR l.missing_rel_type OR l.unknown_rel_type
                  OR l.invalid_percentage
                THEN 'error'::public.import_data_state
                ELSE 'analysing'::public.import_data_state
            END,
            action = CASE
                WHEN l.missing_influencing OR l.unknown_influencing
                  OR l.missing_influenced OR l.unknown_influenced
                  OR l.missing_rel_type OR l.unknown_rel_type
                  OR l.invalid_percentage
                THEN 'skip'::public.import_row_action_type
                ELSE 'use'::public.import_row_action_type
            END,
            operation = CASE
                WHEN l.missing_influencing OR l.unknown_influencing
                  OR l.missing_influenced OR l.unknown_influenced
                  OR l.missing_rel_type OR l.unknown_rel_type
                  OR l.invalid_percentage
                THEN NULL
                ELSE 'insert'::public.import_row_operation_type
            END,
            errors = (dt.errors - %2$L::TEXT[])
                || CASE WHEN l.missing_influencing THEN jsonb_build_object('missing_influencing_tax_ident', 'influencing_tax_ident is required') ELSE '{}'::jsonb END
                || CASE WHEN l.unknown_influencing THEN jsonb_build_object('unknown_influencing_tax_ident', 'No legal unit found for influencing_tax_ident') ELSE '{}'::jsonb END
                || CASE WHEN l.missing_influenced THEN jsonb_build_object('missing_influenced_tax_ident', 'influenced_tax_ident is required') ELSE '{}'::jsonb END
                || CASE WHEN l.unknown_influenced THEN jsonb_build_object('unknown_influenced_tax_ident', 'No legal unit found for influenced_tax_ident') ELSE '{}'::jsonb END
                || CASE WHEN l.missing_rel_type THEN jsonb_build_object('missing_rel_type_code', 'rel_type_code is required') ELSE '{}'::jsonb END
                || CASE WHEN l.unknown_rel_type THEN jsonb_build_object('unknown_rel_type_code', 'Unknown rel_type_code') ELSE '{}'::jsonb END
                || CASE WHEN l.invalid_percentage THEN jsonb_build_object('invalid_percentage', 'percentage must be a number 0-100') ELSE '{}'::jsonb END,
            invalid_codes = CASE
                WHEN l.unknown_rel_type THEN jsonb_strip_nulls((dt.invalid_codes - %3$L::TEXT[]) || jsonb_build_object('rel_type_code', dt.rel_type_code_raw))
                ELSE dt.invalid_codes - %3$L::TEXT[]
            END
        FROM lookups AS l
        WHERE dt.row_id = l.data_row_id;
    $SQL$, v_data_table_name, v_error_keys_to_clear_arr, v_invalid_code_keys_arr);

    BEGIN
        EXECUTE v_sql;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_legal_relationship: Updated % rows in batch.', p_job_id, v_update_count;
    EXCEPTION WHEN others THEN
        RAISE WARNING '[Job %] analyse_legal_relationship: Error during batch update: %', p_job_id, SQLERRM;
        UPDATE public.import_job SET error = jsonb_build_object('analyse_legal_relationship_batch_error', SQLERRM)::TEXT, state = 'failed' WHERE id = p_job_id;
    END;

    -- Advance priority for all batch rows
    v_sql := format('UPDATE public.%1$I dt SET last_completed_priority = %2$L WHERE dt.batch_seq = $1 AND dt.last_completed_priority < %2$L',
                    v_data_table_name, v_step.priority);
    EXECUTE v_sql USING p_batch_seq;

    -- Count errors
    BEGIN
        v_sql := format($$SELECT COUNT(*) FROM public.%1$I dt WHERE dt.batch_seq = $1 AND dt.state = 'error' AND (dt.errors ?| %2$L::text[])$$,
                       v_data_table_name, v_error_keys_to_clear_arr);
        EXECUTE v_sql INTO v_error_count USING p_batch_seq;
    EXCEPTION WHEN others THEN
        RAISE WARNING '[Job %] analyse_legal_relationship: Error during error count: %', p_job_id, SQLERRM;
    END;

    RAISE DEBUG '[Job %] analyse_legal_relationship (Batch): Finished analysis for batch. Total errors: %', p_job_id, v_error_count;
END;
$analyse_legal_relationship$;


CREATE OR REPLACE PROCEDURE import.process_legal_relationship(p_job_id INT, p_batch_seq INTEGER, p_step_code TEXT)
LANGUAGE plpgsql AS $process_legal_relationship$
DECLARE
    v_job public.import_job;
    v_definition public.import_definition;
    v_step public.import_step;
    v_data_table_name TEXT;
    v_sql TEXT;
    v_error_count INT := 0;
    v_update_count INT := 0;
    error_message TEXT;
    v_start_time TIMESTAMPTZ;
    v_duration_ms NUMERIC;
    v_merge_mode sql_saga.temporal_merge_mode;
BEGIN
    v_start_time := clock_timestamp();
    RAISE DEBUG '[Job %] process_legal_relationship (Batch): Starting operation for batch_seq %', p_job_id, p_batch_seq;

    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;

    SELECT * INTO v_definition FROM jsonb_populate_record(NULL::public.import_definition, v_job.definition_snapshot->'import_definition');
    IF v_definition IS NULL THEN RAISE EXCEPTION '[Job %] Failed to load import_definition from snapshot', p_job_id; END IF;

    SELECT * INTO v_step
    FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list')
    WHERE code = 'legal_relationship';
    IF NOT FOUND THEN RAISE EXCEPTION '[Job %] legal_relationship target step not found in snapshot', p_job_id; END IF;

    -- Create updatable view over batch data mapping to legal_relationship columns
    v_sql := format($$
        CREATE OR REPLACE TEMP VIEW temp_legal_relationship_source_view AS
        SELECT
            row_id AS data_row_id,
            founding_row_id,
            legal_relationship_id AS id,
            influencing_id,
            influenced_id,
            type_id,
            percentage,
            valid_from,
            valid_until,
            edit_by_user_id,
            edit_at,
            edit_comment,
            NULLIF(invalid_codes,'{}'::JSONB) AS invalid_codes,
            errors,
            merge_status
        FROM public.%1$I
        WHERE batch_seq = %2$L AND action = 'use';
    $$, v_data_table_name, p_batch_seq);
    EXECUTE v_sql;

    BEGIN
        v_merge_mode := CASE v_definition.strategy
            WHEN 'insert_or_replace' THEN 'MERGE_ENTITY_REPLACE'::sql_saga.temporal_merge_mode
            WHEN 'replace_only' THEN 'REPLACE_FOR_PORTION_OF'::sql_saga.temporal_merge_mode
            WHEN 'insert_or_update' THEN 'MERGE_ENTITY_PATCH'::sql_saga.temporal_merge_mode
            WHEN 'update_only' THEN 'UPDATE_FOR_PORTION_OF'::sql_saga.temporal_merge_mode
            ELSE 'MERGE_ENTITY_PATCH'::sql_saga.temporal_merge_mode
        END;
        RAISE DEBUG '[Job %] process_legal_relationship: Determined merge mode % from strategy %', p_job_id, v_merge_mode, v_definition.strategy;

        CALL sql_saga.temporal_merge(
            target_table => 'public.legal_relationship'::regclass,
            source_table => 'temp_legal_relationship_source_view'::regclass,
            primary_identity_columns => ARRAY['id'],
            mode => v_merge_mode,
            row_id_column => 'data_row_id',
            founding_id_column => 'founding_row_id',
            update_source_with_identity => true,
            update_source_with_feedback => true,
            feedback_status_column => 'merge_status',
            feedback_status_key => 'legal_relationship',
            feedback_error_column => 'errors',
            feedback_error_key => 'legal_relationship'
        );

        v_sql := format($$ SELECT count(*) FROM public.%1$I dt WHERE dt.batch_seq = $1 AND dt.errors->'legal_relationship' IS NOT NULL $$, v_data_table_name);
        EXECUTE v_sql INTO v_error_count USING p_batch_seq;

        v_sql := format($$
            UPDATE public.%1$I dt SET
                state = CASE WHEN dt.errors ? 'legal_relationship' THEN 'error'::public.import_data_state ELSE 'processing'::public.import_data_state END
            WHERE dt.batch_seq = $1 AND dt.action = 'use';
        $$, v_data_table_name);
        EXECUTE v_sql USING p_batch_seq;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        v_update_count := v_update_count - v_error_count;

        RAISE DEBUG '[Job %] process_legal_relationship: temporal_merge finished. Success: %, Errors: %', p_job_id, v_update_count, v_error_count;

        -- Propagate newly assigned legal_relationship_id within batch
        v_sql := format($$
            WITH id_source AS (
                SELECT DISTINCT src.founding_row_id, src.legal_relationship_id
                FROM public.%1$I src
                WHERE src.batch_seq = $1
                  AND src.legal_relationship_id IS NOT NULL
            )
            UPDATE public.%1$I dt
            SET legal_relationship_id = id_source.legal_relationship_id
            FROM id_source
            WHERE dt.batch_seq = $1
              AND dt.founding_row_id = id_source.founding_row_id
              AND dt.legal_relationship_id IS NULL;
        $$, v_data_table_name);
        EXECUTE v_sql USING p_batch_seq;

    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
        RAISE WARNING '[Job %] process_legal_relationship: Unhandled error: %', p_job_id, replace(error_message, '%', '%%');
        BEGIN
            v_sql := format($$UPDATE public.%1$I dt SET state = 'error'::public.import_data_state, errors = errors || jsonb_build_object('unhandled_error_process_legal_relationship', %2$L) WHERE dt.batch_seq = $1 AND dt.state != 'error'::public.import_data_state$$,
                           v_data_table_name, error_message);
            EXECUTE v_sql USING p_batch_seq;
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING '[Job %] process_legal_relationship: Failed to mark rows as error: %', p_job_id, SQLERRM;
        END;
        UPDATE public.import_job SET error = jsonb_build_object('process_legal_relationship_unhandled_error', error_message)::TEXT, state = 'failed' WHERE id = p_job_id;
    END;

    v_duration_ms := (EXTRACT(EPOCH FROM (clock_timestamp() - v_start_time)) * 1000);
    RAISE DEBUG '[Job %] process_legal_relationship (Batch): Finished in % ms. Success: %, Errors: %', p_job_id, round(v_duration_ms, 2), v_update_count, v_error_count;
END;
$process_legal_relationship$;


--------------------------------------------------------------------------------
-- PART 2b: Fix create_source_and_mappings_for_definition to skip stat variables
-- when the definition doesn't have a statistical_variables step
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION import.create_source_and_mappings_for_definition(
    p_definition_id INT,
    p_source_columns TEXT[]
) RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    v_def public.import_definition;
    v_col_name TEXT;
    v_priority INT := 0;
    v_source_col_id INT;
    v_data_col_id INT;
    v_max_priority INT;
    v_col_rec RECORD;
    v_has_stat_step BOOLEAN;
BEGIN
    SELECT * INTO v_def FROM public.import_definition WHERE id = p_definition_id;

    -- Handle validity date mappings based on definition mode
    IF v_def.valid_time_from = 'job_provided' THEN
        FOR v_col_name IN VALUES ('valid_from'), ('valid_to') LOOP
            SELECT dc.id INTO v_data_col_id FROM public.import_data_column dc JOIN public.import_step s ON dc.step_id = s.id WHERE s.code = 'valid_time' AND dc.column_name = v_col_name || '_raw';
            IF v_data_col_id IS NOT NULL THEN
                INSERT INTO public.import_mapping (definition_id, source_expression, target_data_column_id, target_data_column_purpose)
                VALUES (p_definition_id, 'default', v_data_col_id, 'source_input'::public.import_data_column_purpose)
                ON CONFLICT (definition_id, target_data_column_id) WHERE is_ignored = false DO NOTHING;
            END IF;
        END LOOP;
    END IF;

    -- Create source columns and map them
    FOREACH v_col_name IN ARRAY p_source_columns LOOP
        v_priority := v_priority + 1;
        INSERT INTO public.import_source_column (definition_id, column_name, priority)
        VALUES (p_definition_id, v_col_name, v_priority)
        ON CONFLICT DO NOTHING RETURNING id INTO v_source_col_id;

        IF v_source_col_id IS NOT NULL THEN
            SELECT dc.id INTO v_data_col_id
            FROM public.import_definition_step ds
            JOIN public.import_data_column dc ON ds.step_id = dc.step_id
            WHERE ds.definition_id = p_definition_id AND dc.column_name = v_col_name || '_raw' AND dc.purpose = 'source_input';

            IF v_data_col_id IS NOT NULL THEN
                INSERT INTO public.import_mapping (definition_id, source_column_id, target_data_column_id, target_data_column_purpose)
                VALUES (p_definition_id, v_source_col_id, v_data_col_id, 'source_input'::public.import_data_column_purpose)
                ON CONFLICT (definition_id, source_column_id, target_data_column_id) DO NOTHING;
            ELSE
                INSERT INTO public.import_mapping (definition_id, source_column_id, is_ignored)
                VALUES (p_definition_id, v_source_col_id, TRUE)
                ON CONFLICT (definition_id, source_column_id, target_data_column_id) WHERE target_data_column_id IS NULL DO NOTHING;
            END IF;
        END IF;
    END LOOP;

    -- Only add stat variable mappings if the definition has a statistical_variables step
    SELECT EXISTS (
        SELECT 1 FROM public.import_definition_step ids
        JOIN public.import_step s ON ids.step_id = s.id
        WHERE ids.definition_id = p_definition_id AND s.code = 'statistical_variables'
    ) INTO v_has_stat_step;

    IF v_has_stat_step THEN
        -- Dynamically add and map source columns for Statistical Variables
        SELECT COALESCE(MAX(priority), v_priority) INTO v_max_priority FROM public.import_source_column WHERE definition_id = p_definition_id;
        INSERT INTO public.import_source_column (definition_id, column_name, priority)
        SELECT p_definition_id, stat.code, v_max_priority + ROW_NUMBER() OVER (ORDER BY stat.priority)
        FROM public.stat_definition_active stat ON CONFLICT (definition_id, column_name) DO NOTHING;

        FOR v_col_rec IN
            SELECT isc.id as source_col_id, isc.column_name as stat_code FROM public.import_source_column isc
            JOIN public.stat_definition_active sda ON isc.column_name = sda.code
            WHERE isc.definition_id = p_definition_id AND NOT EXISTS (
                SELECT 1 FROM public.import_mapping im WHERE im.definition_id = p_definition_id AND im.source_column_id = isc.id
            )
        LOOP
            SELECT dc.id INTO v_data_col_id FROM public.import_definition_step ds
            JOIN public.import_step s ON ds.step_id = s.id
            JOIN public.import_data_column dc ON ds.step_id = dc.step_id
            WHERE ds.definition_id = p_definition_id AND s.code = 'statistical_variables' AND dc.column_name = v_col_rec.stat_code || '_raw' AND dc.purpose = 'source_input';

            IF v_data_col_id IS NOT NULL THEN
                INSERT INTO public.import_mapping (definition_id, source_column_id, target_data_column_id, target_data_column_purpose)
                VALUES (p_definition_id, v_col_rec.source_col_id, v_data_col_id, 'source_input')
                ON CONFLICT (definition_id, source_column_id, target_data_column_id) DO NOTHING;
            ELSE
                RAISE EXCEPTION '[Definition %] No matching source_input data column found in "statistical_variables" step for dynamically added stat source column "%".', p_definition_id, v_col_rec.stat_code;
            END IF;
        END LOOP;
    END IF;
END;
$$;


--------------------------------------------------------------------------------
-- PART 2c: Update validation to handle legal_relationship mode
-- - Add legal_relationship case to mode-specific checks
-- - Make external_idents mandatory only for unit-based imports
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION admin.validate_import_definition(p_definition_id integer)
 RETURNS void
 LANGUAGE plpgsql
AS $validate_import_definition$
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
        -- Check that 'valid_from_raw' and 'valid_to_raw' are mapped from source columns.
        SELECT EXISTS (
            SELECT 1 FROM public.import_mapping im
            JOIN public.import_data_column idc ON im.target_data_column_id = idc.id JOIN public.import_step s ON idc.step_id = s.id
            WHERE im.definition_id = p_definition_id AND s.code = 'valid_time' AND idc.column_name = 'valid_from_raw' AND im.source_column_id IS NOT NULL AND im.is_ignored = FALSE
        ) INTO v_has_valid_from_mapping;
        SELECT EXISTS (
            SELECT 1 FROM public.import_mapping im
            JOIN public.import_data_column idc ON im.target_data_column_id = idc.id JOIN public.import_step s ON idc.step_id = s.id
            WHERE im.definition_id = p_definition_id AND s.code = 'valid_time' AND idc.column_name = 'valid_to_raw' AND im.source_column_id IS NOT NULL AND im.is_ignored = FALSE
        ) INTO v_has_valid_to_mapping;

        IF NOT (v_has_valid_from_mapping AND v_has_valid_to_mapping) THEN
            v_is_valid := false;
            v_error_messages := array_append(v_error_messages, 'When valid_time_from="source_columns", mappings for both "valid_from_raw" and "valid_to_raw" from source columns are required.');
        END IF;

    ELSIF v_definition.valid_time_from = 'job_provided' THEN
        SELECT EXISTS (
            SELECT 1 FROM public.import_mapping im
            JOIN public.import_data_column idc ON im.target_data_column_id = idc.id JOIN public.import_step s ON idc.step_id = s.id
            WHERE im.definition_id = p_definition_id AND s.code = 'valid_time' AND idc.column_name = 'valid_from_raw' AND im.source_expression = 'default' AND im.is_ignored = FALSE
        ) INTO v_has_valid_from_mapping;
        SELECT EXISTS (
            SELECT 1 FROM public.import_mapping im
            JOIN public.import_data_column idc ON im.target_data_column_id = idc.id JOIN public.import_step s ON idc.step_id = s.id
            WHERE im.definition_id = p_definition_id AND s.code = 'valid_time' AND idc.column_name = 'valid_to_raw' AND im.source_expression = 'default' AND im.is_ignored = FALSE
        ) INTO v_has_valid_to_mapping;

        IF NOT (v_has_valid_from_mapping AND v_has_valid_to_mapping) THEN
            v_is_valid := false;
            v_error_messages := array_append(v_error_messages, 'When valid_time_from="job_provided", mappings for both "valid_from_raw" and "valid_to_raw" using source_expression="default" are required.');
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
    ELSIF v_definition.mode = 'legal_relationship' THEN
        -- Legal relationship mode imports relationships between two legal units.
        -- It identifies units via its own step (influencing/influenced tax_ident), not external_idents.
        IF NOT ('legal_relationship' = ANY(v_step_codes)) THEN
            v_is_valid := false;
            v_error_messages := array_append(v_error_messages, 'Mode "legal_relationship" requires the "legal_relationship" step.');
        END IF;
        RAISE DEBUG '[Validate Def ID %] Mode is legal_relationship.', p_definition_id;
    ELSE
        -- This case should ideally not be reached if the mode enum is exhaustive and NOT NULL
        v_is_valid := false;
        v_error_messages := array_append(v_error_messages, format('Unknown or unhandled import mode: %L.', v_definition.mode));
    END IF;

    -- Enforce unique step priorities within a definition (prevents equal-priority deadlocks in analysis scheduling)
    IF EXISTS (
        SELECT 1
        FROM (
            SELECT s.priority
            FROM public.import_definition_step ids
            JOIN public.import_step s ON s.id = ids.step_id
            WHERE ids.definition_id = p_definition_id
            GROUP BY s.priority
            HAVING COUNT(*) > 1
        ) dup
    ) THEN
        v_is_valid := false;
        v_error_messages := array_append(v_error_messages, 'import_step priorities must be unique per definition (duplicates found).');
    END IF;

    -- 3. Check for mandatory steps
    -- external_idents is mandatory for unit-based imports, but not for relationship imports
    -- which resolve identities within their own step.
    IF v_definition.mode != 'legal_relationship' THEN
        IF NOT ('external_idents' = ANY(v_step_codes)) THEN
            v_is_valid := false;
            v_error_messages := array_append(v_error_messages, 'The "external_idents" step is mandatory.');
        END IF;
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

    -- Conditional check for 'data_source_code_raw' mapping:
    -- If import_definition.data_source_id is NULL, a mapping for 'data_source_code_raw' is required.
    IF v_definition.data_source_id IS NULL THEN
        DECLARE
            v_data_source_code_mapped BOOLEAN;
            v_data_source_code_data_column_exists BOOLEAN;
        BEGIN
            SELECT EXISTS (
                SELECT 1
                FROM public.import_definition_step ids
                JOIN public.import_data_column idc ON ids.step_id = idc.step_id
                WHERE ids.definition_id = p_definition_id
                  AND idc.column_name = 'data_source_code_raw'
                  AND idc.purpose = 'source_input'
            ) INTO v_data_source_code_data_column_exists;

            IF v_data_source_code_data_column_exists THEN
                SELECT EXISTS (
                    SELECT 1 FROM public.import_mapping im
                    JOIN public.import_data_column idc ON im.target_data_column_id = idc.id
                    WHERE im.definition_id = p_definition_id
                      AND idc.column_name = 'data_source_code_raw'
                      AND idc.purpose = 'source_input'
                      AND im.is_ignored = FALSE
                ) INTO v_data_source_code_mapped;

                IF NOT v_data_source_code_mapped THEN
                    v_is_valid := false;
                    v_error_messages := array_append(v_error_messages, 'If import_definition.data_source_id is NULL and a "data_source_code_raw" source_input data column is available for the definition''s steps, it must be mapped.');
                END IF;
            ELSE
                v_is_valid := false;
                v_error_messages := array_append(v_error_messages, 'If import_definition.data_source_id is NULL, a "data_source_code_raw" source_input data column must be available via one of the definition''s steps and mapped. None found.');
            END IF;
        END;
    END IF;

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
        JOIN public.import_data_column idc ON im.target_data_column_id = idc.id
        JOIN public.import_step s ON idc.step_id = s.id
        WHERE im.definition_id = p_definition_id
          AND im.is_ignored = FALSE
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
        SELECT string_agg(DISTINCT error_msg, '; ') INTO v_temp_text FROM unnest(v_error_messages) AS error_msg;
        UPDATE public.import_definition
        SET valid = false, validation_error = v_temp_text
        WHERE id = p_definition_id;
    END IF;

END;
$validate_import_definition$;


--------------------------------------------------------------------------------
-- PART 3: Register the legal_relationship import step
--------------------------------------------------------------------------------

INSERT INTO public.import_step (code, name, priority, analyse_procedure, process_procedure, is_holistic) VALUES
    ('legal_relationship', 'Legal Relationship', 20, 'import.analyse_legal_relationship'::regproc, 'import.process_legal_relationship'::regproc, false)
ON CONFLICT (code) DO UPDATE SET
    name = EXCLUDED.name,
    priority = EXCLUDED.priority,
    analyse_procedure = EXCLUDED.analyse_procedure,
    process_procedure = EXCLUDED.process_procedure,
    is_holistic = EXCLUDED.is_holistic;

--------------------------------------------------------------------------------
-- PART 4: Register data columns for the step
--------------------------------------------------------------------------------

WITH ordered_values AS (
    SELECT
        *,
        ROW_NUMBER() OVER () as original_order
    FROM (
        VALUES
        ('legal_relationship', 'influencing_tax_ident_raw',  'TEXT',    'source_input', true, NULL, false),
        ('legal_relationship', 'influenced_tax_ident_raw',   'TEXT',    'source_input', true, NULL, false),
        ('legal_relationship', 'rel_type_code_raw',          'TEXT',    'source_input', true, NULL, false),
        ('legal_relationship', 'percentage_raw',             'TEXT',    'source_input', true, NULL, false),
        ('legal_relationship', 'influencing_id',             'INTEGER', 'internal',     true, NULL, false),
        ('legal_relationship', 'influenced_id',              'INTEGER', 'internal',     true, NULL, false),
        ('legal_relationship', 'type_id',                    'INTEGER', 'internal',     true, NULL, false),
        ('legal_relationship', 'percentage',                 'numeric(5,2)', 'internal', true, NULL, false),
        ('legal_relationship', 'action',                     'public.import_row_action_type', 'internal', true, NULL, false),
        ('legal_relationship', 'operation',                  'public.import_row_operation_type', 'internal', true, NULL, false),
        ('legal_relationship', 'legal_relationship_id',      'INTEGER', 'pk_id',        true, NULL, false)
    ) AS v_raw(step_code, column_name, column_type, purpose, is_nullable, default_value, is_uniquely_identifying)
),
values_with_priority AS (
    SELECT
        ov.step_code, ov.column_name, ov.column_type, ov.purpose,
        ov.is_nullable, ov.default_value, ov.is_uniquely_identifying,
        ROW_NUMBER() OVER (PARTITION BY ov.step_code ORDER BY ov.original_order) as derived_priority
    FROM ordered_values ov
)
INSERT INTO public.import_data_column (step_id, column_name, column_type, purpose, is_nullable, default_value, is_uniquely_identifying, priority)
SELECT
    s.id, v.column_name, v.column_type, v.purpose::public.import_data_column_purpose,
    COALESCE(v.is_nullable, true), v.default_value, COALESCE(v.is_uniquely_identifying, false),
    v.derived_priority
FROM public.import_step s
JOIN values_with_priority v ON s.code = v.step_code
ON CONFLICT (step_id, column_name) DO NOTHING;


--------------------------------------------------------------------------------
-- PART 5: Default import definitions
--------------------------------------------------------------------------------

DO $$
DECLARE
    def_id INT;
    lr_steps TEXT[] := ARRAY['valid_time', 'legal_relationship', 'edit_info', 'metadata'];
    lr_source_cols TEXT[] := ARRAY[
        'influencing_tax_ident', 'influenced_tax_ident',
        'rel_type_code', 'percentage'
    ];
    lr_explicit_source_cols TEXT[];
    nlr_data_source_id INT;
BEGIN
    lr_explicit_source_cols := lr_source_cols || ARRAY['valid_from', 'valid_to'];

    SELECT id INTO nlr_data_source_id FROM public.data_source WHERE code = 'nlr';
    IF NOT FOUND THEN RAISE EXCEPTION 'Data source "nlr" not found.'; END IF;

    INSERT INTO public.import_definition (slug, name, note, strategy, mode, valid_time_from, valid, data_source_id, custom)
    VALUES ('legal_relationship_source_dates', 'Legal Relationships (Source Dates)',
            'Import legal relationships (ownership/control). Validity from valid_from/valid_to columns in source file.',
            'insert_or_update', 'legal_relationship', 'source_columns', false, nlr_data_source_id, FALSE)
    RETURNING id INTO def_id;
    PERFORM import.link_steps_to_definition(def_id, lr_steps);
    PERFORM import.create_source_and_mappings_for_definition(def_id, lr_explicit_source_cols);

    INSERT INTO public.import_definition (slug, name, note, strategy, mode, valid_time_from, valid, data_source_id, custom)
    VALUES ('legal_relationship_job_provided', 'Legal Relationships (Job Provided Time)',
            'Import legal relationships (ownership/control). Validity from job time context.',
            'insert_or_update', 'legal_relationship', 'job_provided', false, nlr_data_source_id, FALSE)
    RETURNING id INTO def_id;
    PERFORM import.link_steps_to_definition(def_id, lr_steps);
    PERFORM import.create_source_and_mappings_for_definition(def_id, lr_source_cols);
END $$;

-- Validate definitions
DO $$
DECLARE
    def RECORD;
    invalid_definitions_summary TEXT := '';
    first_error BOOLEAN := TRUE;
BEGIN
    RAISE NOTICE 'Validating import definitions after adding legal_relationship...';
    FOR def IN SELECT id, slug, valid, validation_error FROM public.import_definition WHERE slug LIKE 'legal_relationship%' LOOP
        PERFORM admin.validate_import_definition(def.id);
        SELECT slug, valid, validation_error INTO def.slug, def.valid, def.validation_error
        FROM public.import_definition WHERE id = def.id;

        IF NOT def.valid THEN
            IF first_error THEN
                invalid_definitions_summary := format('Definition "%s" (ID: %s) is invalid: %s', def.slug, def.id, def.validation_error);
                first_error := FALSE;
            ELSE
                invalid_definitions_summary := invalid_definitions_summary || format('; Definition "%s" (ID: %s) is invalid: %s', def.slug, def.id, def.validation_error);
            END IF;
        END IF;
    END LOOP;

    IF invalid_definitions_summary != '' THEN
        RAISE EXCEPTION 'Migration failed: Invalid import definitions. Errors: %', invalid_definitions_summary;
    ELSE
        RAISE NOTICE 'Legal relationship import definitions validated successfully.';
    END IF;
END $$;

END;

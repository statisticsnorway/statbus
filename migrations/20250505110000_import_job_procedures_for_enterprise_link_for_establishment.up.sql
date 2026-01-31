-- Migration: import_job_procedures_for_enterprise_link_for_establishment
-- Implements the analyse and process procedures for the enterprise_link_for_establishment import step.

BEGIN;

-- Procedure to analyse enterprise link for standalone establishments
CREATE OR REPLACE PROCEDURE import.analyse_enterprise_link_for_establishment(p_job_id INT, p_batch_seq INTEGER, p_step_code TEXT)
LANGUAGE plpgsql AS $analyse_enterprise_link_for_establishment$
DECLARE
    v_job public.import_job;
    v_step public.import_step;
    v_data_table_name TEXT;
    v_sql TEXT;
    v_update_count INT;
    v_job_mode public.import_mode;
    v_external_ident_source_columns TEXT[];
    error_message TEXT;
BEGIN
    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;
    v_job_mode := (v_job.definition_snapshot->'import_definition'->>'mode')::public.import_mode;

    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = p_step_code;
    IF NOT FOUND THEN RAISE EXCEPTION '[Job %] Step % not found in snapshot', p_job_id, p_step_code; END IF;

    BEGIN
        -- This analysis is only for informal establishments. Other modes do nothing but advance priority.
        IF v_job_mode = 'establishment_informal' THEN
            -- Get the list of external identifier source columns to correctly associate errors.
            SELECT array_agg(idc_elem.value->>'column_name') INTO v_external_ident_source_columns
            FROM jsonb_array_elements(v_job.definition_snapshot->'import_data_column_list') AS idc_elem
            JOIN jsonb_array_elements(v_job.definition_snapshot->'import_step_list') AS step_elem
                ON (step_elem.value->>'code') = 'external_idents' AND (idc_elem.value->>'step_id')::int = (step_elem.value->>'id')::int
            WHERE idc_elem.value->>'purpose' = 'source_input';

            -- For 'replace' or 'update' actions, validate that the existing establishment is informal and has an enterprise link.
            -- This step is crucial to ensure that when a new historical slice is created for an existing establishment,
            -- it correctly inherits the enterprise_id, preventing a check constraint violation in the 'process_establishment' step.
            v_sql := format($$
                WITH validation AS (
                    SELECT
                        dt.row_id,
                        est.id as found_est_id,
                        est.enterprise_id AS existing_enterprise_id,
                        est.primary_for_enterprise AS existing_primary_for_enterprise
                    FROM public.%1$I dt
                    LEFT JOIN public.establishment est ON dt.establishment_id = est.id
                    WHERE dt.batch_seq = $1
                      AND dt.operation IN ('replace', 'update')
                      AND dt.establishment_id IS NOT NULL -- This check should only apply to establishments that existed before this job.
                      AND dt.action IS DISTINCT FROM 'skip'
                )
                UPDATE public.%1$I dt SET
                    enterprise_id = v.existing_enterprise_id,
                    primary_for_enterprise = v.existing_primary_for_enterprise,
                    state = CASE
                        WHEN v.found_est_id IS NULL THEN 'error'::public.import_data_state
                        WHEN v.existing_enterprise_id IS NULL THEN 'error'::public.import_data_state
                        ELSE dt.state
                    END,
                    action = CASE
                        WHEN v.found_est_id IS NULL OR v.existing_enterprise_id IS NULL THEN 'skip'::public.import_row_action_type
                        ELSE dt.action
                    END,
                    errors = dt.errors || CASE
                        WHEN v.found_est_id IS NULL THEN (SELECT jsonb_object_agg(col, 'Informal establishment for "replace" or "update" not found.') FROM unnest(%2$L::TEXT[]) col)
                        WHEN v.existing_enterprise_id IS NULL THEN (SELECT jsonb_object_agg(col, 'Informal establishment for "replace" or "update" is not linked to an enterprise.') FROM unnest(%2$L::TEXT[]) col)
                        ELSE '{}'::jsonb
                    END
                FROM validation v
                WHERE dt.row_id = v.row_id;
            $$, v_data_table_name, v_external_ident_source_columns);
            RAISE DEBUG '[Job %] analyse_enterprise_link_for_establishment (batch_seq=%): Validating "replace" and "update" rows for informal establishments.', p_job_id, p_batch_seq;
            EXECUTE v_sql USING p_batch_seq;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
        RAISE WARNING '[Job %] analyse_enterprise_link_for_establishment: Error during analysis: %', p_job_id, error_message;
        UPDATE public.import_job
        SET error = jsonb_build_object('analyse_enterprise_link_for_establishment_error', error_message), state = 'finished'
        WHERE id = p_job_id;
        RAISE;
    END;

    -- Always advance priority for all rows in the batch to prevent loops.
    v_sql := format('UPDATE public.%I dt SET last_completed_priority = %s WHERE dt.batch_seq = $1 AND dt.last_completed_priority < %s', v_data_table_name, v_step.priority, v_step.priority);
    RAISE DEBUG '[Job %] analyse_enterprise_link_for_establishment (batch_seq=%): Advancing priority for all rows with SQL: %', p_job_id, p_batch_seq, v_sql;
    EXECUTE v_sql USING p_batch_seq;
    GET DIAGNOSTICS v_update_count = ROW_COUNT;

    RAISE DEBUG '[Job %] analyse_enterprise_link_for_establishment (batch_seq=%): Finished analysis. Updated priority for % rows.', p_job_id, p_batch_seq, v_update_count;
END;
$analyse_enterprise_link_for_establishment$;


-- Procedure to process enterprise link for standalone establishments (create enterprise for new ESTs)
CREATE OR REPLACE PROCEDURE import.process_enterprise_link_for_establishment(p_job_id INT, p_batch_seq INTEGER, p_step_code TEXT)
LANGUAGE plpgsql AS $process_enterprise_link_for_establishment$
DECLARE
    v_job public.import_job;
    v_step public.import_step;
    v_data_table_name TEXT;
    v_sql TEXT;
    v_update_count INT := 0;
    v_created_enterprise_count INT := 0;
    error_message TEXT;
    rec_new_est RECORD;
    new_enterprise_id INT;
    v_job_mode public.import_mode;
BEGIN
    RAISE DEBUG '[Job %] process_enterprise_link_for_establishment (batch_seq=%): Starting operation', p_job_id, p_batch_seq;

    -- Get job details
    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;
    v_job_mode := (v_job.definition_snapshot->'import_definition'->>'mode')::public.import_mode;

    -- Find the step details from the snapshot first
    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = 'enterprise_link_for_establishment';
    IF NOT FOUND THEN RAISE EXCEPTION '[Job %] enterprise_link_for_establishment step not found in snapshot', p_job_id; END IF;

    IF v_job_mode != 'establishment_informal' THEN
        RAISE DEBUG '[Job %] process_enterprise_link_for_establishment: Skipping, job mode is %, not ''establishment_informal''. No action needed.', p_job_id, v_job_mode;
        RETURN;
    END IF;

    -- Step 1: Identify rows needing enterprise creation (new standalone ESTs, action = 'insert')
    IF to_regclass('pg_temp.temp_new_est_for_enterprise_creation') IS NOT NULL THEN DROP TABLE temp_new_est_for_enterprise_creation; END IF;
    CREATE TEMP TABLE temp_new_est_for_enterprise_creation (
        data_row_id INTEGER PRIMARY KEY, -- This will be the founding_row_id for the new EST entity
        edit_by_user_id INT,
        edit_at TIMESTAMPTZ,
        edit_comment TEXT
    ) ON COMMIT DROP;

    v_sql := format($$
        INSERT INTO temp_new_est_for_enterprise_creation (data_row_id, edit_by_user_id, edit_at, edit_comment)
        SELECT dt.row_id, dt.edit_by_user_id, dt.edit_at, dt.edit_comment
        FROM public.%1$I dt
        WHERE dt.batch_seq = $1
          AND dt.operation = 'insert' AND dt.founding_row_id = dt.row_id; -- Only process founding rows for new ESTs
    $$, v_data_table_name /* %1$I */);
    RAISE DEBUG '[Job %] process_enterprise_link_for_establishment (batch_seq=%): Populating temp table for new ESTs with SQL: %', p_job_id, p_batch_seq, v_sql;
    EXECUTE v_sql USING p_batch_seq;

    -- Step 2: Create new enterprises for ESTs in temp_new_est_for_enterprise_creation and map them
    -- temp_created_enterprises.data_row_id will store the founding_row_id of the EST
    IF to_regclass('pg_temp.temp_created_enterprises') IS NOT NULL THEN DROP TABLE temp_created_enterprises; END IF;
    CREATE TEMP TABLE temp_created_enterprises (
        data_row_id INTEGER PRIMARY KEY, -- Stores the founding_row_id of the EST
        enterprise_id INT NOT NULL
    ) ON COMMIT DROP;

    v_created_enterprise_count := 0;
    BEGIN
        WITH new_enterprises AS (
            INSERT INTO public.enterprise (short_name, edit_by_user_id, edit_at, edit_comment)
            SELECT
                NULL, -- short_name is set to NULL, will be derived by trigger later
                t.edit_by_user_id,
                t.edit_at,
                t.edit_comment
            FROM temp_new_est_for_enterprise_creation t
            RETURNING id
        ),
        source_with_rn AS (
            SELECT *, ROW_NUMBER() OVER () as rn FROM temp_new_est_for_enterprise_creation
        ),
        created_with_rn AS (
            SELECT id, ROW_NUMBER() OVER () as rn FROM new_enterprises
        )
        INSERT INTO temp_created_enterprises (data_row_id, enterprise_id)
        SELECT s.data_row_id, c.id
        FROM source_with_rn s
        JOIN created_with_rn c ON s.rn = c.rn;

        GET DIAGNOSTICS v_created_enterprise_count = ROW_COUNT;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
        RAISE WARNING '[Job %] process_enterprise_link_for_establishment: Programming error suspected during enterprise creation loop: %', p_job_id, replace(error_message, '%', '%%');
        UPDATE public.import_job SET error = jsonb_build_object('programming_error_process_enterprise_link_est', error_message) WHERE id = p_job_id;
        -- Constraints and temp table cleanup will be handled by the main exception block or successful completion
        RAISE;
    END;

    RAISE DEBUG '[Job %] process_enterprise_link_for_establishment: Created % new enterprises.', p_job_id, v_created_enterprise_count;

    -- Step 3: Update _data table for newly created enterprises (action = 'insert') and their related 'replace' rows
    -- For new informal ESTs linked to new Enterprises, all their initial slices are primary.
    v_sql := format($$
        UPDATE public.%1$I dt SET -- v_data_table_name
            enterprise_id = tce.enterprise_id,
            primary_for_enterprise = TRUE, -- All slices of a new informal EST linked to a new Enterprise are initially primary
            state = %2$L -- 'processing'
        FROM temp_created_enterprises tce -- tce.data_row_id is the founding_row_id
        WHERE dt.batch_seq = $1
          AND dt.founding_row_id = tce.data_row_id -- Link all rows of the entity via founding_row_id
          AND dt.action = 'use'; -- Only update usable rows
    $$, v_data_table_name, 'processing'::public.import_data_state);
    RAISE DEBUG '[Job %] process_enterprise_link_for_establishment (batch_seq=%): Updating _data for new enterprises and their related rows: %', p_job_id, p_batch_seq, v_sql;
    EXECUTE v_sql USING p_batch_seq;
    GET DIAGNOSTICS v_update_count = ROW_COUNT;

    -- Step 4: Update rows that were already processed by analyse step (existing ESTs, action = 'replace') - just advance priority
    v_sql := format($$
        UPDATE public.%1$I dt SET
            state = %2$L
        WHERE dt.batch_seq = $1
          AND dt.operation = 'replace' -- Only update rows for existing ESTs (mode 'establishment_informal' implies no LU link in data)
          AND dt.action = 'use'; -- Only update usable rows
    $$, v_data_table_name /* %1$I */, 'processing' /* %2$L */);
    RAISE DEBUG '[Job %] process_enterprise_link_for_establishment (batch_seq=%): Updating existing ESTs (action=replace, priority only): %', p_job_id, p_batch_seq, v_sql;
    EXECUTE v_sql USING p_batch_seq;

    -- Step 5: Update skipped rows (action = 'skip') - no LCP update needed in processing phase.
    GET DIAGNOSTICS v_update_count = ROW_COUNT; -- Re-using v_update_count, fine for debug
    RAISE DEBUG '[Job %] process_enterprise_link_for_establishment: Advanced priority for % skipped rows.', p_job_id, v_update_count;

    RAISE DEBUG '[Job %] process_enterprise_link_for_establishment (batch_seq=%): Finished operation. Created % enterprises.', p_job_id, p_batch_seq, v_created_enterprise_count;

EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
    RAISE WARNING '[Job %] process_enterprise_link_for_establishment: Unhandled error during operation: %', p_job_id, replace(error_message, '%', '%%');
    -- Update job error
    UPDATE public.import_job
    SET error = jsonb_build_object('process_enterprise_link_for_establishment_error', error_message),
        state = 'finished'
    WHERE id = p_job_id;
    RAISE DEBUG '[Job %] process_enterprise_link_for_establishment: Marked job as failed due to error: %', p_job_id, error_message;
    RAISE; -- Re-raise the original exception
END;
$process_enterprise_link_for_establishment$;

COMMIT;

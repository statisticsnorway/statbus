-- Migration: import_job_procedures_for_enterprise_link_for_establishment
-- Implements the analyse and process procedures for the enterprise_link_for_establishment import step.

BEGIN;

-- Procedure to analyse enterprise link for standalone establishments
CREATE OR REPLACE PROCEDURE import.analyse_enterprise_link_for_establishment(p_job_id INT, p_batch_row_ids INTEGER[], p_step_code TEXT)
LANGUAGE plpgsql AS $analyse_enterprise_link_for_establishment$
DECLARE
    v_job public.import_job;
    v_step public.import_step;
    v_data_table_name TEXT;
    v_sql TEXT;
    v_update_count INT;
    v_job_mode public.import_mode;
    v_error_keys_to_clear TEXT[];
BEGIN
    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;
    v_job_mode := (v_job.definition_snapshot->'import_definition'->>'mode')::public.import_mode;

    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = p_step_code;
    IF NOT FOUND THEN RAISE EXCEPTION '[Job %] Step % not found in snapshot', p_job_id, p_step_code; END IF;

    -- This analysis is only for informal establishments. Other modes do nothing but advance priority.
    IF v_job_mode = 'establishment_informal' THEN
        -- For 'replace' actions, validate that the existing establishment is informal and has an enterprise link.
        v_sql := format($$
            WITH validation AS (
                SELECT
                    dt.row_id,
                    est.id as found_est_id,
                    est.enterprise_id AS existing_enterprise_id,
                    est.primary_for_enterprise AS existing_primary_for_enterprise
                FROM public.%1$I dt
                LEFT JOIN public.establishment est ON dt.establishment_id = est.id
                WHERE dt.row_id = ANY($1)
                  AND dt.operation = 'replace'
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
                    WHEN v.found_est_id IS NULL THEN jsonb_build_object('tax_ident', 'Informal establishment for "replace" not found.')
                    WHEN v.existing_enterprise_id IS NULL THEN jsonb_build_object('tax_ident', 'Informal establishment for "replace" is not linked to an enterprise.')
                    ELSE '{}'::jsonb
                END
            FROM validation v
            WHERE dt.row_id = v.row_id;
        $$, v_data_table_name);
        RAISE DEBUG '[Job %] analyse_enterprise_link_for_establishment: Validating "replace" rows for informal establishments.', p_job_id;
        EXECUTE v_sql USING p_batch_row_ids;
    END IF;

    -- Always advance priority for all rows in the batch to prevent loops.
    EXECUTE format('UPDATE public.%I SET last_completed_priority = %s WHERE row_id = ANY($1)', v_data_table_name, v_step.priority)
    USING p_batch_row_ids;
    GET DIAGNOSTICS v_update_count = ROW_COUNT;

    RAISE DEBUG '[Job %] analyse_enterprise_link_for_establishment (Batch): Finished analysis. Updated priority for % rows.', p_job_id, v_update_count;
END;
$analyse_enterprise_link_for_establishment$;


-- Procedure to process enterprise link for standalone establishments (create enterprise for new ESTs)
CREATE OR REPLACE PROCEDURE import.process_enterprise_link_for_establishment(p_job_id INT, p_batch_row_ids INTEGER[], p_step_code TEXT)
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
    RAISE DEBUG '[Job %] process_enterprise_link_for_establishment (Batch): Starting operation for % rows', p_job_id, array_length(p_batch_row_ids, 1);

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
        est_name TEXT,
        edit_by_user_id INT,
        edit_at TIMESTAMPTZ,
        edit_comment TEXT
    ) ON COMMIT DROP;

    v_sql := format($$
        INSERT INTO temp_new_est_for_enterprise_creation (data_row_id, est_name, edit_by_user_id, edit_at, edit_comment)
        SELECT dt.row_id, dt.name, dt.edit_by_user_id, dt.edit_at, dt.edit_comment
        FROM public.%1$I dt
        WHERE dt.row_id = ANY($1) AND dt.operation = 'insert' AND dt.founding_row_id = dt.row_id; -- Only process founding rows for new ESTs
    $$, v_data_table_name /* %1$I */);
    EXECUTE v_sql USING p_batch_row_ids;

    -- Step 2: Create new enterprises for ESTs in temp_new_est_for_enterprise_creation and map them
    -- temp_created_enterprises.data_row_id will store the founding_row_id of the EST
    IF to_regclass('pg_temp.temp_created_enterprises') IS NOT NULL THEN DROP TABLE temp_created_enterprises; END IF;
    CREATE TEMP TABLE temp_created_enterprises (
        data_row_id INTEGER PRIMARY KEY, -- Stores the founding_row_id of the EST
        enterprise_id INT NOT NULL
    ) ON COMMIT DROP;

    v_created_enterprise_count := 0;
    BEGIN
        FOR rec_new_est IN SELECT * FROM temp_new_est_for_enterprise_creation LOOP
            INSERT INTO public.enterprise (short_name, edit_by_user_id, edit_at, edit_comment)
            VALUES (NULL, rec_new_est.edit_by_user_id, rec_new_est.edit_at, rec_new_est.edit_comment) -- Set short_name to NULL
            RETURNING id INTO new_enterprise_id;

            INSERT INTO temp_created_enterprises (data_row_id, enterprise_id)
            VALUES (rec_new_est.data_row_id, new_enterprise_id);
            v_created_enterprise_count := v_created_enterprise_count + 1;
        END LOOP;
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
        WHERE dt.founding_row_id = tce.data_row_id -- Link all rows of the entity via founding_row_id
          AND dt.row_id = ANY($1) -- p_batch_row_ids
          AND dt.action = 'use'; -- Only update usable rows
    $$, v_data_table_name, 'processing'::public.import_data_state);
    RAISE DEBUG '[Job %] process_enterprise_link_for_establishment: Updating _data for new enterprises and their related rows: %', p_job_id, v_sql;
    EXECUTE v_sql USING p_batch_row_ids;
    GET DIAGNOSTICS v_update_count = ROW_COUNT;

    -- Step 4: Update rows that were already processed by analyse step (existing ESTs, action = 'replace') - just advance priority
    v_sql := format($$
        UPDATE public.%1$I dt SET
            state = %2$L
        WHERE dt.row_id = ANY($1)
          AND dt.operation = 'replace' -- Only update rows for existing ESTs (mode 'establishment_informal' implies no LU link in data)
          AND dt.action = 'use'; -- Only update usable rows
    $$, v_data_table_name /* %1$I */, 'processing' /* %2$L */, 'error' /* %3$L */);
     RAISE DEBUG '[Job %] process_enterprise_link_for_establishment: Updating existing ESTs (action=replace, priority only): %', p_job_id, v_sql;
    EXECUTE v_sql USING p_batch_row_ids;

    -- Step 5: Update skipped rows (action = 'skip') - no LCP update needed in processing phase.
    GET DIAGNOSTICS v_update_count = ROW_COUNT; -- Re-using v_update_count, fine for debug
    RAISE DEBUG '[Job %] process_enterprise_link_for_establishment: Advanced priority for % skipped rows.', p_job_id, v_update_count;

    RAISE DEBUG '[Job %] process_enterprise_link_for_establishment (Batch): Finished operation. Created % enterprises.', p_job_id, v_created_enterprise_count;

    IF to_regclass('pg_temp.temp_new_est_for_enterprise_creation') IS NOT NULL THEN DROP TABLE temp_new_est_for_enterprise_creation; END IF;
    IF to_regclass('pg_temp.temp_created_enterprises') IS NOT NULL THEN DROP TABLE temp_created_enterprises; END IF;

EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
    RAISE WARNING '[Job %] process_enterprise_link_for_establishment: Unhandled error during operation: %', p_job_id, replace(error_message, '%', '%%');
    -- Ensure cleanup even on unexpected error
    IF to_regclass('pg_temp.temp_new_est_for_enterprise_creation') IS NOT NULL THEN DROP TABLE temp_new_est_for_enterprise_creation; END IF;
    IF to_regclass('pg_temp.temp_created_enterprises') IS NOT NULL THEN DROP TABLE temp_created_enterprises; END IF;
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

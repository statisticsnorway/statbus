-- Migration: import_job_procedures_for_enterprise_link_for_establishment
-- Implements the analyse and process procedures for the enterprise_link_for_establishment import step.

BEGIN;

-- Procedure to analyse enterprise link for standalone establishments
CREATE OR REPLACE PROCEDURE import.analyse_enterprise_link_for_establishment(p_job_id INT, p_batch_row_ids BIGINT[], p_step_code TEXT)
LANGUAGE plpgsql AS $analyse_enterprise_link_for_establishment$
DECLARE
    v_job public.import_job;
    v_step RECORD;
    v_data_table_name TEXT;
    v_sql TEXT;
    v_update_count INT := 0;
    v_processed_non_skip_count INT := 0; -- To track rows handled by the first main update
    v_skipped_update_count INT := 0;
    v_error_count INT := 0;
    v_job_mode public.import_mode;
    error_message TEXT;
    v_error_keys_to_clear_arr TEXT[] := ARRAY['enterprise_link_for_establishment'];
BEGIN
    RAISE DEBUG '[Job %] analyse_enterprise_link_for_establishment (Batch): Starting analysis for % rows. Batch Row IDs: %', p_job_id, array_length(p_batch_row_ids, 1), p_batch_row_ids;

    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;
    v_job_mode := (v_job.definition_snapshot->'import_definition'->>'mode')::public.import_mode;

    IF v_job_mode != 'establishment_informal' THEN
        RAISE DEBUG '[Job %] analyse_enterprise_link_for_establishment: Skipping, job mode is %, not ''establishment_informal''.', p_job_id, v_job_mode;
        EXECUTE format('UPDATE public.%I SET last_completed_priority = (SELECT priority FROM public.import_step WHERE code = %L) WHERE row_id = ANY(%L)', 
                       v_data_table_name, p_step_code, p_batch_row_ids);
        RETURN;
    END IF;

    SELECT * INTO v_step FROM public.import_step WHERE code = 'enterprise_link_for_establishment';
    IF NOT FOUND THEN RAISE EXCEPTION '[Job %] enterprise_link_for_establishment step not found', p_job_id; END IF;

    -- For 'replace' actions in 'establishment_informal' mode, attempt to find the existing establishment
    -- and its enterprise. If not found, or if enterprise_id is NULL, it's a fatal error.
    v_sql := format($$
        WITH est_data AS (
            SELECT dt.row_id, est.enterprise_id AS existing_enterprise_id, est.primary_for_enterprise AS existing_primary_for_enterprise, est.id as found_est_id
            FROM public.%1$I dt -- v_data_table_name
            LEFT JOIN public.establishment est ON dt.establishment_id = est.id
            WHERE dt.row_id = ANY(%2$L) AND dt.action = 'replace' AND dt.establishment_id IS NOT NULL AND %3$L = 'establishment_informal' -- p_batch_row_ids, v_job_mode
        )
        UPDATE public.%1$I dt SET -- v_data_table_name
            enterprise_id = CASE
                                WHEN dt.action = 'replace' AND dt.establishment_id IS NOT NULL AND %3$L = 'establishment_informal' AND ed.found_est_id IS NOT NULL THEN ed.existing_enterprise_id -- v_job_mode
                                ELSE dt.enterprise_id
                            END,
            primary_for_enterprise = CASE
                                        WHEN dt.action = 'replace' AND dt.establishment_id IS NOT NULL AND %3$L = 'establishment_informal' AND ed.found_est_id IS NOT NULL THEN ed.existing_primary_for_enterprise -- v_job_mode
                                        ELSE dt.primary_for_enterprise
                                     END,
            state = CASE
                        WHEN dt.action = 'replace' AND dt.establishment_id IS NOT NULL AND %3$L = 'establishment_informal' AND ed.found_est_id IS NULL THEN 'error'::public.import_data_state -- EST not found -- v_job_mode
                        WHEN dt.action = 'replace' AND dt.establishment_id IS NOT NULL AND %3$L = 'establishment_informal' AND ed.found_est_id IS NOT NULL AND ed.existing_enterprise_id IS NULL THEN 'error'::public.import_data_state -- EST found but no enterprise_id (inconsistent for informal) -- v_job_mode
                        ELSE 'analysing'::public.import_data_state
                    END,
            error = CASE
                        WHEN dt.action = 'replace' AND dt.establishment_id IS NOT NULL AND %3$L = 'establishment_informal' AND ed.found_est_id IS NULL THEN -- v_job_mode
                            COALESCE(dt.error, '{}'::jsonb) || jsonb_build_object('enterprise_link_for_establishment', jsonb_build_object('establishment_not_found_for_replace', dt.establishment_id))
                        WHEN dt.action = 'replace' AND dt.establishment_id IS NOT NULL AND %3$L = 'establishment_informal' AND ed.found_est_id IS NOT NULL AND ed.existing_enterprise_id IS NULL THEN -- v_job_mode
                            COALESCE(dt.error, '{}'::jsonb) || jsonb_build_object('enterprise_link_for_establishment', jsonb_build_object('missing_enterprise_for_informal_establishment', dt.establishment_id))
                        ELSE CASE WHEN (dt.error - %4$L::TEXT[]) = '{}'::jsonb THEN NULL ELSE (dt.error - %4$L::TEXT[]) END -- v_error_keys_to_clear_arr
                    END,
            last_completed_priority = CASE
                                        WHEN dt.action = 'replace' AND dt.establishment_id IS NOT NULL AND %3$L = 'establishment_informal' AND (ed.found_est_id IS NULL OR ed.existing_enterprise_id IS NULL) THEN dt.last_completed_priority -- Error: preserve existing LCP -- v_job_mode
                                        ELSE %5$s -- Success or non-applicable: current priority -- v_step.priority
                                      END
        FROM public.%1$I dt_main -- Alias for the main table being updated -- v_data_table_name
        LEFT JOIN est_data ed ON dt_main.row_id = ed.row_id
        WHERE dt_main.row_id = ANY(%2$L) AND dt_main.action = 'replace' AND %3$L = 'establishment_informal'; -- p_batch_row_ids, v_job_mode
    $$,
        v_data_table_name,          -- %1$I
        p_batch_row_ids,            -- %2$L
        v_job_mode,                 -- %3$L
        v_error_keys_to_clear_arr,  -- %4$L
        v_step.priority             -- %5$s
    );

    RAISE DEBUG '[Job %] analyse_enterprise_link_for_establishment: Updating "replace" rows for informal establishments: %', p_job_id, v_sql;

    BEGIN
        EXECUTE v_sql;
        GET DIAGNOSTICS v_processed_non_skip_count = ROW_COUNT; -- This counts rows updated by the above SQL (action='replace' and mode='establishment_informal')
        RAISE DEBUG '[Job %] analyse_enterprise_link_for_establishment: Processed % "replace" rows for informal establishments (includes potential errors).', p_job_id, v_processed_non_skip_count;

        -- Update priority for 'insert' and 'skip' rows, and 'replace' rows not matching the first UPDATE's criteria (e.g. not informal, or establishment_id was NULL)
        v_sql := format($$
            UPDATE public.%1$I dt SET -- v_data_table_name
                last_completed_priority = %2$s, -- v_step.priority
                state = CASE WHEN dt.state != 'error' THEN 'analysing'::public.import_data_state ELSE dt.state END,
                error = CASE WHEN dt.state != 'error' THEN (CASE WHEN (dt.error - %3$L::TEXT[]) = '{}'::jsonb THEN NULL ELSE (dt.error - %3$L::TEXT[]) END) ELSE dt.error END -- v_error_keys_to_clear_arr
            WHERE dt.row_id = ANY(%4$L) -- p_batch_row_ids
              AND (dt.action = 'insert' OR dt.action = 'skip' OR (dt.action = 'replace' AND dt.last_completed_priority < %2$s)); -- v_step.priority
        $$,
            v_data_table_name,        -- %1$I
            v_step.priority,          -- %2$s
            v_error_keys_to_clear_arr,-- %3$L
            p_batch_row_ids           -- %4$L
        );
        EXECUTE v_sql;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_enterprise_link_for_establishment: Updated priority/state for % other rows.', p_job_id, v_update_count;
        v_update_count := v_processed_non_skip_count + v_update_count; -- Total rows touched

    EXCEPTION WHEN OTHERS THEN
        error_message := SQLERRM;
        RAISE WARNING '[Job %] analyse_enterprise_link_for_establishment: Error during batch update: %', p_job_id, error_message;
        UPDATE public.import_job
        SET error = jsonb_build_object('analyse_enterprise_link_for_establishment_error', error_message),
            state = 'finished'
        WHERE id = p_job_id;
        RAISE DEBUG '[Job %] analyse_enterprise_link_for_establishment: Marked job as failed due to error: %', p_job_id, error_message;
        RAISE;
    END;

    RAISE DEBUG '[Job %] analyse_enterprise_link_for_establishment (Batch): Finished analysis successfully.', p_job_id;
END;
$analyse_enterprise_link_for_establishment$;


-- Procedure to process enterprise link for standalone establishments (create enterprise for new ESTs)
CREATE OR REPLACE PROCEDURE import.process_enterprise_link_for_establishment(p_job_id INT, p_batch_row_ids BIGINT[], p_step_code TEXT)
LANGUAGE plpgsql AS $process_enterprise_link_for_establishment$
DECLARE
    v_job public.import_job;
    v_step RECORD;
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

    IF v_job_mode != 'establishment_informal' THEN
        RAISE DEBUG '[Job %] process_enterprise_link_for_establishment: Skipping, job mode is %, not ''establishment_informal''.', p_job_id, v_job_mode;
        EXECUTE format('UPDATE public.%I SET last_completed_priority = (SELECT priority FROM public.import_step WHERE code = %L) WHERE row_id = ANY(%L)', 
                       v_data_table_name, p_step_code, p_batch_row_ids);
        RETURN;
    END IF;

    -- Find the step details
    SELECT * INTO v_step FROM public.import_step WHERE code = 'enterprise_link_for_establishment';
    IF NOT FOUND THEN RAISE EXCEPTION '[Job %] enterprise_link_for_establishment step not found', p_job_id; END IF;

    -- Step 1: Identify rows needing enterprise creation (new standalone ESTs, action = 'insert')
    CREATE TEMP TABLE temp_new_est_for_enterprise_creation (
        data_row_id BIGINT PRIMARY KEY,
        est_name TEXT,
        -- est_short_name VARCHAR(16), -- Removed, short_name will be NULL by default
        edit_by_user_id INT,
        edit_at TIMESTAMPTZ,
        edit_comment TEXT -- Added
    ) ON COMMIT DROP;

    v_sql := format($$
        INSERT INTO temp_new_est_for_enterprise_creation (data_row_id, est_name, edit_by_user_id, edit_at, edit_comment)
        SELECT row_id, name, edit_by_user_id, edit_at, edit_comment
        FROM public.%I
        WHERE row_id = ANY(%L) AND action = 'insert'; -- Only process rows for new standalone ESTs (mode 'establishment_informal' implies no LU link in data)
    $$, v_data_table_name, p_batch_row_ids);
    EXECUTE v_sql;

    -- Step 2: Create new enterprises for ESTs in temp_new_est_for_enterprise_creation and map them
    CREATE TEMP TABLE temp_created_enterprises (
        data_row_id BIGINT PRIMARY KEY,
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

    -- Step 3: Update _data table for newly created enterprises (action = 'insert')
    v_sql := format($$
        UPDATE public.%I dt SET
            enterprise_id = tce.enterprise_id,
            primary_for_enterprise = TRUE, -- New standalone EST becomes primary for its new enterprise
            last_completed_priority = %L,
            error = NULL,
            state = %L
        FROM temp_created_enterprises tce
        WHERE dt.row_id = tce.data_row_id; -- Join on data_row_id
    $$, v_data_table_name, v_step.priority, 'processing');
    RAISE DEBUG '[Job %] process_enterprise_link_for_establishment: Updating _data for new enterprises (action=insert): %', p_job_id, v_sql;
    EXECUTE v_sql;
    GET DIAGNOSTICS v_update_count = ROW_COUNT;

    -- Step 4: Update rows that were already processed by analyse step (existing ESTs, action = 'replace') - just advance priority
    v_sql := format($$
        UPDATE public.%I dt SET
            last_completed_priority = %L,
            state = %L
        WHERE dt.row_id = ANY(%L)
          AND dt.action = 'replace' -- Only update rows for existing ESTs (mode 'establishment_informal' implies no LU link in data)
          AND dt.state != %L; -- Avoid rows already in error
    $$, v_data_table_name, v_step.priority, 'processing', p_batch_row_ids, 'error');
     RAISE DEBUG '[Job %] process_enterprise_link_for_establishment: Updating existing ESTs (action=replace, priority only): %', p_job_id, v_sql;
    EXECUTE v_sql;

    -- Step 5: Update skipped rows (action = 'skip') - just advance priority
    EXECUTE format($$UPDATE public.%I SET last_completed_priority = %L WHERE row_id = ANY(%L) AND action = 'skip'$$,
                   v_data_table_name, v_step.priority, p_batch_row_ids);
    GET DIAGNOSTICS v_update_count = ROW_COUNT; -- Re-using v_update_count, fine for debug
    RAISE DEBUG '[Job %] process_enterprise_link_for_establishment: Advanced priority for % skipped rows.', p_job_id, v_update_count;

    RAISE DEBUG '[Job %] process_enterprise_link_for_establishment (Batch): Finished operation. Created % enterprises.', p_job_id, v_created_enterprise_count;

    DROP TABLE IF EXISTS temp_new_est_for_enterprise_creation;
    DROP TABLE IF EXISTS temp_created_enterprises;

EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
    RAISE WARNING '[Job %] process_enterprise_link_for_establishment: Unhandled error during operation: %', p_job_id, replace(error_message, '%', '%%');
    -- Ensure cleanup even on unexpected error
    DROP TABLE IF EXISTS temp_new_est_for_enterprise_creation;
    DROP TABLE IF EXISTS temp_created_enterprises;
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

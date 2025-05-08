-- Migration: implement_enterprise_link_for_legal_unit_procedures
-- Implements the analyse and process procedures for the enterprise_link import step.

BEGIN;

-- Procedure to analyse enterprise link (find existing enterprise for existing LUs)
CREATE OR REPLACE PROCEDURE admin.analyse_enterprise_link_for_legal_unit(p_job_id INT, p_batch_row_ids BIGINT[], p_step_code TEXT)
LANGUAGE plpgsql AS $analyse_enterprise_link_for_legal_unit$
DECLARE
    v_job public.import_job;
    v_step RECORD;
    v_data_table_name TEXT;
    v_sql TEXT;
    v_update_count INT := 0;
    v_error_count INT := 0;
BEGIN
    RAISE DEBUG '[Job %] analyse_enterprise_link_for_legal_unit (Batch): Starting analysis for % rows', p_job_id, array_length(p_batch_row_ids, 1);

    -- Get job details
    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;

    -- Find the step details
    SELECT * INTO v_step FROM public.import_step WHERE code = 'enterprise_link_for_legal_unit';
    IF NOT FOUND THEN RAISE EXCEPTION '[Job %] enterprise_link step not found', p_job_id; END IF;

    -- Step 1: Identify existing LUs in the batch (action = 'replace')
    CREATE TEMP TABLE temp_existing_lu (data_row_id BIGINT PRIMARY KEY, legal_unit_id INT NOT NULL) ON COMMIT DROP;
    v_sql := format($$
        INSERT INTO temp_existing_lu (data_row_id, legal_unit_id)
        SELECT row_id, legal_unit_id
        FROM public.%I
        WHERE row_id = ANY(%L) AND action = 'replace'; -- Filter by action = 'replace'
    $$, v_data_table_name, p_batch_row_ids);
    EXECUTE v_sql;

    -- Step 2: Look up enterprise info for existing LUs
    CREATE TEMP TABLE temp_enterprise_info (data_row_id BIGINT PRIMARY KEY, enterprise_id INT, is_primary BOOLEAN) ON COMMIT DROP;
    v_sql := format($$
        INSERT INTO temp_enterprise_info (data_row_id, enterprise_id, is_primary)
        SELECT tel.data_row_id, lu.enterprise_id, lu.primary_for_enterprise
        FROM temp_existing_lu tel
        JOIN public.legal_unit lu ON tel.legal_unit_id = lu.id;
    $$);
    EXECUTE v_sql;

    -- Step 3: Update _data table for existing LUs (action = 'replace')
    v_sql := format($$
        UPDATE public.%I dt SET
            enterprise_id = tei.enterprise_id,
            is_primary = tei.is_primary,
            last_completed_priority = %L,
            -- error = NULL, -- Removed: This step should not clear errors from prior steps
            state = %L
        FROM temp_enterprise_info tei
        WHERE dt.row_id = tei.data_row_id AND dt.action = 'replace'; -- Ensure we only update rows with action = 'replace'
    $$, v_data_table_name, v_step.priority, 'analysing');
    RAISE DEBUG '[Job %] analyse_enterprise_link_for_legal_unit: Updating existing LUs (action=replace): %', p_job_id, v_sql;
    EXECUTE v_sql;
    GET DIAGNOSTICS v_update_count = ROW_COUNT;

    -- Step 4: Update remaining rows (new LUs, action = 'insert') - just advance priority
    v_sql := format($$
        UPDATE public.%I dt SET
            last_completed_priority = %L,
            -- error = NULL, -- Removed: This step should not clear errors from prior steps
            state = %L
        WHERE dt.row_id = ANY(%L)
          AND dt.action = 'insert' -- Only update rows identified as new LUs
          AND dt.state != %L; -- Avoid rows already in error
    $$, v_data_table_name, v_step.priority, 'analysing', p_batch_row_ids, 'error');
     RAISE DEBUG '[Job %] analyse_enterprise_link_for_legal_unit: Updating new LUs (action=insert, priority only): %', p_job_id, v_sql;
    EXECUTE v_sql;

    -- Step 5: Update skipped rows (action = 'skip') - just advance priority
    EXECUTE format($$UPDATE public.%I SET last_completed_priority = %L WHERE row_id = ANY(%L) AND action = 'skip'$$,
                   v_data_table_name, v_step.priority, p_batch_row_ids);
    GET DIAGNOSTICS v_update_count = ROW_COUNT; -- Re-using v_update_count, fine for debug
    RAISE DEBUG '[Job %] analyse_enterprise_link_for_legal_unit: Advanced priority for % skipped rows.', p_job_id, v_update_count;

    RAISE DEBUG '[Job %] analyse_enterprise_link_for_legal_unit (Batch): Finished analysis. Updated % existing LUs.', p_job_id, v_update_count;

    DROP TABLE IF EXISTS temp_existing_lu;
    DROP TABLE IF EXISTS temp_enterprise_info;
END;
$analyse_enterprise_link_for_legal_unit$;


-- Procedure to process enterprise link (create enterprise for new LUs)
CREATE OR REPLACE PROCEDURE admin.process_enterprise_link_for_legal_unit(p_job_id INT, p_batch_row_ids BIGINT[], p_step_code TEXT)
LANGUAGE plpgsql AS $process_enterprise_link_for_legal_unit$
DECLARE
    v_job public.import_job;
    v_step RECORD;
    v_data_table_name TEXT;
    v_sql TEXT;
    v_update_count INT := 0;
    v_error_count INT := 0;
    statbus_constraints_already_deferred BOOLEAN;
    error_message TEXT;
BEGIN
    RAISE DEBUG '[Job %] process_enterprise_link_for_legal_unit (Batch): Starting operation for % rows', p_job_id, array_length(p_batch_row_ids, 1);

    -- Get job details
    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;

    -- Find the step details
    SELECT * INTO v_step FROM public.import_step WHERE code = 'enterprise_link_for_legal_unit';
    IF NOT FOUND THEN RAISE EXCEPTION '[Job %] enterprise_link step not found', p_job_id; END IF;

    -- Check if constraints are already deferred
    SELECT COALESCE(NULLIF(current_setting('statbus.constraints_already_deferred', true),'')::boolean,false) INTO statbus_constraints_already_deferred;
    IF NOT statbus_constraints_already_deferred THEN
        SET CONSTRAINTS ALL DEFERRED;
    END IF;

    -- Step 1: Identify rows needing enterprise creation (new LUs, action = 'insert')
    CREATE TEMP TABLE temp_new_lu (
        data_row_id BIGINT PRIMARY KEY,
        name TEXT, -- Needed to create enterprise
        edit_by_user_id INT,
        edit_at TIMESTAMPTZ
    ) ON COMMIT DROP;

    v_sql := format($$
        INSERT INTO temp_new_lu (data_row_id, name, edit_by_user_id, edit_at)
        SELECT row_id, name, edit_by_user_id, edit_at -- Select row_id from source, insert into data_row_id
        FROM public.%I
        WHERE row_id = ANY(%L) AND action = 'insert'; -- Only process rows for new LUs
    $$, v_data_table_name, p_batch_row_ids);
    EXECUTE v_sql;

    -- Step 2: Batch INSERT new enterprises
    CREATE TEMP TABLE temp_created_enterprises (
        data_row_id BIGINT PRIMARY KEY,
        enterprise_id INT NOT NULL
    ) ON COMMIT DROP;

    BEGIN
        v_sql := format($$
            WITH inserted_enterprises AS (
                INSERT INTO public.enterprise (short_name, edit_by_user_id, edit_at)
                SELECT SUBSTRING(tnl.name FROM 1 FOR 16), tnl.edit_by_user_id, tnl.edit_at
                FROM temp_new_lu tnl
                RETURNING id, short_name
            )
            INSERT INTO temp_created_enterprises (data_row_id, enterprise_id)
            SELECT tnl.data_row_id, ie.id -- Use data_row_id from temp_new_lu
            FROM temp_new_lu tnl
            JOIN inserted_enterprises ie ON SUBSTRING(tnl.name FROM 1 FOR 16) = ie.short_name; -- Match on substring
            -- A better approach might involve RETURNING row_id if possible, or a staging table.
        $$);
        RAISE DEBUG '[Job %] process_enterprise_link_for_legal_unit: Creating new enterprises: %', p_job_id, v_sql;
        EXECUTE v_sql;

    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
        RAISE WARNING '[Job %] process_enterprise_link_for_legal_unit: Error during enterprise creation: %', p_job_id, error_message;
        -- Mark affected rows as error
        v_sql := format($$
            UPDATE public.%I dt SET
                state = %L,
                error = COALESCE(dt.error, %L) || jsonb_build_object('enterprise_link_for_legal_unit', 'Failed to create enterprise: ' || %L),
                last_completed_priority = %L
            FROM temp_new_lu tnl
            WHERE dt.row_id = tnl.data_row_id; -- Use data_row_id for join
        $$, v_data_table_name, 'error', '{}'::jsonb, error_message, v_step.priority - 1);
        EXECUTE v_sql;
        GET DIAGNOSTICS v_error_count = ROW_COUNT;
        -- Update job error
        UPDATE public.import_job SET error = jsonb_build_object('process_enterprise_link_for_legal_unit_error', error_message) WHERE id = p_job_id;
        -- Skip further processing for this batch if creation failed
        IF NOT statbus_constraints_already_deferred THEN SET CONSTRAINTS ALL IMMEDIATE; END IF;
        RAISE DEBUG '[Job %] process_enterprise_link_for_legal_unit (Batch): Finished operation due to error. Errors: %', p_job_id, v_error_count;
        RETURN;
    END;

    -- Step 3: Update _data table for newly created enterprises (action = 'insert')
    v_sql := format($$
        UPDATE public.%I dt SET
            enterprise_id = tce.enterprise_id,
            is_primary = true, -- Assume new LU is primary for new enterprise
            last_completed_priority = %L,
            error = NULL,
            state = %L
        FROM temp_created_enterprises tce
        WHERE dt.row_id = tce.data_row_id; -- Use data_row_id for join
    $$, v_data_table_name, v_step.priority, 'processing');
    RAISE DEBUG '[Job %] process_enterprise_link_for_legal_unit: Updating _data for new enterprises (action=insert): %', p_job_id, v_sql;
    EXECUTE v_sql;
    GET DIAGNOSTICS v_update_count = ROW_COUNT;

    -- Step 4: Update rows that were already processed by analyse step (existing LUs, action = 'replace') - just advance priority
    v_sql := format($$
        UPDATE public.%I dt SET
            last_completed_priority = %L,
            state = %L
        WHERE dt.row_id = ANY(%L)
          AND dt.action = 'replace' -- Only update rows for existing LUs
          AND dt.state != %L; -- Avoid rows already in error
    $$, v_data_table_name, v_step.priority, 'processing', p_batch_row_ids, 'error');
     RAISE DEBUG '[Job %] process_enterprise_link_for_legal_unit: Updating existing LUs (action=replace, priority only): %', p_job_id, v_sql;
    EXECUTE v_sql;

    -- Step 5: Update skipped rows (action = 'skip') - just advance priority
    EXECUTE format($$UPDATE public.%I SET last_completed_priority = %L WHERE row_id = ANY(%L) AND action = 'skip'$$,
                   v_data_table_name, v_step.priority, p_batch_row_ids);
    GET DIAGNOSTICS v_update_count = ROW_COUNT; -- Re-using v_update_count, fine for debug
    RAISE DEBUG '[Job %] process_enterprise_link_for_legal_unit: Advanced priority for % skipped rows.', p_job_id, v_update_count;

    -- Reset constraints if they were deferred by this function
    IF NOT statbus_constraints_already_deferred THEN
        SET CONSTRAINTS ALL IMMEDIATE;
    END IF;

    RAISE DEBUG '[Job %] process_enterprise_link_for_legal_unit (Batch): Finished operation. Created % enterprises.', p_job_id, v_update_count;

    DROP TABLE IF EXISTS temp_new_lu;
    DROP TABLE IF EXISTS temp_created_enterprises;
END;
$process_enterprise_link_for_legal_unit$;

COMMIT;

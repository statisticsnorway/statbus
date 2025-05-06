-- Migration: implement_enterprise_link_for_legal_unit_procedures
-- Implements the analyse and process procedures for the enterprise_link import step.

BEGIN;

-- Procedure to analyse enterprise link (find existing enterprise for existing LUs)
CREATE OR REPLACE PROCEDURE admin.analyse_enterprise_link_for_legal_unit(p_job_id INT, p_batch_ctids TID[], p_step_code TEXT)
LANGUAGE plpgsql AS $analyse_enterprise_link_for_legal_unit$
DECLARE
    v_job public.import_job;
    v_step RECORD;
    v_data_table_name TEXT;
    v_sql TEXT;
    v_update_count INT := 0;
    v_error_count INT := 0;
BEGIN
    RAISE DEBUG '[Job %] analyse_enterprise_link_for_legal_unit (Batch): Starting analysis for % rows', p_job_id, array_length(p_batch_ctids, 1);

    -- Get job details
    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;

    -- Find the step details
    SELECT * INTO v_step FROM public.import_step WHERE code = 'enterprise_link_for_legal_unit';
    IF NOT FOUND THEN RAISE EXCEPTION '[Job %] enterprise_link step not found', p_job_id; END IF;

    -- Step 1: Identify existing LUs in the batch
    CREATE TEMP TABLE temp_existing_lu (data_ctid TID PRIMARY KEY, legal_unit_id INT NOT NULL) ON COMMIT DROP;
    -- 'ctid' here is from public.%I (the data_table_name)
    -- legal_unit_id resolved by external_idents step
    v_sql := format($$
        INSERT INTO temp_existing_lu (data_ctid, legal_unit_id)
        SELECT ctid, legal_unit_id
        FROM public.%I
        WHERE ctid = ANY(%L) AND legal_unit_id IS NOT NULL;
    $$, v_data_table_name, p_batch_ctids);
    EXECUTE v_sql;

    -- Step 2: Look up enterprise info for existing LUs
    CREATE TEMP TABLE temp_enterprise_info (data_ctid TID PRIMARY KEY, enterprise_id INT, is_primary BOOLEAN) ON COMMIT DROP;
    v_sql := format($$
        INSERT INTO temp_enterprise_info (data_ctid, enterprise_id, is_primary)
        SELECT tel.data_ctid, lu.enterprise_id, lu.primary_for_enterprise
        FROM temp_existing_lu tel
        JOIN public.legal_unit lu ON tel.legal_unit_id = lu.id;
    $$);
    EXECUTE v_sql;

    -- Step 3: Update _data table for existing LUs
    v_sql := format($$
        UPDATE public.%I dt SET
            enterprise_id = tei.enterprise_id,
            is_primary = tei.is_primary,
            last_completed_priority = %L,
            -- error = NULL, -- Removed: This step should not clear errors from prior steps
            state = %L
        FROM temp_enterprise_info tei
        WHERE dt.ctid = tei.data_ctid; -- Use renamed column from temp_enterprise_info
    $$, v_data_table_name, v_step.priority, 'analysing');
    RAISE DEBUG '[Job %] analyse_enterprise_link_for_legal_unit: Updating existing LUs: %', p_job_id, v_sql;
    EXECUTE v_sql;
    GET DIAGNOSTICS v_update_count = ROW_COUNT;

    -- Step 4: Update remaining rows (new LUs) - just advance priority
    v_sql := format($$
        UPDATE public.%I dt SET
            last_completed_priority = %L,
            -- error = NULL, -- Removed: This step should not clear errors from prior steps
            state = %L
        WHERE dt.ctid = ANY(%L)
          AND dt.legal_unit_id IS NULL -- Only update rows identified as new LUs
          AND dt.state != %L; -- Avoid rows already in error
    $$, v_data_table_name, v_step.priority, 'analysing', p_batch_ctids, 'error');
     RAISE DEBUG '[Job %] analyse_enterprise_link_for_legal_unit: Updating new LUs (priority only): %', p_job_id, v_sql;
    EXECUTE v_sql;

    RAISE DEBUG '[Job %] analyse_enterprise_link_for_legal_unit (Batch): Finished analysis. Updated % existing LUs.', p_job_id, v_update_count;

    DROP TABLE IF EXISTS temp_existing_lu;
    DROP TABLE IF EXISTS temp_enterprise_info;
END;
$analyse_enterprise_link_for_legal_unit$;


-- Procedure to process enterprise link (create enterprise for new LUs)
CREATE OR REPLACE PROCEDURE admin.process_enterprise_link_for_legal_unit(p_job_id INT, p_batch_ctids TID[], p_step_code TEXT)
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
    RAISE DEBUG '[Job %] process_enterprise_link_for_legal_unit (Batch): Starting operation for % rows', p_job_id, array_length(p_batch_ctids, 1);

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

    -- Step 1: Identify rows needing enterprise creation (new LUs)
    CREATE TEMP TABLE temp_new_lu (
        data_ctid TID PRIMARY KEY, -- Renamed ctid to data_ctid
        name TEXT, -- Needed to create enterprise
        edit_by_user_id INT,
        edit_at TIMESTAMPTZ
    ) ON COMMIT DROP;

    v_sql := format($$
        INSERT INTO temp_new_lu (data_ctid, name, edit_by_user_id, edit_at) -- Renamed ctid to data_ctid
        SELECT ctid, name, edit_by_user_id, edit_at -- Select ctid from source, insert into data_ctid
        FROM public.%I
        WHERE ctid = ANY(%L) AND legal_unit_id IS NULL; -- Only process rows for new LUs
    $$, v_data_table_name, p_batch_ctids);
    EXECUTE v_sql;

    -- Step 2: Batch INSERT new enterprises
    CREATE TEMP TABLE temp_created_enterprises (
        data_ctid TID PRIMARY KEY, -- Renamed ctid to data_ctid
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
            INSERT INTO temp_created_enterprises (data_ctid, enterprise_id) -- Renamed ctid to data_ctid
            SELECT tnl.data_ctid, ie.id -- Use data_ctid from temp_new_lu
            FROM temp_new_lu tnl
            JOIN inserted_enterprises ie ON SUBSTRING(tnl.name FROM 1 FOR 16) = ie.short_name; -- Match on substring
            -- A better approach might involve RETURNING ctid if possible, or a staging table.
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
            WHERE dt.ctid = tnl.data_ctid; -- Use data_ctid for join
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

    -- Step 3: Update _data table for newly created enterprises
    v_sql := format($$
        UPDATE public.%I dt SET
            enterprise_id = tce.enterprise_id,
            is_primary = true, -- Assume new LU is primary for new enterprise
            last_completed_priority = %L,
            error = NULL,
            state = %L
        FROM temp_created_enterprises tce
        WHERE dt.ctid = tce.data_ctid; -- Use data_ctid for join
    $$, v_data_table_name, v_step.priority, 'processing');
    RAISE DEBUG '[Job %] process_enterprise_link_for_legal_unit: Updating _data for new enterprises: %', p_job_id, v_sql;
    EXECUTE v_sql;
    GET DIAGNOSTICS v_update_count = ROW_COUNT;

    -- Step 4: Update rows that were already processed by analyse step (existing LUs) - just advance priority
    v_sql := format($$
        UPDATE public.%I dt SET
            last_completed_priority = %L,
            state = %L
        WHERE dt.ctid = ANY(%L)
          AND dt.legal_unit_id IS NOT NULL -- Only update rows for existing LUs
          AND dt.state != %L; -- Avoid rows already in error
    $$, v_data_table_name, v_step.priority, 'processing', p_batch_ctids, 'error');
     RAISE DEBUG '[Job %] process_enterprise_link_for_legal_unit: Updating existing LUs (priority only): %', p_job_id, v_sql;
    EXECUTE v_sql;


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

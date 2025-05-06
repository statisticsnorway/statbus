-- Migration: implement_enterprise_link_for_establishment_procedures
-- Implements the analyse and process procedures for the enterprise_link_for_establishment import step.

BEGIN;

-- Procedure to analyse enterprise link for standalone establishments
CREATE OR REPLACE PROCEDURE admin.analyse_enterprise_link_for_establishment(p_job_id INT, p_batch_ctids TID[], p_step_code TEXT)
LANGUAGE plpgsql AS $analyse_enterprise_link_for_establishment$
DECLARE
    v_job public.import_job;
    v_step RECORD;
    v_data_table_name TEXT;
    v_sql TEXT;
    v_update_count INT := 0;
    v_error_count INT := 0;
BEGIN
    RAISE DEBUG '[Job %] analyse_enterprise_link_for_establishment (Batch): Starting analysis for % rows', p_job_id, array_length(p_batch_ctids, 1);

    -- Get job details
    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;

    -- Find the step details
    SELECT * INTO v_step FROM public.import_step WHERE code = 'enterprise_link_for_establishment';
    IF NOT FOUND THEN RAISE EXCEPTION '[Job %] enterprise_link_for_establishment step not found', p_job_id; END IF;

    -- Step 1: Identify existing ESTs in the batch (should have establishment_id from external_idents step)
    CREATE TEMP TABLE temp_existing_est (data_ctid TID PRIMARY KEY, establishment_id INT NOT NULL) ON COMMIT DROP;
    v_sql := format($$
        INSERT INTO temp_existing_est (data_ctid, establishment_id)
        SELECT ctid, establishment_id -- 'ctid' here is from public.%I (the data_table_name)
        FROM public.%I
        WHERE ctid = ANY(%L) AND establishment_id IS NOT NULL AND legal_unit_id IS NULL; -- Only standalone ESTs
    $$, v_data_table_name, p_batch_ctids);
    EXECUTE v_sql;

    -- Step 2: Look up enterprise info for existing ESTs
    CREATE TEMP TABLE temp_enterprise_info (data_ctid TID PRIMARY KEY, enterprise_id INT) ON COMMIT DROP;
    v_sql := format($$
        INSERT INTO temp_enterprise_info (data_ctid, enterprise_id)
        SELECT tee.data_ctid, est.enterprise_id
        FROM temp_existing_est tee
        JOIN public.establishment est ON tee.establishment_id = est.id
        WHERE est.enterprise_id IS NOT NULL; -- Ensure the existing EST has an enterprise link
    $$);
    EXECUTE v_sql;

    -- Step 3: Update _data table for existing ESTs
    v_sql := format($$
        UPDATE public.%I dt SET
            enterprise_id = tei.enterprise_id,
            last_completed_priority = %L,
            -- error = NULL, -- Removed: This step should not clear errors from prior steps
            state = %L
        FROM temp_enterprise_info tei
        WHERE dt.ctid = tei.data_ctid; -- Use renamed column from temp_enterprise_info
    $$, v_data_table_name, v_step.priority, 'analysing');
    RAISE DEBUG '[Job %] analyse_enterprise_link_for_establishment: Updating existing ESTs: %', p_job_id, v_sql;
    EXECUTE v_sql;
    GET DIAGNOSTICS v_update_count = ROW_COUNT;

    -- Step 4: Update remaining rows (new ESTs) - just advance priority
    v_sql := format($$
        UPDATE public.%I dt SET
            last_completed_priority = %L,
            -- error = NULL, -- Removed: This step should not clear errors from prior steps
            state = %L
        WHERE dt.ctid = ANY(%L)
          AND dt.establishment_id IS NULL -- Only update rows identified as new ESTs
          AND dt.legal_unit_id IS NULL -- Ensure it's a standalone EST import row
          AND dt.state != %L; -- Avoid rows already in error
    $$, v_data_table_name, v_step.priority, 'analysing', p_batch_ctids, 'error');
     RAISE DEBUG '[Job %] analyse_enterprise_link_for_establishment: Updating new ESTs (priority only): %', p_job_id, v_sql;
    EXECUTE v_sql;

    RAISE DEBUG '[Job %] analyse_enterprise_link_for_establishment (Batch): Finished analysis. Updated % existing ESTs.', p_job_id, v_update_count;

    DROP TABLE IF EXISTS temp_existing_est;
    DROP TABLE IF EXISTS temp_enterprise_info;
END;
$analyse_enterprise_link_for_establishment$;


-- Procedure to process enterprise link for standalone establishments (create enterprise for new ESTs)
CREATE OR REPLACE PROCEDURE admin.process_enterprise_link_for_establishment(p_job_id INT, p_batch_ctids TID[], p_step_code TEXT)
LANGUAGE plpgsql AS $process_enterprise_link_for_establishment$
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
    RAISE DEBUG '[Job %] process_enterprise_link_for_establishment (Batch): Starting operation for % rows', p_job_id, array_length(p_batch_ctids, 1);

    -- Get job details
    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;

    -- Find the step details
    SELECT * INTO v_step FROM public.import_step WHERE code = 'enterprise_link_for_establishment';
    IF NOT FOUND THEN RAISE EXCEPTION '[Job %] enterprise_link_for_establishment step not found', p_job_id; END IF;

    -- Check if constraints are already deferred
    SELECT COALESCE(NULLIF(current_setting('statbus.constraints_already_deferred', true),'')::boolean,false) INTO statbus_constraints_already_deferred;
    IF NOT statbus_constraints_already_deferred THEN
        SET CONSTRAINTS ALL DEFERRED;
    END IF;

    -- Step 1: Identify rows needing enterprise creation (new standalone ESTs)
    CREATE TEMP TABLE temp_new_est (
        data_ctid TID PRIMARY KEY, -- Renamed ctid to data_ctid
        name TEXT, -- Needed to create enterprise (use EST name)
        edit_by_user_id INT,
        edit_at TIMESTAMPTZ
    ) ON COMMIT DROP;

    v_sql := format($$
        INSERT INTO temp_new_est (data_ctid, name, edit_by_user_id, edit_at) -- Renamed ctid to data_ctid
        SELECT ctid, name, edit_by_user_id, edit_at -- Select ctid from source, insert into data_ctid
        FROM public.%I
        WHERE ctid = ANY(%L) AND establishment_id IS NULL AND legal_unit_id IS NULL; -- Only process rows for new standalone ESTs
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
                SELECT SUBSTRING(tne.name FROM 1 FOR 16), tne.edit_by_user_id, tne.edit_at
                FROM temp_new_est tne
                RETURNING id, short_name
            )
            INSERT INTO temp_created_enterprises (data_ctid, enterprise_id) -- Renamed ctid to data_ctid
            SELECT tne.data_ctid, ie.id -- Use data_ctid from temp_new_est
            FROM temp_new_est tne
            JOIN inserted_enterprises ie ON SUBSTRING(tne.name FROM 1 FOR 16) = ie.short_name; -- Match on substring
        $$);
        RAISE DEBUG '[Job %] process_enterprise_link_for_establishment: Creating new enterprises: %', p_job_id, v_sql;
        EXECUTE v_sql;

    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
        RAISE WARNING '[Job %] process_enterprise_link_for_establishment: Error during enterprise creation: %', p_job_id, error_message;
        -- Mark affected rows as error
        v_sql := format($$
            UPDATE public.%I dt SET
                state = %L,
                error = COALESCE(dt.error, %L) || jsonb_build_object(''enterprise_link_for_establishment'', ''Failed to create enterprise: '' || %L),
                last_completed_priority = %L
            FROM temp_new_est tne
            WHERE dt.ctid = tne.data_ctid; -- Use data_ctid for join
        $$, v_data_table_name, 'error', '{}'::jsonb, error_message, v_step.priority - 1);
        EXECUTE v_sql;
        GET DIAGNOSTICS v_error_count = ROW_COUNT;
        -- Update job error
        UPDATE public.import_job SET error = jsonb_build_object('process_enterprise_link_for_establishment_error', error_message) WHERE id = p_job_id;
        -- Skip further processing for this batch if creation failed
        IF NOT statbus_constraints_already_deferred THEN SET CONSTRAINTS ALL IMMEDIATE; END IF;
        RAISE DEBUG '[Job %] process_enterprise_link_for_establishment (Batch): Finished operation due to error. Errors: %', p_job_id, v_error_count;
        RETURN;
    END;

    -- Step 3: Update _data table for newly created enterprises
    v_sql := format($$
        UPDATE public.%I dt SET
            enterprise_id = tce.enterprise_id,
            last_completed_priority = %L,
            error = NULL,
            state = %L
        FROM temp_created_enterprises tce
        WHERE dt.ctid = tce.data_ctid; -- Use data_ctid for join
    $$, v_data_table_name, v_step.priority, 'processing');
    RAISE DEBUG '[Job %] process_enterprise_link_for_establishment: Updating _data for new enterprises: %', p_job_id, v_sql;
    EXECUTE v_sql;
    GET DIAGNOSTICS v_update_count = ROW_COUNT;

    -- Step 4: Update rows that were already processed by analyse step (existing ESTs) - just advance priority
    v_sql := format($$
        UPDATE public.%I dt SET
            last_completed_priority = %L,
            state = %L
        WHERE dt.ctid = ANY(%L)
          AND dt.establishment_id IS NOT NULL -- Only update rows for existing ESTs
          AND dt.legal_unit_id IS NULL -- Ensure it's a standalone EST import row
          AND dt.state != %L; -- Avoid rows already in error
    $$, v_data_table_name, v_step.priority, 'processing', p_batch_ctids, 'error');
     RAISE DEBUG '[Job %] process_enterprise_link_for_establishment: Updating existing ESTs (priority only): %', p_job_id, v_sql;
    EXECUTE v_sql;


    -- Reset constraints if they were deferred by this function
    IF NOT statbus_constraints_already_deferred THEN
        SET CONSTRAINTS ALL IMMEDIATE;
    END IF;

    RAISE DEBUG '[Job %] process_enterprise_link_for_establishment (Batch): Finished operation. Created % enterprises.', p_job_id, v_update_count;

    DROP TABLE IF EXISTS temp_new_est;
    DROP TABLE IF EXISTS temp_created_enterprises;
END;
$process_enterprise_link_for_establishment$;

COMMIT;

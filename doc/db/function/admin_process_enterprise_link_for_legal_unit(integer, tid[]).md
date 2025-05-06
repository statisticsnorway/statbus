```sql
CREATE OR REPLACE PROCEDURE admin.process_enterprise_link_for_legal_unit(IN p_job_id integer, IN p_batch_ctids tid[])
 LANGUAGE plpgsql
AS $procedure$
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
        ctid TID PRIMARY KEY,
        name TEXT, -- Needed to create enterprise
        edit_by_user_id INT,
        edit_at TIMESTAMPTZ
    ) ON COMMIT DROP;

    v_sql := format($$
        INSERT INTO temp_new_lu (ctid, name, edit_by_user_id, edit_at)
        SELECT ctid, name, edit_by_user_id, edit_at
        FROM public.%I
        WHERE ctid = ANY(%L) AND legal_unit_id IS NULL; -- Only process rows for new LUs
    $$, v_data_table_name, p_batch_ctids);
    EXECUTE v_sql;

    -- Step 2: Batch INSERT new enterprises
    CREATE TEMP TABLE temp_created_enterprises (
        ctid TID PRIMARY KEY,
        enterprise_id INT NOT NULL
    ) ON COMMIT DROP;

    BEGIN
        v_sql := format($$
            WITH inserted_enterprises AS (
                INSERT INTO public.enterprise (name, edit_by_user_id, edit_at)
                SELECT tnl.name, tnl.edit_by_user_id, tnl.edit_at
                FROM temp_new_lu tnl
                RETURNING id, name -- Assuming name can roughly link back for now
            )
            INSERT INTO temp_created_enterprises (ctid, enterprise_id)
            SELECT tnl.ctid, ie.id
            FROM temp_new_lu tnl
            JOIN inserted_enterprises ie ON tnl.name = ie.name; -- Linking back via name is weak, needs improvement if names aren't unique
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
                error = COALESCE(dt.error, %L) || jsonb_build_object(''enterprise_link_for_legal_unit'', ''Failed to create enterprise: '' || %L),
                last_completed_priority = %L
            FROM temp_new_lu tnl
            WHERE dt.ctid = tnl.ctid;
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
        WHERE dt.ctid = tce.ctid;
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

END;
$procedure$
```

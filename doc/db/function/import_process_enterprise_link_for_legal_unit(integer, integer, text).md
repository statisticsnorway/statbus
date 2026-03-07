```sql
CREATE OR REPLACE PROCEDURE import.process_enterprise_link_for_legal_unit(IN p_job_id integer, IN p_batch_seq integer, IN p_step_code text)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_job public.import_job;
    v_step public.import_step;
    v_data_table_name TEXT;
    v_sql TEXT;
    v_update_count INT := 0;
    v_created_enterprise_count INT := 0;
    error_message TEXT; -- For main exception handler
    rec_new_lu RECORD;
    new_enterprise_id INT;
    v_job_mode public.import_mode;
BEGIN
    RAISE DEBUG '[Job %] process_enterprise_link_for_legal_unit (Batch): Starting operation for batch_seq %', p_job_id, p_batch_seq;

    -- Get job details
    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;
    v_job_mode := (v_job.definition_snapshot->'import_definition'->>'mode')::public.import_mode;

    -- Find the step details from the snapshot
    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = 'enterprise_link_for_legal_unit';
    IF NOT FOUND THEN RAISE EXCEPTION '[Job %] enterprise_link_for_legal_unit step not found in snapshot', p_job_id; END IF;

    IF v_job_mode != 'legal_unit' THEN
        RAISE DEBUG '[Job %] process_enterprise_link_for_legal_unit: Skipping, job mode is %, not ''legal_unit''. No action needed.', p_job_id, v_job_mode;
        RETURN;
    END IF;

    -- Step 1: Identify rows needing enterprise creation (new LUs, action = 'insert')
    IF to_regclass('pg_temp.temp_new_lu_for_enterprise_creation') IS NOT NULL THEN DROP TABLE temp_new_lu_for_enterprise_creation; END IF;
    CREATE TEMP TABLE temp_new_lu_for_enterprise_creation (
        data_row_id INTEGER PRIMARY KEY, -- This will be the founding_row_id for the new LU entity
        edit_by_user_id INT,
        edit_at TIMESTAMPTZ,
        edit_comment TEXT
    ) ON COMMIT DROP;

    v_sql := format($$
        INSERT INTO temp_new_lu_for_enterprise_creation (data_row_id, edit_by_user_id, edit_at, edit_comment)
        SELECT dt.row_id, dt.edit_by_user_id, dt.edit_at, dt.edit_comment
        FROM public.%1$I dt
        WHERE dt.batch_seq = $1
          AND dt.action = 'use' AND dt.legal_unit_id IS NULL AND dt.founding_row_id = dt.row_id; -- Only process founding rows for new LUs
    $$, v_data_table_name /* %1$I */);
    RAISE DEBUG '[Job %] process_enterprise_link_for_legal_unit: Populating temp table for new LUs with SQL: %', p_job_id, v_sql;
    EXECUTE v_sql USING p_batch_seq;

    -- Step 2: Create new enterprises for LUs in temp_new_lu_for_enterprise_creation and map them
    -- temp_created_enterprises.data_row_id will store the founding_row_id of the LU
    IF to_regclass('pg_temp.temp_created_enterprises') IS NOT NULL THEN DROP TABLE temp_created_enterprises; END IF;
    CREATE TEMP TABLE temp_created_enterprises (
        data_row_id INTEGER PRIMARY KEY, -- Stores the founding_row_id of the LU
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
            FROM temp_new_lu_for_enterprise_creation t
            RETURNING id
        ),
        -- This mapping is tricky because INSERT...RETURNING doesn't give us back the source rows.
        -- We rely on the fact that the order should be preserved and join by row_number.
        -- This is safe as we are in a single transaction and not using parallel workers.
        source_with_rn AS (
            SELECT *, ROW_NUMBER() OVER () as rn FROM temp_new_lu_for_enterprise_creation
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
        RAISE WARNING '[Job %] process_enterprise_link_for_legal_unit: Programming error suspected during enterprise creation loop: %', p_job_id, replace(error_message, '%', '%%');
        UPDATE public.import_job SET error = jsonb_build_object('programming_error_process_enterprise_link_lu', error_message) WHERE id = p_job_id;
        -- Constraints and temp table cleanup will be handled by the main exception block or successful completion
        RAISE; 
    END;

    RAISE DEBUG '[Job %] process_enterprise_link_for_legal_unit: Created % new enterprises.', p_job_id, v_created_enterprise_count;

    -- Step 3: Update _data table for newly created enterprises (action = 'insert')
    -- For new LUs linked to new Enterprises, all their initial slices are primary.
    v_sql := format($$
        UPDATE public.%1$I dt SET
            enterprise_id = tce.enterprise_id,
            primary_for_enterprise = TRUE, -- All slices of a new LU linked to a new Enterprise are initially primary
            state = %2$L
        FROM temp_created_enterprises tce -- tce.data_row_id is the founding_row_id
        WHERE dt.batch_seq = $1
          AND dt.founding_row_id = tce.data_row_id -- Link all rows of the entity via founding_row_id
          AND dt.action = 'use'; -- Only update usable rows
    $$, v_data_table_name /* %1$I */, 'processing'::public.import_data_state /* %2$L */);
    RAISE DEBUG '[Job %] process_enterprise_link_for_legal_unit: Updating _data for new enterprises and their related rows (action=insert): %', p_job_id, v_sql;
    EXECUTE v_sql USING p_batch_seq;
    GET DIAGNOSTICS v_update_count = ROW_COUNT;

    -- Step 4: Update rows that were already processed by analyse step (existing LUs) - just advance priority
    v_sql := format($$
        UPDATE public.%1$I dt SET
            state = %2$L::public.import_data_state
        WHERE dt.batch_seq = $1
          AND dt.action = 'use' AND dt.legal_unit_id IS NOT NULL; -- Only update rows for existing LUs
    $$, v_data_table_name /* %1$I */, 'processing' /* %2$L */);
     RAISE DEBUG '[Job %] process_enterprise_link_for_legal_unit: Updating existing LUs (action=replace, priority only): %', p_job_id, v_sql;
    EXECUTE v_sql USING p_batch_seq;

    -- Step 5: Update skipped rows (action = 'skip') - no LCP update needed in processing phase.
    GET DIAGNOSTICS v_update_count = ROW_COUNT; -- Re-using v_update_count, fine for debug
    RAISE DEBUG '[Job %] process_enterprise_link_for_legal_unit: Advanced priority for % skipped rows.', p_job_id, v_update_count;

    RAISE DEBUG '[Job %] process_enterprise_link_for_legal_unit (Batch): Finished operation. Linked % LUs to enterprises (includes new and existing).', p_job_id, v_update_count; -- v_update_count here is from the last UPDATE (skipped rows)

EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
    RAISE WARNING '[Job %] process_enterprise_link_for_legal_unit: Unhandled error during operation: %', p_job_id, replace(error_message, '%', '%%');
    -- Update job error
    UPDATE public.import_job
    SET error = jsonb_build_object('process_enterprise_link_for_legal_unit_error', error_message),
        state = 'finished'
    WHERE id = p_job_id;
    RAISE DEBUG '[Job %] process_enterprise_link_for_legal_unit: Marked job as failed due to error: %', p_job_id, error_message;
    RAISE; -- Re-raise the original exception
END;
$procedure$
```

```sql
CREATE OR REPLACE PROCEDURE admin.analyse_enterprise_link_for_legal_unit(IN p_job_id integer, IN p_batch_ctids tid[])
 LANGUAGE plpgsql
AS $procedure$
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
    CREATE TEMP TABLE temp_existing_lu (ctid TID PRIMARY KEY, legal_unit_id INT NOT NULL) ON COMMIT DROP;
    v_sql := format($$
        INSERT INTO temp_existing_lu (ctid, legal_unit_id)
        SELECT ctid, legal_unit_id
        FROM public.%I
        WHERE ctid = ANY(%L) AND legal_unit_id IS NOT NULL; -- legal_unit_id resolved by external_idents step
    $$, v_data_table_name, p_batch_ctids);
    EXECUTE v_sql;

    -- Step 2: Look up enterprise info for existing LUs
    CREATE TEMP TABLE temp_enterprise_info (ctid TID PRIMARY KEY, enterprise_id INT, is_primary BOOLEAN) ON COMMIT DROP;
    v_sql := format($$
        INSERT INTO temp_enterprise_info (ctid, enterprise_id, is_primary)
        SELECT tel.ctid, lu.enterprise_id, lu.primary_for_enterprise
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
            error = NULL,
            state = %L
        FROM temp_enterprise_info tei
        WHERE dt.ctid = tei.ctid;
    $$, v_data_table_name, v_step.priority, 'analysing');
    RAISE DEBUG '[Job %] analyse_enterprise_link_for_legal_unit: Updating existing LUs: %', p_job_id, v_sql;
    EXECUTE v_sql;
    GET DIAGNOSTICS v_update_count = ROW_COUNT;

    -- Step 4: Update remaining rows (new LUs) - just advance priority
    v_sql := format($$
        UPDATE public.%I dt SET
            last_completed_priority = %L,
            error = NULL,
            state = %L
        WHERE dt.ctid = ANY(%L)
          AND dt.legal_unit_id IS NULL -- Only update rows identified as new LUs
          AND dt.state != %L; -- Avoid rows already in error
    $$, v_data_table_name, v_step.priority, 'analysing', p_batch_ctids, 'error');
     RAISE DEBUG '[Job %] analyse_enterprise_link_for_legal_unit: Updating new LUs (priority only): %', p_job_id, v_sql;
    EXECUTE v_sql;

    RAISE DEBUG '[Job %] analyse_enterprise_link_for_legal_unit (Batch): Finished analysis. Updated % existing LUs.', p_job_id, v_update_count;

END;
$procedure$
```

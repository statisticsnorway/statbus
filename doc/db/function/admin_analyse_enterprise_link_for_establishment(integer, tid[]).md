```sql
CREATE OR REPLACE PROCEDURE admin.analyse_enterprise_link_for_establishment(IN p_job_id integer, IN p_batch_ctids tid[])
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
    RAISE DEBUG '[Job %] analyse_enterprise_link_for_establishment (Batch): Starting analysis for % rows', p_job_id, array_length(p_batch_ctids, 1);

    -- Get job details
    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;

    -- Find the step details
    SELECT * INTO v_step FROM public.import_step WHERE code = 'enterprise_link_for_establishment';
    IF NOT FOUND THEN RAISE EXCEPTION '[Job %] enterprise_link_for_establishment step not found', p_job_id; END IF;

    -- Step 1: Identify existing ESTs in the batch (should have establishment_id from external_idents step)
    CREATE TEMP TABLE temp_existing_est (ctid TID PRIMARY KEY, establishment_id INT NOT NULL) ON COMMIT DROP;
    v_sql := format($$
        INSERT INTO temp_existing_est (ctid, establishment_id)
        SELECT ctid, establishment_id
        FROM public.%I
        WHERE ctid = ANY(%L) AND establishment_id IS NOT NULL AND legal_unit_id IS NULL; -- Only standalone ESTs
    $$, v_data_table_name, p_batch_ctids);
    EXECUTE v_sql;

    -- Step 2: Look up enterprise info for existing ESTs
    CREATE TEMP TABLE temp_enterprise_info (ctid TID PRIMARY KEY, enterprise_id INT) ON COMMIT DROP;
    v_sql := format($$
        INSERT INTO temp_enterprise_info (ctid, enterprise_id)
        SELECT tee.ctid, est.enterprise_id
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
            error = NULL,
            state = %L
        FROM temp_enterprise_info tei
        WHERE dt.ctid = tei.ctid;
    $$, v_data_table_name, v_step.priority, 'analysing');
    RAISE DEBUG '[Job %] analyse_enterprise_link_for_establishment: Updating existing ESTs: %', p_job_id, v_sql;
    EXECUTE v_sql;
    GET DIAGNOSTICS v_update_count = ROW_COUNT;

    -- Step 4: Update remaining rows (new ESTs) - just advance priority
    v_sql := format($$
        UPDATE public.%I dt SET
            last_completed_priority = %L,
            error = NULL,
            state = %L
        WHERE dt.ctid = ANY(%L)
          AND dt.establishment_id IS NULL -- Only update rows identified as new ESTs
          AND dt.legal_unit_id IS NULL -- Ensure it's a standalone EST import row
          AND dt.state != %L; -- Avoid rows already in error
    $$, v_data_table_name, v_step.priority, 'analysing', p_batch_ctids, 'error');
     RAISE DEBUG '[Job %] analyse_enterprise_link_for_establishment: Updating new ESTs (priority only): %', p_job_id, v_sql;
    EXECUTE v_sql;

    RAISE DEBUG '[Job %] analyse_enterprise_link_for_establishment (Batch): Finished analysis. Updated % existing ESTs.', p_job_id, v_update_count;

END;
$procedure$
```

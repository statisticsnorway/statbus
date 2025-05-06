```sql
CREATE OR REPLACE PROCEDURE admin.analyse_activity(IN p_job_id integer, IN p_batch_ctids tid[])
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_job public.import_job;
    v_step RECORD;
    v_data_table_name TEXT;
    v_error_ctids TID[] := ARRAY[]::TID[];
    v_error_count INT := 0;
    v_update_count INT := 0;
    v_sql TEXT;
    v_current_target_priority INT;
BEGIN
    RAISE DEBUG '[Job %] analyse_activity (Batch): Starting analysis for % rows', p_job_id, array_length(p_batch_ctids, 1);

    -- Get job details
    SELECT * INTO v_job FROM public.import_job ij WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name; -- Assign separately

    -- Determine which target (Primary or Secondary) is likely being processed
    EXECUTE format('SELECT MIN(last_completed_priority) FROM public.%I WHERE ctid = ANY(%L)',
                   v_data_table_name, p_batch_ctids)
    INTO v_current_target_priority;

    SELECT * INTO v_step
    FROM public.import_step
    WHERE priority > v_current_target_priority AND name IN ('primary_activity', 'secondary_activity')
    ORDER BY priority
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE WARNING '[Job %] analyse_activity: Could not determine current activity target based on priority %. Skipping.', p_job_id, v_current_target_priority;
        RETURN;
    END IF;

    RAISE DEBUG '[Job %] analyse_activity: Determined target as % (priority %)', p_job_id, v_step.name, v_step.priority;

    -- Step 1: Batch Update Lookups
    v_sql := format('
        UPDATE public.%I dt SET
            primary_activity_category_id = pac.id,
            secondary_activity_category_id = sac.id
        FROM unnest(%L::TID[]) AS batch(data_ctid)
        LEFT JOIN public.activity_category pac ON dt.primary_activity_category_code IS NOT NULL AND pac.code = dt.primary_activity_category_code
        LEFT JOIN public.activity_category sac ON dt.secondary_activity_category_code IS NOT NULL AND sac.code = dt.secondary_activity_category_code
        WHERE dt.ctid = batch.data_ctid;
    ', v_data_table_name, p_batch_ctids);
    RAISE DEBUG '[Job %] analyse_activity: Batch updating lookups: %', p_job_id, v_sql;
    EXECUTE v_sql;

    -- Step 2: Identify and Aggregate Errors Post-Batch
    CREATE TEMP TABLE temp_batch_errors (data_ctid TID PRIMARY KEY, error_jsonb JSONB) ON COMMIT DROP;
    v_sql := format($$
        INSERT INTO temp_batch_errors (data_ctid, error_jsonb)
        SELECT
            ctid,
            jsonb_strip_nulls(
                jsonb_build_object(''primary_activity_category_code'', CASE WHEN primary_activity_category_code IS NOT NULL AND primary_activity_category_id IS NULL THEN ''Not found'' ELSE NULL END) ||
                jsonb_build_object(''secondary_activity_category_code'', CASE WHEN secondary_activity_category_code IS NOT NULL AND secondary_activity_category_id IS NULL THEN ''Not found'' ELSE NULL END)
            ) AS error_jsonb
        FROM public.%I
        WHERE ctid = ANY(%L)
    $$, v_data_table_name, p_batch_ctids);
     RAISE DEBUG '[Job %] analyse_activity: Identifying errors post-batch: %', p_job_id, v_sql;
     EXECUTE v_sql;

    -- Step 3: Batch Update Error Rows
    v_sql := format($$
        UPDATE public.%I dt SET
            state = %L,
            error = COALESCE(dt.error, %L) || err.error_jsonb,
            last_completed_priority = %L
        FROM temp_batch_errors err
        WHERE dt.ctid = err.data_ctid AND err.error_jsonb != %L;
    $$, v_data_table_name, 'error', '{}'::jsonb, v_step.priority - 1, '{}'::jsonb);
    RAISE DEBUG '[Job %] analyse_activity: Updating error rows: %', p_job_id, v_sql;
    EXECUTE v_sql;
    GET DIAGNOSTICS v_update_count = ROW_COUNT;
    v_error_count := v_update_count;
    SELECT array_agg(data_ctid) INTO v_error_ctids FROM temp_batch_errors WHERE error_jsonb != '{}'::jsonb;
    RAISE DEBUG '[Job %] analyse_activity: Marked % rows as error.', p_job_id, v_update_count;

    -- Step 4: Batch Update Success Rows
    v_sql := format($$
        UPDATE public.%I dt SET
            last_completed_priority = %L,
            error = NULL, -- Clear errors if successful now
            state = %L
        WHERE dt.ctid = ANY(%L) AND dt.ctid != ALL(%L); -- Update only non-error rows from the original batch
    $$, v_data_table_name, v_step.priority, 'analysing', p_batch_ctids, COALESCE(v_error_ctids, ARRAY[]::TID[]));
    RAISE DEBUG '[Job %] analyse_activity: Updating success rows: %', p_job_id, v_sql;
    EXECUTE v_sql;
    GET DIAGNOSTICS v_update_count = ROW_COUNT;
    RAISE DEBUG '[Job %] analyse_activity: Marked % rows as success for this target.', p_job_id, v_update_count;

    RAISE DEBUG '[Job %] analyse_activity (Batch): Finished analysis for batch. Total errors in batch: %', p_job_id, v_error_count;
END;
$procedure$
```

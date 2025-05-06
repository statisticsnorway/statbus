```sql
CREATE OR REPLACE PROCEDURE admin.process_tags(IN p_job_id integer, IN p_batch_ctids tid[])
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_job public.import_job;
    v_snapshot JSONB;
    v_definition JSONB;
    v_step RECORD;
    v_strategy public.import_strategy;
    v_edit_by_user_id INT;
    v_timestamp TIMESTAMPTZ := clock_timestamp();
    v_data_table_name TEXT;
    v_sql TEXT;
    v_error_count INT := 0;
    v_update_count INT := 0;
    statbus_constraints_already_deferred BOOLEAN;
    error_message TEXT;
BEGIN
    RAISE DEBUG '[Job %] process_tags (Batch): Starting operation for % rows', p_job_id, array_length(p_batch_ctids, 1);

    -- Get job details and snapshot
    SELECT * INTO v_job FROM public.import_job ij WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name; -- Assign separately
    v_definition := v_job.definition_snapshot->'import_definition'; -- Read from snapshot column

    IF v_definition IS NULL OR jsonb_typeof(v_definition) != 'object' THEN
        RAISE EXCEPTION '[Job %] Failed to load valid import_definition object from definition_snapshot', p_job_id;
    END IF;

    -- Find the target step details
    SELECT * INTO v_step FROM public.import_step WHERE code = 'tags';
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] tags target not found', p_job_id;
    END IF;

    -- Determine operation type and user ID
    v_strategy := (v_definition->>'strategy')::public.import_strategy;
    v_edit_by_user_id := v_job.user_id;

    -- Check if constraints are already deferred
    SELECT COALESCE(NULLIF(current_setting('statbus.constraints_already_deferred', true),'')::boolean,false) INTO statbus_constraints_already_deferred;
    IF NOT statbus_constraints_already_deferred THEN
        SET CONSTRAINTS ALL DEFERRED;
    END IF;

    -- Step 1: Fetch batch data into a temporary table
    CREATE TEMP TABLE temp_batch_data (
        ctid TID PRIMARY KEY,
        legal_unit_id INT,
        establishment_id INT,
        tag_id INT,
        existing_link_id INT
    ) ON COMMIT DROP;

    v_sql := format('
        INSERT INTO temp_batch_data (ctid, legal_unit_id, establishment_id, tag_id)
        SELECT ctid, legal_unit_id, establishment_id, tag_id
        FROM public.%I WHERE ctid = ANY(%L) AND tag_id IS NOT NULL; -- Only process rows with a tag_id
    ', v_data_table_name, p_batch_ctids);
    RAISE DEBUG '[Job %] process_tags: Fetching batch data: %', p_job_id, v_sql;
    EXECUTE v_sql;

    -- Step 2: Determine existing link IDs (tag_for_unit)
    v_sql := format('
        UPDATE temp_batch_data tbd SET
            existing_link_id = tfu.id
        FROM public.tag_for_unit tfu
        WHERE tfu.tag_id = tbd.tag_id
          AND tfu.legal_unit_id IS NOT DISTINCT FROM tbd.legal_unit_id
          AND tfu.establishment_id IS NOT DISTINCT FROM tbd.establishment_id;
    ');
    RAISE DEBUG '[Job %] process_tags: Determining existing link IDs: %', p_job_id, v_sql;
    EXECUTE v_sql;

    -- Step 3: Perform Batch INSERT/UPDATE/UPSERT on tag_for_unit
    -- Since tag_for_unit is NOT temporal, we handle operations directly.
    BEGIN
        IF v_strategy = 'insert_only' THEN
            v_sql := format('
                INSERT INTO public.tag_for_unit (tag_id, legal_unit_id, establishment_id, edit_by_user_id, edit_at)
                SELECT tbd.tag_id, tbd.legal_unit_id, tbd.establishment_id, dt.edit_by_user_id, dt.edit_at
                FROM temp_batch_data tbd
                JOIN public.%I dt ON tbd.ctid = dt.ctid -- Join to get audit info
                WHERE tbd.existing_link_id IS NULL;
            ', v_data_table_name);
        ELSIF v_strategy = 'update_only' THEN
            v_sql := format('
                UPDATE public.tag_for_unit tfu SET
                    edit_by_user_id = dt.edit_by_user_id, edit_at = dt.edit_at
                FROM temp_batch_data tbd
                JOIN public.%I dt ON tbd.ctid = dt.ctid -- Join to get audit info
                WHERE tfu.id = tbd.existing_link_id;
            ', v_data_table_name);
        ELSIF v_strategy = 'upsert' THEN
             v_sql := format('
                INSERT INTO public.tag_for_unit (tag_id, legal_unit_id, establishment_id, edit_by_user_id, edit_at)
                SELECT tbd.tag_id, tbd.legal_unit_id, tbd.establishment_id, dt.edit_by_user_id, dt.edit_at
                FROM temp_batch_data tbd
                JOIN public.%I dt ON tbd.ctid = dt.ctid -- Join to get audit info
                ON CONFLICT (tag_id, legal_unit_id, establishment_id) DO UPDATE SET -- Use natural key constraint
                    edit_by_user_id = EXCLUDED.edit_by_user_id,
                    edit_at = EXCLUDED.edit_at;
            ', v_data_table_name);
        END IF;

        RAISE DEBUG '[Job %] process_tags: Performing batch %: %', p_job_id, v_strategy, v_sql;
        EXECUTE v_sql;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;

        -- Step 3b: Update _data table with resulting tag_for_unit_id (Post-operation)
        v_sql := format('
            WITH link_lookup AS (
                 SELECT id as link_id, tag_id, legal_unit_id, establishment_id
                 FROM public.tag_for_unit
            )
            UPDATE public.%I dt SET
                tag_for_unit_id = ll.link_id,
                last_completed_priority = %L,
                error = NULL,
                state = %L
            FROM temp_batch_data tbd
            JOIN link_lookup ll ON ll.tag_id = tbd.tag_id
                               AND ll.legal_unit_id IS NOT DISTINCT FROM tbd.legal_unit_id
                               AND ll.establishment_id IS NOT DISTINCT FROM tbd.establishment_id
            WHERE dt.ctid = tbd.ctid
              AND dt.state != %L
              AND CASE %L::public.import_strategy
                    WHEN ''insert_only'' THEN tbd.existing_link_id IS NULL
                    WHEN ''update_only'' THEN tbd.existing_link_id IS NOT NULL
                    WHEN ''upsert'' THEN TRUE
                  END;
        ', v_data_table_name, v_step.priority, 'importing', 'error', v_strategy);
        RAISE DEBUG '[Job %] process_tags: Updating _data table with final IDs: %', p_job_id, v_sql;
        EXECUTE v_sql;

    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
        RAISE WARNING '[Job %] process_tags: Error during batch operation: %', p_job_id, error_message;
        -- Mark the entire batch as error in _data table
        v_sql := format('UPDATE public.%I SET state = %L, error = %L, last_completed_priority = %L WHERE ctid = ANY(%L)',
                       v_data_table_name, 'error', jsonb_build_object('batch_error', error_message), v_step.priority - 1, p_batch_ctids);
        EXECUTE v_sql;
        GET DIAGNOSTICS v_error_count = ROW_COUNT;
        -- Update job error
        UPDATE public.import_job SET error = jsonb_build_object('process_tags_error', error_message) WHERE id = p_job_id;
    END;

     -- Update priority for rows that didn't have a tag_id (were skipped)
     v_sql := format('
        UPDATE public.%I dt SET
            last_completed_priority = %L
        WHERE dt.ctid = ANY(%L) AND dt.state != %L AND dt.tag_id IS NULL;
    ', v_data_table_name, v_step.priority, p_batch_ctids, 'error');
    EXECUTE v_sql;

    -- Reset constraints if they were deferred by this function
    IF NOT statbus_constraints_already_deferred THEN
        SET CONSTRAINTS ALL IMMEDIATE;
    END IF;

    RAISE DEBUG '[Job %] process_tags (Batch): Finished operation for batch. Initial batch size: %. Errors (estimated): %', p_job_id, array_length(p_batch_ctids, 1), v_error_count;
END;
$procedure$
```

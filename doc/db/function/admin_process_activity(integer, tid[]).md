```sql
CREATE OR REPLACE PROCEDURE admin.process_activity(IN p_job_id integer, IN p_batch_ctids tid[])
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
    v_current_target_priority INT;
    v_activity_type public.activity_type;
    v_category_id_col TEXT;
    v_final_id_col TEXT;
BEGIN
    RAISE DEBUG '[Job %] process_activity (Batch): Starting operation for % rows', p_job_id, array_length(p_batch_ctids, 1);

    -- Get job details and snapshot
    SELECT * INTO v_job FROM public.import_job ij WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name; -- Assign separately
    v_definition := v_job.definition_snapshot->'import_definition'; -- Read from snapshot column

    IF v_definition IS NULL OR jsonb_typeof(v_definition) != 'object' THEN
        RAISE EXCEPTION '[Job %] Failed to load valid import_definition object from definition_snapshot', p_job_id;
    END IF;

    -- Determine which target step (Primary or Secondary) is likely being processed
    EXECUTE format('SELECT MIN(last_completed_priority) FROM public.%I WHERE ctid = ANY(%L)',
                   v_data_table_name, p_batch_ctids)
    INTO v_current_target_priority;

    SELECT * INTO v_step
    FROM public.import_step
    WHERE priority > v_current_target_priority AND name IN ('primary_activity', 'secondary_activity')
    ORDER BY priority
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE WARNING '[Job %] process_activity: Could not determine current activity target based on priority %. Skipping.', p_job_id, v_current_target_priority;
        RETURN;
    END IF;

    RAISE DEBUG '[Job %] process_activity: Determined target as % (priority %)', p_job_id, v_step.name, v_step.priority;
    v_activity_type := CASE v_step.name WHEN 'primary_activity' THEN 'primary' WHEN 'secondary_activity' THEN 'secondary' END;
    v_category_id_col := CASE v_activity_type WHEN 'primary' THEN 'primary_activity_category_id' ELSE 'secondary_activity_category_id' END;
    v_final_id_col := CASE v_activity_type WHEN 'primary' THEN 'primary_activity_id' ELSE 'secondary_activity_id' END;

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
        data_ctid TID PRIMARY KEY,
        legal_unit_id INT,
        establishment_id INT,
        valid_from DATE,
        valid_to DATE,
        data_source_id INT,
        category_id INT,
        existing_act_id INT
    ) ON COMMIT DROP;

    v_sql := format('
        INSERT INTO temp_batch_data (
            data_ctid, legal_unit_id, establishment_id, valid_from, valid_to, data_source_id, category_id
        )
        SELECT
            ctid, legal_unit_id, establishment_id,
            COALESCE(typed_valid_from, computed_valid_from),
            COALESCE(typed_valid_to, computed_valid_to),
            data_source_id,
            %I -- Select the correct category ID column based on target
         FROM public.%I WHERE ctid = ANY(%L) AND %I IS NOT NULL; -- Only process rows with a category ID for this type
    ', v_category_id_col, v_data_table_name, p_batch_ctids, v_category_id_col);
    RAISE DEBUG '[Job %] process_activity: Fetching batch data for type %: %', p_job_id, v_activity_type, v_sql;
    EXECUTE v_sql;

    -- Step 2: Determine existing activity IDs
    v_sql := format('
        UPDATE temp_batch_data tbd SET
            existing_act_id = act.id
        FROM public.activity act
        WHERE act.type = %L
          AND act.category_id = tbd.category_id
          AND act.legal_unit_id IS NOT DISTINCT FROM tbd.legal_unit_id
          AND act.establishment_id IS NOT DISTINCT FROM tbd.establishment_id;
    ', v_activity_type);
    RAISE DEBUG '[Job %] process_activity: Determining existing IDs: %', p_job_id, v_sql;
    EXECUTE v_sql;

    -- Step 3: Perform Batch INSERT into activity_era (Leveraging Trigger)
    BEGIN
        v_sql := format('
            INSERT INTO public.activity_era (
                id, legal_unit_id, establishment_id, type, category_id, valid_from, valid_to,
                data_source_id, edit_by_user_id, edit_at
            )
            SELECT
                tbd.existing_act_id, tbd.legal_unit_id, tbd.establishment_id, %L, tbd.category_id, tbd.valid_from, tbd.valid_to,
                tbd.data_source_id, dt.edit_by_user_id, dt.edit_at -- Read from _data table via temp table join
            FROM temp_batch_data tbd
            JOIN public.%I dt ON tbd.data_ctid = dt.ctid -- Join to get audit info
            WHERE
                CASE %L::public.import_strategy
                    WHEN ''insert_only'' THEN tbd.existing_act_id IS NULL
                    WHEN ''update_only'' THEN tbd.existing_act_id IS NOT NULL
                    WHEN ''upsert'' THEN TRUE
                END;
        ', v_activity_type, v_data_table_name, v_strategy); -- Removed v_edit_by_user_id, v_timestamp

        RAISE DEBUG '[Job %] process_activity: Performing batch INSERT into activity_era: %', p_job_id, v_sql;
        EXECUTE v_sql;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;

        -- Step 3b: Update _data table with resulting activity_id (Post-INSERT)
        v_sql := format($$
            WITH act_lookup AS (
                 SELECT DISTINCT ON (legal_unit_id, establishment_id, category_id)
                        id as activity_id, legal_unit_id, establishment_id, category_id
                 FROM public.activity
                 WHERE type = %L
                 ORDER BY legal_unit_id, establishment_id, category_id, id DESC
            )
            UPDATE public.%I dt SET
                %I = act.activity_id, -- Set primary_activity_id or secondary_activity_id
                last_completed_priority = %L,
                error = NULL,
                state = %L
            FROM temp_batch_data tbd
            JOIN act_lookup act ON act.category_id = tbd.category_id
                               AND act.legal_unit_id IS NOT DISTINCT FROM tbd.legal_unit_id
                               AND act.establishment_id IS NOT DISTINCT FROM tbd.establishment_id
            WHERE dt.ctid = tbd.data_ctid
              AND dt.state != %L
              AND CASE %L::public.import_strategy
                    WHEN ''insert_only'' THEN tbd.existing_act_id IS NULL
                    WHEN ''update_only'' THEN tbd.existing_act_id IS NOT NULL
                    WHEN ''upsert'' THEN TRUE
                  END;
        $$, v_activity_type, v_data_table_name, v_final_id_col, v_step.priority, 'importing', 'error', v_strategy);
        RAISE DEBUG '[Job %] process_activity: Updating _data table with final IDs: %', p_job_id, v_sql;
        EXECUTE v_sql;

    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
        RAISE WARNING '[Job %] process_activity: Error during batch operation for type %: %', p_job_id, v_activity_type, error_message;
        -- Mark the entire batch as error in _data table
        v_sql := format('UPDATE public.%I SET state = %L, error = %L, last_completed_priority = %L WHERE ctid = ANY(%L)',
                       v_data_table_name, 'error', jsonb_build_object('batch_error', error_message), v_step.priority - 1, p_batch_ctids);
        EXECUTE v_sql;
        GET DIAGNOSTICS v_error_count = ROW_COUNT;
        -- Update job error
        UPDATE public.import_job SET error = jsonb_build_object('process_activity_error', format('Error for type %s: %s', v_activity_type, error_message)) WHERE id = p_job_id;
    END;

    -- Update priority for rows that didn't have the relevant category ID (were skipped)
     v_sql := format('
        UPDATE public.%I dt SET
            last_completed_priority = %L
        WHERE dt.ctid = ANY(%L) AND dt.state != %L AND %I IS NULL;
    ', v_data_table_name, v_step.priority, p_batch_ctids, 'error', v_category_id_col);
    EXECUTE v_sql;


    -- Reset constraints if they were deferred by this function
    IF NOT statbus_constraints_already_deferred THEN
        SET CONSTRAINTS ALL IMMEDIATE;
    END IF;

    RAISE DEBUG '[Job %] process_activity (Batch): Finished operation for batch type %. Initial batch size: %. Errors (estimated): %', p_job_id, v_activity_type, array_length(p_batch_ctids, 1), v_error_count;
END;
$procedure$
```

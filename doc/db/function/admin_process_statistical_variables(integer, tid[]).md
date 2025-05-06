```sql
CREATE OR REPLACE PROCEDURE admin.process_statistical_variables(IN p_job_id integer, IN p_batch_ctids tid[])
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
    v_stat_data_cols JSONB;
    v_col_rec RECORD;
    v_sql TEXT;
    v_error_count INT := 0;
    v_update_count INT := 0;
    statbus_constraints_already_deferred BOOLEAN;
    error_message TEXT;
    v_unpivot_sql TEXT := '';
    v_add_separator BOOLEAN := FALSE;
BEGIN
    RAISE DEBUG '[Job %] process_statistical_variables (Batch): Starting operation for % rows', p_job_id, array_length(p_batch_ctids, 1);

    -- Get job details and snapshot
    SELECT * INTO v_job FROM public.import_job ij WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name; -- Assign separately
    v_definition := v_job.definition_snapshot->'import_definition'; -- Read from snapshot column
    v_stat_data_cols := v_job.definition_snapshot->'import_data_column_list'; -- Read from snapshot column

    IF v_definition IS NULL OR jsonb_typeof(v_definition) != 'object' OR
       v_stat_data_cols IS NULL OR jsonb_typeof(v_stat_data_cols) != 'array' THEN
        RAISE EXCEPTION '[Job %] Failed to load valid import_definition or import_data_column_list from definition_snapshot', p_job_id;
    END IF;

    -- Find the target step details
    SELECT * INTO v_step FROM public.import_step WHERE code = 'statistical_variables';
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] statistical_variables target not found', p_job_id;
    END IF;

    -- Determine operation type and user ID
    v_strategy := (v_definition->>'strategy')::public.import_strategy;
    v_edit_by_user_id := v_job.user_id;

    -- Filter data columns relevant to this step and build unpivot logic
    v_add_separator := FALSE;
    FOR v_col_rec IN SELECT value->>'column_name' as col_name
                     FROM jsonb_array_elements(v_stat_data_cols) value -- Added alias 'value' here
                     WHERE (value->>'step_id')::int = v_step.id AND value->>'purpose' = 'source_input' -- Changed target_id to step_id
    LOOP
        IF v_add_separator THEN v_unpivot_sql := v_unpivot_sql || ' UNION ALL '; END IF;
        v_unpivot_sql := v_unpivot_sql || format('SELECT %L AS stat_code, dt.%I AS stat_value, dt.ctid FROM public.%I dt WHERE dt.%I IS NOT NULL AND dt.ctid = ANY(%L)',
                                                 v_col_rec.col_name, v_col_rec.col_name, v_data_table_name, v_col_rec.col_name, p_batch_ctids);
        v_add_separator := TRUE;
    END LOOP;

    IF v_unpivot_sql = '' THEN
         RAISE DEBUG '[Job %] process_statistical_variables: No stat data columns found in snapshot for target %. Skipping operation.', p_job_id, v_step.id;
         EXECUTE format('UPDATE public.%I SET last_completed_priority = %L WHERE ctid = ANY(%L)',
                        v_data_table_name, v_step.priority, p_batch_ctids);
         RETURN;
    END IF;

    -- Check if constraints are already deferred
    SELECT COALESCE(NULLIF(current_setting('statbus.constraints_already_deferred', true),'')::boolean,false) INTO statbus_constraints_already_deferred;
    IF NOT statbus_constraints_already_deferred THEN
        SET CONSTRAINTS ALL DEFERRED;
    END IF;

    -- Step 1: Unpivot and Fetch batch data into a temporary table
    CREATE TEMP TABLE temp_batch_data (
        data_ctid TID,
        legal_unit_id INT,
        establishment_id INT,
        valid_from DATE,
        valid_to DATE,
        data_source_id INT,
        stat_definition_id INT,
        stat_value TEXT,
        existing_link_id INT,
        PRIMARY KEY (data_ctid, stat_definition_id) -- Ensure uniqueness per row/stat
    ) ON COMMIT DROP;

    v_sql := format('
        WITH unpivoted_stats AS ( %s )
        INSERT INTO temp_batch_data (
            data_ctid, legal_unit_id, establishment_id, valid_from, valid_to, data_source_id,
            stat_definition_id, stat_value
        )
        SELECT
            up.data_ctid, dt.legal_unit_id, dt.establishment_id,
            COALESCE(dt.typed_valid_from, dt.computed_valid_from),
            COALESCE(dt.typed_valid_to, dt.computed_valid_to),
            dt.data_source_id,
            sd.id, up.stat_value
        FROM unpivoted_stats up
        JOIN public.%I dt ON up.data_ctid = dt.ctid
        JOIN public.stat_definition sd ON sd.code = up.stat_code; -- Join to get definition ID
    ', v_unpivot_sql, v_data_table_name);
    RAISE DEBUG '[Job %] process_statistical_variables: Fetching and unpivoting batch data: %', p_job_id, v_sql;
    EXECUTE v_sql;

    -- Step 2: Determine existing link IDs (stat_for_unit)
    v_sql := format('
        UPDATE temp_batch_data tbd SET
            existing_link_id = sfu.id
        FROM public.stat_for_unit sfu
        WHERE sfu.stat_definition_id = tbd.stat_definition_id -- Use stat_definition_id
          AND sfu.legal_unit_id IS NOT DISTINCT FROM tbd.legal_unit_id
          AND sfu.establishment_id IS NOT DISTINCT FROM tbd.establishment_id;
    ');
    RAISE DEBUG '[Job %] process_statistical_variables: Determining existing link IDs: %', p_job_id, v_sql;
    EXECUTE v_sql;

    -- Step 3: Perform Batch INSERT into stat_for_unit_era (Leveraging Trigger)
    BEGIN
        v_sql := format('
            INSERT INTO public.stat_for_unit_era (
                id, stat_definition_id, legal_unit_id, establishment_id, value, valid_from, valid_to, -- Use stat_definition_id
                data_source_id, edit_by_user_id, edit_at
            )
            SELECT
                tbd.existing_link_id, tbd.stat_definition_id, tbd.legal_unit_id, tbd.establishment_id, tbd.stat_value, tbd.valid_from, tbd.valid_to,
                tbd.data_source_id, dt.edit_by_user_id, dt.edit_at -- Read from _data table via temp table join
            FROM temp_batch_data tbd
            JOIN public.%I dt ON tbd.data_ctid = dt.ctid -- Join to get audit info
            WHERE
                CASE %L::public.import_strategy
                    WHEN ''insert_only'' THEN tbd.existing_link_id IS NULL
                    WHEN ''update_only'' THEN tbd.existing_link_id IS NOT NULL
                    WHEN ''upsert'' THEN TRUE
                END;
        ', v_data_table_name, v_strategy); -- Removed v_edit_by_user_id, v_timestamp

        RAISE DEBUG '[Job %] process_statistical_variables: Performing batch INSERT into stat_for_unit_era: %', p_job_id, v_sql;
        EXECUTE v_sql;
        GET DIAGNOSTICS v_update_count = ROW_COUNT; -- Count of rows INSERTED into _era

        -- Step 3b: Update _data table with resulting stat_for_unit IDs (Post-INSERT)
        -- This needs to update the dynamic columns like stat_for_unit_employees_id
        DECLARE
            v_update_sql TEXT := '';
            v_stat_def RECORD;
            v_pk_col_name TEXT;
        BEGIN
            v_update_sql := format('UPDATE public.%I dt SET last_completed_priority = %L, error = NULL, state = %L',
                                   v_data_table_name, v_step.priority, 'importing');

            FOR v_stat_def IN SELECT id, code FROM public.stat_definition
            LOOP
                v_pk_col_name := format('stat_for_unit_%s_id', v_stat_def.code);
                -- Check if the dynamic pk_id column exists in the snapshot for safety
                IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_stat_data_cols) val
                           WHERE val->>'column_name' = v_pk_col_name AND val->>'purpose' = 'pk_id' AND (val->>'definition_id')::int = v_job.definition_id) -- Check definition_id from snapshot
                THEN
                    v_update_sql := v_update_sql || format(
                        ', %I = (SELECT sfu.id FROM public.stat_for_unit sfu JOIN temp_batch_data tbd ON dt.ctid = tbd.data_ctid WHERE sfu.stat_definition_id = %L AND sfu.legal_unit_id IS NOT DISTINCT FROM tbd.legal_unit_id AND sfu.establishment_id IS NOT DISTINCT FROM tbd.establishment_id LIMIT 1)', -- Use stat_definition_id
                        v_pk_col_name, v_stat_def.id
                    );
                END IF;
            END LOOP;

            v_update_sql := v_update_sql || format(' WHERE dt.ctid = ANY(%L) AND dt.state != %L', p_batch_ctids, 'error');

            RAISE DEBUG '[Job %] process_statistical_variables: Updating _data table with final IDs: %', p_job_id, v_update_sql;
            EXECUTE v_update_sql;
        END;


    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
        RAISE WARNING '[Job %] process_statistical_variables: Error during batch operation: %', p_job_id, error_message;
        -- Mark the entire batch as error in _data table
        v_sql := format('UPDATE public.%I SET state = %L, error = %L, last_completed_priority = %L WHERE ctid = ANY(%L)',
                       v_data_table_name, 'error', jsonb_build_object('batch_error', error_message), v_step.priority - 1, p_batch_ctids);
        EXECUTE v_sql;
        GET DIAGNOSTICS v_error_count = ROW_COUNT;
        -- Update job error
        UPDATE public.import_job SET error = jsonb_build_object('process_statistical_variables_error', error_message) WHERE id = p_job_id;
    END;

     -- Update priority for rows that didn't have any stat variables (were skipped)
     v_sql := format('
        UPDATE public.%I dt SET
            last_completed_priority = %L
        WHERE dt.ctid = ANY(%L) AND dt.state != %L
          AND NOT EXISTS (SELECT 1 FROM temp_batch_data tbd WHERE tbd.data_ctid = dt.ctid);
    ', v_data_table_name, v_step.priority, p_batch_ctids, 'error');
    EXECUTE v_sql;

    -- Reset constraints if they were deferred by this function
    IF NOT statbus_constraints_already_deferred THEN
        SET CONSTRAINTS ALL IMMEDIATE;
    END IF;

    RAISE DEBUG '[Job %] process_statistical_variables (Batch): Finished operation for batch. Initial batch size: %. Errors (estimated): %', p_job_id, array_length(p_batch_ctids, 1), v_error_count;
END;
$procedure$
```

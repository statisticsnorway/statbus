BEGIN;

-- Procedure to analyse base establishment data (Batch Oriented)
CREATE OR REPLACE PROCEDURE admin.analyse_establishment(p_job_id INT, p_batch_row_ids BIGINT[], p_step_code TEXT)
LANGUAGE plpgsql AS $analyse_establishment$
DECLARE
    v_job public.import_job;
    v_snapshot JSONB;
    v_definition JSONB;
    v_step RECORD;
    -- v_computed_valid_from DATE; -- Removed
    -- v_computed_valid_to DATE;   -- Removed
    v_data_table_name TEXT;
    v_error_row_ids BIGINT[] := ARRAY[]::BIGINT[];
    v_error_count INT := 0;
    v_update_count INT := 0;
    v_sql TEXT;
BEGIN
    RAISE DEBUG '[Job %] analyse_establishment (Batch): Starting analysis for % rows', p_job_id, array_length(p_batch_row_ids, 1);

    -- Get job details and snapshot
    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_definition := v_job.definition_snapshot; -- Assign snapshot from the job record
    v_data_table_name := v_job.data_table_name; -- Assign separately

    IF v_definition IS NULL OR jsonb_typeof(v_definition) != 'object' THEN
        RAISE EXCEPTION '[Job %] Failed to load valid definition snapshot from import_job record', p_job_id;
    END IF;

    -- Find the target details for establishment
    SELECT * INTO v_step FROM public.import_step WHERE code = 'establishment';
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] establishment target not found', p_job_id;
    END IF;

    -- Removed logic for v_computed_valid_from/to

    -- Step 1: Batch Update Lookups
    v_sql := format('
        UPDATE public.%I dt SET
            data_source_id = src.data_source_id,
            status_id = src.status_id,
            sector_id = src.sector_id,
            unit_size_id = src.unit_size_id
        FROM (
            SELECT
                dt_sub.row_id AS row_id_for_join,
                ds.id as data_source_id,
                s.id as status_id,
                sec.id as sector_id,
                us.id as unit_size_id
            FROM public.%I dt_sub
            LEFT JOIN public.data_source ds ON dt_sub.data_source_code IS NOT NULL AND ds.code = dt_sub.data_source_code
            LEFT JOIN public.status s ON dt_sub.status_code IS NOT NULL AND s.code = dt_sub.status_code
            LEFT JOIN public.sector sec ON dt_sub.sector_code IS NOT NULL AND sec.code = dt_source.sector_code
            LEFT JOIN public.unit_size us ON dt_sub.unit_size_code IS NOT NULL AND us.code = dt_sub.unit_size_code
            WHERE dt_sub.row_id = ANY(%L) -- Filter for the batch
        ) AS src
        WHERE dt.row_id = src.row_id_for_join;
    ', v_data_table_name, v_data_table_name, p_batch_row_ids);
    RAISE DEBUG '[Job %] analyse_establishment: Batch updating lookups: %', p_job_id, v_sql;
    EXECUTE v_sql;

    -- Step 2: Batch Update Typed Dates
    v_sql := format('
        UPDATE public.%I dt SET
            typed_birth_date = admin.safe_cast_to_date(dt.birth_date),
            typed_death_date = admin.safe_cast_to_date(dt.death_date)
            -- Removed assignments to typed_valid_from/to and computed_valid_from/to
        WHERE dt.row_id = ANY(%L);
    ', v_data_table_name, p_batch_row_ids);
    RAISE DEBUG '[Job %] analyse_establishment: Batch updating typed birth/death dates: %', p_job_id, v_sql;
    EXECUTE v_sql;

    -- Step 3: Identify and Aggregate Errors Post-Batch
    CREATE TEMP TABLE temp_batch_errors (data_row_id BIGINT PRIMARY KEY, error_jsonb JSONB) ON COMMIT DROP;
    v_sql := format('
        INSERT INTO temp_batch_errors (data_row_id, error_jsonb)
        SELECT
            row_id,
            jsonb_strip_nulls(
                jsonb_build_object(''data_source_code'', CASE WHEN data_source_code IS NOT NULL AND data_source_id IS NULL THEN ''Not found'' ELSE NULL END) ||
                jsonb_build_object(''status_code'', CASE WHEN status_code IS NOT NULL AND status_id IS NULL THEN ''Not found'' ELSE NULL END) ||
                jsonb_build_object(''sector_code'', CASE WHEN sector_code IS NOT NULL AND sector_id IS NULL THEN ''Not found'' ELSE NULL END) ||
                jsonb_build_object(''unit_size_code'', CASE WHEN unit_size_code IS NOT NULL AND unit_size_id IS NULL THEN ''Not found'' ELSE NULL END) ||
                jsonb_build_object(''birth_date'', CASE WHEN birth_date IS NOT NULL AND typed_birth_date IS NULL THEN ''Invalid format'' ELSE NULL END) ||
                jsonb_build_object(''death_date'', CASE WHEN death_date IS NOT NULL AND typed_death_date IS NULL THEN ''Invalid format'' ELSE NULL END)
                -- Removed error checks for valid_from/to as they are handled by analyse_valid_time_from_source
            ) AS error_jsonb
        FROM public.%I
        WHERE row_id = ANY(%L)
    ', v_data_table_name, p_batch_row_ids);
     RAISE DEBUG '[Job %] analyse_establishment: Identifying errors post-batch: %', p_job_id, v_sql;
     EXECUTE v_sql;

    -- Step 4: Batch Update Error Rows
    v_sql := format('
        UPDATE public.%I dt SET
            state = %L,
            error = COALESCE(dt.error, %L) || err.error_jsonb,
            last_completed_priority = %L
        FROM temp_batch_errors err
        WHERE dt.row_id = err.data_row_id AND err.error_jsonb != %L;
    ', v_data_table_name, 'error', '{}'::jsonb, v_step.priority - 1, '{}'::jsonb);
    RAISE DEBUG '[Job %] analyse_establishment: Updating error rows: %', p_job_id, v_sql;
    EXECUTE v_sql;
    GET DIAGNOSTICS v_update_count = ROW_COUNT;
    v_error_count := v_update_count;
    SELECT array_agg(data_row_id) INTO v_error_row_ids FROM temp_batch_errors WHERE error_jsonb != '{}'::jsonb;
    RAISE DEBUG '[Job %] analyse_establishment: Marked % rows as error.', p_job_id, v_update_count;

    -- Step 5: Batch Update Success Rows
    v_sql := format('
        UPDATE public.%I dt SET
            last_completed_priority = %L,
            error = CASE WHEN (dt.error - ''data_source_code'' - ''status_code'' - ''sector_code'' - ''unit_size_code'' - ''birth_date'' - ''death_date'') = ''{}''::jsonb THEN NULL ELSE (dt.error - ''data_source_code'' - ''status_code'' - ''sector_code'' - ''unit_size_code'' - ''birth_date'' - ''death_date'') END, -- Clear only this step''s error keys (removed valid_from/to)
            state = %L
        WHERE dt.row_id = ANY(%L) AND dt.row_id != ALL(%L); -- Update only non-error rows from the original batch
    ', v_data_table_name, v_step.priority, 'analysing', p_batch_row_ids, COALESCE(v_error_row_ids, ARRAY[]::BIGINT[]));
    RAISE DEBUG '[Job %] analyse_establishment: Updating success rows: %', p_job_id, v_sql;
    EXECUTE v_sql;
    GET DIAGNOSTICS v_update_count = ROW_COUNT;
    RAISE DEBUG '[Job %] analyse_establishment: Marked % rows as success for this target.', p_job_id, v_update_count;

    DROP TABLE IF EXISTS temp_batch_errors;

    RAISE DEBUG '[Job %] analyse_establishment (Batch): Finished analysis for batch. Total errors in batch: %', p_job_id, v_error_count;
END;
$analyse_establishment$;


-- Procedure to operate (insert/update/upsert) base establishment data (Batch Oriented)
CREATE OR REPLACE PROCEDURE admin.process_establishment(p_job_id INT, p_batch_row_ids BIGINT[], p_step_code TEXT)
LANGUAGE plpgsql AS $process_establishment$
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
    RAISE DEBUG '[Job %] process_establishment (Batch): Starting operation for % rows', p_job_id, array_length(p_batch_row_ids, 1);

    -- Get job details and snapshot
    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_definition := v_job.definition_snapshot; -- Assign snapshot from the job record
    v_data_table_name := v_job.data_table_name; -- Assign separately

    IF v_definition IS NULL OR jsonb_typeof(v_definition) != 'object' THEN
        RAISE EXCEPTION '[Job %] Failed to load valid definition snapshot from import_job record', p_job_id;
    END IF;

    -- Find the target details for establishment
    SELECT * INTO v_step FROM public.import_step WHERE code = 'establishment';
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] establishment target not found', p_job_id;
    END IF;

    -- Determine operation type and user ID
    v_strategy := (v_definition->>'strategy')::public.import_strategy;
    v_edit_by_user_id := v_job.user_id;

    RAISE DEBUG '[Job %] process_establishment: Operation Type: %, User ID: %', p_job_id, v_strategy, v_edit_by_user_id;

    -- Check if constraints are already deferred
    SELECT COALESCE(NULLIF(current_setting('statbus.constraints_already_deferred', true),'')::boolean,false) INTO statbus_constraints_already_deferred;
    IF NOT statbus_constraints_already_deferred THEN
        SET CONSTRAINTS ALL DEFERRED;
    END IF;

    -- Step 1: Fetch batch data into a temporary table
    CREATE TEMP TABLE temp_batch_data (
        data_row_id BIGINT PRIMARY KEY,
        establishment_tax_ident TEXT, -- Keep for linking back inserts
        legal_unit_id INT, -- Populated by link_establishment_to_legal_unit step
        enterprise_id INT, -- Populated by enterprise_link_for_establishment step
        name TEXT,
        typed_birth_date DATE,
        typed_death_date DATE,
        valid_from DATE,
        valid_to DATE,
        sector_id INT,
        unit_size_id INT,
        status_id INT,
        data_source_id INT,
        existing_est_id INT -- Populated from _data table analysis result
    ) ON COMMIT DROP;

    -- Select data including the pre-resolved establishment_id and relevant link IDs
    v_sql := format($$
        INSERT INTO temp_batch_data (
            data_row_id, establishment_tax_ident, legal_unit_id, enterprise_id, name, typed_birth_date, typed_death_date,
            valid_from, valid_to, sector_id, unit_size_id, status_id, data_source_id,
            existing_est_id -- Populate directly
        )
        SELECT
            row_id,
            establishment_tax_ident, -- Still needed for linking back inserts
            legal_unit_id, -- Resolved by link_establishment_to_legal_unit step
            enterprise_id, -- Resolved by enterprise_link_for_establishment step
            name,
            typed_birth_date,
            typed_death_date,
            derived_valid_from as valid_from, -- Changed to derived_valid_from
            derived_valid_to as valid_to,     -- Changed to derived_valid_to
            sector_id,
            unit_size_id,
            status_id,
            data_source_id,
            establishment_id -- Use the ID resolved by analyse_external_idents
         FROM public.%I WHERE row_id = ANY(%L);
    $$, v_data_table_name, p_batch_row_ids);
    RAISE DEBUG '[Job %] process_establishment: Fetching batch data including pre-resolved IDs: %', p_job_id, v_sql;
    EXECUTE v_sql;

    -- Step 2: Determine existing establishment IDs (REMOVED - Handled by selecting existing_est_id above)

    -- Step 3: Perform Batch INSERT into establishment_era (Leveraging Trigger)
    BEGIN
        -- Pass EITHER legal_unit_id OR enterprise_id to the trigger based on which one is populated
        v_sql := format($$
            INSERT INTO public.establishment_era (
                id, legal_unit_id, enterprise_id, valid_from, valid_to, name, birth_date, death_date, active, edit_comment,
                sector_id, unit_size_id, status_id, data_source_id, edit_by_user_id, edit_at
            )
            SELECT
                tbd.existing_est_id, -- Provide existing ID for trigger
                tbd.legal_unit_id, -- Will be NULL for standalone ESTs
                tbd.enterprise_id, -- Will be NULL for ESTs linked to LUs
                tbd.valid_from, tbd.valid_to, tbd.name, tbd.typed_birth_date, tbd.typed_death_date, true, 'Import Job Batch',
                tbd.sector_id, tbd.unit_size_id, tbd.status_id, tbd.data_source_id, dt.edit_by_user_id, dt.edit_at -- Read from _data table via temp table join
            FROM temp_batch_data tbd
            JOIN public.%I dt ON tbd.data_row_id = dt.row_id -- Join to get audit info
            WHERE
                CASE %L::public.import_strategy -- Filter based on operation type
                    WHEN 'insert_only' THEN tbd.existing_est_id IS NULL
                    WHEN 'update_only' THEN tbd.existing_est_id IS NOT NULL
                    WHEN 'upsert' THEN TRUE
                END;
            -- RETURNING id is less useful here as we need to link back to row_id
        $$, v_data_table_name, v_strategy); -- Removed v_edit_by_user_id, v_timestamp

        RAISE DEBUG '[Job %] process_establishment: Performing batch INSERT into establishment_era: %', p_job_id, v_sql;
        EXECUTE v_sql;
        GET DIAGNOSTICS v_update_count = ROW_COUNT; -- Count of rows INSERTED into _era (or attempted)

        -- Step 3b: Update _data table with resulting establishment_id (Post-INSERT - Revised Logic)

        -- Part 1: Update rows that were UPDATES (used existing_est_id)
        v_sql := format($$
            UPDATE public.%I dt SET
                establishment_id = tbd.existing_est_id, -- Use the pre-resolved ID
                last_completed_priority = %L,
                error = NULL,
                state = %L
            FROM temp_batch_data tbd
            WHERE dt.row_id = tbd.data_row_id
              AND tbd.existing_est_id IS NOT NULL -- Identify rows that were updates
              AND dt.state != %L
              AND CASE %L::public.import_strategy
                    WHEN 'insert_only' THEN false -- Should not happen if existing_est_id is not null
                    ELSE TRUE
                  END;
        $$, v_data_table_name, v_step.priority, 'processing', 'error', v_strategy);
        RAISE DEBUG '[Job %] process_establishment: Updating _data for existing units: %', p_job_id, v_sql;
        EXECUTE v_sql;

        -- Part 2: Update rows that were INSERTS (need to lookup the new ID via tax_ident)
        v_sql := format($$
            WITH est_lookup AS (
                 SELECT DISTINCT ON (xi.ident) est.id as establishment_id, xi.ident as tax_ident
                 FROM public.establishment est
                 JOIN public.external_ident xi ON xi.establishment_id = est.id
                 JOIN public.external_ident_type xit ON xit.id = xi.type_id
                 WHERE xit.code = 'tax_ident' -- Assuming tax_ident is the unique key
                 ORDER BY xi.ident, est.id DESC -- Get latest ID in case of duplicates
            )
            UPDATE public.%I dt SET
                establishment_id = est.establishment_id, -- Use the newly found ID
                last_completed_priority = %L,
                error = NULL,
                state = %L
            FROM temp_batch_data tbd
            JOIN est_lookup est ON tbd.establishment_tax_ident IS NOT NULL AND est.tax_ident = tbd.establishment_tax_ident
            WHERE dt.row_id = tbd.data_row_id
              AND tbd.existing_est_id IS NULL -- Identify rows that were inserts
              AND dt.state != %L
              AND CASE %L::public.import_strategy
                    WHEN 'update_only' THEN false -- Should not happen if existing_est_id is null
                    ELSE TRUE
                  END;
        $$, v_data_table_name, v_step.priority, 'processing', 'error', v_strategy); -- Use 'processing' state
        RAISE DEBUG '[Job %] process_establishment: Updating _data for new units: %', p_job_id, v_sql;
        EXECUTE v_sql;

    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
        RAISE WARNING '[Job %] process_establishment: Error during batch operation: %', p_job_id, error_message;
        -- Mark the entire batch as error in _data table
        v_sql := format($$
          UPDATE public.%I SET state = %L, error = %L, last_completed_priority = %L WHERE row_id = ANY(%L)
          $$, v_data_table_name, 'error', jsonb_build_object('batch_error', error_message), v_step.priority - 1, p_batch_row_ids);
        EXECUTE v_sql;
        GET DIAGNOSTICS v_error_count = ROW_COUNT;
        -- Update job error
        UPDATE public.import_job SET error = jsonb_build_object('process_establishment_error', error_message) WHERE id = p_job_id;
    END;

    -- Reset constraints if they were deferred by this function
    IF NOT statbus_constraints_already_deferred THEN
        SET CONSTRAINTS ALL IMMEDIATE;
    END IF;

    RAISE DEBUG '[Job %] process_establishment (Batch): Finished operation for batch. Initial batch size: %. Errors (estimated): %', p_job_id, array_length(p_batch_row_ids, 1), v_error_count;

    DROP TABLE IF EXISTS temp_batch_data;
END;
$process_establishment$;

END;

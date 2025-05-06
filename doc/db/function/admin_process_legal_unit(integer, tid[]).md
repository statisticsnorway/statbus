```sql
CREATE OR REPLACE PROCEDURE admin.process_legal_unit(IN p_job_id integer, IN p_batch_ctids tid[])
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
    RAISE DEBUG '[Job %] process_legal_unit (Batch): Starting operation for % rows', p_job_id, array_length(p_batch_ctids, 1);

    -- Get job details and snapshot
    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_definition := v_job.definition_snapshot; -- Assign snapshot from the job record
    v_data_table_name := v_job.data_table_name; -- Assign from the record

    IF v_definition IS NULL OR jsonb_typeof(v_definition) != 'object' THEN
        RAISE EXCEPTION '[Job %] Failed to load valid definition snapshot from import_job record', p_job_id;
    END IF;

    -- Find the target details for legal_unit
    SELECT * INTO v_step FROM public.import_step WHERE code = 'legal_unit';
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] legal_unit target not found', p_job_id;
    END IF;

    -- Determine operation type and user ID
    v_strategy := (v_definition->>'strategy')::public.import_strategy;
    v_edit_by_user_id := v_job.user_id;

    RAISE DEBUG '[Job %] process_legal_unit: Operation Type: %, User ID: %', p_job_id, v_strategy, v_edit_by_user_id;

    -- Check if constraints are already deferred
    SELECT COALESCE(NULLIF(current_setting('statbus.constraints_already_deferred', true),'')::boolean,false) INTO statbus_constraints_already_deferred;
    IF NOT statbus_constraints_already_deferred THEN
        SET CONSTRAINTS ALL DEFERRED;
    END IF;

    -- Step 1: Fetch batch data into a temporary table
    CREATE TEMP TABLE temp_batch_data (
        ctid TID PRIMARY KEY,
        tax_ident TEXT, -- Keep for linking back inserts
        name TEXT,
        typed_birth_date DATE,
        typed_death_date DATE,
        valid_from DATE,
        valid_to DATE,
        sector_id INT,
        unit_size_id INT,
        status_id INT,
        legal_form_id INT,
        data_source_id INT,
        existing_lu_id INT, -- Populated from _data table analysis result
        enterprise_id INT,
        is_primary BOOLEAN
    ) ON COMMIT DROP;

    -- Select data including the pre-resolved legal_unit_id from the analysis step
    v_sql := format('
        INSERT INTO temp_batch_data (
            ctid, tax_ident, name, typed_birth_date, typed_death_date, valid_from, valid_to,
            sector_id, unit_size_id, status_id, legal_form_id, data_source_id,
            existing_lu_id -- Populate directly
        )
        SELECT
            ctid,
            tax_ident, -- Still needed for linking back inserts
            name,
            typed_birth_date,
            typed_death_date,
            COALESCE(typed_valid_from, computed_valid_from) as valid_from,
            COALESCE(typed_valid_to, computed_valid_to) as valid_to,
            sector_id,
            unit_size_id,
            status_id,
            legal_form_id,
            data_source_id,
            legal_unit_id -- Use the ID resolved by analyse_external_idents
            enterprise_id, is_primary -- Select the newly populated columns
         FROM public.%I WHERE ctid = ANY(%L);
    ', v_data_table_name, p_batch_ctids);
    RAISE DEBUG '[Job %] process_legal_unit: Fetching batch data including pre-resolved IDs and enterprise info: %', p_job_id, v_sql;
    EXECUTE v_sql;

    -- Step 2: Determine existing legal_unit IDs (REMOVED - Handled by selecting existing_lu_id above)

    -- Step 3: Process enterprise connection (REMOVED - Handled by enterprise_link step)

    -- Step 4: Perform Batch INSERT into legal_unit_era (Leveraging Trigger)
    BEGIN
        v_sql := format($$
            WITH inserted_eras AS (
                INSERT INTO public.legal_unit_era (
                    id, valid_from, valid_to, name, birth_date, death_date, active, edit_comment,
                    sector_id, unit_size_id, status_id, legal_form_id, enterprise_id,
                    primary_for_enterprise, data_source_id, edit_by_user_id, edit_at
                )
                SELECT
                    tbd.existing_lu_id, -- Provide existing ID for trigger
                    tbd.valid_from, tbd.valid_to, tbd.name, tbd.typed_birth_date, tbd.typed_death_date, true, ''Import Job Batch'',
                    tbd.sector_id, tbd.unit_size_id, tbd.status_id, tbd.legal_form_id, tbd.enterprise_id, -- Use enterprise info if available
                    tbd.is_primary, tbd.data_source_id, dt.edit_by_user_id, dt.edit_at -- Read from _data table via temp table join
                FROM temp_batch_data tbd
                JOIN public.%I dt ON tbd.ctid = dt.ctid -- Join to get audit info
                WHERE
                    CASE %L::public.import_strategy -- Filter based on operation type
                        WHEN ''insert_only'' THEN tbd.existing_lu_id IS NULL
                        WHEN ''update_only'' THEN tbd.existing_lu_id IS NOT NULL
                        WHEN ''upsert'' THEN TRUE
                    END
                RETURNING id -- Removed problematic ctid RETURNING
            )
            SELECT count(*) FROM inserted_eras; -- Placeholder to execute the INSERT
        $$, v_data_table_name, v_strategy); -- Removed v_edit_by_user_id, v_timestamp, p_batch_ctids

        RAISE DEBUG '[Job %] process_legal_unit: Performing batch INSERT into legal_unit_era: %', p_job_id, v_sql;
        EXECUTE v_sql;
        GET DIAGNOSTICS v_update_count = ROW_COUNT; -- Count of rows INSERTED into _era (or attempted)

        -- Step 4b: Update _data table with resulting legal_unit_id (Post-INSERT - Revised Logic)

        -- Part 1: Update rows that were UPDATES (used existing_lu_id)
        v_sql := format('
            UPDATE public.%I dt SET
                legal_unit_id = tbd.existing_lu_id, -- Use the pre-resolved ID
                last_completed_priority = %L,
                error = NULL,
                state = %L
            FROM temp_batch_data tbd
            WHERE dt.ctid = tbd.ctid
              AND tbd.existing_lu_id IS NOT NULL -- Identify rows that were updates
              AND dt.state != %L
              AND CASE %L::public.import_strategy
                    WHEN ''insert_only'' THEN false -- Should not happen if existing_lu_id is not null
                    ELSE TRUE
                  END;
        ', v_data_table_name, v_step.priority, 'processing', 'error', v_strategy); -- Use 'processing' state
        RAISE DEBUG '[Job %] process_legal_unit: Updating _data for existing units: %', p_job_id, v_sql;
        EXECUTE v_sql;

        -- Part 2: Update rows that were INSERTS (need to lookup the new ID via tax_ident)
        v_sql := format($$
            WITH lu_lookup AS (
                 SELECT DISTINCT ON (xi.value) lu.id as legal_unit_id, xi.value as tax_ident
                 FROM public.legal_unit lu
                 JOIN public.external_ident_for_unit xifu ON xifu.legal_unit_id = lu.id
                 JOIN public.external_ident xi ON xi.id = xifu.external_ident_id
                 JOIN public.external_ident_type xit ON xit.id = xi.type_id
                 WHERE xit.code = 'tax_ident'
                 ORDER BY xi.value, lu.id DESC -- Get latest ID in case of duplicates (shouldn't happen)
            )
            UPDATE public.%I dt SET
                legal_unit_id = lu.legal_unit_id, -- Use the newly found ID
                last_completed_priority = %L,
                error = NULL,
                state = %L
            FROM temp_batch_data tbd
            JOIN lu_lookup lu ON tbd.tax_ident IS NOT NULL AND lu.tax_ident = tbd.tax_ident
            WHERE dt.ctid = tbd.ctid
              AND tbd.existing_lu_id IS NULL -- Identify rows that were inserts
              AND dt.state != %L
              AND CASE %L::public.import_strategy
                    WHEN 'update_only' THEN false -- Should not happen if existing_lu_id is null
                    ELSE TRUE
                  END;
        $$, v_data_table_name, v_step.priority, 'processing', 'error', v_strategy); -- Use 'processing' state
        RAISE DEBUG '[Job %] process_legal_unit: Updating _data for new units: %', p_job_id, v_sql;
        EXECUTE v_sql;

    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
        RAISE WARNING '[Job %] process_legal_unit: Error during batch operation: %', p_job_id, error_message;
        -- Mark the entire batch as error in _data table
        v_sql := format('UPDATE public.%I SET state = %L, error = %L, last_completed_priority = %L WHERE ctid = ANY(%L)',
                       v_data_table_name, 'error', jsonb_build_object('batch_error', error_message), v_step.priority - 1, p_batch_ctids);
        EXECUTE v_sql;
        GET DIAGNOSTICS v_error_count = ROW_COUNT;
        -- Update job error
        UPDATE public.import_job SET error = jsonb_build_object('process_legal_unit_error', error_message) WHERE id = p_job_id;
    END;

    -- Reset constraints if they were deferred by this function
    IF NOT statbus_constraints_already_deferred THEN
        SET CONSTRAINTS ALL IMMEDIATE;
    END IF;

    RAISE DEBUG '[Job %] process_legal_unit (Batch): Finished operation for batch. Initial batch size: %. Errors (estimated): %', p_job_id, array_length(p_batch_ctids, 1), v_error_count;

END;
$procedure$
```

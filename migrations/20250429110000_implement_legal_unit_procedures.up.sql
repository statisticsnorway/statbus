-- Migration: implement_base_legal_unit_procedures
-- Implements the analyse and operation procedures for the legal_unit import target.

BEGIN;

-- Procedure to analyse base legal unit data
CREATE OR REPLACE PROCEDURE admin.analyse_legal_unit(p_job_id INT, p_batch_ctids TID[], p_step_code TEXT)
LANGUAGE plpgsql AS $analyse_legal_unit$
DECLARE
    v_job public.import_job;
    v_snapshot JSONB;
    v_definition JSONB;
    v_step RECORD;
    v_row RECORD;
    -- v_update_sql TEXT; -- Will be constructed dynamically inside the loop
    v_select_sql TEXT;
    v_data_source_id INT;
    v_legal_form_id INT;
    v_status_id INT;
    v_sector_id INT;
    v_unit_size_id INT;
    -- v_computed_valid_from DATE; -- Removed, handled by upstream validity steps
    -- v_computed_valid_to DATE;   -- Removed, handled by upstream validity steps
    v_error_count INT := 0;
    -- v_has_vts_step BOOLEAN := false; -- Removed
    -- v_has_vtc_step BOOLEAN := false; -- Removed
    -- v_step_info JSONB; -- Removed
BEGIN
    RAISE DEBUG '[Job %] analyse_legal_unit: Starting analysis for % rows', p_job_id, array_length(p_batch_ctids, 1);

    -- Get job details and snapshot
    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_definition := v_job.definition_snapshot; -- Assign snapshot from the job record

    IF v_definition IS NULL OR jsonb_typeof(v_definition) != 'object' THEN
        RAISE EXCEPTION '[Job %] Failed to load valid definition snapshot from import_job record', p_job_id;
    END IF;

    -- Find the target details for legal_unit
    SELECT * INTO v_step FROM public.import_step WHERE code = 'legal_unit';
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] legal_unit target not found', p_job_id;
    END IF;

    -- Removed logic for v_has_vts_step, v_has_vtc_step

    -- Prepare select SQL (validity dates are now assumed to be in derived_valid_from/to if applicable)
    v_select_sql := format($$
        SELECT
            ctid,
            NULLIF(data_source_code, '''') as data_source_code,
            NULLIF(legal_form_code, '''') as legal_form_code,
            NULLIF(status_code, '''') as status_code,
            NULLIF(sector_code, '''') as sector_code,
            NULLIF(unit_size_code, '''') as unit_size_code,
            NULLIF(birth_date, '''') as birth_date_str,
            NULLIF(death_date, '''') as death_date_str
            -- derived_valid_from/to are not selected here as they are not directly used by this step's casting logic
            -- but are used by process_legal_unit.
         FROM public.%I WHERE ctid = ANY(%L)
        $$,
        v_job.data_table_name, p_batch_ctids
    );
    RAISE DEBUG '[Job %] analyse_legal_unit: Select SQL: %', p_job_id, v_select_sql;

    -- Removed logic for v_computed_valid_from/to, handled by upstream validity steps

    -- Loop through rows in the batch
    FOR v_row IN EXECUTE v_select_sql
    LOOP
        BEGIN
            -- Perform lookups
            SELECT id INTO v_data_source_id FROM public.data_source WHERE code = v_row.data_source_code;
            SELECT id INTO v_legal_form_id FROM public.legal_form WHERE code = v_row.legal_form_code;
            SELECT id INTO v_status_id FROM public.status WHERE code = v_row.status_code;
            SELECT id INTO v_sector_id FROM public.sector WHERE code = v_row.sector_code;
            SELECT id INTO v_unit_size_id FROM public.unit_size WHERE code = v_row.unit_size_code;

            -- Perform type conversions (handle potential errors)
            DECLARE
                v_birth_date DATE;
                v_death_date DATE;
                -- v_valid_from DATE; -- Removed, handled by upstream validity steps
                -- v_valid_to DATE;   -- Removed, handled by upstream validity steps
            BEGIN
                v_birth_date := admin.safe_cast_to_date(v_row.birth_date_str);
                v_death_date := admin.safe_cast_to_date(v_row.death_date_str);

                -- Removed logic for v_valid_from/to based on v_definition->>'time_context_ident'
                -- derived_valid_from/to are assumed to be populated by prior steps.

                -- Dynamically construct the SET clause for the UPDATE statement
                DECLARE
                    v_update_set_parts TEXT[];
                    v_update_sql_final TEXT;
                BEGIN
                    v_update_set_parts := ARRAY[
                        format('data_source_id = %s', quote_nullable(v_data_source_id)),
                        format('legal_form_id = %s', quote_nullable(v_legal_form_id)),
                        format('status_id = %s', quote_nullable(v_status_id)),
                        format('sector_id = %s', quote_nullable(v_sector_id)),
                        format('unit_size_id = %s', quote_nullable(v_unit_size_id)),
                        format('typed_birth_date = %s', quote_nullable(v_birth_date)),
                        format('typed_death_date = %s', quote_nullable(v_death_date)),
                        format('last_completed_priority = %s', v_step.priority),
                        -- Removed 'valid_from' and 'valid_to' from error clearing as they are handled by analyse_valid_time_from_source
                        format('error = CASE WHEN (error - ''data_source_code'' - ''legal_form_code'' - ''status_code'' - ''sector_code'' - ''unit_size_code'' - ''birth_date'' - ''death_date'' - ''conversion_lookup_error'' - ''unexpected_error'') = ''{}''::jsonb THEN NULL ELSE (error - ''data_source_code'' - ''legal_form_code'' - ''status_code'' - ''sector_code'' - ''unit_size_code'' - ''birth_date'' - ''death_date'' - ''conversion_lookup_error'' - ''unexpected_error'') END'),
                        format('state = %L', 'analysing'::public.import_data_state)
                    ];

                    -- Removed conditional appends for typed_valid_from/to and computed_valid_from/to

                    v_update_sql_final := format($$UPDATE public.%I SET %s WHERE ctid = %L$$,
                        v_job.data_table_name,
                        array_to_string(v_update_set_parts, ', '),
                        v_row.ctid
                    );
                    RAISE DEBUG '[Job %] analyse_legal_unit: Update SQL for row %: %', p_job_id, v_row.ctid, v_update_sql_final;
                    EXECUTE v_update_sql_final;
                END;

            EXCEPTION WHEN others THEN
                 -- Error during type conversion or lookup
                 v_error_count := v_error_count + 1;
                 RAISE DEBUG '[Job %] analyse_legal_unit: SQLERRM for row %: %', p_job_id, v_row.ctid, SQLERRM;
                 EXECUTE format($$UPDATE public.%I SET state = %L, error = COALESCE(error, '{}'::jsonb) || jsonb_build_object('conversion_lookup_error', %L), last_completed_priority = %L WHERE ctid = %L$$,
                                v_job.data_table_name, 'error', SQLERRM, v_step.priority - 1, v_row.ctid);
                 RAISE DEBUG '[Job %] analyse_legal_unit: Error processing row %: %', p_job_id, v_row.ctid, SQLERRM;
            END;

        EXCEPTION WHEN others THEN
            -- Catch-all for unexpected errors during row processing
            v_error_count := v_error_count + 1;
            RAISE DEBUG '[Job %] analyse_legal_unit: SQLERRM (unexpected) for row %: %', p_job_id, v_row.ctid, SQLERRM;
            EXECUTE format($$UPDATE public.%I SET state = %L, error = COALESCE(error, '{}'::jsonb) || jsonb_build_object('unexpected_error', %L), last_completed_priority = %L WHERE ctid = %L$$,
                           v_job.data_table_name, 'error', 'Unexpected error: ' || SQLERRM, v_step.priority - 1, v_row.ctid);
            RAISE WARNING '[Job %] analyse_legal_unit: Unexpected error processing row %: %', p_job_id, v_row.ctid, SQLERRM;
        END;
    END LOOP;

    RAISE DEBUG '[Job %] analyse_legal_unit: Finished analysis for batch. Errors: %', p_job_id, v_error_count;

END;
$analyse_legal_unit$;


-- Procedure to operate (insert/update/upsert) base legal unit data (Batch Oriented)
CREATE OR REPLACE PROCEDURE admin.process_legal_unit(p_job_id INT, p_batch_ctids TID[], p_step_code TEXT)
LANGUAGE plpgsql AS $process_legal_unit$
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
        data_ctid TID PRIMARY KEY, -- Renamed ctid to data_ctid
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
        is_primary BOOLEAN,
        edit_by_user_id INT, -- Added for audit info
        edit_at TIMESTAMPTZ  -- Added for audit info
    ) ON COMMIT DROP;

    -- Select data including the pre-resolved legal_unit_id from the analysis step
    v_sql := format($$
        INSERT INTO temp_batch_data (
            data_ctid, tax_ident, name, typed_birth_date, typed_death_date, valid_from, valid_to,
            sector_id, unit_size_id, status_id, legal_form_id, data_source_id,
            existing_lu_id, enterprise_id, is_primary, edit_by_user_id, edit_at -- Added audit columns
        )
        SELECT
            ctid, -- Source ctid from the data table
            tax_ident, -- Still needed for linking back inserts
            name,
            typed_birth_date,
            typed_death_date,
            derived_valid_from as valid_from, -- Changed to derived_valid_from
            derived_valid_to as valid_to,     -- Changed to derived_valid_to
            sector_id,
            unit_size_id,
            status_id,
            legal_form_id,
            data_source_id,
            legal_unit_id, -- Use the ID resolved by analyse_external_idents
            enterprise_id, is_primary, -- Select the newly populated columns
            edit_by_user_id, edit_at -- Select audit columns
         FROM public.%I WHERE ctid = ANY(%L);
    $$, v_data_table_name, p_batch_ctids);
    RAISE DEBUG '[Job %] process_legal_unit: Fetching batch data including pre-resolved IDs and enterprise info: %', p_job_id, v_sql;
    EXECUTE v_sql;

    -- Step 2 & 3 Removed

    -- Step 4: Perform Batch INSERT into legal_unit_era (Leveraging Trigger)
    -- Store the returned ID and the original ctid
    CREATE TEMP TABLE temp_inserted_lu_ids (
        data_ctid TID PRIMARY KEY,
        legal_unit_id INT NOT NULL
    ) ON COMMIT DROP;

    BEGIN
        -- *** Revised Step 4 Logic: Use RETURNING with CTE to capture original ctid ***
        v_sql := format($$
            WITH data_to_insert AS (
                SELECT
                    tbd.data_ctid, -- Keep original ctid
                    tbd.existing_lu_id,
                    tbd.valid_from, tbd.valid_to, tbd.name, tbd.typed_birth_date, tbd.typed_death_date, true as active, 'Import Job Batch' as edit_comment,
                    tbd.sector_id, tbd.unit_size_id, tbd.status_id, tbd.legal_form_id, tbd.enterprise_id,
                    tbd.is_primary, tbd.data_source_id, tbd.edit_by_user_id, tbd.edit_at
                FROM temp_batch_data tbd
                WHERE
                    CASE %L::public.import_strategy
                        WHEN 'insert_only' THEN tbd.existing_lu_id IS NULL
                        WHEN 'update_only' THEN tbd.existing_lu_id IS NOT NULL
                        WHEN 'upsert' THEN TRUE
                    END
            ), inserted_eras AS (
                INSERT INTO public.legal_unit_era (
                    id, valid_from, valid_to, name, birth_date, death_date, active, edit_comment,
                    sector_id, unit_size_id, status_id, legal_form_id, enterprise_id,
                    primary_for_enterprise, data_source_id, edit_by_user_id, edit_at
                )
                SELECT
                    dti.existing_lu_id,
                    dti.valid_from, dti.valid_to, dti.name, dti.typed_birth_date, dti.typed_death_date, dti.active, dti.edit_comment,
                    dti.sector_id, dti.unit_size_id, dti.status_id, dti.legal_form_id, dti.enterprise_id,
                    dti.is_primary, dti.data_source_id, dti.edit_by_user_id, dti.edit_at
                FROM data_to_insert dti
                RETURNING id -- Return the actual ID used/created
            )
            INSERT INTO temp_inserted_lu_ids (data_ctid, legal_unit_id)
            SELECT dti.data_ctid, ie.id
            FROM data_to_insert dti
            JOIN inserted_eras ie ON TRUE; -- Simple join, assumes order is preserved or single row insert
            -- *** WARNING: This join might be unreliable for batch inserts if RETURNING doesn't guarantee order matching the SELECT. ***
            -- A more robust method might involve joining back on unique data if available, or processing row-by-row if batch RETURNING is problematic.
            -- For now, we proceed with this, but it's a potential point of failure.
        $$, v_strategy);

        RAISE DEBUG '[Job %] process_legal_unit: Performing batch INSERT into legal_unit_era and capturing IDs: %', p_job_id, v_sql;
        EXECUTE v_sql;
        GET DIAGNOSTICS v_update_count = ROW_COUNT; -- Rows inserted into temp_inserted_lu_ids

        -- Step 4b: Update _data table with resulting legal_unit_id using the captured IDs
        v_sql := format($$
            UPDATE public.%I dt SET
                legal_unit_id = til.legal_unit_id, -- Use the ID captured from RETURNING
                last_completed_priority = %L,
                error = NULL,
                state = %L
            FROM temp_inserted_lu_ids til
            WHERE dt.ctid = til.data_ctid -- Join based on the original ctid
              AND dt.state != %L;
        $$, v_data_table_name, v_step.priority, 'processing', 'error');
        RAISE DEBUG '[Job %] process_legal_unit: Updating _data table with final IDs: %', p_job_id, v_sql;
        EXECUTE v_sql;

    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
        RAISE WARNING '[Job %] process_legal_unit: Error during batch operation: %', p_job_id, error_message;
        -- Mark the entire batch as error in _data table
        v_sql := format($$UPDATE public.%I SET state = %L, error = %L, last_completed_priority = %L WHERE ctid = ANY(%L)$$,
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

    DROP TABLE IF EXISTS temp_batch_data;
    DROP TABLE IF EXISTS temp_inserted_lu_ids; -- Drop the new temp table
END;
$process_legal_unit$;


-- Helper function for safe date casting (example)
-- Moved to 20250429105000_implement_valid_time_procedures.up.sql to avoid redefinition
-- CREATE OR REPLACE FUNCTION admin.safe_cast_to_date(p_text_date TEXT) ...

COMMIT;

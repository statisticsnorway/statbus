-- Implements the analyse and operation procedures for the legal_unit import target.

BEGIN;

-- Procedure to analyse base legal unit data
CREATE OR REPLACE PROCEDURE import.analyse_legal_unit(p_job_id INT, p_batch_row_ids BIGINT[], p_step_code TEXT)
LANGUAGE plpgsql AS $analyse_legal_unit$
DECLARE
    v_job public.import_job;
    v_snapshot JSONB;
    v_definition_snapshot JSONB; -- Renamed to avoid conflict with CONVENTIONS.md example
    v_step RECORD;
    v_sql TEXT;
    v_update_count INT := 0;
    v_skipped_update_count INT := 0;
    v_error_count INT := 0;
    v_error_keys_to_clear_arr TEXT[] := ARRAY['data_source_code', 'legal_form_code', 'sector_code', 'unit_size_code', 'birth_date', 'death_date', 'status_id_missing']; -- Removed conversion_lookup_error, unexpected_error as they are too generic for specific clearing
    v_invalid_code_keys_arr TEXT[] := ARRAY['data_source_code', 'legal_form_code', 'sector_code', 'unit_size_code', 'birth_date', 'death_date']; -- Keys that go into invalid_codes
BEGIN
    RAISE DEBUG '[Job %] analyse_legal_unit (Batch): Starting analysis for % rows', p_job_id, array_length(p_batch_row_ids, 1);

    -- Get default status_id -- Removed
    -- SELECT id INTO v_default_status_id FROM public.status WHERE assigned_by_default = true AND active = true LIMIT 1;
    -- RAISE DEBUG '[Job %] analyse_legal_unit: Default status_id found: %', p_job_id, v_default_status_id;

    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_definition_snapshot := v_job.definition_snapshot; 

    IF v_definition_snapshot IS NULL OR jsonb_typeof(v_definition_snapshot) != 'object' THEN
        RAISE EXCEPTION '[Job %] Failed to load valid definition snapshot from import_job record', p_job_id;
    END IF;

    SELECT * INTO v_step FROM public.import_step WHERE code = 'legal_unit';
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] legal_unit target step not found', p_job_id;
    END IF;

    v_sql := format($$
        WITH lookups AS (
            SELECT
                dt_sub.row_id as data_row_id,
                ds.id as resolved_data_source_id,
                lf.id as resolved_legal_form_id,
                -- s.id as resolved_status_id, -- Status is now resolved in a prior step
                sec.id as resolved_sector_id,
                us.id as resolved_unit_size_id,
                import.safe_cast_to_date(dt_sub.birth_date) as resolved_typed_birth_date,
                import.safe_cast_to_date(dt_sub.death_date) as resolved_typed_death_date
            FROM public.%I dt_sub
            LEFT JOIN public.data_source_available ds ON NULLIF(dt_sub.data_source_code, '') IS NOT NULL AND ds.code = NULLIF(dt_sub.data_source_code, '')
            LEFT JOIN public.legal_form_available lf ON NULLIF(dt_sub.legal_form_code, '') IS NOT NULL AND lf.code = NULLIF(dt_sub.legal_form_code, '')
            -- LEFT JOIN public.status s ON NULLIF(dt_sub.status_code, '') IS NOT NULL AND s.code = NULLIF(dt_sub.status_code, '') AND s.active = true -- Removed
            LEFT JOIN public.sector_available sec ON NULLIF(dt_sub.sector_code, '') IS NOT NULL AND sec.code = NULLIF(dt_sub.sector_code, '')
            LEFT JOIN public.unit_size_available us ON NULLIF(dt_sub.unit_size_code, '') IS NOT NULL AND us.code = NULLIF(dt_sub.unit_size_code, '')
            WHERE dt_sub.row_id = ANY(%L) AND dt_sub.action != 'skip'
        )
        UPDATE public.%I dt SET
            data_source_id = l.resolved_data_source_id,
            legal_form_id = l.resolved_legal_form_id,
            -- status_id = CASE ... END, -- Removed: status_id is now populated by 'status' step
            sector_id = l.resolved_sector_id,
            unit_size_id = l.resolved_unit_size_id,
            typed_birth_date = l.resolved_typed_birth_date,
            typed_death_date = l.resolved_typed_death_date,
            state = CASE
                        WHEN dt.status_id IS NULL THEN 'error'::public.import_data_state -- Fatal if status_id is missing
                        ELSE -- No error in this step
                            CASE
                                WHEN dt.state = 'error'::public.import_data_state THEN 'error'::public.import_data_state -- Preserve previous error
                                ELSE 'analysing'::public.import_data_state -- OK to set to analysing
                            END
                    END,
            action = CASE
                        WHEN dt.status_id IS NULL THEN 'skip'::public.import_row_action_type -- Fatal error implies skip
                        ELSE dt.action -- Preserve action from previous steps if no new fatal error here
                     END,
            error = CASE
                        WHEN dt.status_id IS NULL THEN
                            COALESCE(dt.error, '{}'::jsonb) || jsonb_build_object('status_id_missing', 'Status ID not resolved by prior step')
                        ELSE -- Clear specific non-fatal error keys if they were previously set and no new fatal error
                            CASE WHEN (dt.error - %L::TEXT[]) = '{}'::jsonb THEN NULL ELSE (dt.error - %L::TEXT[]) END
                    END,
            invalid_codes = CASE
                                WHEN dt.status_id IS NOT NULL THEN -- Only populate invalid_codes if status_id is present (not a fatal error for this step)
                                    jsonb_strip_nulls(
                                     COALESCE(dt.invalid_codes, '{}'::jsonb) - %L::TEXT[] || -- Remove old keys first, then add new ones
                                     jsonb_build_object('data_source_code', CASE WHEN NULLIF(dt.data_source_code, '') IS NOT NULL AND l.resolved_data_source_id IS NULL THEN dt.data_source_code ELSE NULL END) ||
                                     jsonb_build_object('legal_form_code', CASE WHEN NULLIF(dt.legal_form_code, '') IS NOT NULL AND l.resolved_legal_form_id IS NULL THEN dt.legal_form_code ELSE NULL END) ||
                                     jsonb_build_object('sector_code', CASE WHEN NULLIF(dt.sector_code, '') IS NOT NULL AND l.resolved_sector_id IS NULL THEN dt.sector_code ELSE NULL END) ||
                                     jsonb_build_object('unit_size_code', CASE WHEN NULLIF(dt.unit_size_code, '') IS NOT NULL AND l.resolved_unit_size_id IS NULL THEN dt.unit_size_code ELSE NULL END) ||
                                     jsonb_build_object('birth_date', CASE WHEN NULLIF(dt.birth_date, '') IS NOT NULL AND l.resolved_typed_birth_date IS NULL THEN dt.birth_date ELSE NULL END) ||
                                     jsonb_build_object('death_date', CASE WHEN NULLIF(dt.death_date, '') IS NOT NULL AND l.resolved_typed_death_date IS NULL THEN dt.death_date ELSE NULL END)
                                    )
                                ELSE dt.invalid_codes -- Keep existing invalid_codes if it's a fatal status_id error (action will be skip anyway)
                            END,
            last_completed_priority = %s -- Always v_step.priority
        FROM lookups l
        WHERE dt.row_id = l.data_row_id AND dt.row_id = ANY(%L) AND dt.action IS DISTINCT FROM 'skip'; -- Process if action was not already 'skip' from a prior step.
    $$,
        v_job.data_table_name, p_batch_row_ids,                     -- For lookups CTE
        v_job.data_table_name,                                      -- For main UPDATE target
        v_error_keys_to_clear_arr, v_error_keys_to_clear_arr,       -- For error CASE (clear)
        v_invalid_code_keys_arr,                                    -- For invalid_codes CASE (clear old)
        v_step.priority,                                            -- For last_completed_priority (always this step's priority)
        p_batch_row_ids                                             -- For final WHERE clause
    );

    RAISE DEBUG '[Job %] analyse_legal_unit: Single-pass batch update for non-skipped rows: %', p_job_id, v_sql;

    BEGIN
        EXECUTE v_sql;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_legal_unit: Updated % non-skipped rows in single pass.', p_job_id, v_update_count;

        -- Update priority for skipped rows
        EXECUTE format('
            UPDATE public.%I dt SET
                last_completed_priority = %L
            WHERE dt.row_id = ANY(%L) AND dt.action = ''skip'';
        ', v_job.data_table_name, v_step.priority, p_batch_row_ids);
        GET DIAGNOSTICS v_skipped_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_legal_unit: Updated last_completed_priority for % skipped rows.', p_job_id, v_skipped_update_count;

        v_update_count := v_update_count + v_skipped_update_count; -- Total rows affected

        EXECUTE format('SELECT COUNT(*) FROM public.%I WHERE row_id = ANY(%L) AND state = ''error'' AND (error ?| %L::text[])',
                       v_job.data_table_name, p_batch_row_ids, v_error_keys_to_clear_arr)
        INTO v_error_count;
        RAISE DEBUG '[Job %] analyse_legal_unit: Estimated errors in this step for batch: %', p_job_id, v_error_count;

    EXCEPTION WHEN others THEN
        RAISE WARNING '[Job %] analyse_legal_unit: Error during single-pass batch update: %', p_job_id, SQLERRM;
        UPDATE public.import_job
        SET error = jsonb_build_object('analyse_legal_unit_batch_error', SQLERRM),
            state = 'finished'
        WHERE id = p_job_id;
        RAISE DEBUG '[Job %] analyse_legal_unit: Marked job as failed due to error: %', p_job_id, SQLERRM;
        RAISE;
    END;

    RAISE DEBUG '[Job %] analyse_legal_unit (Batch): Finished analysis for batch. Total errors in batch: %', p_job_id, v_error_count;
END;
$analyse_legal_unit$;


-- Procedure to operate (insert/update/upsert) base legal unit data (Batch Oriented)
CREATE OR REPLACE PROCEDURE import.process_legal_unit(p_job_id INT, p_batch_row_ids BIGINT[], p_step_code TEXT)
LANGUAGE plpgsql AS $process_legal_unit$
DECLARE
    v_job public.import_job;
    v_snapshot JSONB;
    v_definition_snapshot JSONB;
    v_step RECORD;
    v_strategy public.import_strategy;
    v_edit_by_user_id INT;
    v_timestamp TIMESTAMPTZ := clock_timestamp();
    v_data_table_name TEXT;
    v_sql TEXT;
    v_error_count INT := 0;
    v_inserted_new_lu_count INT := 0;
    v_intended_replace_lu_count INT := 0; 
    v_intended_update_lu_count INT := 0;
    v_actually_replaced_lu_count INT := 0;
    v_actually_updated_lu_count INT := 0;
    error_message TEXT;
    v_batch_result RECORD;
    v_batch_error_row_ids BIGINT[] := ARRAY[]::BIGINT[];
    v_batch_success_row_ids BIGINT[] := ARRAY[]::BIGINT[];
    rec_created_lu RECORD;
    rec_ident_type public.external_ident_type_active;
    rec_demotion RECORD;
    v_ident_value TEXT;
    v_data_table_col_name TEXT;
    v_inserted_ext_id INT; -- For debugging
    v_inserted_lu_id INT;  -- For debugging
    v_current_op_row_count INT; -- For storing ROW_COUNT from individual DML operations
BEGIN
    RAISE DEBUG '[Job %] process_legal_unit (Batch): Starting operation for % rows', p_job_id, array_length(p_batch_row_ids, 1);

    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_definition_snapshot := v_job.definition_snapshot;
    v_data_table_name := v_job.data_table_name;

    IF v_definition_snapshot IS NULL OR jsonb_typeof(v_definition_snapshot) != 'object' THEN
        RAISE EXCEPTION '[Job %] Failed to load valid definition snapshot from import_job record', p_job_id;
    END IF;

    SELECT * INTO v_step FROM public.import_step WHERE code = 'legal_unit';
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] legal_unit target step not found', p_job_id;
    END IF;

    v_strategy := (v_definition_snapshot->'import_definition'->>'strategy')::public.import_strategy;
    IF v_strategy IS NULL THEN
        RAISE EXCEPTION '[Job %] Strategy is NULL, cannot proceed. Check definition_snapshot structure. It should be under import_definition key.', p_job_id;
    END IF;

    v_edit_by_user_id := v_job.user_id;

    RAISE DEBUG '[Job %] process_legal_unit: Operation Type: %, User ID: %', p_job_id, v_strategy, v_edit_by_user_id;

    CREATE TEMP TABLE temp_batch_data (
        data_row_id BIGINT PRIMARY KEY,
        tax_ident TEXT, 
        name TEXT,
        typed_birth_date DATE,
        typed_death_date DATE,
        valid_after DATE, -- Added
        valid_from DATE,
        valid_to DATE,
        sector_id INT,
        unit_size_id INT,
        status_id INT,
        legal_form_id INT,
        data_source_id INT,
        existing_lu_id INT,
        enterprise_id INT,
        primary_for_enterprise BOOLEAN,
        edit_by_user_id INT,
        edit_at TIMESTAMPTZ,
        edit_comment TEXT, -- Added
        invalid_codes JSONB, -- Added
        action public.import_row_action_type,
        founding_row_id BIGINT
    ) ON COMMIT DROP;

    v_sql := format($$
        INSERT INTO temp_batch_data (
            data_row_id, founding_row_id, name, typed_birth_date, typed_death_date, valid_after, valid_from, valid_to,
            sector_id, unit_size_id, status_id, legal_form_id, data_source_id,
            existing_lu_id, enterprise_id, primary_for_enterprise, edit_by_user_id, edit_at, edit_comment,
            invalid_codes, -- Added
            action
        )
        SELECT
            dt.row_id,
            dt.founding_row_id,
            dt.name,
            dt.typed_birth_date,
            dt.typed_death_date,
            dt.derived_valid_after, -- Added
            dt.derived_valid_from,
            dt.derived_valid_to,
            dt.sector_id,
            dt.unit_size_id,
            dt.status_id,
            dt.legal_form_id,
            dt.data_source_id,
            dt.legal_unit_id,
            dt.enterprise_id, dt.primary_for_enterprise,
            dt.edit_by_user_id, dt.edit_at, dt.edit_comment,
            dt.invalid_codes, -- Added
            dt.action
         FROM public.%I dt WHERE dt.row_id = ANY(%L) AND dt.action IS DISTINCT FROM 'skip' AND dt.state != 'error'; -- Added dt.state != 'error'
    $$, v_data_table_name, p_batch_row_ids);
    RAISE DEBUG '[Job %] process_legal_unit: Fetching core batch data (including invalid_codes and founding_row_id), excluding rows in error state: %', p_job_id, v_sql;
    EXECUTE v_sql;

    -- Propagate enterprise_id and primary_for_enterprise from founding 'insert' row to subsequent 'replace'/'update' rows in temp_batch_data
    -- This ensures that entities newly created and linked to an enterprise in this batch
    -- have their enterprise information correctly carried over to their subsequent time slices within the same batch.
    UPDATE temp_batch_data tbd_target
    SET enterprise_id = tbd_source.enterprise_id,
        primary_for_enterprise = tbd_source.primary_for_enterprise -- If founding insert was primary, subsequent slices are too (before conflict resolution)
    FROM temp_batch_data tbd_source
    WHERE tbd_target.founding_row_id IS NOT NULL                         -- Target must be a subsequent row
      AND tbd_target.founding_row_id = tbd_source.data_row_id          -- Link target to its source/founding row
      AND tbd_target.data_row_id != tbd_source.data_row_id            -- Ensure it's a different row
      AND tbd_source.action = 'insert'                                 -- Source must be the original insert action
      AND tbd_target.enterprise_id IS NULL;                            -- Only update if target's enterprise_id is currently NULL (avoid overwriting already resolved ones for existing LUs)
    IF FOUND THEN
        RAISE DEBUG '[Job %] process_legal_unit: Propagated enterprise_id and primary_for_enterprise from founding insert rows to subsequent rows in temp_batch_data.', p_job_id;
    END IF;

    -- Resolve primary_for_enterprise conflicts within the current batch in temp_batch_data
    -- For each enterprise and overlapping period, ensure only one LU (the "winner") has primary_for_enterprise = true.
    RAISE DEBUG '[Job %] process_legal_unit: Resolving primary_for_enterprise conflicts within temp_batch_data.', p_job_id;
    WITH BatchPrimaries AS (
        SELECT
            data_row_id,
            enterprise_id,
            valid_after,
            valid_to,
            existing_lu_id, -- Assuming this is the actual LU ID
            primary_for_enterprise,
            -- Determine the winner within each group of conflicting primaries
            FIRST_VALUE(data_row_id) OVER (
                PARTITION BY enterprise_id, daterange(valid_after, valid_to, '(]') -- Partition by enterprise and the validity range
                ORDER BY existing_lu_id ASC NULLS LAST, data_row_id ASC -- Deterministic tie-breaking: lowest LU ID, then lowest data_row_id
            ) as winner_data_row_id
        FROM temp_batch_data
        WHERE action IN ('replace', 'update')
          AND primary_for_enterprise = true -- Only consider those initially marked as primary
          AND enterprise_id IS NOT NULL
    )
    UPDATE temp_batch_data tbd
    SET primary_for_enterprise = false
    FROM BatchPrimaries bp
    WHERE tbd.data_row_id = bp.data_row_id
      AND tbd.data_row_id != bp.winner_data_row_id -- Set to false if not the winner
      AND tbd.primary_for_enterprise = true; -- Only update if it was true

    IF FOUND THEN
        RAISE DEBUG '[Job %] process_legal_unit: Resolved primary_for_enterprise conflicts in temp_batch_data. Some LUs were demoted within the batch.', p_job_id;
    ELSE
        RAISE DEBUG '[Job %] process_legal_unit: No primary_for_enterprise conflicts to resolve within temp_batch_data, or no candidates found.', p_job_id;
    END IF;

    CREATE TEMP TABLE temp_created_lus ( -- For 'insert' action
        data_row_id BIGINT PRIMARY KEY,
        new_legal_unit_id INT NOT NULL
    ) ON COMMIT DROP;

    CREATE TEMP TABLE temp_processed_action_lu_ids ( -- For 'replace' and 'update' actions
        data_row_id BIGINT PRIMARY KEY,
        actual_legal_unit_id INT NOT NULL
    ) ON COMMIT DROP;

    -- Temp table for REPLACE action
    CREATE TEMP TABLE temp_lu_replace_source (
        row_id BIGINT PRIMARY KEY,
        founding_row_id BIGINT,
        id INT,
        valid_after DATE NOT NULL, -- Changed from valid_from
        valid_to DATE NOT NULL,
        name TEXT,
        birth_date DATE,
        death_date DATE,
        active BOOLEAN,
        sector_id INT,
        unit_size_id INT,
        status_id INT,
        legal_form_id INT,
        enterprise_id INT,
        primary_for_enterprise BOOLEAN,
        data_source_id INT,
        invalid_codes JSONB, -- Added
        edit_by_user_id INT,
        edit_at TIMESTAMPTZ,
        edit_comment TEXT
    ) ON COMMIT DROP;

    -- Temp table for UPDATE action (identical structure to replace)
    CREATE TEMP TABLE temp_lu_update_source (
        row_id BIGINT PRIMARY KEY,
        founding_row_id BIGINT,
        id INT,
        valid_after DATE NOT NULL, -- Changed from valid_from
        valid_to DATE NOT NULL,
        name TEXT,
        birth_date DATE,
        death_date DATE,
        active BOOLEAN,
        sector_id INT,
        unit_size_id INT,
        status_id INT,
        legal_form_id INT,
        enterprise_id INT,
        primary_for_enterprise BOOLEAN,
        data_source_id INT,
        invalid_codes JSONB, -- Added
        edit_by_user_id INT,
        edit_at TIMESTAMPTZ,
        edit_comment TEXT
    ) ON COMMIT DROP;

    -- Temp table for demotion operations
    CREATE TEMP TABLE temp_lu_demotion_ops (
        row_id BIGINT PRIMARY KEY, -- Can be a synthetic ID for this temp table if needed, or map to an existing LU ID
        founding_row_id BIGINT,    -- Not strictly needed for demotion, but part of target table structure
        id INT NOT NULL,           -- The ID of the LU in public.legal_unit to be demoted
        valid_after DATE NOT NULL,
        valid_to DATE NOT NULL,
        name TEXT,
        birth_date DATE,
        death_date DATE,
        active BOOLEAN,
        sector_id INT,
        unit_size_id INT,
        status_id INT,
        legal_form_id INT,
        enterprise_id INT,
        primary_for_enterprise BOOLEAN NOT NULL DEFAULT false, -- Will be false for demotion
        data_source_id INT,
        invalid_codes JSONB,
        edit_by_user_id INT,
        edit_at TIMESTAMPTZ,
        edit_comment TEXT
    ) ON COMMIT DROP;

    BEGIN
        RAISE DEBUG '[Job %] process_legal_unit: Starting demotion of conflicting primary LUs.', p_job_id;

        INSERT INTO temp_lu_demotion_ops (
            id, valid_after, valid_to, name, birth_date, death_date, active, sector_id, unit_size_id, status_id, legal_form_id,
            enterprise_id, primary_for_enterprise, data_source_id, invalid_codes,
            edit_by_user_id, edit_at, edit_comment,
            row_id -- Synthetic PK for temp_lu_demotion_ops
        )
        SELECT
            ex_lu.id, -- ID of the LU to be demoted
            incoming_primary.new_primary_valid_after, -- Demotion period starts when new primary starts
            incoming_primary.new_primary_valid_to,   -- Demotion period ends when new primary ends
            ex_lu.name, ex_lu.birth_date, ex_lu.death_date, ex_lu.active, ex_lu.sector_id, ex_lu.unit_size_id, ex_lu.status_id, ex_lu.legal_form_id,
            ex_lu.enterprise_id,
            false, -- Explicitly demoting
            ex_lu.data_source_id, ex_lu.invalid_codes,
            incoming_primary.demotion_edit_by_user_id,
            incoming_primary.demotion_edit_at,
            COALESCE(ex_lu.edit_comment || '; ', '') || 'Demoted: LU ' || COALESCE(incoming_primary.incoming_lu_id::TEXT, 'NEW') || 
                ' became primary for enterprise ' || incoming_primary.target_enterprise_id || 
                ' for period ' || incoming_primary.new_primary_valid_after || ' to ' || incoming_primary.new_primary_valid_to || 
                ' by job ' || p_job_id,
            -- Generate a unique row_id for the temp table using row_number()
            row_number() OVER (ORDER BY ex_lu.id, incoming_primary.new_primary_valid_after)
        FROM
            public.legal_unit ex_lu
        JOIN
            (SELECT -- Subquery to get all incoming LUs from the current batch that are to be primary
                 sfi_sub.data_row_id AS source_data_row_id,
                 sfi_sub.existing_lu_id AS incoming_lu_id,
                 sfi_sub.enterprise_id AS target_enterprise_id,
                 sfi_sub.valid_after AS new_primary_valid_after,
                 sfi_sub.valid_to AS new_primary_valid_to,
                 sfi_sub.edit_by_user_id AS demotion_edit_by_user_id,
                 sfi_sub.edit_at AS demotion_edit_at
             FROM temp_batch_data sfi_sub
             WHERE sfi_sub.action IN ('replace', 'update') -- Only consider LUs being updated/replaced in this batch
               AND sfi_sub.primary_for_enterprise = true
               AND sfi_sub.enterprise_id IS NOT NULL
            ) AS incoming_primary
        ON ex_lu.enterprise_id = incoming_primary.target_enterprise_id
        WHERE
            ex_lu.id != incoming_primary.incoming_lu_id -- Don't demote the LU being processed itself
            AND ex_lu.primary_for_enterprise = true      -- Only consider existing LUs that are currently primary
            AND public.after_to_overlaps(ex_lu.valid_after, ex_lu.valid_to, incoming_primary.new_primary_valid_after, incoming_primary.new_primary_valid_to); -- Check for overlap

        IF FOUND THEN
            RAISE DEBUG '[Job %] process_legal_unit: Identified % LUs for demotion. Populated temp_lu_demotion_ops.', p_job_id, (SELECT count(*) FROM temp_lu_demotion_ops);

            FOR v_batch_result IN
                SELECT * FROM import.batch_insert_or_replace_generic_valid_time_table(
                    p_target_schema_name => 'public', p_target_table_name => 'legal_unit',
                    p_source_schema_name => 'pg_temp', p_source_table_name => 'temp_lu_demotion_ops',
                    p_id_column_name => 'id',
                    p_unique_columns => '[]'::jsonb,
                    p_ephemeral_columns => ARRAY['edit_comment', 'edit_by_user_id', 'edit_at']
                )
            LOOP
                IF v_batch_result.status = 'ERROR' THEN
                    RAISE WARNING '[Job %] process_legal_unit: Error during demotion batch_replace for LU ID % (source_row_id %): %',
                                  p_job_id, v_batch_result.upserted_record_id, v_batch_result.source_row_id, v_batch_result.error_message;
                    UPDATE public.import_job SET error = COALESCE(error, '{}'::jsonb) || jsonb_build_object('demotion_error_lu_' || v_batch_result.upserted_record_id, v_batch_result.error_message)
                    WHERE id = p_job_id;
                ELSE
                    RAISE DEBUG '[Job %] process_legal_unit: Successfully processed demotion for LU ID % (source_row_id %)',
                                  p_job_id, v_batch_result.upserted_record_id, v_batch_result.source_row_id;
                END IF;
            END LOOP;
        ELSE
            RAISE DEBUG '[Job %] process_legal_unit: No existing primary LUs found to demote based on current batch.', p_job_id;
        END IF;
        RAISE DEBUG '[Job %] process_legal_unit: Finished demotion of conflicting primary LUs.', p_job_id;

        RAISE DEBUG '[Job %] process_legal_unit: Handling INSERTS for new LUs using MERGE.', p_job_id;
        WITH source_for_insert AS (
            SELECT
                data_row_id, name, typed_birth_date, typed_death_date,
                sector_id, unit_size_id, status_id, legal_form_id, enterprise_id,
                primary_for_enterprise, data_source_id, invalid_codes,
                valid_after, valid_to, -- Changed valid_from to valid_after
                edit_by_user_id, edit_at, edit_comment,
                action -- Though action is 'insert', including it for completeness if MERGE logic were more complex
            FROM temp_batch_data
            WHERE action = 'insert'
        ),
        merged_legal_units AS (
            MERGE INTO public.legal_unit lu
            USING source_for_insert sfi
            ON 1 = 0 -- Always insert for this action when action = 'insert'
            WHEN NOT MATCHED THEN -- This condition will always be true due to "ON 1 = 0"
                INSERT (
                    name, birth_date, death_date,
                    sector_id, unit_size_id, status_id, legal_form_id, enterprise_id,
                    primary_for_enterprise, data_source_id, invalid_codes,
                    valid_after, valid_to, -- Changed valid_from to valid_after
                    edit_by_user_id, edit_at, edit_comment
                )
                VALUES (
                    sfi.name, sfi.typed_birth_date, sfi.typed_death_date,
                    sfi.sector_id, sfi.unit_size_id, sfi.status_id, sfi.legal_form_id, sfi.enterprise_id,
                    sfi.primary_for_enterprise, sfi.data_source_id,
                    sfi.invalid_codes,
                    sfi.valid_after, sfi.valid_to, -- Changed sfi.valid_from to sfi.valid_after
                    sfi.edit_by_user_id, sfi.edit_at, sfi.edit_comment
                )
            RETURNING lu.id AS new_legal_unit_id, sfi.data_row_id AS data_row_id
        )
        INSERT INTO temp_created_lus (data_row_id, new_legal_unit_id)
        SELECT data_row_id, new_legal_unit_id
        FROM merged_legal_units;

        GET DIAGNOSTICS v_inserted_new_lu_count = ROW_COUNT;
        RAISE DEBUG '[Job %] process_legal_unit: Inserted % new legal units into temp_created_lus via MERGE.', p_job_id, v_inserted_new_lu_count;

        IF v_inserted_new_lu_count > 0 THEN
            FOR rec_created_lu IN SELECT tcl.data_row_id, tcl.new_legal_unit_id, tbd.edit_by_user_id, tbd.edit_at, tbd.edit_comment
                                  FROM temp_created_lus tcl
                                  JOIN temp_batch_data tbd ON tcl.data_row_id = tbd.data_row_id
            LOOP
                FOR rec_ident_type IN SELECT * FROM public.external_ident_type_active ORDER BY priority LOOP
                    v_data_table_col_name := rec_ident_type.code;
                    BEGIN
                        EXECUTE format('SELECT %I FROM public.%I WHERE row_id = %L',
                                       v_data_table_col_name, v_data_table_name, rec_created_lu.data_row_id)
                        INTO v_ident_value;

                        IF v_ident_value IS NOT NULL AND v_ident_value <> '' THEN
                            RAISE DEBUG '[Job %] process_legal_unit: For new LU (id: %), data_row_id: %, ident_type: % (code: %), value: %',
                                        p_job_id, rec_created_lu.new_legal_unit_id, rec_created_lu.data_row_id, rec_ident_type.id, rec_ident_type.code, v_ident_value;
                            INSERT INTO public.external_ident (legal_unit_id, type_id, ident, edit_by_user_id, edit_at, edit_comment)
                            VALUES (rec_created_lu.new_legal_unit_id, rec_ident_type.id, v_ident_value, rec_created_lu.edit_by_user_id, rec_created_lu.edit_at, rec_created_lu.edit_comment)
                            ON CONFLICT (type_id, ident) DO UPDATE SET
                                legal_unit_id = EXCLUDED.legal_unit_id,
                                establishment_id = NULL, enterprise_id = NULL, enterprise_group_id = NULL,
                                edit_by_user_id = EXCLUDED.edit_by_user_id, edit_at = EXCLUDED.edit_at, edit_comment = EXCLUDED.edit_comment
                            RETURNING public.external_ident.id, public.external_ident.legal_unit_id INTO v_inserted_ext_id, v_inserted_lu_id;

                            RAISE DEBUG '[Job %] process_legal_unit: Upserted external_ident ID %, LU_ID %, for LU ID %, type_id %, ident %',
                                        p_job_id, v_inserted_ext_id, v_inserted_lu_id, rec_created_lu.new_legal_unit_id, rec_ident_type.id, v_ident_value;
                        END IF;
                    EXCEPTION
                        WHEN undefined_column THEN
                            RAISE DEBUG '[Job %] process_legal_unit: Column % for ident type % not found in % for data_row_id %, skipping this ident type for this row.',
                                        p_job_id, v_data_table_col_name, rec_ident_type.code, v_data_table_name, rec_created_lu.data_row_id;
                    END;
                END LOOP;
            END LOOP;

            RAISE DEBUG '[Job %] process_legal_unit: Processed external idents for % new LUs.', p_job_id, v_inserted_new_lu_count;

            -- Update temp_batch_data with the new_legal_unit_id for subsequent 'replace'/'update' rows of the same logical entity
            -- This uses the founding_row_id determined by analyse_external_idents to link to the 'insert' row that created the LU.
            UPDATE temp_batch_data tbd_target
            SET existing_lu_id = tcl.new_legal_unit_id
            FROM temp_created_lus tcl
            WHERE tbd_target.founding_row_id IS NOT NULL             -- Target must be a subsequent row of a new entity
              AND tbd_target.founding_row_id = tcl.data_row_id     -- Match target's founding_row_id to the data_row_id of the 'insert' action in temp_created_lus
              AND tbd_target.action IN ('replace', 'update');        -- Apply to subsequent 'replace' or 'update' actions
            IF FOUND THEN
                 GET DIAGNOSTICS v_current_op_row_count = ROW_COUNT;
                 RAISE DEBUG '[Job %] process_legal_unit: Updated temp_batch_data.existing_lu_id for % subsequent replace/update rows based on founding_row_id.', p_job_id, v_current_op_row_count;
            END IF;

            EXECUTE format($$
                UPDATE public.%I dt SET
                    legal_unit_id = tcl.new_legal_unit_id, -- This updates the _data table for the 'insert' rows
                    last_completed_priority = %L,
                    error = NULL,
                    state = %L
                FROM temp_created_lus tcl
                WHERE dt.row_id = tcl.data_row_id AND dt.state != 'error';
            $$, v_data_table_name, v_step.priority, 'processing'::public.import_data_state);
            RAISE DEBUG '[Job %] process_legal_unit: Updated _data table for % new LUs.', p_job_id, v_inserted_new_lu_count;
        END IF;

        -- Handle REPLACE action
        RAISE DEBUG '[Job %] process_legal_unit: Handling REPLACE action for existing LUs.', p_job_id;
        INSERT INTO temp_lu_replace_source (
            row_id, founding_row_id, id, valid_after, valid_to, name, birth_date, death_date, active,
            sector_id, unit_size_id, status_id, legal_form_id, enterprise_id,
            primary_for_enterprise, data_source_id, invalid_codes, -- Added invalid_codes
            edit_by_user_id, edit_at, edit_comment
        )
        SELECT
            tbd.data_row_id, tbd.founding_row_id, tbd.existing_lu_id, tbd.valid_after, tbd.valid_to, tbd.name,
            tbd.typed_birth_date, tbd.typed_death_date, true, -- Assuming active=true for replace actions
            tbd.sector_id, tbd.unit_size_id, tbd.status_id, tbd.legal_form_id, tbd.enterprise_id,
            tbd.primary_for_enterprise, tbd.data_source_id,
            tbd.invalid_codes,
            tbd.edit_by_user_id, tbd.edit_at,
            tbd.edit_comment
        FROM (
            SELECT DISTINCT ON (existing_lu_id, valid_after) * -- Select one row per LU ID and valid_after
            FROM temp_batch_data
            WHERE action = 'replace'
            ORDER BY existing_lu_id ASC NULLS LAST, valid_after ASC, data_row_id ASC -- Deterministic pick
        ) tbd;

        GET DIAGNOSTICS v_intended_replace_lu_count = ROW_COUNT;
        RAISE DEBUG '[Job %] process_legal_unit: Populated temp_lu_replace_source with % rows for action=replace.', p_job_id, v_intended_replace_lu_count;

        IF v_intended_replace_lu_count > 0 THEN
            v_batch_error_row_ids := ARRAY[]::BIGINT[];
            v_batch_success_row_ids := ARRAY[]::BIGINT[];
            RAISE DEBUG '[Job %] process_legal_unit: Calling batch_insert_or_replace_generic_valid_time_table for legal_unit (replace).', p_job_id;
            FOR v_batch_result IN
                SELECT * FROM import.batch_insert_or_replace_generic_valid_time_table(
                    p_target_schema_name => 'public', p_target_table_name => 'legal_unit',
                    p_source_schema_name => 'pg_temp', p_source_table_name => 'temp_lu_replace_source',
                    p_id_column_name => 'id', -- Ensure this is the PK in temp_lu_replace_source
                    p_unique_columns => '[]'::jsonb,
                    p_ephemeral_columns => ARRAY['edit_comment', 'edit_by_user_id', 'edit_at']
                    -- p_source_row_id_column_name, p_temporal_columns, p_founding_row_id_column_name are removed
                )
            LOOP
                IF v_batch_result.status = 'ERROR' THEN
                    v_batch_error_row_ids := array_append(v_batch_error_row_ids, v_batch_result.source_row_id);
                    EXECUTE format($$
                        UPDATE public.%I SET state = %L, error = COALESCE(error, '{}'::jsonb) || jsonb_build_object('batch_replace_lu_error', %L)
                        -- last_completed_priority is preserved (not changed) on error
                        WHERE row_id = %L;
                    $$, v_data_table_name, 'error'::public.import_data_state, v_batch_result.error_message, v_batch_result.source_row_id);
                ELSE
                    v_batch_success_row_ids := array_append(v_batch_success_row_ids, v_batch_result.source_row_id);
                    INSERT INTO temp_processed_action_lu_ids (data_row_id, actual_legal_unit_id)
                    VALUES (v_batch_result.source_row_id, v_batch_result.upserted_record_id); -- Corrected to upserted_record_id
                END IF;
            END LOOP;

            v_actually_replaced_lu_count := array_length(v_batch_success_row_ids, 1);
            v_error_count := array_length(v_batch_error_row_ids, 1); 
            RAISE DEBUG '[Job %] process_legal_unit: Batch replace finished. Success: %, Errors: %', p_job_id, v_actually_replaced_lu_count, v_error_count;

            IF v_actually_replaced_lu_count > 0 THEN
                FOR rec_created_lu IN
                    SELECT
                        tbd.data_row_id,
                        tpai.actual_legal_unit_id as new_legal_unit_id,
                        tbd.edit_by_user_id,
                        tbd.edit_at,
                        tbd.edit_comment
                    FROM temp_batch_data tbd
                    JOIN temp_processed_action_lu_ids tpai ON tbd.data_row_id = tpai.data_row_id
                    WHERE tbd.data_row_id = ANY(v_batch_success_row_ids) AND tbd.action = 'replace'
                LOOP
                    FOR rec_ident_type IN SELECT * FROM public.external_ident_type_active ORDER BY priority LOOP
                        v_data_table_col_name := rec_ident_type.code;
                        BEGIN
                            EXECUTE format('SELECT %I FROM public.%I WHERE row_id = %L',
                                           v_data_table_col_name, v_data_table_name, rec_created_lu.data_row_id)
                            INTO v_ident_value;

                            IF v_ident_value IS NOT NULL AND v_ident_value <> '' THEN
                                RAISE DEBUG '[Job %] process_legal_unit: For existing LU (id: %), data_row_id: %, ident_type: % (code: %), value: %',
                                            p_job_id, rec_created_lu.new_legal_unit_id, rec_created_lu.data_row_id, rec_ident_type.id, rec_ident_type.code, v_ident_value;
                                INSERT INTO public.external_ident (legal_unit_id, type_id, ident, edit_by_user_id, edit_at, edit_comment)
                                VALUES (rec_created_lu.new_legal_unit_id, rec_ident_type.id, v_ident_value, rec_created_lu.edit_by_user_id, rec_created_lu.edit_at, rec_created_lu.edit_comment)
                                ON CONFLICT (type_id, ident) DO UPDATE SET
                                    legal_unit_id = EXCLUDED.legal_unit_id, establishment_id = NULL, enterprise_id = NULL, enterprise_group_id = NULL,
                                    edit_by_user_id = EXCLUDED.edit_by_user_id, edit_at = EXCLUDED.edit_at, edit_comment = EXCLUDED.edit_comment;
                            END IF;
                        EXCEPTION
                            WHEN undefined_column THEN
                                RAISE DEBUG '[Job %] process_legal_unit: Column % for ident type % not found in % for data_row_id %, skipping this ident type for this row.',
                                            p_job_id, v_data_table_col_name, rec_ident_type.code, v_data_table_name, rec_created_lu.data_row_id;
                        END;
                    END LOOP;
                END LOOP;
                RAISE DEBUG '[Job %] process_legal_unit: Ensured/Updated external_ident for % successfully replaced LUs.', p_job_id, v_actually_replaced_lu_count;

                EXECUTE format($$
                    UPDATE public.%I dt SET
                        legal_unit_id = tpai.actual_legal_unit_id,
                        last_completed_priority = %L,
                        error = NULL,
                        state = %L
                    FROM temp_processed_action_lu_ids tpai
                    WHERE dt.row_id = tpai.data_row_id AND dt.row_id = ANY(%L) AND dt.action = 'replace';
                $$, v_data_table_name, v_step.priority, 'processing'::public.import_data_state, v_batch_success_row_ids);
                RAISE DEBUG '[Job %] process_legal_unit: Updated _data table for % successfully replaced LUs with correct ID.', p_job_id, v_actually_replaced_lu_count;
            END IF;
        END IF; -- End v_intended_replace_lu_count > 0

        -- Handle UPDATE action
        RAISE DEBUG '[Job %] process_legal_unit: Handling UPDATE action for existing LUs.', p_job_id;
        INSERT INTO temp_lu_update_source (
            row_id, founding_row_id, id, valid_after, valid_to, name, birth_date, death_date, active,
            sector_id, unit_size_id, status_id, legal_form_id, enterprise_id,
            primary_for_enterprise, data_source_id, invalid_codes, -- Added invalid_codes
            edit_by_user_id, edit_at, edit_comment
        )
        SELECT
            tbd.data_row_id, tbd.founding_row_id, tbd.existing_lu_id, tbd.valid_after, tbd.valid_to, tbd.name,
            tbd.typed_birth_date, tbd.typed_death_date, true, -- Assuming active=true for update actions
            tbd.sector_id, tbd.unit_size_id, tbd.status_id, tbd.legal_form_id, tbd.enterprise_id,
            tbd.primary_for_enterprise, tbd.data_source_id,
            tbd.invalid_codes,
            tbd.edit_by_user_id, tbd.edit_at,
            tbd.edit_comment
        FROM (
            SELECT DISTINCT ON (existing_lu_id, valid_after) * -- Select one row per LU ID and valid_after
            FROM temp_batch_data
            WHERE action = 'update'
            ORDER BY existing_lu_id ASC NULLS LAST, valid_after ASC, data_row_id ASC -- Deterministic pick
        ) tbd;

        GET DIAGNOSTICS v_intended_update_lu_count = ROW_COUNT;
        RAISE DEBUG '[Job %] process_legal_unit: Populated temp_lu_update_source with % rows for action=update.', p_job_id, v_intended_update_lu_count;

        IF v_intended_update_lu_count > 0 THEN
            v_batch_error_row_ids := ARRAY[]::BIGINT[];
            v_batch_success_row_ids := ARRAY[]::BIGINT[];
            -- Clear and reuse temp_processed_action_lu_ids for this action type if needed, or ensure it's empty.
            -- For simplicity, if external_idents are not re-processed for 'update', this might not be strictly needed for ID storage,
            -- but good for consistency if the _data table's legal_unit_id needs updating.
            DELETE FROM temp_processed_action_lu_ids WHERE data_row_id = ANY (SELECT data_row_id FROM temp_lu_update_source);

            RAISE DEBUG '[Job %] process_legal_unit: Calling batch_insert_or_update_generic_valid_time_table for legal_unit (update).', p_job_id;
            FOR v_batch_result IN
                SELECT * FROM import.batch_insert_or_update_generic_valid_time_table(
                    p_target_schema_name => 'public', p_target_table_name => 'legal_unit',
                    p_source_schema_name => 'pg_temp', p_source_table_name => 'temp_lu_update_source',
                    p_id_column_name => 'id', -- Ensure this is the PK in temp_lu_update_source
                    p_unique_columns => '[]'::jsonb,
                    p_ephemeral_columns => ARRAY['edit_comment', 'edit_by_user_id', 'edit_at', 'primary_for_enterprise', 'invalid_codes']
                    -- p_source_row_id_column_name, p_temporal_columns, p_founding_row_id_column_name are removed
                )
            LOOP
                IF v_batch_result.status = 'ERROR' THEN
                    v_batch_error_row_ids := array_append(v_batch_error_row_ids, v_batch_result.source_row_id);
                    EXECUTE format($$
                        UPDATE public.%I SET state = %L, error = COALESCE(error, '{}'::jsonb) || jsonb_build_object('batch_update_lu_error', %L)
                        -- last_completed_priority is preserved (not changed) on error
                        WHERE row_id = %L;
                    $$, v_data_table_name, 'error'::public.import_data_state, v_batch_result.error_message, v_batch_result.source_row_id);
                ELSE
                    v_batch_success_row_ids := array_append(v_batch_success_row_ids, v_batch_result.source_row_id);
                    INSERT INTO temp_processed_action_lu_ids (data_row_id, actual_legal_unit_id)
                    VALUES (v_batch_result.source_row_id, v_batch_result.upserted_record_id); -- Corrected to upserted_record_id
                END IF;
            END LOOP;

            v_actually_updated_lu_count := array_length(v_batch_success_row_ids, 1);
            v_error_count := v_error_count + array_length(v_batch_error_row_ids, 1);
            RAISE DEBUG '[Job %] process_legal_unit: Batch update finished. Success: %, Errors: %',
                        p_job_id, v_actually_updated_lu_count, array_length(v_batch_error_row_ids, 1);

            IF v_actually_updated_lu_count > 0 THEN
                -- External idents are generally not re-processed on 'update' unless the definition implies they can change.
                -- If they could, logic similar to 'replace' would be needed here.
                -- Update the _data table with the actual ID and advance state.
                EXECUTE format($$
                    UPDATE public.%I dt SET
                        legal_unit_id = tpai.actual_legal_unit_id,
                        last_completed_priority = %L,
                        error = NULL,
                        state = %L
                    FROM temp_processed_action_lu_ids tpai
                    WHERE dt.row_id = tpai.data_row_id AND dt.row_id = ANY(%L) AND dt.action = 'update';
                $$, v_data_table_name, v_step.priority, 'processing'::public.import_data_state, v_batch_success_row_ids);
                RAISE DEBUG '[Job %] process_legal_unit: Updated _data table for % successfully updated LUs with correct ID.', p_job_id, v_actually_updated_lu_count;
            END IF;
        END IF; -- End v_intended_update_lu_count > 0

    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
        RAISE WARNING '[Job %] process_legal_unit: Error during batch operation: %', p_job_id, replace(error_message, '%', '%%');
        UPDATE public.import_job
        SET error = jsonb_build_object('process_legal_unit_error', error_message),
            state = 'finished'
        WHERE id = p_job_id;
        RAISE DEBUG '[Job %] process_legal_unit: Marked job as failed due to error: %', p_job_id, error_message;
        RAISE; -- Re-raise to halt processing
    END;

    EXECUTE format($$UPDATE public.%I SET last_completed_priority = %L WHERE row_id = ANY(%L) AND action = 'skip'$$,
                   v_job.data_table_name, v_step.priority, p_batch_row_ids);

    RAISE DEBUG '[Job %] process_legal_unit (Batch): Finished. New (insert): %, Replaced (ok): %, Updated (ok): %. Total Errors in step: %',
        p_job_id, v_inserted_new_lu_count, v_actually_replaced_lu_count, v_actually_updated_lu_count, v_error_count;

    DROP TABLE IF EXISTS temp_batch_data;
    DROP TABLE IF EXISTS temp_created_lus;
    DROP TABLE IF EXISTS temp_lu_replace_source;
    DROP TABLE IF EXISTS temp_lu_update_source;
    DROP TABLE IF EXISTS temp_processed_action_lu_ids;
    DROP TABLE IF EXISTS temp_lu_demotion_ops;

EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
    RAISE WARNING '[Job %] process_legal_unit: Unhandled error: %', p_job_id, replace(error_message, '%', '%%');
    -- Ensure all temp tables are dropped
    DROP TABLE IF EXISTS temp_batch_data; DROP TABLE IF EXISTS temp_created_lus;
    DROP TABLE IF EXISTS temp_lu_replace_source; DROP TABLE IF EXISTS temp_lu_update_source;
    DROP TABLE IF EXISTS temp_processed_action_lu_ids; DROP TABLE IF EXISTS temp_lu_demotion_ops;
    -- Attempt to mark individual data rows as error (best effort)
    BEGIN
        v_sql := format($$UPDATE public.%I SET state = %L, error = COALESCE(error, '{}'::jsonb) || jsonb_build_object('unhandled_error_process_lu', %L) WHERE row_id = ANY(%L) AND state != 'error'$$, -- LCP not changed here
                       v_data_table_name, 'error'::public.import_data_state, error_message, p_batch_row_ids);
        EXECUTE v_sql;
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING '[Job %] process_legal_unit: Failed to mark individual data rows as error after unhandled exception: %', p_job_id, SQLERRM;
    END;
    -- Mark the job as failed
    UPDATE public.import_job
    SET error = jsonb_build_object('process_legal_unit_unhandled_error', error_message),
        state = 'finished'
    WHERE id = p_job_id;
    RAISE DEBUG '[Job %] process_legal_unit: Marked job as failed due to unhandled error: %', p_job_id, error_message;
    RAISE; -- Re-raise the original unhandled error
END;
$process_legal_unit$;

COMMIT;

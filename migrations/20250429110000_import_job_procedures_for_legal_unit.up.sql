-- Implements the analyse and operation procedures for the legal_unit import target.

-- Procedure to analyse base legal unit data
CREATE OR REPLACE PROCEDURE import.analyse_legal_unit(p_job_id INT, p_batch_row_ids INTEGER[], p_step_code TEXT)
LANGUAGE plpgsql AS $analyse_legal_unit$
DECLARE
    v_job public.import_job;
    v_snapshot JSONB;
    v_definition_snapshot JSONB; -- Renamed to avoid conflict with CONVENTIONS.md example
    v_step public.import_step;
    v_sql TEXT;
    v_update_count INT := 0;
    v_skipped_update_count INT := 0;
    v_error_count INT := 0;
    v_error_keys_to_clear_arr TEXT[] := ARRAY['name', 'data_source_code', 'legal_form_code', 'sector_code', 'unit_size_code', 'birth_date', 'death_date', 'status_id_missing', 'legal_unit'];
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

    -- Find the step details from the snapshot
    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = 'legal_unit';
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] legal_unit target step not found in snapshot', p_job_id;
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
                (import.safe_cast_to_date(dt_sub.birth_date)).p_value as resolved_typed_birth_date,
                (import.safe_cast_to_date(dt_sub.birth_date)).p_error_message as birth_date_error_msg,
                (import.safe_cast_to_date(dt_sub.death_date)).p_value as resolved_typed_death_date,
                (import.safe_cast_to_date(dt_sub.death_date)).p_error_message as death_date_error_msg
            FROM public.%1$I dt_sub
            LEFT JOIN public.data_source_available ds ON NULLIF(dt_sub.data_source_code, '') IS NOT NULL AND ds.code = NULLIF(dt_sub.data_source_code, '')
            LEFT JOIN public.legal_form_available lf ON NULLIF(dt_sub.legal_form_code, '') IS NOT NULL AND lf.code = NULLIF(dt_sub.legal_form_code, '')
            -- LEFT JOIN public.status s ON NULLIF(dt_sub.status_code, '') IS NOT NULL AND s.code = NULLIF(dt_sub.status_code, '') AND s.active = true -- Removed
            LEFT JOIN public.sector_available sec ON NULLIF(dt_sub.sector_code, '') IS NOT NULL AND sec.code = NULLIF(dt_sub.sector_code, '')
            LEFT JOIN public.unit_size_available us ON NULLIF(dt_sub.unit_size_code, '') IS NOT NULL AND us.code = NULLIF(dt_sub.unit_size_code, '')
            WHERE dt_sub.row_id = ANY($1) AND dt_sub.action IS DISTINCT FROM 'skip'
        )
        UPDATE public.%2$I dt SET
            data_source_id = l.resolved_data_source_id,
            legal_form_id = l.resolved_legal_form_id,
            -- status_id = CASE ... END, -- Removed: status_id is now populated by 'status' step
            sector_id = l.resolved_sector_id,
            unit_size_id = l.resolved_unit_size_id,
            typed_birth_date = l.resolved_typed_birth_date,
            typed_death_date = l.resolved_typed_death_date,
            state = CASE
                        WHEN NULLIF(trim(dt.name), '') IS NULL THEN 'error'::public.import_data_state
                        WHEN dt.status_id IS NULL THEN 'error'::public.import_data_state
                        ELSE 'analysing'::public.import_data_state
                    END,
            action = CASE
                        WHEN NULLIF(trim(dt.name), '') IS NULL THEN 'skip'::public.import_row_action_type
                        WHEN dt.status_id IS NULL THEN 'skip'::public.import_row_action_type
                        ELSE dt.action
                     END,
            errors = CASE
                        WHEN NULLIF(trim(dt.name), '') IS NULL THEN
                            COALESCE(dt.errors, '{}'::jsonb) || jsonb_build_object('name', 'Missing required name')
                        WHEN dt.status_id IS NULL THEN
                            COALESCE(dt.errors, '{}'::jsonb) || jsonb_build_object('status_code', 'Status code could not be resolved and is required for this operation.')
                        ELSE 
                            CASE WHEN (dt.errors - %3$L::TEXT[]) = '{}'::jsonb THEN NULL ELSE (dt.errors - %3$L::TEXT[]) END
                    END,
            invalid_codes = CASE
                                WHEN (NULLIF(trim(dt.name), '') IS NOT NULL) AND dt.status_id IS NOT NULL THEN -- Only populate invalid_codes if no fatal error in this step
                                    jsonb_strip_nulls(
                                     COALESCE(dt.invalid_codes, '{}'::jsonb) - %4$L::TEXT[] || 
                                     jsonb_build_object('data_source_code', CASE WHEN NULLIF(dt.data_source_code, '') IS NOT NULL AND l.resolved_data_source_id IS NULL THEN dt.data_source_code ELSE NULL END) ||
                                     jsonb_build_object('legal_form_code', CASE WHEN NULLIF(dt.legal_form_code, '') IS NOT NULL AND l.resolved_legal_form_id IS NULL THEN dt.legal_form_code ELSE NULL END) ||
                                     jsonb_build_object('sector_code', CASE WHEN NULLIF(dt.sector_code, '') IS NOT NULL AND l.resolved_sector_id IS NULL THEN dt.sector_code ELSE NULL END) ||
                                     jsonb_build_object('unit_size_code', CASE WHEN NULLIF(dt.unit_size_code, '') IS NOT NULL AND l.resolved_unit_size_id IS NULL THEN dt.unit_size_code ELSE NULL END) ||
                                     jsonb_build_object('birth_date', CASE WHEN NULLIF(dt.birth_date, '') IS NOT NULL AND l.birth_date_error_msg IS NOT NULL THEN dt.birth_date ELSE NULL END) ||
                                     jsonb_build_object('death_date', CASE WHEN NULLIF(dt.death_date, '') IS NOT NULL AND l.death_date_error_msg IS NOT NULL THEN dt.death_date ELSE NULL END)
                                    )
                                ELSE dt.invalid_codes -- Keep existing invalid_codes if it's a fatal status_id error (action will be skip anyway)
                            END,
            last_completed_priority = %5$L -- Always v_step.priority
        FROM lookups l
        WHERE dt.row_id = l.data_row_id; -- Join is sufficient, lookups CTE is already filtered
    $$,
        v_job.data_table_name /* %1$I */,                           -- For lookups CTE
        v_job.data_table_name /* %2$I */,                           -- For main UPDATE target
        v_error_keys_to_clear_arr /* %3$L */,                       -- For error CASE (clear)
        v_invalid_code_keys_arr /* %4$L */,                         -- For invalid_codes CASE (clear old)
        v_step.priority /* %5$L */                                  -- For last_completed_priority (always this step's priority)
    );

    RAISE DEBUG '[Job %] analyse_legal_unit: Single-pass batch update for non-skipped rows: %', p_job_id, v_sql;

    BEGIN
        EXECUTE v_sql USING p_batch_row_ids;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_legal_unit: Updated % non-skipped rows in single pass.', p_job_id, v_update_count;

        -- Update priority for skipped rows
        EXECUTE format($$
            UPDATE public.%1$I dt SET
                last_completed_priority = %2$L
            WHERE dt.row_id = ANY($1) AND dt.action = 'skip';
        $$, v_job.data_table_name /* %1$I */, v_step.priority /* %2$L */) USING p_batch_row_ids;
        GET DIAGNOSTICS v_skipped_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_legal_unit: Updated last_completed_priority for % skipped rows.', p_job_id, v_skipped_update_count;

        v_update_count := v_update_count + v_skipped_update_count; -- Total rows affected

        EXECUTE format($$SELECT COUNT(*) FROM public.%1$I WHERE row_id = ANY($1) AND state = 'error' AND (errors ?| %2$L::text[])$$,
                       v_job.data_table_name /* %1$I */, v_error_keys_to_clear_arr /* %2$L */)
        INTO v_error_count
        USING p_batch_row_ids;
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

    -- Propagate errors to all rows of a new entity if one fails
    CALL import.propagate_fatal_error_to_entity_batch(p_job_id, v_job.data_table_name, p_batch_row_ids, v_error_keys_to_clear_arr, 'analyse_legal_unit');

    RAISE DEBUG '[Job %] analyse_legal_unit (Batch): Finished analysis for batch. Total errors in batch: %', p_job_id, v_error_count;
END;
$analyse_legal_unit$;


CREATE OR REPLACE PROCEDURE import.process_legal_unit(IN p_job_id integer, IN p_batch_row_ids integer[], IN p_step_code text)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_job public.import_job;
    v_definition public.import_definition;
    v_definition_snapshot JSONB;
    v_step public.import_step;
    v_edit_by_user_id INT;
    v_data_table_name TEXT;
    v_sql TEXT;
    v_error_count INT := 0;
    v_update_count INT := 0;
    error_message TEXT;
    v_batch_result RECORD;
    rec_created_lu RECORD;
    v_start_time TIMESTAMPTZ;
    v_duration_ms NUMERIC;
BEGIN
    v_start_time := clock_timestamp();
    RAISE DEBUG '[Job %] process_legal_unit (Batch): Starting operation for % rows', p_job_id, array_length(p_batch_row_ids, 1);

    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;
    v_definition_snapshot := v_job.definition_snapshot;

    IF v_definition_snapshot IS NULL OR jsonb_typeof(v_definition_snapshot) != 'object' THEN
        RAISE EXCEPTION '[Job %] Failed to load valid definition snapshot from import_job record', p_job_id;
    END IF;
    SELECT * INTO v_definition FROM jsonb_populate_record(NULL::public.import_definition, v_job.definition_snapshot->'import_definition');
    IF v_definition IS NULL THEN RAISE EXCEPTION '[Job %] Failed to load import_definition from snapshot', p_job_id; END IF;

    -- Find the step details from the snapshot
    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = 'legal_unit';
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] legal_unit target step not found in snapshot', p_job_id;
    END IF;

    v_edit_by_user_id := v_job.user_id;

    RAISE DEBUG '[Job %] process_legal_unit: Operation Type: %, User ID: %', p_job_id, v_definition.strategy, v_edit_by_user_id;

    -- Resolve primary_for_enterprise conflicts within the current batch in the main data table
    RAISE DEBUG '[Job %] process_legal_unit: Resolving primary_for_enterprise conflicts within the batch in %s.', p_job_id, v_data_table_name;
    v_sql := format($$
        WITH BatchPrimaries AS (
            SELECT
                row_id,
                FIRST_VALUE(row_id) OVER (
                    PARTITION BY enterprise_id, daterange(derived_valid_from, derived_valid_until, '[)')
                    ORDER BY legal_unit_id ASC NULLS LAST, row_id ASC
                ) as winner_row_id
            FROM public.%1$I
            WHERE row_id = ANY($1) AND primary_for_enterprise = true AND enterprise_id IS NOT NULL
        )
        UPDATE public.%1$I dt
        SET primary_for_enterprise = false
        FROM BatchPrimaries bp
        WHERE dt.row_id = bp.row_id
          AND dt.row_id != bp.winner_row_id
          AND dt.primary_for_enterprise = true;
    $$, v_data_table_name);
    EXECUTE v_sql USING p_batch_row_ids;

    IF FOUND THEN
        RAISE DEBUG '[Job %] process_legal_unit: Resolved primary_for_enterprise conflicts in %s.', p_job_id, v_data_table_name;
    END IF;

    -- Create an updatable view over the batch data. This avoids copying data to a temp table
    -- and allows sql_saga to write feedback and generated IDs directly back to the main data table.
    v_sql := format($$
        CREATE OR REPLACE TEMP VIEW temp_lu_source_view AS
        SELECT
            row_id AS data_row_id,
            founding_row_id,
            legal_unit_id AS id,
            name,
            typed_birth_date AS birth_date,
            typed_death_date AS death_date,
            derived_valid_from AS valid_from,
            derived_valid_to AS valid_to,
            derived_valid_until AS valid_until,
            sector_id,
            unit_size_id,
            status_id,
            legal_form_id,
            data_source_id,
            enterprise_id,
            primary_for_enterprise,
            edit_by_user_id,
            edit_at,
            edit_comment,
            invalid_codes,
            errors,
            merge_statuses
        FROM public.%1$I
        WHERE row_id = ANY(%2$L) AND action = 'use' AND state != 'error';
    $$, v_data_table_name, p_batch_row_ids);
    EXECUTE v_sql;

    BEGIN
        -- Demotion logic
        IF to_regclass('pg_temp.temp_lu_demotion_source') IS NOT NULL THEN DROP TABLE temp_lu_demotion_source; END IF;
        CREATE TEMP TABLE temp_lu_demotion_source (
            row_id int generated by default as identity,
            id INT NOT NULL,
            primary_for_enterprise BOOLEAN NOT NULL,
            valid_from DATE NOT NULL,
            valid_until DATE NOT NULL,
            edit_by_user_id INT,
            edit_at TIMESTAMPTZ,
            edit_comment TEXT
        ) ON COMMIT DROP;

        RAISE DEBUG '[Job %] process_legal_unit: Starting demotion of conflicting primary LUs.', p_job_id;
        v_sql := format($$
            INSERT INTO temp_lu_demotion_source (id, primary_for_enterprise, valid_from, valid_until, edit_by_user_id, edit_at, edit_comment)
            SELECT
                ex_lu.id, false, incoming_primary.new_primary_valid_from, incoming_primary.new_primary_valid_until,
                incoming_primary.demotion_edit_by_user_id, incoming_primary.demotion_edit_at,
                COALESCE(ex_lu.edit_comment || '; ', '') || 'Demoted: LU ' || COALESCE(incoming_primary.incoming_lu_id::TEXT, 'NEW') ||
                    ' became primary for enterprise ' || incoming_primary.target_enterprise_id ||
                    ' for period [' || incoming_primary.new_primary_valid_from || ', ' || incoming_primary.new_primary_valid_until || ')' ||
                    ' by job ' || %2$L
            FROM public.legal_unit ex_lu
            JOIN (
                SELECT dt.legal_unit_id AS incoming_lu_id, dt.enterprise_id AS target_enterprise_id,
                       dt.derived_valid_from AS new_primary_valid_from, dt.derived_valid_until AS new_primary_valid_until,
                       dt.edit_by_user_id AS demotion_edit_by_user_id, dt.edit_at AS demotion_edit_at
                FROM public.%1$I dt
                WHERE dt.row_id = ANY($1) AND dt.primary_for_enterprise = true AND dt.enterprise_id IS NOT NULL
            ) AS incoming_primary
            ON ex_lu.enterprise_id = incoming_primary.target_enterprise_id
            WHERE ex_lu.id IS DISTINCT FROM incoming_primary.incoming_lu_id
              AND ex_lu.primary_for_enterprise = true
              AND public.from_until_overlaps(ex_lu.valid_from, ex_lu.valid_until, incoming_primary.new_primary_valid_from, incoming_primary.new_primary_valid_until);
        $$, v_data_table_name, p_job_id);
        EXECUTE v_sql USING p_batch_row_ids;

        IF FOUND THEN
            RAISE DEBUG '[Job %] process_legal_unit: Identified % LUs for demotion.', p_job_id, (SELECT count(*) FROM temp_lu_demotion_source);
            CALL sql_saga.temporal_merge(
                p_target_table => 'public.legal_unit'::regclass,
                p_source_table => 'temp_lu_demotion_source'::regclass,
                p_identity_columns => ARRAY['id'],
                p_ephemeral_columns => ARRAY['edit_comment', 'edit_by_user_id', 'edit_at'],
                p_mode => 'PATCH_FOR_PORTION_OF',
                p_source_row_id_column => 'row_id'
            );
            FOR v_batch_result IN SELECT * FROM pg_temp.temporal_merge_feedback WHERE status = 'ERROR' LOOP
                 RAISE WARNING '[Job %] process_legal_unit: Error during demotion for LU ID %: %', p_job_id, (v_batch_result.target_entity_ids->0->>'id')::INT, v_batch_result.error_message;
            END LOOP;
        ELSE
            RAISE DEBUG '[Job %] process_legal_unit: No existing primary LUs found to demote.', p_job_id;
        END IF;

        -- Main data merge operation
        RAISE DEBUG '[Job %] process_legal_unit: Calling main sql_saga.temporal_merge operation.', p_job_id;
        CALL sql_saga.temporal_merge(
            p_target_table => 'public.legal_unit'::regclass,
            p_source_table => 'temp_lu_source_view'::regclass,
            p_identity_columns => ARRAY['id'],
            p_ephemeral_columns => ARRAY['edit_comment', 'edit_by_user_id', 'edit_at', 'invalid_codes'],
            p_mode => 'MERGE_ENTITY_REPLACE',
            p_identity_correlation_column => 'founding_row_id',
            p_update_source_with_identity => true,
            p_update_source_with_feedback => true,
            p_feedback_status_column => 'merge_statuses',
            p_feedback_status_key => 'legal_unit',
            p_feedback_error_column => 'errors',
            p_feedback_error_key => 'legal_unit',
            p_source_row_id_column => 'data_row_id'
        );

        -- With feedback written directly to the data table, we just need to count successes and errors.
        EXECUTE format($$ SELECT count(*) FROM public.%1$I WHERE row_id = ANY($1) AND errors->'legal_unit' IS NOT NULL $$, v_data_table_name)
            INTO v_error_count USING p_batch_row_ids;

        EXECUTE format($$
            UPDATE public.%1$I dt SET
                state = CASE WHEN dt.errors IS NULL THEN 'processing'::public.import_data_state ELSE 'error'::public.import_data_state END
            WHERE dt.row_id = ANY($1) AND dt.action = 'use';
        $$, v_data_table_name)
        USING p_batch_row_ids;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        v_update_count := v_update_count - v_error_count;

        RAISE DEBUG '[Job %] process_legal_unit: temporal_merge finished. Success: %, Errors: %', p_job_id, v_update_count, v_error_count;

    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
        RAISE WARNING '[Job %] process_legal_unit: Error during batch operation: %', p_job_id, replace(error_message, '%', '%%');
        UPDATE public.import_job
        SET error = jsonb_build_object('process_legal_unit_error', error_message), state = 'finished'
        WHERE id = p_job_id;
        RAISE;
    END;

    -- The framework now handles advancing priority for all rows, including 'skip'. No update needed here.

    v_duration_ms := (EXTRACT(EPOCH FROM (clock_timestamp() - v_start_time)) * 1000);
    RAISE DEBUG '[Job %] process_legal_unit (Batch): Finished in % ms. Success: %, Errors: %',
        p_job_id, round(v_duration_ms, 2), v_update_count, v_error_count;

    IF to_regclass('pg_temp.temp_lu_source_view') IS NOT NULL THEN DROP VIEW temp_lu_source_view; END IF;
    IF to_regclass('pg_temp.temp_lu_demotion_source') IS NOT NULL THEN DROP TABLE temp_lu_demotion_source; END IF;

EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
    RAISE WARNING '[Job %] process_legal_unit: Unhandled error: %', p_job_id, replace(error_message, '%', '%%');
    -- Ensure all temp tables are dropped
    IF to_regclass('pg_temp.temp_lu_source_view') IS NOT NULL THEN DROP VIEW temp_lu_source_view; END IF;
    IF to_regclass('pg_temp.temp_lu_demotion_source') IS NOT NULL THEN DROP TABLE temp_lu_demotion_source; END IF;
    -- Attempt to mark individual data rows as error (best effort)
    BEGIN
        v_sql := format($$UPDATE public.%1$I SET state = %2$L, errors = COALESCE(errors, '{}'::jsonb) || jsonb_build_object('unhandled_error_process_lu', %3$L) WHERE row_id = ANY($1) AND state != 'error'$$, -- LCP not changed here
                       v_data_table_name /* %1$I */, 'error'::public.import_data_state /* %2$L */, error_message /* %3$L */);
        EXECUTE v_sql USING p_batch_row_ids;
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
$procedure$;

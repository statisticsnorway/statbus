BEGIN;

-- Procedure to analyse base establishment data (Batch Oriented)
CREATE OR REPLACE PROCEDURE import.analyse_establishment(p_job_id INT, p_batch_row_ids INTEGER[], p_step_code TEXT)
LANGUAGE plpgsql AS $analyse_establishment$
DECLARE
    v_job public.import_job;
    v_snapshot JSONB;
    v_step public.import_step;
    v_data_table_name TEXT;
    v_error_count INT := 0;
    v_update_count INT := 0;
    v_skipped_update_count INT := 0;
    v_sql TEXT;
    v_error_keys_to_clear_arr TEXT[] := ARRAY['name', 'sector_code', 'unit_size_code', 'birth_date', 'death_date', 'status_id_missing', 'establishment'];
    v_invalid_code_keys_arr TEXT[] := ARRAY['sector_code', 'unit_size_code', 'birth_date', 'death_date'];
BEGIN
    RAISE DEBUG '[Job %] analyse_establishment (Batch): Starting analysis for % rows', p_job_id, array_length(p_batch_row_ids, 1);

    -- Get default status_id -- Removed
    -- SELECT id INTO v_default_status_id FROM public.status WHERE assigned_by_default = true AND active = true LIMIT 1;
    -- RAISE DEBUG '[Job %] analyse_establishment: Default status_id found: %', p_job_id, v_default_status_id;

    -- Get job details and snapshot
    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name; 

    -- Find the step details from the snapshot
    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = 'establishment';
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] establishment target not found in snapshot', p_job_id;
    END IF;

    v_sql := format($$
        WITH lookups AS (
            SELECT
                dt_sub.row_id as data_row_id,
                -- s.id as resolved_status_id, -- Removed status lookup
                sec.id as resolved_sector_id,
                us.id as resolved_unit_size_id,
                (import.safe_cast_to_date(dt_sub.birth_date)).p_value as resolved_typed_birth_date,
                (import.safe_cast_to_date(dt_sub.birth_date)).p_error_message as birth_date_error_msg,
                (import.safe_cast_to_date(dt_sub.death_date)).p_value as resolved_typed_death_date,
                (import.safe_cast_to_date(dt_sub.death_date)).p_error_message as death_date_error_msg
            FROM public.%1$I dt_sub
            -- LEFT JOIN public.status s ON NULLIF(dt_sub.status_code, '') IS NOT NULL AND s.code = NULLIF(dt_sub.status_code, '') AND s.active = true -- Removed
            LEFT JOIN public.sector_available sec ON NULLIF(dt_sub.sector_code, '') IS NOT NULL AND sec.code = NULLIF(dt_sub.sector_code, '')
            LEFT JOIN public.unit_size_available us ON NULLIF(dt_sub.unit_size_code, '') IS NOT NULL AND us.code = NULLIF(dt_sub.unit_size_code, '')
            WHERE dt_sub.row_id = ANY($1) AND dt_sub.action IS DISTINCT FROM 'skip' -- Exclude skipped rows
        )
        UPDATE public.%2$I dt SET
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
            action = CASE -- Added action update
                        WHEN NULLIF(trim(dt.name), '') IS NULL THEN 'skip'::public.import_row_action_type
                        WHEN dt.status_id IS NULL THEN 'skip'::public.import_row_action_type
                        ELSE dt.action
                     END,
            errors = CASE
                        WHEN NULLIF(trim(dt.name), '') IS NULL THEN
                            dt.errors || jsonb_build_object('name', 'Missing required name')
                        WHEN dt.status_id IS NULL THEN
                            dt.errors || jsonb_build_object('status_code', 'Status code could not be resolved and is required for this operation.')
                        ELSE
                            dt.errors - %3$L::TEXT[]
                    END,
            invalid_codes = CASE
                                WHEN (NULLIF(trim(dt.name), '') IS NOT NULL) AND dt.status_id IS NOT NULL THEN -- Only populate invalid_codes if no fatal error in this step
                                    jsonb_strip_nulls(
                                     (dt.invalid_codes - %4$L::TEXT[]) ||
                                     jsonb_build_object('sector_code', CASE WHEN NULLIF(dt.sector_code, '') IS NOT NULL AND l.resolved_sector_id IS NULL THEN dt.sector_code ELSE NULL END) ||
                                     jsonb_build_object('unit_size_code', CASE WHEN NULLIF(dt.unit_size_code, '') IS NOT NULL AND l.resolved_unit_size_id IS NULL THEN dt.unit_size_code ELSE NULL END) ||
                                     jsonb_build_object('birth_date', CASE WHEN NULLIF(dt.birth_date, '') IS NOT NULL AND l.birth_date_error_msg IS NOT NULL THEN dt.birth_date ELSE NULL END) ||
                                     jsonb_build_object('death_date', CASE WHEN NULLIF(dt.death_date, '') IS NOT NULL AND l.death_date_error_msg IS NOT NULL THEN dt.death_date ELSE NULL END)
                                    )
                                ELSE dt.invalid_codes -- Keep existing invalid_codes if it's a fatal status_id error
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

    RAISE DEBUG '[Job %] analyse_establishment: Single-pass batch update for non-skipped rows: %', p_job_id, v_sql;

    BEGIN
        EXECUTE v_sql USING p_batch_row_ids;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_establishment: Updated % non-skipped rows in single pass.', p_job_id, v_update_count;

        -- Update priority for skipped rows
        EXECUTE format($$
            UPDATE public.%1$I dt SET
                last_completed_priority = %2$L
            WHERE dt.row_id = ANY($1) AND dt.action = 'skip';
        $$, v_data_table_name /* %1$I */, v_step.priority /* %2$L */) USING p_batch_row_ids;
        GET DIAGNOSTICS v_skipped_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_establishment: Updated last_completed_priority for % skipped rows.', p_job_id, v_skipped_update_count;

        v_update_count := v_update_count + v_skipped_update_count; -- Total rows affected

        EXECUTE format($$SELECT COUNT(*) FROM public.%1$I WHERE row_id = ANY($1) AND state = 'error' AND (errors ?| %2$L::text[])$$,
                       v_job.data_table_name /* %1$I */, v_error_keys_to_clear_arr /* %2$L */)
        INTO v_error_count
        USING p_batch_row_ids;
        RAISE DEBUG '[Job %] analyse_establishment: Estimated errors in this step for batch: %', p_job_id, v_error_count;

    EXCEPTION WHEN others THEN
        RAISE WARNING '[Job %] analyse_establishment: Error during single-pass batch update: %', p_job_id, SQLERRM;
        UPDATE public.import_job
        SET error = jsonb_build_object('analyse_establishment_batch_error', SQLERRM),
            state = 'finished'
        WHERE id = p_job_id;
        RAISE DEBUG '[Job %] analyse_establishment: Marked job as failed due to error: %', p_job_id, SQLERRM;
        RAISE;
    END;

    -- Propagate errors to all rows of a new entity if one fails
    CALL import.propagate_fatal_error_to_entity_batch(p_job_id, v_job.data_table_name, p_batch_row_ids, v_error_keys_to_clear_arr, 'analyse_establishment');

    -- Resolve primary conflicts within the current batch in the main data table
    -- This is done here because this step runs AFTER link steps have populated parent IDs and primary flags
    IF v_job.definition_snapshot->'import_definition'->>'mode' = 'establishment_formal' THEN
        v_sql := format($$
            WITH BatchPrimaries AS (
                SELECT row_id, FIRST_VALUE(row_id) OVER (PARTITION BY legal_unit_id, daterange(derived_valid_from, derived_valid_until, '[)') ORDER BY establishment_id ASC NULLS LAST, row_id ASC) as winner_row_id
                FROM public.%1$I WHERE row_id = ANY($1) AND primary_for_legal_unit = true AND legal_unit_id IS NOT NULL
            )
            UPDATE public.%1$I dt SET primary_for_legal_unit = false FROM BatchPrimaries bp
            WHERE dt.row_id = bp.row_id AND dt.row_id != bp.winner_row_id AND dt.primary_for_legal_unit = true;
        $$, v_data_table_name);
        EXECUTE v_sql USING p_batch_row_ids;
    ELSIF v_job.definition_snapshot->'import_definition'->>'mode' = 'establishment_informal' THEN
        v_sql := format($$
            WITH BatchPrimaries AS (
                SELECT row_id, FIRST_VALUE(row_id) OVER (PARTITION BY enterprise_id, daterange(derived_valid_from, derived_valid_until, '[)') ORDER BY establishment_id ASC NULLS LAST, row_id ASC) as winner_row_id
                FROM public.%1$I WHERE row_id = ANY($1) AND primary_for_enterprise = true AND enterprise_id IS NOT NULL
            )
            UPDATE public.%1$I dt SET primary_for_enterprise = false FROM BatchPrimaries bp
            WHERE dt.row_id = bp.row_id AND dt.row_id != bp.winner_row_id AND dt.primary_for_enterprise = true;
        $$, v_data_table_name);
        EXECUTE v_sql USING p_batch_row_ids;
    END IF;

    RAISE DEBUG '[Job %] analyse_establishment (Batch): Finished analysis for batch. Total errors in batch: %', p_job_id, v_error_count;
END;
$analyse_establishment$;


-- Procedure to operate (insert/update/upsert) base establishment data (Batch Oriented)
CREATE OR REPLACE PROCEDURE import.process_establishment(p_job_id INT, p_batch_row_ids INTEGER[], p_step_code TEXT)
LANGUAGE plpgsql AS $process_establishment$
DECLARE
    v_job public.import_job;
    v_definition public.import_definition;
    v_step public.import_step;
    v_data_table_name TEXT;
    v_sql TEXT;
    v_error_count INT := 0;
    v_update_count INT := 0;
    error_message TEXT;
    v_batch_result RECORD;
    rec_created_est RECORD;
    v_select_enterprise_id_expr TEXT := 'NULL::INTEGER';
    v_select_legal_unit_id_expr TEXT := 'NULL::INTEGER';
    v_select_primary_for_legal_unit_expr TEXT := 'NULL::BOOLEAN';
    v_select_primary_for_enterprise_expr TEXT := 'NULL::BOOLEAN';
    v_select_list TEXT;
    v_job_mode public.import_mode;
    v_start_time TIMESTAMPTZ;
    v_duration_ms NUMERIC;
    v_merge_mode sql_saga.temporal_merge_mode;
BEGIN
    v_start_time := clock_timestamp();
    RAISE DEBUG '[Job %] process_establishment (Batch): Starting operation for % rows', p_job_id, array_length(p_batch_row_ids, 1);

    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;
    SELECT * INTO v_definition FROM jsonb_populate_record(NULL::public.import_definition, v_job.definition_snapshot->'import_definition');

    IF v_definition IS NULL THEN
        RAISE EXCEPTION '[Job %] Failed to load valid import_definition object from definition_snapshot', p_job_id;
    END IF;

    v_job_mode := v_definition.mode;
    IF v_job_mode IS NULL OR v_job_mode NOT IN ('establishment_formal', 'establishment_informal') THEN
        RAISE EXCEPTION '[Job %] Invalid or missing mode for establishment processing: %. Expected ''establishment_formal'' or ''establishment_informal''.', p_job_id, v_job_mode;
    END IF;
    RAISE DEBUG '[Job %] process_establishment: Job mode is %', p_job_id, v_job_mode;

    -- Find the step details from the snapshot
    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = 'establishment';
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] establishment target not found in snapshot', p_job_id;
    END IF;

    -- Determine select expressions based on job mode
    IF v_job_mode = 'establishment_formal' THEN
        v_select_legal_unit_id_expr := 'dt.legal_unit_id';
        v_select_primary_for_legal_unit_expr := 'dt.primary_for_legal_unit';
    ELSIF v_job_mode = 'establishment_informal' THEN
        v_select_enterprise_id_expr := 'dt.enterprise_id';
        v_select_primary_for_enterprise_expr := 'dt.primary_for_enterprise';
    END IF;

    -- Create an updatable view over the batch data. This avoids copying data to a temp table
    -- and allows sql_saga to write feedback and generated IDs directly back to the main data table.
    v_select_list := format($$
        row_id AS data_row_id, founding_row_id, tax_ident,
        %1$s AS legal_unit_id,
        %2$s AS primary_for_legal_unit,
        %3$s AS enterprise_id,
        %4$s AS primary_for_enterprise,
        name, typed_birth_date AS birth_date, typed_death_date AS death_date,
        derived_valid_from AS valid_from, derived_valid_to AS valid_to, derived_valid_until AS valid_until,
        sector_id, unit_size_id, status_id, data_source_id,
        establishment_id AS id,
        NULLIF(invalid_codes, '{}'::jsonb) as invalid_codes,
        edit_by_user_id, edit_at, edit_comment,
        errors,
        merge_status
    $$,
        v_select_legal_unit_id_expr,          /* %1$s */
        v_select_primary_for_legal_unit_expr, /* %2$s */
        v_select_enterprise_id_expr,          /* %3$s */
        v_select_primary_for_enterprise_expr  /* %4$s */
    );

    v_sql := format($$
        CREATE OR REPLACE TEMP VIEW temp_es_source_view AS
        SELECT %1$s
        FROM public.%2$I dt
        WHERE dt.row_id = ANY(%3$L) AND dt.action = 'use';
    $$,
        v_select_list,     /* %1$s */
        v_data_table_name, /* %2$I */
        p_batch_row_ids    /* %3$L */
    );
    EXECUTE v_sql;

    BEGIN
        -- Demotion logic
        IF to_regclass('pg_temp.temp_es_demotion_source') IS NOT NULL THEN DROP TABLE temp_es_demotion_source; END IF;
        CREATE TEMP TABLE temp_es_demotion_source (
            row_id int generated by default as identity, id INT NOT NULL, valid_from DATE NOT NULL, valid_until DATE NOT NULL,
            primary_for_legal_unit BOOLEAN, primary_for_enterprise BOOLEAN,
            edit_by_user_id INT, edit_at TIMESTAMPTZ, edit_comment TEXT
        ) ON COMMIT DROP;

        IF v_job_mode = 'establishment_formal' THEN
            v_sql := format($$
                INSERT INTO temp_es_demotion_source (id, valid_from, valid_until, primary_for_legal_unit, edit_by_user_id, edit_at, edit_comment)
                SELECT ex_es.id, ipes.new_primary_valid_from, ipes.new_primary_valid_until, false, ipes.demotion_edit_by_user_id, ipes.demotion_edit_at,
                       'Demoted from primary for LU by import job ' || %L || '; new primary is EST ' ||
                       COALESCE(ipes.incoming_est_id::TEXT, 'NEW') || ' for LU ' || ipes.target_legal_unit_id ||
                       ' during [' || ipes.new_primary_valid_from || ', ' || ipes.new_primary_valid_until || ')'
                FROM public.establishment ex_es
                JOIN (SELECT dt.establishment_id AS incoming_est_id, dt.legal_unit_id AS target_legal_unit_id, dt.derived_valid_from AS new_primary_valid_from, dt.derived_valid_until AS new_primary_valid_until, dt.edit_by_user_id AS demotion_edit_by_user_id, dt.edit_at AS demotion_edit_at FROM public.%I dt WHERE dt.row_id = ANY($1) AND dt.primary_for_legal_unit = true AND dt.legal_unit_id IS NOT NULL) AS ipes
                ON ex_es.legal_unit_id = ipes.target_legal_unit_id
                WHERE ex_es.id IS DISTINCT FROM ipes.incoming_est_id AND ex_es.primary_for_legal_unit = true AND public.from_until_overlaps(ex_es.valid_from, ex_es.valid_until, ipes.new_primary_valid_from, ipes.new_primary_valid_until);
            $$, p_job_id, v_data_table_name);
            EXECUTE v_sql USING p_batch_row_ids;

            IF FOUND THEN
                CALL sql_saga.temporal_merge(
                    target_table => 'public.establishment'::regclass,
                    source_table => 'temp_es_demotion_source'::regclass,
                    identity_columns => ARRAY['id'],
                    ephemeral_columns => ARRAY['edit_comment', 'edit_by_user_id', 'edit_at'],
                    mode => 'PATCH_FOR_PORTION_OF',
                    source_row_id_column => 'row_id'
                );
                FOR v_batch_result IN SELECT * FROM pg_temp.temporal_merge_feedback WHERE status = 'ERROR' LOOP RAISE WARNING '[Job %] process_establishment: Error during PFLU demotion for EST ID %: %', p_job_id, (v_batch_result.target_entity_ids->0->>'id')::INT, v_batch_result.error_message; END LOOP;
                TRUNCATE TABLE temp_es_demotion_source;
            END IF;
        ELSIF v_job_mode = 'establishment_informal' THEN
            v_sql := format($$
                INSERT INTO temp_es_demotion_source (id, valid_from, valid_until, primary_for_enterprise, edit_by_user_id, edit_at, edit_comment)
                SELECT ex_es.id, ipes.new_primary_valid_from, ipes.new_primary_valid_until, false, ipes.demotion_edit_by_user_id, ipes.demotion_edit_at,
                       'Demoted from primary for EN by import job ' || %L || '; new primary is EST ' ||
                       COALESCE(ipes.incoming_est_id::TEXT, 'NEW') || ' for EN ' || ipes.target_enterprise_id ||
                       ' during [' || ipes.new_primary_valid_from || ', ' || ipes.new_primary_valid_until || ')'
                FROM public.establishment ex_es
                JOIN (SELECT dt.establishment_id AS incoming_est_id, dt.enterprise_id AS target_enterprise_id, dt.derived_valid_from AS new_primary_valid_from, dt.derived_valid_until AS new_primary_valid_until, dt.edit_by_user_id AS demotion_edit_by_user_id, dt.edit_at AS demotion_edit_at FROM public.%I dt WHERE dt.row_id = ANY($1) AND dt.primary_for_enterprise = true AND dt.enterprise_id IS NOT NULL) AS ipes
                ON ex_es.enterprise_id = ipes.target_enterprise_id
                WHERE ex_es.id IS DISTINCT FROM ipes.incoming_est_id AND ex_es.primary_for_enterprise = true AND public.from_until_overlaps(ex_es.valid_from, ex_es.valid_until, ipes.new_primary_valid_from, ipes.new_primary_valid_until);
            $$, p_job_id, v_data_table_name);
            EXECUTE v_sql USING p_batch_row_ids;

            IF FOUND THEN
                CALL sql_saga.temporal_merge(
                    target_table => 'public.establishment'::regclass,
                    source_table => 'temp_es_demotion_source'::regclass,
                    identity_columns => ARRAY['id'],
                    ephemeral_columns => ARRAY['edit_comment', 'edit_by_user_id', 'edit_at'],
                    mode => 'PATCH_FOR_PORTION_OF',
                    source_row_id_column => 'row_id'
                );
                FOR v_batch_result IN SELECT * FROM pg_temp.temporal_merge_feedback WHERE status = 'ERROR' LOOP RAISE WARNING '[Job %] process_establishment: Error during PFE demotion for EST ID %: %', p_job_id, (v_batch_result.target_entity_ids->0->>'id')::INT, v_batch_result.error_message; END LOOP;
                TRUNCATE TABLE temp_es_demotion_source;
            END IF;
        END IF;

        -- Main data merge operation
        -- Determine merge mode from job strategy
        v_merge_mode := CASE v_definition.strategy
            WHEN 'insert_or_replace' THEN 'MERGE_ENTITY_REPLACE'::sql_saga.temporal_merge_mode
            WHEN 'replace_only' THEN 'MERGE_ENTITY_REPLACE'::sql_saga.temporal_merge_mode
            WHEN 'insert_or_update' THEN 'MERGE_ENTITY_PATCH'::sql_saga.temporal_merge_mode
            WHEN 'update_only' THEN 'MERGE_ENTITY_PATCH'::sql_saga.temporal_merge_mode
            ELSE 'MERGE_ENTITY_PATCH'::sql_saga.temporal_merge_mode -- Default to safer patch
        END;
        RAISE DEBUG '[Job %] process_establishment: Determined merge mode % from strategy %', p_job_id, v_merge_mode, v_definition.strategy;

        CALL sql_saga.temporal_merge(
            target_table => 'public.establishment'::regclass, source_table => 'temp_es_source_view'::regclass,
            identity_columns => ARRAY['id'], ephemeral_columns => ARRAY['edit_comment', 'edit_by_user_id', 'edit_at', 'invalid_codes'],
            mode => v_merge_mode,
            identity_correlation_column => 'founding_row_id',
            update_source_with_identity => true,
            update_source_with_feedback => true,
            feedback_status_column => 'merge_status',
            feedback_status_key => 'establishment',
            feedback_error_column => 'errors',
            feedback_error_key => 'establishment',
            source_row_id_column => 'data_row_id'
        );

        -- Process feedback
        EXECUTE format($$ SELECT count(*) FROM public.%1$I WHERE row_id = ANY($1) AND errors->'establishment' IS NOT NULL $$, v_data_table_name)
            INTO v_error_count USING p_batch_row_ids;

        EXECUTE format($$
            UPDATE public.%1$I dt SET
                state = CASE WHEN dt.errors ? 'establishment' THEN 'error'::public.import_data_state ELSE 'processing'::public.import_data_state END
            WHERE dt.row_id = ANY($1) AND dt.action = 'use';
        $$, v_data_table_name)
        USING p_batch_row_ids;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        v_update_count := v_update_count - v_error_count;
        RAISE DEBUG '[Job %] process_establishment: temporal_merge finished. Success: %, Errors: %', p_job_id, v_update_count, v_error_count;

        -- Intra-batch propagation of newly assigned establishment_id
        RAISE DEBUG '[Job %] process_establishment: Propagating establishment_id for new entities within the batch.', p_job_id;
        v_sql := format($$
            WITH id_source AS (
                SELECT DISTINCT founding_row_id, establishment_id
                FROM public.%1$I
                WHERE row_id = ANY($1) AND establishment_id IS NOT NULL
            )
            UPDATE public.%1$I dt
            SET establishment_id = id_source.establishment_id
            FROM id_source
            WHERE dt.row_id = ANY($1)
              AND dt.founding_row_id = id_source.founding_row_id
              AND dt.establishment_id IS NULL;
        $$, v_data_table_name);
        EXECUTE v_sql USING p_batch_row_ids;

        -- Process external identifiers now that establishment_id is available for new units
        CALL import.helper_process_external_idents(p_job_id, p_batch_row_ids, 'external_idents');

    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
        RAISE WARNING '[Job %] process_establishment: Unhandled error during batch operation: %', p_job_id, replace(error_message, '%', '%%');
        -- Attempt to mark individual data rows as error (best effort)
        BEGIN
            v_sql := format($$UPDATE public.%1$I SET state = 'error'::public.import_data_state, errors = errors || jsonb_build_object('unhandled_error_process_est', %2$L) WHERE row_id = ANY($1) AND state != 'error'::public.import_data_state$$,
                           v_data_table_name, /* %1$I */
                           error_message      /* %2$L */
            );
            EXECUTE v_sql USING p_batch_row_ids;
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING '[Job %] process_establishment: Failed to mark batch rows as error after unhandled exception: %', p_job_id, SQLERRM;
        END;
        -- Mark the job as failed
        UPDATE public.import_job
        SET error = jsonb_build_object('process_establishment_unhandled_error', error_message),
            state = 'finished'
        WHERE id = p_job_id;
        RAISE DEBUG '[Job %] process_establishment: Marked job as failed due to unhandled error: %', p_job_id, error_message;
        RAISE;
    END;

    -- The framework now handles advancing priority for all rows.
    IF to_regclass('pg_temp.temp_es_source_view') IS NOT NULL THEN DROP VIEW temp_es_source_view; END IF;
    IF to_regclass('pg_temp.temp_es_demotion_source') IS NOT NULL THEN DROP TABLE temp_es_demotion_source; END IF;
    v_duration_ms := (EXTRACT(EPOCH FROM (clock_timestamp() - v_start_time)) * 1000);
    RAISE DEBUG '[Job %] process_establishment (Batch): Finished in % ms. Success: %, Errors: %', p_job_id, round(v_duration_ms, 2), v_update_count, v_error_count;
END;
$process_establishment$;

-- Procedure to link establishments to enterprises or handle enterprise creation for informal establishments
CREATE OR REPLACE PROCEDURE import.analyse_enterprise_link_for_establishment(p_job_id INT, p_batch_row_ids INTEGER[], p_step_code TEXT)
LANGUAGE plpgsql AS $analyse_enterprise_link_for_establishment$
DECLARE
    v_job public.import_job;
    v_snapshot JSONB;
    v_data_table_name TEXT;
    v_step public.import_step;
    v_job_mode public.import_mode;
    v_update_count INT;
    v_sql TEXT;
    v_error_keys_to_clear_arr TEXT[];
BEGIN
    RAISE DEBUG '[Job %] analyse_enterprise_link_for_establishment (Batch): Starting analysis for % rows. Batch Row IDs: %', p_job_id, array_length(p_batch_row_ids, 1), p_batch_row_ids;

    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;
    v_snapshot := v_job.definition_snapshot;
    v_job_mode := v_snapshot->'import_definition'->>'mode';

    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_snapshot->'import_step_list') WHERE code = p_step_code;
    IF NOT FOUND THEN RAISE EXCEPTION '[Job %] Step % not found in snapshot', p_job_id, p_step_code; END IF;

    -- For informal establishments, enterprise link is created/handled here.
    IF v_job_mode = 'establishment_informal' THEN
        -- Handle INSERT operations: create a new enterprise for each new informal establishment.
        v_sql := format($$
            WITH new_enterprises AS (
                INSERT INTO public.enterprise (short_name, edit_by_user_id, edit_at, edit_comment)
                SELECT
                    LEFT(dt.name, 16) as short_name,
                    dt.edit_by_user_id,
                    dt.edit_at,
                    'Created for informal establishment import job ' || %L
                FROM public.%I dt
                WHERE dt.row_id = ANY($1) AND dt.operation = 'insert' AND dt.action IS DISTINCT FROM 'skip'
                RETURNING id, short_name
            ),
            mapped_rows AS (
                SELECT dt.row_id, ne.id as new_enterprise_id
                FROM public.%I dt
                JOIN new_enterprises ne ON LEFT(dt.name, 16) = ne.short_name -- This join is imperfect but sufficient for batch context
                WHERE dt.row_id = ANY($1) AND dt.operation = 'insert'
            )
            UPDATE public.%I dt SET
                enterprise_id = mr.new_enterprise_id,
                primary_for_enterprise = TRUE
            FROM mapped_rows mr
            WHERE dt.row_id = mr.row_id;
        $$, p_job_id, v_data_table_name, v_data_table_name, v_data_table_name);
        RAISE DEBUG '[Job %] analyse_enterprise_link_for_establishment: Creating enterprises for new informal establishments: %', p_job_id, v_sql;
        EXECUTE v_sql USING p_batch_row_ids;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_enterprise_link_for_establishment: Processed % "insert" rows for informal establishments.', p_job_id, v_update_count;

        -- Handle REPLACE operations: find existing enterprise_id
        v_error_keys_to_clear_arr := ARRAY(SELECT DISTINCT value->>'column_name' FROM jsonb_array_elements(v_snapshot->'import_data_column_list') AS value WHERE value->>'purpose' = 'source_input' AND value->>'step_id' = (SELECT id FROM public.import_step WHERE code='external_idents'));
        RAISE DEBUG '[Job %] analyse_enterprise_link_for_establishment: Identified external_idents source_input columns: %', p_job_id, v_error_keys_to_clear_arr;

        v_sql := format($$
            WITH est_data AS (
                SELECT dt.row_id, est.enterprise_id AS existing_enterprise_id, est.primary_for_enterprise AS existing_primary_for_enterprise, est.id as found_est_id
                FROM public.%I dt
                LEFT JOIN public.establishment est ON dt.establishment_id = est.id
                WHERE dt.row_id = ANY($1) AND dt.operation = 'replace' AND dt.establishment_id IS NOT NULL AND %L = 'establishment_informal'
            )
            UPDATE public.%I dt SET
                enterprise_id = CASE
                                    WHEN dt.operation = 'replace' AND dt.establishment_id IS NOT NULL AND %L = 'establishment_informal' AND ed.found_est_id IS NOT NULL THEN ed.existing_enterprise_id
                                    ELSE dt.enterprise_id
                                END,
                primary_for_enterprise = CASE
                                            WHEN dt.operation = 'replace' AND dt.establishment_id IS NOT NULL AND %L = 'establishment_informal' AND ed.found_est_id IS NOT NULL THEN ed.existing_primary_for_enterprise
                                            ELSE dt.primary_for_enterprise
                                         END,
                state = CASE
                            WHEN dt.operation = 'replace' AND dt.establishment_id IS NOT NULL AND %L = 'establishment_informal' AND ed.found_est_id IS NULL THEN 'error'::public.import_data_state -- EST not found
                            WHEN dt.operation = 'replace' AND dt.establishment_id IS NOT NULL AND %L = 'establishment_informal' AND ed.found_est_id IS NOT NULL AND ed.existing_enterprise_id IS NULL THEN 'error'::public.import_data_state -- EST found but no enterprise_id (inconsistent for informal)
                            ELSE dt.state
                        END,
                errors = CASE
                            WHEN dt.operation = 'replace' AND dt.establishment_id IS NOT NULL AND %L = 'establishment_informal' AND ed.found_est_id IS NULL THEN
                                dt.errors || (SELECT jsonb_object_agg(col_name, 'Establishment identified by external identifier was not found for ''replace'' action.') FROM unnest(%L::TEXT[]) as col_name)
                            WHEN dt.operation = 'replace' AND dt.establishment_id IS NOT NULL AND %L = 'establishment_informal' AND ed.found_est_id IS NOT NULL AND ed.existing_enterprise_id IS NULL THEN
                                dt.errors || (SELECT jsonb_object_agg(col_name, 'Informal establishment found for ''replace'' action, but it is not linked to an enterprise.') FROM unnest(%L::TEXT[]) as col_name)
                            ELSE dt.errors - %L::TEXT[]
                        END
            FROM public.%I dt_main
            LEFT JOIN est_data ed ON dt_main.row_id = ed.row_id
            WHERE dt.row_id = dt_main.row_id
              AND dt_main.row_id = ANY($1) AND dt_main.operation = 'replace' AND %L = 'establishment_informal';
        $$, v_data_table_name, v_job_mode, v_data_table_name, v_job_mode, v_job_mode, v_job_mode, v_job_mode, v_error_keys_to_clear_arr, v_job_mode, v_error_keys_to_clear_arr, v_error_keys_to_clear_arr, v_data_table_name, v_job_mode);
        RAISE DEBUG '[Job %] analyse_enterprise_link_for_establishment: Updating "replace" rows for informal establishments: %', p_job_id, v_sql;
        EXECUTE v_sql USING p_batch_row_ids;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_enterprise_link_for_establishment: Processed % "replace" rows for informal establishments (includes potential errors).', p_job_id, v_update_count;
    END IF;

    -- Always advance priority for all rows in the batch to prevent loops.
    EXECUTE format('UPDATE public.%I SET last_completed_priority = %s WHERE row_id = ANY($1)', v_data_table_name, v_step.priority)
    USING p_batch_row_ids;
    GET DIAGNOSTICS v_update_count = ROW_COUNT;

    RAISE DEBUG '[Job %] analyse_enterprise_link_for_establishment (Batch): Finished analysis successfully. Updated priority for % rows.', p_job_id, v_update_count;
END;
$analyse_enterprise_link_for_establishment$;
END;

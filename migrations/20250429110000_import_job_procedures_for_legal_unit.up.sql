-- Implements the analyse and operation procedures for the legal_unit import target.
BEGIN;

-- Procedure to analyse base legal unit data
CREATE OR REPLACE PROCEDURE import.analyse_legal_unit(p_job_id INT, p_batch_row_id_ranges int4multirange, p_step_code TEXT)
LANGUAGE plpgsql AS $analyse_legal_unit$
DECLARE
    v_job public.import_job;
    v_step public.import_step;
    v_sql TEXT;
    v_update_count INT := 0;
    v_error_count INT := 0;
    v_data_table_name TEXT;
    v_error_keys_to_clear_arr TEXT[] := ARRAY['name_raw', 'legal_form_code_raw', 'sector_code_raw', 'unit_size_code_raw', 'birth_date_raw', 'death_date_raw', 'status_code_raw', 'legal_unit'];
    v_invalid_code_keys_arr TEXT[] := ARRAY['legal_form_code_raw', 'sector_code_raw', 'unit_size_code_raw', 'birth_date_raw', 'death_date_raw']; -- Keys that go into invalid_codes
BEGIN
    RAISE DEBUG '[Job %] analyse_legal_unit (Batch): Starting analysis for range %s', p_job_id, p_batch_row_id_ranges::text;

    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;

    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = 'legal_unit';
    IF NOT FOUND THEN RAISE EXCEPTION '[Job %] legal_unit target step not found in snapshot', p_job_id; END IF;

    -- Step 1: Materialize the batch data into a temp table for performance.
    IF to_regclass('pg_temp.t_batch_data') IS NOT NULL THEN DROP TABLE t_batch_data; END IF;
    v_sql := format($$
        CREATE TEMP TABLE t_batch_data ON COMMIT DROP AS
        SELECT dt.row_id, dt.operation, dt.name_raw, dt.status_id,
               dt.legal_form_code_raw, dt.sector_code_raw, dt.unit_size_code_raw,
               dt.birth_date_raw, dt.death_date_raw
        FROM %I dt
        JOIN unnest($1) AS r(range)
          ON dt.row_id >= lower(r.range) AND dt.row_id < upper(r.range)
        WHERE dt.action IS DISTINCT FROM 'skip';
    $$, v_data_table_name);
    EXECUTE v_sql USING p_batch_row_id_ranges;

    ANALYZE t_batch_data;

    -- Step 2: Resolve all distinct codes and dates from the batch in separate temp tables.
    IF to_regclass('pg_temp.t_resolved_codes') IS NOT NULL THEN DROP TABLE t_resolved_codes; END IF;
    CREATE TEMP TABLE t_resolved_codes ON COMMIT DROP AS
    WITH distinct_codes AS (
        SELECT legal_form_code_raw AS code, 'legal_form' AS type FROM t_batch_data WHERE NULLIF(legal_form_code_raw, '') IS NOT NULL
        UNION SELECT sector_code_raw AS code, 'sector' AS type FROM t_batch_data WHERE NULLIF(sector_code_raw, '') IS NOT NULL
        UNION SELECT unit_size_code_raw AS code, 'unit_size' AS type FROM t_batch_data WHERE NULLIF(unit_size_code_raw, '') IS NOT NULL
    )
    SELECT
        dc.code, dc.type, COALESCE(lf.id, s.id, us.id) AS resolved_id
    FROM distinct_codes dc
    LEFT JOIN public.legal_form_available lf ON dc.type = 'legal_form' AND dc.code = lf.code
    LEFT JOIN public.sector_available s ON dc.type = 'sector' AND dc.code = s.code
    LEFT JOIN public.unit_size_available us ON dc.type = 'unit_size' AND dc.code = us.code;

    IF to_regclass('pg_temp.t_resolved_dates') IS NOT NULL THEN DROP TABLE t_resolved_dates; END IF;
    CREATE TEMP TABLE t_resolved_dates ON COMMIT DROP AS
    WITH distinct_dates AS (
        SELECT birth_date_raw AS date_string FROM t_batch_data WHERE NULLIF(birth_date_raw, '') IS NOT NULL
        UNION SELECT death_date_raw AS date_string FROM t_batch_data WHERE NULLIF(death_date_raw, '') IS NOT NULL
    )
    SELECT dd.date_string, sc.p_value, sc.p_error_message
    FROM distinct_dates dd
    LEFT JOIN LATERAL import.safe_cast_to_date(dd.date_string) AS sc ON TRUE;

    ANALYZE t_resolved_codes;
    ANALYZE t_resolved_dates;

    -- Step 3: Perform the main update using the pre-resolved lookup tables.
    v_sql := format($SQL$
        WITH lookups AS (
            SELECT
                bd.row_id as data_row_id,
                bd.operation, bd.name_raw as name, bd.status_id,
                bd.legal_form_code_raw as legal_form_code,
                bd.sector_code_raw as sector_code,
                bd.unit_size_code_raw as unit_size_code,
                bd.birth_date_raw as birth_date,
                bd.death_date_raw as death_date,
                lf.resolved_id as resolved_legal_form_id,
                s.resolved_id as resolved_sector_id,
                us.resolved_id as resolved_unit_size_id,
                b_date.p_value as resolved_typed_birth_date,
                b_date.p_error_message as birth_date_error_msg,
                d_date.p_value as resolved_typed_death_date,
                d_date.p_error_message as death_date_error_msg
            FROM t_batch_data bd
            LEFT JOIN t_resolved_codes lf ON bd.legal_form_code_raw = lf.code AND lf.type = 'legal_form'
            LEFT JOIN t_resolved_codes s ON bd.sector_code_raw = s.code AND s.type = 'sector'
            LEFT JOIN t_resolved_codes us ON bd.unit_size_code_raw = us.code AND us.type = 'unit_size'
            LEFT JOIN t_resolved_dates b_date ON bd.birth_date_raw = b_date.date_string
            LEFT JOIN t_resolved_dates d_date ON bd.death_date_raw = d_date.date_string
        )
        UPDATE public.%1$I dt SET
            name = NULLIF(trim(l.name), ''),
            legal_form_id = l.resolved_legal_form_id,
            sector_id = l.resolved_sector_id,
            unit_size_id = l.resolved_unit_size_id,
            birth_date = l.resolved_typed_birth_date,
            death_date = l.resolved_typed_death_date,
            state = CASE
                        WHEN l.operation != 'update' AND NULLIF(trim(l.name), '') IS NULL THEN 'error'::public.import_data_state
                        WHEN l.status_id IS NULL THEN 'error'::public.import_data_state
                        ELSE 'analysing'::public.import_data_state
                    END,
            action = CASE
                        WHEN l.operation != 'update' AND NULLIF(trim(l.name), '') IS NULL THEN 'skip'::public.import_row_action_type
                        WHEN l.status_id IS NULL THEN 'skip'::public.import_row_action_type
                        ELSE dt.action
                     END,
            errors = CASE
                        WHEN l.operation != 'update' AND NULLIF(trim(l.name), '') IS NULL THEN
                            dt.errors || jsonb_build_object('name_raw', 'Missing required name')
                        WHEN l.status_id IS NULL THEN
                            dt.errors || jsonb_build_object('status_code_raw', 'Status code could not be resolved and is required for this operation.')
                        ELSE
                            dt.errors - %2$L::TEXT[]
                    END,
            invalid_codes = CASE
                                WHEN (l.operation = 'update' OR NULLIF(trim(l.name), '') IS NOT NULL) AND l.status_id IS NOT NULL THEN
                                    jsonb_strip_nulls(
                                     (dt.invalid_codes - %3$L::TEXT[]) ||
                                     jsonb_build_object('legal_form_code_raw', CASE WHEN NULLIF(l.legal_form_code, '') IS NOT NULL AND l.resolved_legal_form_id IS NULL THEN l.legal_form_code ELSE NULL END) ||
                                     jsonb_build_object('sector_code_raw', CASE WHEN NULLIF(l.sector_code, '') IS NOT NULL AND l.resolved_sector_id IS NULL THEN l.sector_code ELSE NULL END) ||
                                     jsonb_build_object('unit_size_code_raw', CASE WHEN NULLIF(l.unit_size_code, '') IS NOT NULL AND l.resolved_unit_size_id IS NULL THEN l.unit_size_code ELSE NULL END) ||
                                     jsonb_build_object('birth_date_raw', CASE WHEN NULLIF(l.birth_date, '') IS NOT NULL AND l.birth_date_error_msg IS NOT NULL THEN l.birth_date ELSE NULL END) ||
                                     jsonb_build_object('death_date_raw', CASE WHEN NULLIF(l.death_date, '') IS NOT NULL AND l.death_date_error_msg IS NOT NULL THEN l.death_date ELSE NULL END)
                                    )
                                ELSE dt.invalid_codes
                            END
        FROM lookups l
        WHERE dt.row_id = l.data_row_id;
    $SQL$,
        v_data_table_name,             -- %1$I
        v_error_keys_to_clear_arr,     -- %2$L
        v_invalid_code_keys_arr       -- %3$L
    );

    BEGIN
        RAISE DEBUG '[Job %] analyse_legal_unit: Updating batch data with SQL: %', p_job_id, v_sql;
        EXECUTE v_sql;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_legal_unit: Updated % rows in batch.', p_job_id, v_update_count;
    EXCEPTION WHEN others THEN
        RAISE WARNING '[Job %] analyse_legal_unit: Error during batch update: %', p_job_id, SQLERRM;
        UPDATE public.import_job SET error = jsonb_build_object('analyse_legal_unit_batch_error', SQLERRM), state = 'finished' WHERE id = p_job_id;
        RAISE;
    END;

    -- Unconditionally advance priority for all rows in batch to ensure progress
    v_sql := format('UPDATE public.%1$I dt SET last_completed_priority = %2$L WHERE dt.row_id <@ $1 AND dt.last_completed_priority < %2$L',
                    v_data_table_name, v_step.priority);
    RAISE DEBUG '[Job %] analyse_legal_unit: Unconditionally advancing priority for all batch rows with SQL: %', p_job_id, v_sql;
    EXECUTE v_sql USING p_batch_row_id_ranges;

    BEGIN
        v_sql := format($$SELECT COUNT(*) FROM public.%1$I WHERE row_id <@ $1 AND state = 'error' AND (errors ?| %2$L::text[])$$,
                       v_data_table_name, v_error_keys_to_clear_arr);
        RAISE DEBUG '[Job %] analyse_legal_unit: Counting errors with SQL: %', p_job_id, v_sql;
        EXECUTE v_sql INTO v_error_count USING p_batch_row_id_ranges;
        RAISE DEBUG '[Job %] analyse_legal_unit: Estimated errors in this step for batch: %', p_job_id, v_error_count;
    EXCEPTION WHEN others THEN
        RAISE WARNING '[Job %] analyse_legal_unit: Error during error count: %', p_job_id, SQLERRM;
    END;

    -- Propagate errors to all rows of a new entity if one fails (best-effort)
    BEGIN
        CALL import.propagate_fatal_error_to_entity_batch(p_job_id, v_data_table_name, p_batch_row_id_ranges, v_error_keys_to_clear_arr, 'analyse_legal_unit');
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING '[Job %] analyse_legal_unit: Non-fatal error during error propagation: %', p_job_id, SQLERRM;
    END;

    -- Resolve primary_for_enterprise conflicts (best-effort)
    BEGIN
        RAISE DEBUG '[Job %] analyse_legal_unit: Resolving primary_for_enterprise conflicts within the batch in %s.', p_job_id, v_data_table_name;
        v_sql := format($$
            WITH BatchPrimaries AS (
                SELECT
                    row_id,
                    FIRST_VALUE(row_id) OVER (
                        PARTITION BY enterprise_id, daterange(valid_from, valid_until, '[)')
                        ORDER BY legal_unit_id ASC NULLS LAST, row_id ASC
                    ) as winner_row_id
                FROM public.%1$I
                WHERE row_id <@ $1 AND primary_for_enterprise = true AND enterprise_id IS NOT NULL
            )
            UPDATE public.%1$I dt
            SET primary_for_enterprise = false
            FROM BatchPrimaries bp
            WHERE dt.row_id = bp.row_id
              AND dt.row_id != bp.winner_row_id
              AND dt.primary_for_enterprise = true;
        $$, v_data_table_name);
        RAISE DEBUG '[Job %] analyse_legal_unit: Resolving primary conflicts with SQL: %', p_job_id, v_sql;
        EXECUTE v_sql USING p_batch_row_id_ranges;
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING '[Job %] analyse_legal_unit: Non-fatal error during primary conflict resolution: %', p_job_id, SQLERRM;
    END;

    RAISE DEBUG '[Job %] analyse_legal_unit (Batch): Finished analysis for batch. Total errors in batch: %', p_job_id, v_error_count;
END;
$analyse_legal_unit$;


CREATE OR REPLACE PROCEDURE import.process_legal_unit(IN p_job_id integer, IN p_batch_row_id_ranges int4multirange, IN p_step_code text)
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
    v_merge_mode sql_saga.temporal_merge_mode;
BEGIN
    v_start_time := clock_timestamp();
    RAISE DEBUG '[Job %] process_legal_unit (Batch): Starting operation for range %s', p_job_id, p_batch_row_id_ranges::text;

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

    -- Create an updatable view over the batch data. This avoids copying data to a temp table
    -- and allows sql_saga to write feedback and generated IDs directly back to the main data table.
    v_sql := format($$
        CREATE OR REPLACE TEMP VIEW temp_lu_source_view AS
        SELECT
            row_id AS data_row_id,
            founding_row_id,
            legal_unit_id AS id,
            name,
            birth_date,
            death_date,
            valid_from,
            valid_to,
            valid_until,
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
            NULLIF(invalid_codes,'{}'::JSONB) AS invalid_codes,
            errors,
            merge_status
        FROM public.%1$I
        WHERE row_id <@ %2$L::int4multirange AND action = 'use';
    $$, v_data_table_name /* %1$I */, p_batch_row_id_ranges /* %2$L */);
    RAISE DEBUG '[Job %] process_legal_unit: Creating temp view with SQL: %', p_job_id, v_sql;
    EXECUTE v_sql;

    -- Log the contents of the source view for debugging
    IF current_setting('client_min_messages') = 'debug' THEN
        DECLARE
            r RECORD;
        BEGIN
            FOR r IN SELECT * FROM temp_lu_source_view ORDER BY data_row_id LOOP
                RAISE DEBUG '[Job %][Row %] process_legal_unit source_view: lu_id=%, ent_id=%, valid_to="%", valid_until="%", death_date="%"', p_job_id, r.data_row_id, r.id, r.enterprise_id, r.valid_to, r.valid_until, r.death_date;
            END LOOP;
        END;
    END IF;

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
                'Demoted from primary by import job ' || %1$L ||
                '; new primary is LU ' || COALESCE(incoming_primary.incoming_lu_id::TEXT, 'NEW') ||
                ' for enterprise ' || incoming_primary.target_enterprise_id ||
                ' during [' || incoming_primary.new_primary_valid_from || ', ' || incoming_primary.new_primary_valid_until || ')'
            FROM public.legal_unit ex_lu
            JOIN (
                SELECT dt.legal_unit_id AS incoming_lu_id, dt.enterprise_id AS target_enterprise_id,
                       dt.valid_from AS new_primary_valid_from, dt.valid_until AS new_primary_valid_until,
                       dt.edit_by_user_id AS demotion_edit_by_user_id, dt.edit_at AS demotion_edit_at
                FROM public.%2$I dt
                WHERE dt.row_id <@ $1 AND dt.primary_for_enterprise = true AND dt.enterprise_id IS NOT NULL
            ) AS incoming_primary
            ON ex_lu.enterprise_id = incoming_primary.target_enterprise_id
            WHERE ex_lu.id IS DISTINCT FROM incoming_primary.incoming_lu_id
              AND ex_lu.primary_for_enterprise = true
              AND public.from_until_overlaps(ex_lu.valid_from, ex_lu.valid_until, incoming_primary.new_primary_valid_from, incoming_primary.new_primary_valid_until);
        $$, p_job_id /* %1$L */, v_data_table_name /* %2$I */);
        RAISE DEBUG '[Job %] process_legal_unit: Populating demotion source with SQL: %', p_job_id, v_sql;
        -- Ensure the correct multirange variable is passed to EXECUTE
        EXECUTE v_sql USING p_batch_row_id_ranges;

        IF FOUND THEN
            RAISE DEBUG '[Job %] process_legal_unit: Identified % LUs for demotion.', p_job_id, (SELECT count(*) FROM temp_lu_demotion_source);
            CALL sql_saga.temporal_merge(
                target_table => 'public.legal_unit'::regclass,
                source_table => 'temp_lu_demotion_source'::regclass,
                identity_columns => ARRAY['id'],
                ephemeral_columns => ARRAY['edit_comment', 'edit_by_user_id', 'edit_at'],
                mode => 'PATCH_FOR_PORTION_OF',
                source_row_id_column => 'row_id'
            );
            FOR v_batch_result IN SELECT * FROM pg_temp.temporal_merge_feedback WHERE status = 'ERROR' LOOP
                 RAISE WARNING '[Job %] process_legal_unit: Error during demotion for LU ID %: %', p_job_id, (v_batch_result.target_entity_ids->0->>'id')::INT, v_batch_result.error_message;
            END LOOP;
        ELSE
            RAISE DEBUG '[Job %] process_legal_unit: No existing primary LUs found to demote.', p_job_id;
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
        RAISE DEBUG '[Job %] process_legal_unit: Determined merge mode % from strategy %', p_job_id, v_merge_mode, v_definition.strategy;

        RAISE DEBUG '[Job %] process_legal_unit: Calling main sql_saga.temporal_merge operation.', p_job_id;
        CALL sql_saga.temporal_merge(
            target_table => 'public.legal_unit'::regclass,
            source_table => 'temp_lu_source_view'::regclass,
            identity_columns => ARRAY['id'],
            ephemeral_columns => ARRAY['edit_comment', 'edit_by_user_id', 'edit_at', 'invalid_codes'],
            mode => v_merge_mode,
            identity_correlation_column => 'founding_row_id',
            update_source_with_identity => true,
            update_source_with_feedback => true,
            feedback_status_column => 'merge_status',
            feedback_status_key => 'legal_unit',
            feedback_error_column => 'errors',
            feedback_error_key => 'legal_unit',
            source_row_id_column => 'data_row_id'
        );

        -- With feedback written directly to the data table, we just need to count successes and errors.
        v_sql := format($$ SELECT count(*) FROM public.%1$I WHERE row_id <@ $1 AND errors->'legal_unit' IS NOT NULL $$, v_data_table_name);
        RAISE DEBUG '[Job %] process_legal_unit: Counting merge errors with SQL: %', p_job_id, v_sql;
        EXECUTE v_sql INTO v_error_count USING p_batch_row_id_ranges;

        v_sql := format($$
            UPDATE public.%1$I dt SET
                state = CASE WHEN dt.errors ? 'legal_unit' THEN 'error'::public.import_data_state ELSE 'processing'::public.import_data_state END
            WHERE dt.row_id <@ $1 AND dt.action = 'use';
        $$, v_data_table_name);
        RAISE DEBUG '[Job %] process_legal_unit: Updating state post-merge with SQL: %', p_job_id, v_sql;
        EXECUTE v_sql USING p_batch_row_id_ranges;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        v_update_count := v_update_count - v_error_count;

        RAISE DEBUG '[Job %] process_legal_unit: temporal_merge finished. Success: %, Errors: %', p_job_id, v_update_count, v_error_count;

        -- Intra-batch propagation of newly assigned legal_unit_id
        RAISE DEBUG '[Job %] process_legal_unit: Propagating legal_unit_id for new entities within the batch.', p_job_id;
        v_sql := format($$
            WITH id_source AS (
                SELECT DISTINCT founding_row_id, legal_unit_id
                FROM public.%1$I
                WHERE row_id <@ $1 AND legal_unit_id IS NOT NULL
            )
            UPDATE public.%1$I dt
            SET legal_unit_id = id_source.legal_unit_id
            FROM id_source
            WHERE dt.row_id <@ $1
              AND dt.founding_row_id = id_source.founding_row_id
              AND dt.legal_unit_id IS NULL;
        $$, v_data_table_name);
        RAISE DEBUG '[Job %] process_legal_unit: Propagating legal_unit_id with SQL: %', p_job_id, v_sql;
        EXECUTE v_sql USING p_batch_row_id_ranges;

        -- Process external identifiers now that legal_unit_id is available for new units
        CALL import.helper_process_external_idents(p_job_id, p_batch_row_id_ranges, 'external_idents');

    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
        RAISE WARNING '[Job %] process_legal_unit: Unhandled error during batch operation: %', p_job_id, replace(error_message, '%', '%%');
        -- Attempt to mark individual data rows as error (best effort)
        BEGIN
            v_sql := format($$UPDATE public.%1$I SET state = %2$L, errors = errors || jsonb_build_object('unhandled_error_process_lu', %3$L) WHERE row_id <@ $1 AND state != 'error'$$, -- LCP not changed here
                           v_data_table_name /* %1$I */, 'error'::public.import_data_state /* %2$L */, error_message /* %3$L */);
            RAISE DEBUG '[Job %] process_legal_unit: Marking rows as error in exception handler with SQL: %', p_job_id, v_sql;
            EXECUTE v_sql USING p_batch_row_id_ranges;
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

    -- The framework now handles advancing priority for all rows, including 'skip'. No update needed here.

    v_duration_ms := (EXTRACT(EPOCH FROM (clock_timestamp() - v_start_time)) * 1000);
    RAISE DEBUG '[Job %] process_legal_unit (Batch): Finished in % ms. Success: %, Errors: %',
        p_job_id, round(v_duration_ms, 2), v_update_count, v_error_count;
END;
$procedure$;

END;

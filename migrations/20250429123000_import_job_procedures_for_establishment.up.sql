BEGIN;

-- Procedure to analyse base establishment data (Batch Oriented)
CREATE OR REPLACE PROCEDURE import.analyse_establishment(p_job_id INT, p_batch_row_id_ranges int4multirange, p_step_code TEXT)
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
    v_error_keys_to_clear_arr TEXT[] := ARRAY['name_raw', 'sector_code_raw', 'unit_size_code_raw', 'birth_date_raw', 'death_date_raw', 'status_code_raw', 'establishment'];
    v_invalid_code_keys_arr TEXT[] := ARRAY['sector_code_raw', 'unit_size_code_raw', 'birth_date_raw', 'death_date_raw'];
BEGIN
    RAISE DEBUG '[Job %] analyse_establishment (Batch): Starting analysis for range %s', p_job_id, p_batch_row_id_ranges::text;

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

    v_sql := format($SQL$
        WITH
        batch_data AS (
            SELECT
                row_id, operation, name_raw as name, status_id,
                sector_code_raw as sector_code, unit_size_code_raw as unit_size_code,
                birth_date_raw as birth_date, death_date_raw as death_date
            FROM public.%1$I
            WHERE row_id <@ $1 AND action IS DISTINCT FROM 'skip'
        ),
        distinct_codes AS (
            SELECT sector_code AS code, 'sector' AS type FROM batch_data WHERE NULLIF(sector_code, '') IS NOT NULL
            UNION SELECT unit_size_code AS code, 'unit_size' AS type FROM batch_data WHERE NULLIF(unit_size_code, '') IS NOT NULL
        ),
        resolved_codes AS (
            SELECT
                dc.code,
                dc.type,
                COALESCE(s.id, us.id) AS resolved_id
            FROM distinct_codes dc
            LEFT JOIN public.sector_available s ON dc.type = 'sector' AND dc.code = s.code
            LEFT JOIN public.unit_size_available us ON dc.type = 'unit_size' AND dc.code = us.code
        ),
        distinct_dates AS (
            SELECT birth_date AS date_string FROM batch_data WHERE NULLIF(birth_date, '') IS NOT NULL
            UNION SELECT death_date AS date_string FROM batch_data WHERE NULLIF(death_date, '') IS NOT NULL
        ),
        resolved_dates AS (
            SELECT
                dd.date_string,
                sc.p_value,
                sc.p_error_message
            FROM distinct_dates dd
            LEFT JOIN LATERAL import.safe_cast_to_date(dd.date_string) AS sc ON TRUE
        ),
        lookups AS (
            SELECT
                bd.row_id as data_row_id,
                bd.operation, bd.name, bd.status_id,
                bd.sector_code, bd.unit_size_code,
                bd.birth_date, bd.death_date,
                s.resolved_id as resolved_sector_id,
                us.resolved_id as resolved_unit_size_id,
                b_date.p_value as resolved_typed_birth_date,
                b_date.p_error_message as birth_date_error_msg,
                d_date.p_value as resolved_typed_death_date,
                d_date.p_error_message as death_date_error_msg
            FROM batch_data bd
            LEFT JOIN resolved_codes s ON bd.sector_code = s.code AND s.type = 'sector'
            LEFT JOIN resolved_codes us ON bd.unit_size_code = us.code AND us.type = 'unit_size'
            LEFT JOIN resolved_dates b_date ON bd.birth_date = b_date.date_string
            LEFT JOIN resolved_dates d_date ON bd.death_date = d_date.date_string
        )
        UPDATE public.%2$I dt SET
            name = NULLIF(trim(l.name), ''),
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
                            dt.errors - %3$L::TEXT[]
                    END,
            invalid_codes = CASE
                                WHEN (l.operation = 'update' OR NULLIF(trim(l.name), '') IS NOT NULL) AND l.status_id IS NOT NULL THEN
                                    jsonb_strip_nulls(
                                     (dt.invalid_codes - %4$L::TEXT[]) ||
                                     jsonb_build_object('sector_code_raw', CASE WHEN NULLIF(l.sector_code, '') IS NOT NULL AND l.resolved_sector_id IS NULL THEN l.sector_code ELSE NULL END) ||
                                     jsonb_build_object('unit_size_code_raw', CASE WHEN NULLIF(l.unit_size_code, '') IS NOT NULL AND l.resolved_unit_size_id IS NULL THEN l.unit_size_code ELSE NULL END) ||
                                     jsonb_build_object('birth_date_raw', CASE WHEN NULLIF(l.birth_date, '') IS NOT NULL AND l.birth_date_error_msg IS NOT NULL THEN l.birth_date ELSE NULL END) ||
                                     jsonb_build_object('death_date_raw', CASE WHEN NULLIF(l.death_date, '') IS NOT NULL AND l.death_date_error_msg IS NOT NULL THEN l.death_date ELSE NULL END)
                                    )
                                ELSE dt.invalid_codes
                            END,
            last_completed_priority = %5$L
        FROM lookups l
        WHERE dt.row_id = l.data_row_id;
    $SQL$,
        v_job.data_table_name /* %1$I */,                           -- For lookups CTE
        v_job.data_table_name /* %2$I */,                           -- For main UPDATE target
        v_error_keys_to_clear_arr /* %3$L */,                       -- For error CASE (clear)
        v_invalid_code_keys_arr /* %4$L */,                         -- For invalid_codes CASE (clear old)
        v_step.priority /* %5$L */                                  -- For last_completed_priority (always this step's priority)
    );

    RAISE DEBUG '[Job %] analyse_establishment: Single-pass batch update for non-skipped rows: %', p_job_id, v_sql;

    BEGIN
        EXECUTE v_sql USING p_batch_row_id_ranges;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_establishment: Updated % non-skipped rows in single pass.', p_job_id, v_update_count;

        v_sql := format($$SELECT COUNT(*) FROM public.%1$I WHERE row_id <@ $1 AND state = 'error' AND (errors ?| %2$L::text[])$$,
                       v_job.data_table_name /* %1$I */, v_error_keys_to_clear_arr /* %2$L */);
        RAISE DEBUG '[Job %] analyse_establishment: Counting errors with SQL: %', p_job_id, v_sql;
        EXECUTE v_sql
        INTO v_error_count
        USING p_batch_row_id_ranges;
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

    -- Unconditionally advance priority for all rows in batch to ensure progress
    v_sql := format($$
        UPDATE public.%1$I dt SET
            last_completed_priority = %2$L
        WHERE dt.row_id <@ $1 AND dt.last_completed_priority < %2$L;
    $$, v_data_table_name /* %1$I */, v_step.priority /* %2$L */);
    RAISE DEBUG '[Job %] analyse_establishment: Unconditionally advancing priority for all batch rows with SQL: %', p_job_id, v_sql;
    EXECUTE v_sql USING p_batch_row_id_ranges;

    -- Propagate errors to all rows of a new entity if one fails (best-effort)
    BEGIN
        CALL import.propagate_fatal_error_to_entity_batch(p_job_id, v_job.data_table_name, p_batch_row_id_ranges, v_error_keys_to_clear_arr, 'analyse_establishment');
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING '[Job %] analyse_establishment: Non-fatal error during error propagation: %', p_job_id, SQLERRM;
    END;

    -- Resolve primary conflicts (best-effort)
    BEGIN
        IF v_job.definition_snapshot->'import_definition'->>'mode' = 'establishment_formal' THEN
            v_sql := format($$
                WITH BatchPrimaries AS (
                    SELECT row_id, FIRST_VALUE(row_id) OVER (PARTITION BY legal_unit_id, daterange(valid_from, valid_until, '[)') ORDER BY establishment_id ASC NULLS LAST, row_id ASC) as winner_row_id
                    FROM public.%1$I WHERE row_id <@ $1 AND primary_for_legal_unit = true AND legal_unit_id IS NOT NULL
                )
                UPDATE public.%1$I dt SET primary_for_legal_unit = false FROM BatchPrimaries bp
                WHERE dt.row_id = bp.row_id AND dt.row_id != bp.winner_row_id AND dt.primary_for_legal_unit = true;
            $$, v_data_table_name);
            RAISE DEBUG '[Job %] analyse_establishment: Resolving primary conflicts (formal) with SQL: %', p_job_id, v_sql;
            EXECUTE v_sql USING p_batch_row_id_ranges;
        ELSIF v_job.definition_snapshot->'import_definition'->>'mode' = 'establishment_informal' THEN
            v_sql := format($$
                WITH BatchPrimaries AS (
                    SELECT row_id, FIRST_VALUE(row_id) OVER (PARTITION BY enterprise_id, daterange(valid_from, valid_until, '[)') ORDER BY establishment_id ASC NULLS LAST, row_id ASC) as winner_row_id
                    FROM public.%1$I WHERE row_id <@ $1 AND primary_for_enterprise = true AND enterprise_id IS NOT NULL
                )
                UPDATE public.%1$I dt SET primary_for_enterprise = false FROM BatchPrimaries bp
                WHERE dt.row_id = bp.row_id AND dt.row_id != bp.winner_row_id AND dt.primary_for_enterprise = true;
            $$, v_data_table_name);
            RAISE DEBUG '[Job %] analyse_establishment: Resolving primary conflicts (informal) with SQL: %', p_job_id, v_sql;
            EXECUTE v_sql USING p_batch_row_id_ranges;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING '[Job %] analyse_establishment: Non-fatal error during primary conflict resolution: %', p_job_id, SQLERRM;
    END;

    RAISE DEBUG '[Job %] analyse_establishment (Batch): Finished analysis for batch. Total errors in batch: %', p_job_id, v_error_count;
END;
$analyse_establishment$;


-- Procedure to operate (insert/update/upsert) base establishment data (Batch Oriented)
CREATE OR REPLACE PROCEDURE import.process_establishment(p_job_id INT, p_batch_row_id_ranges int4multirange, p_step_code TEXT)
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
    RAISE DEBUG '[Job %] process_establishment (Batch): Starting operation for range %s', p_job_id, p_batch_row_id_ranges::text;

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
        row_id AS data_row_id, founding_row_id,
        %1$s AS legal_unit_id,
        %2$s AS primary_for_legal_unit,
        %3$s AS enterprise_id,
        %4$s AS primary_for_enterprise,
        name, birth_date, death_date,
        valid_from, valid_to, valid_until,
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
        WHERE dt.row_id <@ %3$L::int4multirange AND dt.action = 'use';
    $$,
        v_select_list,        /* %1$s */
        v_data_table_name,    /* %2$I */
        p_batch_row_id_ranges /* %3$L */
    );
    RAISE DEBUG '[Job %] process_establishment: Creating temp source view with SQL: %', p_job_id, v_sql;
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
                       'Demoted from primary for LU by import job ' || %1$L || '; new primary is EST ' ||
                       COALESCE(ipes.incoming_est_id::TEXT, 'NEW') || ' for LU ' || ipes.target_legal_unit_id ||
                       ' during [' || ipes.new_primary_valid_from || ', ' || ipes.new_primary_valid_until || ')'
                FROM public.establishment ex_es
                JOIN (SELECT dt.establishment_id AS incoming_est_id, dt.legal_unit_id AS target_legal_unit_id, dt.valid_from AS new_primary_valid_from, dt.valid_until AS new_primary_valid_until, dt.edit_by_user_id AS demotion_edit_by_user_id, dt.edit_at AS demotion_edit_at FROM public.%2$I dt WHERE dt.row_id <@ $1 AND dt.primary_for_legal_unit = true AND dt.legal_unit_id IS NOT NULL) AS ipes
                ON ex_es.legal_unit_id = ipes.target_legal_unit_id
                WHERE ex_es.id IS DISTINCT FROM ipes.incoming_est_id AND ex_es.primary_for_legal_unit = true AND public.from_until_overlaps(ex_es.valid_from, ex_es.valid_until, ipes.new_primary_valid_from, ipes.new_primary_valid_until);
            $$, p_job_id /* %1$L */, v_data_table_name /* %2$I */);
            RAISE DEBUG '[Job %] process_establishment: Populating demotion source (formal) with SQL: %', p_job_id, v_sql;
            EXECUTE v_sql USING p_batch_row_id_ranges;

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
                       'Demoted from primary for EN by import job ' || %1$L || '; new primary is EST ' ||
                       COALESCE(ipes.incoming_est_id::TEXT, 'NEW') || ' for EN ' || ipes.target_enterprise_id ||
                       ' during [' || ipes.new_primary_valid_from || ', ' || ipes.new_primary_valid_until || ')'
                FROM public.establishment ex_es
                JOIN (SELECT dt.establishment_id AS incoming_est_id, dt.enterprise_id AS target_enterprise_id, dt.valid_from AS new_primary_valid_from, dt.valid_until AS new_primary_valid_until, dt.edit_by_user_id AS demotion_edit_by_user_id, dt.edit_at AS demotion_edit_at FROM public.%2$I dt WHERE dt.row_id <@ $1 AND dt.primary_for_enterprise = true AND dt.enterprise_id IS NOT NULL) AS ipes
                ON ex_es.enterprise_id = ipes.target_enterprise_id
                WHERE ex_es.id IS DISTINCT FROM ipes.incoming_est_id AND ex_es.primary_for_enterprise = true AND public.from_until_overlaps(ex_es.valid_from, ex_es.valid_until, ipes.new_primary_valid_from, ipes.new_primary_valid_until);
            $$, p_job_id /* %1$L */, v_data_table_name /* %2$I */);
            RAISE DEBUG '[Job %] process_establishment: Populating demotion source (informal) with SQL: %', p_job_id, v_sql;
            EXECUTE v_sql USING p_batch_row_id_ranges;

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
        v_sql := format($$ SELECT count(*) FROM public.%1$I WHERE row_id <@ $1 AND errors->'establishment' IS NOT NULL $$, v_data_table_name);
        RAISE DEBUG '[Job %] process_establishment: Counting merge errors with SQL: %', p_job_id, v_sql;
        EXECUTE v_sql INTO v_error_count USING p_batch_row_id_ranges;

        v_sql := format($$
            UPDATE public.%1$I dt SET
                state = CASE WHEN dt.errors ? 'establishment' THEN 'error'::public.import_data_state ELSE 'processing'::public.import_data_state END
            WHERE dt.row_id <@ $1 AND dt.action = 'use';
        $$, v_data_table_name);
        RAISE DEBUG '[Job %] process_establishment: Updating state post-merge with SQL: %', p_job_id, v_sql;
        EXECUTE v_sql USING p_batch_row_id_ranges;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        v_update_count := v_update_count - v_error_count;
        RAISE DEBUG '[Job %] process_establishment: temporal_merge finished. Success: %, Errors: %', p_job_id, v_update_count, v_error_count;

        -- Intra-batch propagation of newly assigned establishment_id
        RAISE DEBUG '[Job %] process_establishment: Propagating establishment_id for new entities within the batch.', p_job_id;
        v_sql := format($$
            WITH id_source AS (
                SELECT DISTINCT founding_row_id, establishment_id
                FROM public.%1$I
                WHERE row_id <@ $1 AND establishment_id IS NOT NULL
            )
            UPDATE public.%1$I dt
            SET establishment_id = id_source.establishment_id
            FROM id_source
            WHERE dt.row_id <@ $1
              AND dt.founding_row_id = id_source.founding_row_id
              AND dt.establishment_id IS NULL;
        $$, v_data_table_name);
        RAISE DEBUG '[Job %] process_establishment: Propagating establishment_id with SQL: %', p_job_id, v_sql;
        EXECUTE v_sql USING p_batch_row_id_ranges;

        -- Process external identifiers now that establishment_id is available for new units
        CALL import.helper_process_external_idents(p_job_id, p_batch_row_id_ranges, 'external_idents');

    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
        RAISE WARNING '[Job %] process_establishment: Unhandled error during batch operation: %', p_job_id, replace(error_message, '%', '%%');
        -- Attempt to mark individual data rows as error (best effort)
        BEGIN
            v_sql := format($$UPDATE public.%1$I SET state = 'error'::public.import_data_state, errors = errors || jsonb_build_object('unhandled_error_process_est', %2$L) WHERE row_id <@ $1 AND state != 'error'::public.import_data_state$$,
                           v_data_table_name, /* %1$I */
                           error_message      /* %2$L */
            );
            RAISE DEBUG '[Job %] process_establishment: Marking rows as error in exception handler with SQL: %', p_job_id, v_sql;
            EXECUTE v_sql USING p_batch_row_id_ranges;
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
    v_duration_ms := (EXTRACT(EPOCH FROM (clock_timestamp() - v_start_time)) * 1000);
    RAISE DEBUG '[Job %] process_establishment (Batch): Finished in % ms. Success: %, Errors: %', p_job_id, round(v_duration_ms, 2), v_update_count, v_error_count;
END;
$process_establishment$;

END;

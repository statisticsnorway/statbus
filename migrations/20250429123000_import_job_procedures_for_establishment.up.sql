BEGIN;

-- Procedure to analyse base establishment data (Batch Oriented)
CREATE OR REPLACE PROCEDURE import.analyse_establishment(p_job_id INT, p_batch_seq INTEGER, p_step_code TEXT)
LANGUAGE plpgsql AS $analyse_establishment$
DECLARE
    v_job public.import_job;
    v_step public.import_step;
    v_data_table_name TEXT;
    v_error_count INT := 0;
    v_update_count INT := 0;
    v_sql TEXT;
    v_error_keys_to_clear_arr TEXT[] := ARRAY['name_raw', 'sector_code_raw', 'unit_size_code_raw', 'birth_date_raw', 'death_date_raw', 'status_code_raw', 'establishment'];
    v_invalid_code_keys_arr TEXT[] := ARRAY['sector_code_raw', 'unit_size_code_raw', 'birth_date_raw', 'death_date_raw'];
BEGIN
    RAISE DEBUG '[Job %] analyse_establishment (Batch): Starting analysis for batch_seq %', p_job_id, p_batch_seq;

    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name; 

    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = 'establishment';
    IF NOT FOUND THEN RAISE EXCEPTION '[Job %] establishment target not found in snapshot', p_job_id; END IF;

    -- Step 1: Materialize the batch data into a temp table for performance.
    IF to_regclass('pg_temp.t_batch_data') IS NOT NULL THEN DROP TABLE t_batch_data; END IF;
    v_sql := format($$
        CREATE TEMP TABLE t_batch_data ON COMMIT DROP AS
        SELECT dt.row_id, dt.operation, dt.name_raw, dt.status_id, establishment_id,
               dt.sector_code_raw, dt.unit_size_code_raw, dt.birth_date_raw, dt.death_date_raw
        FROM %I dt
        WHERE dt.batch_seq = $1
          AND dt.action IS DISTINCT FROM 'skip';
    $$, v_data_table_name);
    EXECUTE v_sql USING p_batch_seq;

    ANALYZE t_batch_data;

    -- Step 2: Resolve all distinct codes and dates from the batch in separate temp tables.
    IF to_regclass('pg_temp.t_resolved_codes') IS NOT NULL THEN DROP TABLE t_resolved_codes; END IF;
    CREATE TEMP TABLE t_resolved_codes ON COMMIT DROP AS
    WITH distinct_codes AS (
        SELECT sector_code_raw AS code, 'sector' AS type FROM t_batch_data WHERE NULLIF(sector_code_raw, '') IS NOT NULL
        UNION SELECT unit_size_code_raw AS code, 'unit_size' AS type FROM t_batch_data WHERE NULLIF(unit_size_code_raw, '') IS NOT NULL
    )
    SELECT
        dc.code, dc.type, COALESCE(s.id, us.id) AS resolved_id
    FROM distinct_codes dc
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
                bd.operation, bd.name_raw as name, bd.status_id, bd.establishment_id,
                bd.sector_code_raw as sector_code, bd.unit_size_code_raw as unit_size_code,
                bd.birth_date_raw as birth_date, bd.death_date_raw as death_date,
                s.resolved_id as resolved_sector_id,
                us.resolved_id as resolved_unit_size_id,
                b_date.p_value as resolved_typed_birth_date,
                b_date.p_error_message as birth_date_error_msg,
                d_date.p_value as resolved_typed_death_date,
                d_date.p_error_message as death_date_error_msg
            FROM t_batch_data bd
            LEFT JOIN t_resolved_codes s ON bd.sector_code_raw = s.code AND s.type = 'sector'
            LEFT JOIN t_resolved_codes us ON bd.unit_size_code_raw = us.code AND us.type = 'unit_size'
            LEFT JOIN t_resolved_dates b_date ON bd.birth_date_raw = b_date.date_string
            LEFT JOIN t_resolved_dates d_date ON bd.death_date_raw = d_date.date_string
        )
        UPDATE public.%1$I dt SET
            name = NULLIF(trim(l.name), ''),
            sector_id = l.resolved_sector_id,
            unit_size_id = l.resolved_unit_size_id,
            birth_date = l.resolved_typed_birth_date,
            death_date = l.resolved_typed_death_date,
            state = CASE
                        WHEN l.establishment_id IS NULL AND NULLIF(trim(l.name), '') IS NULL THEN 'error'::public.import_data_state
                        WHEN l.status_id IS NULL THEN 'error'::public.import_data_state
                        ELSE 'analysing'::public.import_data_state
                    END,
            action = CASE
                        WHEN l.establishment_id IS NULL AND NULLIF(trim(l.name), '') IS NULL THEN 'skip'::public.import_row_action_type
                        WHEN l.status_id IS NULL THEN 'skip'::public.import_row_action_type
                        ELSE dt.action
                     END,
            errors = CASE
                        WHEN l.establishment_id IS NULL AND NULLIF(trim(l.name), '') IS NULL THEN
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
        v_data_table_name,            -- %1$I
        v_error_keys_to_clear_arr,    -- %2$L
        v_invalid_code_keys_arr       -- %3$L
    );

    BEGIN
        EXECUTE v_sql;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_establishment: Updated % rows in batch.', p_job_id, v_update_count;
    EXCEPTION WHEN others THEN
        RAISE WARNING '[Job %] analyse_establishment: Error during batch update: %', p_job_id, SQLERRM;
        UPDATE public.import_job SET error = jsonb_build_object('analyse_establishment_batch_error', SQLERRM)::TEXT, state = 'failed' WHERE id = p_job_id;
        -- Don't re-raise - job is marked as failed
    END;

    -- Unconditionally advance priority for all rows in batch to ensure progress
    v_sql := format('UPDATE public.%1$I dt SET last_completed_priority = %2$L WHERE dt.batch_seq = $1 AND dt.last_completed_priority < %2$L',
                    v_data_table_name, v_step.priority);
    RAISE DEBUG '[Job %] analyse_establishment: Unconditionally advancing priority for all batch rows with SQL: %', p_job_id, v_sql;
    EXECUTE v_sql USING p_batch_seq;

    BEGIN
        v_sql := format($$SELECT COUNT(*) FROM public.%1$I dt WHERE dt.batch_seq = $1 AND dt.state = 'error' AND (dt.errors ?| %2$L::text[])$$,
                       v_data_table_name, v_error_keys_to_clear_arr);
        RAISE DEBUG '[Job %] analyse_establishment: Counting errors with SQL: %', p_job_id, v_sql;
        EXECUTE v_sql INTO v_error_count USING p_batch_seq;
        RAISE DEBUG '[Job %] analyse_establishment: Estimated errors in this step for batch: %', p_job_id, v_error_count;
    EXCEPTION WHEN others THEN
        RAISE WARNING '[Job %] analyse_establishment: Error during error count: %', p_job_id, SQLERRM;
    END;

    -- Propagate errors to all rows of a new entity if one fails (best-effort)
    BEGIN
        CALL import.propagate_fatal_error_to_entity_batch(p_job_id, v_data_table_name, p_batch_seq, v_error_keys_to_clear_arr, 'analyse_establishment');
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING '[Job %] analyse_establishment: Non-fatal error during error propagation: %', p_job_id, SQLERRM;
    END;

    -- Resolve primary conflicts (best-effort)
    BEGIN
        IF v_job.definition_snapshot->'import_definition'->>'mode' = 'establishment_formal' THEN
            v_sql := format($$
                WITH BatchPrimaries AS (
                    SELECT src.row_id, FIRST_VALUE(src.row_id) OVER (PARTITION BY src.legal_unit_id, daterange(src.valid_from, src.valid_until, '[)') ORDER BY src.establishment_id ASC NULLS LAST, src.row_id ASC) as winner_row_id
                    FROM public.%1$I src WHERE src.batch_seq = $1 AND src.primary_for_legal_unit = true AND src.legal_unit_id IS NOT NULL
                )
                UPDATE public.%1$I dt SET primary_for_legal_unit = false FROM BatchPrimaries bp
                WHERE dt.row_id = bp.row_id AND dt.row_id != bp.winner_row_id AND dt.primary_for_legal_unit = true;
            $$, v_data_table_name);
            RAISE DEBUG '[Job %] analyse_establishment: Resolving primary conflicts (formal) with SQL: %', p_job_id, v_sql;
            EXECUTE v_sql USING p_batch_seq;
        ELSIF v_job.definition_snapshot->'import_definition'->>'mode' = 'establishment_informal' THEN
            v_sql := format($$
                WITH BatchPrimaries AS (
                    SELECT src.row_id, FIRST_VALUE(src.row_id) OVER (PARTITION BY src.enterprise_id, daterange(src.valid_from, src.valid_until, '[)') ORDER BY src.establishment_id ASC NULLS LAST, src.row_id ASC) as winner_row_id
                    FROM public.%1$I src WHERE src.batch_seq = $1 AND src.primary_for_enterprise = true AND src.enterprise_id IS NOT NULL
                )
                UPDATE public.%1$I dt SET primary_for_enterprise = false FROM BatchPrimaries bp
                WHERE dt.row_id = bp.row_id AND dt.row_id != bp.winner_row_id AND dt.primary_for_enterprise = true;
            $$, v_data_table_name);
            RAISE DEBUG '[Job %] analyse_establishment: Resolving primary conflicts (informal) with SQL: %', p_job_id, v_sql;
            EXECUTE v_sql USING p_batch_seq;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING '[Job %] analyse_establishment: Non-fatal error during primary conflict resolution: %', p_job_id, SQLERRM;
    END;

    RAISE DEBUG '[Job %] analyse_establishment (Batch): Finished analysis for batch. Total errors in batch: %', p_job_id, v_error_count;
END;
$analyse_establishment$;


-- Procedure to operate (insert/update/upsert) base establishment data (Batch Oriented)
CREATE OR REPLACE PROCEDURE import.process_establishment(p_job_id INT, p_batch_seq INTEGER, p_step_code TEXT)
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
    v_select_list TEXT;
    v_job_mode public.import_mode;
    v_start_time TIMESTAMPTZ;
    v_duration_ms NUMERIC;
    v_merge_mode sql_saga.temporal_merge_mode;
BEGIN
    v_start_time := clock_timestamp();
    RAISE DEBUG '[Job %] process_establishment (Batch): Starting operation for batch_seq %', p_job_id, p_batch_seq;

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

    -- Create an updatable view over the batch data. This view will be the source for the temporal_merge.
    -- The view's columns are conditional on the job mode. This ensures that for 'formal' establishment
    -- imports, we only affect legal_unit_id links, and for 'informal' imports, we only affect
    -- enterprise_id links. This prevents temporal_merge from overwriting existing links with NULLs,
    -- which would violate the check constraint on the 'establishment' table.
    IF v_job_mode = 'establishment_formal' THEN
        v_select_list := $$
            row_id AS data_row_id, founding_row_id,
            legal_unit_id,
            primary_for_legal_unit,
            name, birth_date, death_date,
            valid_from, valid_to, valid_until,
            sector_id, unit_size_id, status_id, data_source_id,
            establishment_id AS id,
            NULLIF(invalid_codes, '{}'::jsonb) as invalid_codes,
            edit_by_user_id, edit_at, edit_comment,
            errors,
            merge_status
        $$;
    ELSIF v_job_mode = 'establishment_informal' THEN
        v_select_list := $$
            row_id AS data_row_id, founding_row_id,
            enterprise_id,
            primary_for_enterprise,
            name, birth_date, death_date,
            valid_from, valid_to, valid_until,
            sector_id, unit_size_id, status_id, data_source_id,
            establishment_id AS id,
            NULLIF(invalid_codes, '{}'::jsonb) as invalid_codes,
            edit_by_user_id, edit_at, edit_comment,
            errors,
            merge_status
        $$;
    END IF;

    -- Drop the view if it exists from a previous run in the same session, to avoid column name/type conflicts with CREATE OR REPLACE VIEW.
    IF to_regclass('pg_temp.temp_es_source_view') IS NOT NULL THEN
        DROP VIEW pg_temp.temp_es_source_view;
    END IF;

    v_sql := format($$
        CREATE TEMP VIEW temp_es_source_view AS
        SELECT %1$s
        FROM public.%2$I dt
        WHERE dt.batch_seq = %3$L AND dt.action = 'use';
    $$,
        v_select_list,     /* %1$s */
        v_data_table_name, /* %2$I */
        p_batch_seq        /* %3$L */
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
                JOIN (SELECT dt.establishment_id AS incoming_est_id, dt.legal_unit_id AS target_legal_unit_id, dt.valid_from AS new_primary_valid_from, dt.valid_until AS new_primary_valid_until, dt.edit_by_user_id AS demotion_edit_by_user_id, dt.edit_at AS demotion_edit_at FROM public.%2$I dt WHERE dt.batch_seq = $1 AND dt.primary_for_legal_unit = true AND dt.legal_unit_id IS NOT NULL) AS ipes
                ON ex_es.legal_unit_id = ipes.target_legal_unit_id
                WHERE ex_es.id IS DISTINCT FROM ipes.incoming_est_id AND ex_es.primary_for_legal_unit = true AND public.from_until_overlaps(ex_es.valid_from, ex_es.valid_until, ipes.new_primary_valid_from, ipes.new_primary_valid_until);
            $$, p_job_id /* %1$L */, v_data_table_name /* %2$I */);
            RAISE DEBUG '[Job %] process_establishment: Populating demotion source (formal) with SQL: %', p_job_id, v_sql;
            EXECUTE v_sql USING p_batch_seq;

            IF FOUND THEN
                CALL sql_saga.temporal_merge(
                    target_table => 'public.establishment'::regclass,
                    source_table => 'temp_es_demotion_source'::regclass,
                    primary_identity_columns => ARRAY['id'],
                    mode => 'PATCH_FOR_PORTION_OF',
                    row_id_column => 'row_id'
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
                JOIN (SELECT dt.establishment_id AS incoming_est_id, dt.enterprise_id AS target_enterprise_id, dt.valid_from AS new_primary_valid_from, dt.valid_until AS new_primary_valid_until, dt.edit_by_user_id AS demotion_edit_by_user_id, dt.edit_at AS demotion_edit_at FROM public.%2$I dt WHERE dt.batch_seq = $1 AND dt.primary_for_enterprise = true AND dt.enterprise_id IS NOT NULL) AS ipes
                ON ex_es.enterprise_id = ipes.target_enterprise_id
                WHERE ex_es.id IS DISTINCT FROM ipes.incoming_est_id AND ex_es.primary_for_enterprise = true AND public.from_until_overlaps(ex_es.valid_from, ex_es.valid_until, ipes.new_primary_valid_from, ipes.new_primary_valid_until);
            $$, p_job_id /* %1$L */, v_data_table_name /* %2$I */);
            RAISE DEBUG '[Job %] process_establishment: Populating demotion source (informal) with SQL: %', p_job_id, v_sql;
            EXECUTE v_sql USING p_batch_seq;

            IF FOUND THEN
                CALL sql_saga.temporal_merge(
                    target_table => 'public.establishment'::regclass,
                    source_table => 'temp_es_demotion_source'::regclass,
                    primary_identity_columns => ARRAY['id'],
                    mode => 'PATCH_FOR_PORTION_OF',
                    row_id_column => 'row_id'
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
            WHEN 'update_only' THEN 'MERGE_ENTITY_UPSERT'::sql_saga.temporal_merge_mode
            ELSE 'MERGE_ENTITY_PATCH'::sql_saga.temporal_merge_mode -- Default to safer patch for other cases
        END;
        RAISE DEBUG '[Job %] process_establishment: Determined merge mode % from strategy %', p_job_id, v_merge_mode, v_definition.strategy;

        CALL sql_saga.temporal_merge(
            target_table => 'public.establishment'::regclass,
            source_table => 'temp_es_source_view'::regclass,
            primary_identity_columns => ARRAY['id'],
            mode => v_merge_mode,
            row_id_column => 'data_row_id',
            founding_id_column => 'founding_row_id',
            update_source_with_identity => true,
            update_source_with_feedback => true,
            feedback_status_column => 'merge_status',
            feedback_status_key => 'establishment',
            feedback_error_column => 'errors',
            feedback_error_key => 'establishment'
        );

        -- Process feedback
        v_sql := format($$ SELECT count(*) FROM public.%1$I dt WHERE dt.batch_seq = $1 AND dt.errors->'establishment' IS NOT NULL $$, v_data_table_name);
        RAISE DEBUG '[Job %] process_establishment: Counting merge errors with SQL: %', p_job_id, v_sql;
        EXECUTE v_sql INTO v_error_count USING p_batch_seq;

        v_sql := format($$
            UPDATE public.%1$I dt SET
                state = CASE WHEN dt.errors ? 'establishment' THEN 'error'::public.import_data_state ELSE 'processing'::public.import_data_state END
            WHERE dt.batch_seq = $1 AND dt.action = 'use';
        $$, v_data_table_name);
        RAISE DEBUG '[Job %] process_establishment: Updating state post-merge with SQL: %', p_job_id, v_sql;
        EXECUTE v_sql USING p_batch_seq;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        v_update_count := v_update_count - v_error_count;
        RAISE DEBUG '[Job %] process_establishment: temporal_merge finished. Success: %, Errors: %', p_job_id, v_update_count, v_error_count;

        -- Intra-batch propagation of newly assigned establishment_id
        RAISE DEBUG '[Job %] process_establishment: Propagating establishment_id for new entities within the batch.', p_job_id;
        v_sql := format($$
            WITH id_source AS (
                SELECT DISTINCT src.founding_row_id, src.establishment_id
                FROM public.%1$I src
                WHERE src.batch_seq = $1
                  AND src.establishment_id IS NOT NULL
            )
            UPDATE public.%1$I dt
            SET establishment_id = id_source.establishment_id
            FROM id_source
            WHERE dt.batch_seq = $1
              AND dt.founding_row_id = id_source.founding_row_id
              AND dt.establishment_id IS NULL;
        $$, v_data_table_name);
        RAISE DEBUG '[Job %] process_establishment: Propagating establishment_id with SQL: %', p_job_id, v_sql;
        EXECUTE v_sql USING p_batch_seq;

        -- Process external identifiers now that establishment_id is available for new units
        CALL import.helper_process_external_idents(p_job_id, p_batch_seq, 'external_idents');

    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
        RAISE WARNING '[Job %] process_establishment: Unhandled error during batch operation: %', p_job_id, replace(error_message, '%', '%%');
        -- Attempt to mark individual data rows as error (best effort)
        BEGIN
            v_sql := format($$UPDATE public.%1$I dt SET state = 'error'::public.import_data_state, errors = errors || jsonb_build_object('unhandled_error_process_est', %2$L) WHERE dt.batch_seq = $1 AND dt.state != 'error'::public.import_data_state$$,
                           v_data_table_name, /* %1$I */
                           error_message      /* %2$L */
            );
            RAISE DEBUG '[Job %] process_establishment: Marking rows as error in exception handler with SQL: %', p_job_id, v_sql;
            EXECUTE v_sql USING p_batch_seq;
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING '[Job %] process_establishment: Failed to mark batch rows as error after unhandled exception: %', p_job_id, SQLERRM;
        END;
        -- Mark the job as failed
        UPDATE public.import_job
        SET error = jsonb_build_object('process_establishment_unhandled_error', error_message)::TEXT,
            state = 'failed'
        WHERE id = p_job_id;
        RAISE DEBUG '[Job %] process_establishment: Marked job as failed due to unhandled error: %', p_job_id, error_message;
        -- Don't re-raise - job is marked as failed
    END;

    -- The framework now handles advancing priority for all rows.
    v_duration_ms := (EXTRACT(EPOCH FROM (clock_timestamp() - v_start_time)) * 1000);
    RAISE DEBUG '[Job %] process_establishment (Batch): Finished in % ms. Success: %, Errors: %', p_job_id, round(v_duration_ms, 2), v_update_count, v_error_count;
END;
$process_establishment$;

END;

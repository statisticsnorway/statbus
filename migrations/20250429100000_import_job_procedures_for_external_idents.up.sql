-- Implements the analyse and operation procedures for the ExternalIdents import target.

BEGIN;


-- Procedure to analyse external identifier data (Batch Oriented)
CREATE OR REPLACE PROCEDURE import.analyse_external_idents(p_job_id INT, p_batch_row_ids BIGINT[], p_step_code TEXT)
LANGUAGE plpgsql AS $analyse_external_idents$
DECLARE
    v_job public.import_job;
    v_step RECORD;
    v_snapshot JSONB;
    v_data_table_name TEXT;
    v_ident_data_cols JSONB;
    v_col_rec RECORD;
    v_sql TEXT;
    v_update_count INT := 0;
    v_error_count INT := 0;
    v_skipped_update_count INT := 0;
    v_unpivot_sql TEXT;
    v_add_separator BOOLEAN;
    v_error_row_ids BIGINT[] := ARRAY[]::BIGINT[];
    v_error_keys_to_clear_arr TEXT[] := ARRAY['external_idents'];
    v_has_lu_id_col BOOLEAN := FALSE;
    v_has_est_id_col BOOLEAN := FALSE;
    v_set_clause TEXT;
    v_strategy public.import_strategy;
BEGIN
    RAISE DEBUG '[Job %] analyse_external_idents (Batch): Starting analysis for % rows', p_job_id, array_length(p_batch_row_ids, 1);

    -- Get job details and snapshot
    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;
    v_strategy := (v_job.definition_snapshot->'import_definition'->>'strategy')::public.import_strategy;

    -- Check for existence of key columns in the _data table
    SELECT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = v_data_table_name AND column_name = 'legal_unit_id'
    ) INTO v_has_lu_id_col;
    RAISE DEBUG '[Job %] Data table % has legal_unit_id column: %', p_job_id, v_data_table_name, v_has_lu_id_col;

    SELECT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = v_data_table_name AND column_name = 'establishment_id'
    ) INTO v_has_est_id_col;
    RAISE DEBUG '[Job %] Data table % has establishment_id column: %', p_job_id, v_data_table_name, v_has_est_id_col;

    v_ident_data_cols := v_job.definition_snapshot->'import_data_column_list';

    IF v_ident_data_cols IS NULL OR jsonb_typeof(v_ident_data_cols) != 'array' THEN
        RAISE EXCEPTION '[Job %] Failed to load valid import_data_column_list from definition_snapshot', p_job_id;
    END IF;

    -- Find the target step details
    SELECT * INTO v_step FROM public.import_step WHERE code = 'external_idents';
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] external_idents target not found', p_job_id;
    END IF;

    -- Filter data columns relevant to this step
    SELECT jsonb_agg(value) INTO v_ident_data_cols
    FROM jsonb_array_elements(v_ident_data_cols) value
    WHERE (value->>'step_id')::int = v_step.id AND value->>'purpose' = 'source_input';

    IF v_ident_data_cols IS NULL OR jsonb_array_length(v_ident_data_cols) = 0 THEN
         RAISE DEBUG '[Job %] analyse_external_idents: No external ident source_input data columns found in snapshot for step %. Skipping analysis.', p_job_id, v_step.id;
         EXECUTE format($$UPDATE public.%I SET last_completed_priority = %L WHERE row_id = ANY(%L)$$,
                        v_data_table_name, v_step.priority, p_batch_row_ids);
         RETURN;
    END IF;

    -- Step 1: Unpivot provided identifiers and lookup existing units
    CREATE TEMP TABLE temp_unpivoted_idents (
        data_row_id BIGINT,
        source_ident_code TEXT, -- The code/column name from the _data table e.g. 'tax_ident'
        ident_value TEXT,
        ident_type_id INT,      -- Resolved ID from external_ident_type, NULL if source_ident_code is unknown
        resolved_lu_id INT,
        resolved_est_id INT
        -- PRIMARY KEY (data_row_id, source_ident_code) -- Might be too restrictive if same source_ident_code appears multiple times (should not happen with current unpivot)
    ) ON COMMIT DROP;

    v_unpivot_sql := '';
    v_add_separator := FALSE;
    FOR v_col_rec IN SELECT value->>'column_name' as col_name
                     FROM jsonb_array_elements(v_ident_data_cols) value
    LOOP
        IF v_add_separator THEN v_unpivot_sql := v_unpivot_sql || ' UNION ALL '; END IF;
        v_unpivot_sql := v_unpivot_sql || format(
            $$SELECT dt.row_id, %L AS ident_code, dt.%I AS ident_value
             FROM public.%I dt WHERE dt.%I IS NOT NULL AND dt.row_id = ANY(%L) AND dt.action IS DISTINCT FROM 'skip'$$, -- Exclude pre-skipped, handle NULL action
             v_col_rec.col_name, v_col_rec.col_name, v_data_table_name, v_col_rec.col_name, p_batch_row_ids
        );
        v_add_separator := TRUE;
    END LOOP;

    IF v_unpivot_sql = '' THEN
        RAISE DEBUG '[Job %] analyse_external_idents: No external ident values found in batch. Skipping further analysis.', p_job_id;
        v_sql := format($$
            UPDATE public.%I dt SET
                state = %L,
                error = jsonb_build_object('external_idents', 'No identifier provided'),
                -- last_completed_priority is preserved (not changed) on error
                operation = 'insert'::public.import_row_operation_type, -- Always set operation
                action = %L
            WHERE dt.row_id = ANY(%L);
        $$, v_data_table_name, 'error', 'skip'::public.import_row_action_type, p_batch_row_ids);
        EXECUTE v_sql;
        GET DIAGNOSTICS v_error_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_external_idents (Batch): Finished analysis for batch. Errors: % (all rows missing identifiers)', p_job_id, v_error_count;
        DROP TABLE IF EXISTS temp_unpivoted_idents; -- Ensure cleanup
        RETURN;
    END IF;

    v_sql := format($$
        INSERT INTO temp_unpivoted_idents (data_row_id, source_ident_code, ident_value, ident_type_id, resolved_lu_id, resolved_est_id)
        SELECT
            up.row_id, 
            up.ident_code AS source_ident_code, 
            up.ident_value, 
            xit.id AS ident_type_id, -- This will be NULL if up.ident_code is not found in xit.code
            xi.legal_unit_id, 
            xi.establishment_id
        FROM ( %s ) up -- up.ident_code is the column name from _data table, e.g. 'tax_ident'
        LEFT JOIN public.external_ident_type_active xit ON xit.code = up.ident_code -- Use _active view
        LEFT JOIN public.external_ident xi ON xi.type_id = xit.id AND xi.ident = up.ident_value; -- xi.type_id will be NULL if xit.id is NULL
    $$, v_unpivot_sql);
    RAISE DEBUG '[Job %] analyse_external_idents: Unpivoting and looking up identifiers: %', p_job_id, v_sql;
    EXECUTE v_sql;

    -- Debug: Log contents of temp_unpivoted_idents
    DECLARE
        tui_rec RECORD;
    BEGIN
        RAISE DEBUG '[Job %] analyse_external_idents: Contents of temp_unpivoted_idents for batch %:', p_job_id, p_batch_row_ids;
        FOR tui_rec IN SELECT * FROM temp_unpivoted_idents WHERE data_row_id = ANY(p_batch_row_ids) ORDER BY data_row_id, source_ident_code LOOP
            RAISE DEBUG '[Job %]   TUI: data_row_id=%, source_ident_code=%, ident_value=%, ident_type_id=%, resolved_lu_id=%, resolved_est_id=%',
                        p_job_id, tui_rec.data_row_id, tui_rec.source_ident_code, tui_rec.ident_value, tui_rec.ident_type_id, tui_rec.resolved_lu_id, tui_rec.resolved_est_id;
        END LOOP;
    END;

    -- Step 2: Identify and Aggregate Errors, Determine Operation and Action
    CREATE TEMP TABLE temp_batch_analysis (
        data_row_id BIGINT PRIMARY KEY,
        error_jsonb JSONB,
        resolved_lu_id INT,
        resolved_est_id INT,
        operation public.import_row_operation_type,
        action public.import_row_action_type
    ) ON COMMIT DROP;

    v_sql := format($$
        WITH RowChecks AS (
            SELECT
                orig.data_row_id,
                COUNT(tui.ident_value) FILTER (WHERE tui.ident_value IS NOT NULL) AS num_raw_idents_with_value, -- Count of idents that had a value from source
                COUNT(tui.ident_type_id) FILTER (WHERE tui.ident_value IS NOT NULL AND tui.ident_type_id IS NOT NULL) AS num_valid_type_idents_with_value, -- Count of idents with value AND recognized type
                array_agg(DISTINCT tui.source_ident_code) FILTER (WHERE tui.ident_value IS NOT NULL AND tui.ident_type_id IS NULL) as unknown_ident_codes, -- List of codes for unknown types that had a value
                COUNT(DISTINCT tui.resolved_lu_id) FILTER (WHERE tui.resolved_lu_id IS NOT NULL AND tui.ident_type_id IS NOT NULL) AS distinct_lu_ids,
                COUNT(DISTINCT tui.resolved_est_id) FILTER (WHERE tui.resolved_est_id IS NOT NULL AND tui.ident_type_id IS NOT NULL) AS distinct_est_ids,
                MAX(tui.resolved_lu_id) FILTER (WHERE tui.resolved_lu_id IS NOT NULL AND tui.ident_type_id IS NOT NULL) AS final_lu_id,
                MAX(tui.resolved_est_id) FILTER (WHERE tui.resolved_est_id IS NOT NULL AND tui.ident_type_id IS NOT NULL) AS final_est_id
            FROM (SELECT unnest(%L::BIGINT[]) as data_row_id) orig
            LEFT JOIN temp_unpivoted_idents tui ON orig.data_row_id = tui.data_row_id
            GROUP BY orig.data_row_id
        ),
        AnalysisWithOperation AS (
            SELECT
                rc.data_row_id,
                rc.final_lu_id,
                rc.final_est_id,
                jsonb_strip_nulls(jsonb_build_object(
                    'missing_identifier_value', CASE WHEN rc.num_raw_idents_with_value = 0 THEN true ELSE NULL END, -- Error if NO identifier had any value
                    'unknown_identifier_type', CASE WHEN rc.num_raw_idents_with_value > 0 AND rc.num_valid_type_idents_with_value = 0 THEN rc.unknown_ident_codes ELSE NULL END, -- Error if values provided but for types not in external_ident_type
                    'inconsistent_legal_unit', CASE WHEN rc.distinct_lu_ids > 1 THEN true ELSE NULL END,
                    'inconsistent_establishment', CASE WHEN rc.distinct_est_ids > 1 THEN true ELSE NULL END,
                    'ambiguous_unit_type', CASE WHEN rc.final_lu_id IS NOT NULL AND rc.final_est_id IS NOT NULL THEN true ELSE NULL END
                )) as error_jsonb,
                CASE
                    WHEN rc.final_lu_id IS NULL AND rc.final_est_id IS NULL THEN 'insert'::public.import_row_operation_type
                    WHEN %L::public.import_strategy IN ('insert_or_update', 'update_only') THEN 'update'::public.import_row_operation_type
                    ELSE 'replace'::public.import_row_operation_type -- Covers insert_or_replace, replace_only, and insert_only (when existing is found)
                END as operation
            FROM RowChecks rc
        )
        INSERT INTO temp_batch_analysis (data_row_id, error_jsonb, resolved_lu_id, resolved_est_id, operation, action)
        SELECT
            awo.data_row_id,
            awo.error_jsonb,
            awo.final_lu_id,
            awo.final_est_id,
            awo.operation,
            CASE
                WHEN awo.error_jsonb != '{}'::jsonb THEN 'skip'::public.import_row_action_type -- Priority 1: Error

                -- Strategy: insert_only. Skip if operation is not 'insert'.
                WHEN %L::public.import_strategy = 'insert_only' AND awo.operation != 'insert'::public.import_row_operation_type THEN 'skip'::public.import_row_action_type

                -- Strategy: replace_only. Skip if operation is not 'replace'.
                WHEN %L::public.import_strategy = 'replace_only' AND awo.operation != 'replace'::public.import_row_operation_type THEN 'skip'::public.import_row_action_type
                
                -- Strategy: update_only. Skip if operation is not 'update'.
                WHEN %L::public.import_strategy = 'update_only' AND awo.operation != 'update'::public.import_row_operation_type THEN 'skip'::public.import_row_action_type

                -- Otherwise, action is the same as the (now strategy-aware) operation.
                ELSE (awo.operation::text)::public.import_row_action_type
            END as action
        FROM AnalysisWithOperation awo;
    $$, p_batch_row_ids, v_strategy, -- For operation CASE
        v_strategy, v_strategy, v_strategy); -- For action CASE
    RAISE DEBUG '[Job %] analyse_external_idents: Identifying errors, determining operation and action: %', p_job_id, v_sql;
    EXECUTE v_sql;
    
    -- Debug: Log results from RowChecks logic (which is inside the v_sql for temp_batch_analysis)
    DECLARE
        rc_rec RECORD;
        debug_sql TEXT;
    BEGIN
        debug_sql := format($$
            WITH RowChecks AS (
                SELECT
                    orig.data_row_id,
                    COUNT(tui.ident_value) FILTER (WHERE tui.ident_value IS NOT NULL) AS num_raw_idents_with_value,
                    COUNT(tui.ident_type_id) FILTER (WHERE tui.ident_value IS NOT NULL AND tui.ident_type_id IS NOT NULL) AS num_valid_type_idents_with_value,
                    array_agg(DISTINCT tui.source_ident_code) FILTER (WHERE tui.ident_value IS NOT NULL AND tui.ident_type_id IS NULL) as unknown_ident_codes,
                    COUNT(DISTINCT tui.resolved_lu_id) FILTER (WHERE tui.resolved_lu_id IS NOT NULL AND tui.ident_type_id IS NOT NULL) AS distinct_lu_ids,
                    COUNT(DISTINCT tui.resolved_est_id) FILTER (WHERE tui.resolved_est_id IS NOT NULL AND tui.ident_type_id IS NOT NULL) AS distinct_est_ids,
                    MAX(tui.resolved_lu_id) FILTER (WHERE tui.resolved_lu_id IS NOT NULL AND tui.ident_type_id IS NOT NULL) AS final_lu_id,
                    MAX(tui.resolved_est_id) FILTER (WHERE tui.resolved_est_id IS NOT NULL AND tui.ident_type_id IS NOT NULL) AS final_est_id
                FROM (SELECT unnest(%L::BIGINT[]) as data_row_id) orig
                LEFT JOIN temp_unpivoted_idents tui ON orig.data_row_id = tui.data_row_id
                GROUP BY orig.data_row_id
            )
            SELECT * FROM RowChecks WHERE data_row_id = ANY(%L::BIGINT[]) ORDER BY data_row_id;
        $$, p_batch_row_ids, p_batch_row_ids); -- Pass p_batch_row_ids for both %L

        RAISE DEBUG '[Job %] analyse_external_idents: Debugging RowChecks logic with SQL: %', p_job_id, debug_sql;
        FOR rc_rec IN EXECUTE debug_sql
        LOOP
            RAISE DEBUG '[Job %]   RowChecks for data_row_id=%: num_raw_idents_with_value=%, num_valid_type_idents_with_value=%, unknown_ident_codes=%, distinct_lu_ids=%, distinct_est_ids=%, final_lu_id=%, final_est_id=%',
                        p_job_id, rc_rec.data_row_id, rc_rec.num_raw_idents_with_value, rc_rec.num_valid_type_idents_with_value, rc_rec.unknown_ident_codes,
                        rc_rec.distinct_lu_ids, rc_rec.distinct_est_ids, rc_rec.final_lu_id, rc_rec.final_est_id;
        END LOOP;
    END;

    -- Step 3: Batch Update Error Rows
    BEGIN
        v_sql := format($$
            UPDATE public.%I dt SET
                state = %L,
                error = COALESCE(dt.error, %L) || jsonb_build_object('external_idents', err.error_jsonb),
                -- last_completed_priority is preserved (not changed) on error
                operation = err.operation, -- Always set operation
                action = err.action
            FROM temp_batch_analysis err
            WHERE dt.row_id = err.data_row_id AND err.error_jsonb != %L;
        $$, v_data_table_name, 'error', '{}'::jsonb, '{}'::jsonb);
        RAISE DEBUG '[Job %] analyse_external_idents: Updating error rows: %', p_job_id, v_sql;
        EXECUTE v_sql;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        v_error_count := v_update_count;
        SELECT array_agg(data_row_id) INTO v_error_row_ids FROM temp_batch_analysis WHERE error_jsonb != '{}'::jsonb;
        RAISE DEBUG '[Job %] analyse_external_idents: Marked % rows as error.', p_job_id, v_update_count;
    END;

    -- Step 4: Batch Update Non-Error Rows (Success or Strategy Skips)
    v_set_clause := format('last_completed_priority = %L, error = CASE WHEN (error - %L::TEXT[]) = ''{}''::jsonb THEN NULL ELSE (error - %L::TEXT[]) END, state = %L, action = ru.action, operation = ru.operation',
                           v_step.priority, v_error_keys_to_clear_arr, v_error_keys_to_clear_arr, 'analysing'::public.import_data_state);
    IF v_has_lu_id_col THEN
        v_set_clause := v_set_clause || ', legal_unit_id = ru.resolved_lu_id';
    END IF;
    IF v_has_est_id_col THEN
        v_set_clause := v_set_clause || ', establishment_id = ru.resolved_est_id';
    END IF;

    IF NOT v_has_lu_id_col AND NOT v_has_est_id_col THEN
        RAISE DEBUG '[Job %] analyse_external_idents: No specific unit ID columns (legal_unit_id, establishment_id) exist in % for Step 4. Updating metadata, action, and operation.', p_job_id, v_data_table_name;
    END IF;

    v_sql := format($$
        UPDATE public.%I dt SET
            %s -- Dynamic SET clause
        FROM temp_batch_analysis ru
        WHERE dt.row_id = ru.data_row_id
          AND dt.row_id = ANY(%L) AND dt.row_id != ALL(%L); -- Update only non-error rows from the original batch
    $$, v_data_table_name, v_set_clause, p_batch_row_ids, COALESCE(v_error_row_ids, ARRAY[]::BIGINT[]));
    RAISE DEBUG '[Job %] analyse_external_idents: Updating non-error rows (success or strategy skips): %', p_job_id, v_sql;
    EXECUTE v_sql;
    GET DIAGNOSTICS v_update_count = ROW_COUNT;
    RAISE DEBUG '[Job %] analyse_external_idents: Updated % non-error rows.', p_job_id, v_update_count;

    DROP TABLE IF EXISTS temp_unpivoted_idents;
    DROP TABLE IF EXISTS temp_batch_analysis;

    -- Update priority for rows that were initially skipped
    EXECUTE format('
        UPDATE public.%I dt SET
            last_completed_priority = %L
        WHERE dt.row_id = ANY(%L) AND dt.action = ''skip'';
    ', v_data_table_name, v_step.priority, p_batch_row_ids);
    GET DIAGNOSTICS v_skipped_update_count = ROW_COUNT;
    RAISE DEBUG '[Job %] analyse_external_idents: Updated last_completed_priority for % pre-skipped rows.', p_job_id, v_skipped_update_count;

    RAISE DEBUG '[Job %] analyse_external_idents (Batch): Finished analysis for batch. Total errors in batch: %', p_job_id, v_error_count;

EXCEPTION WHEN OTHERS THEN
    RAISE WARNING '[Job %] analyse_external_idents: Error during analysis: %', p_job_id, SQLERRM;
    -- Ensure cleanup even on error
    DROP TABLE IF EXISTS temp_unpivoted_idents;
    DROP TABLE IF EXISTS temp_batch_analysis;
    -- Mark the job itself as failed
    UPDATE public.import_job
    SET error = jsonb_build_object('analyse_external_idents_error', SQLERRM),
        state = 'finished' -- Or a new 'failed' state
    WHERE id = p_job_id;
    RAISE DEBUG '[Job %] analyse_external_idents: Marked job as failed due to error: %', p_job_id, SQLERRM;
    RAISE; -- Re-raise the exception
END;
$analyse_external_idents$;


CREATE FUNCTION import.process_external_idents(
    new_jsonb JSONB,
    unit_type TEXT,
    OUT external_idents public.external_ident[],
    OUT prior_id INTEGER
) RETURNS RECORD AS $process_external_idents$
DECLARE
    unit_fk_field TEXT;
    unit_fk_value INTEGER;
    ident_code TEXT;
    ident_value TEXT;
    ident_row public.external_ident;
    ident_type_row public.external_ident_type_active; -- Changed to use _active view
    ident_codes TEXT[] := '{}';
    -- Helpers to provide error messages to the user, with the ident_type_code
    -- that would otherwise be lost.
    ident_jsonb JSONB;
    prev_ident_jsonb JSONB;
    unique_ident_specified BOOLEAN := false;
BEGIN
    IF unit_type NOT IN ('legal_unit', 'establishment') THEN
        RAISE EXCEPTION 'Invalid unit_type: %', unit_type;
    END IF;

    unit_fk_field := unit_type || '_id';

    FOR ident_type_row IN
        (SELECT * FROM public.external_ident_type_active ORDER BY priority) -- Changed to use _active view and added ORDER BY
    LOOP
        ident_code := ident_type_row.code;
        ident_codes := array_append(ident_codes, ident_code);

        IF new_jsonb ? ident_code THEN
            ident_value := new_jsonb ->> ident_code;

            IF ident_value IS NOT NULL AND ident_value <> '' THEN
                unique_ident_specified := true;

                SELECT to_jsonb(ei.*)
                     || jsonb_build_object(
                    'ident_code', eit.code -- For user feedback
                    ) INTO ident_jsonb
                FROM public.external_ident AS ei
                JOIN public.external_ident_type AS eit -- Keep join on base table for ID
                  ON ei.type_id = eit.id
                WHERE eit.id = ident_type_row.id -- Use ID from _active view iteration
                  AND ei.ident = ident_value;

                IF NOT FOUND THEN
                    -- Prepare a row to be added later after the legal_unit is created
                    -- and the legal_unit_id is known.
                    ident_jsonb := jsonb_build_object(
                                'ident_code', ident_type_row.code, -- For user feedback - ignored by jsonb_populate_record
                                'type_id', ident_type_row.id, -- For jsonb_populate_record
                                'ident', ident_value
                        );
                    -- Initialise the ROW using mandatory positions, however,
                    -- populate with jsonb_populate_record for avoiding possible mismatch.
                    ident_row := ROW(NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL);
                    ident_row := jsonb_populate_record(NULL::public.external_ident,ident_jsonb);
                    external_idents := array_append(external_idents, ident_row);
                ELSE -- FOUND
                    unit_fk_value := (ident_jsonb ->> unit_fk_field)::INTEGER;
                    IF unit_fk_value IS NULL THEN
                        DECLARE
                          conflicting_unit_type TEXT;
                        BEGIN
                          CASE
                            WHEN (ident_jsonb ->> 'establishment_id') IS NOT NULL THEN
                              conflicting_unit_type := 'establishment';
                            WHEN (ident_jsonb ->> 'legal_unit_id') IS NOT NULL THEN
                              conflicting_unit_type := 'legal_unit';
                            WHEN (ident_jsonb ->> 'enterprise_id') IS NOT NULL THEN
                              conflicting_unit_type := 'enterprise';
                            WHEN (ident_jsonb ->> 'enterprise_group_id') IS NOT NULL THEN
                              conflicting_unit_type := 'enterprise_group';
                            ELSE
                              RAISE EXCEPTION 'Missing logic for external_ident %', ident_jsonb;
                          END CASE;
                          RAISE EXCEPTION 'The external identifier % for % already taken by a % for row %'
                                          , ident_code, unit_type, conflicting_unit_type, new_jsonb;
                        END;
                    END IF;
                    IF prior_id IS NULL THEN
                        prior_id := unit_fk_value;
                    ELSEIF prior_id IS DISTINCT FROM unit_fk_value THEN
                        -- All matching identifiers must be consistent.
                        RAISE EXCEPTION 'Inconsistent external identifiers % and % for row %'
                                        , prev_ident_jsonb, ident_jsonb, new_jsonb;
                    END IF;
                END IF; -- FOUND / NOT FOUND
                prev_ident_jsonb := ident_jsonb;
            END IF; -- ident_value provided
        END IF; -- ident_type.code in import
    END LOOP; -- public.external_ident_type_active

    IF NOT unique_ident_specified THEN
        RAISE EXCEPTION 'No external identifier (%) is specified for row %', array_to_string(ident_codes, ','), new_jsonb;
    END IF;
END; -- Process external identifiers
$process_external_idents$ LANGUAGE plpgsql;


COMMIT;

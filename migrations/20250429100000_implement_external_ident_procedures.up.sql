-- Migration: implement_external_ident_procedures
-- Implements the analyse and operation procedures for the ExternalIdents import target.

BEGIN;

-- Procedure to analyse external identifier data (Batch Oriented)
CREATE OR REPLACE PROCEDURE admin.analyse_external_idents(p_job_id INT, p_batch_row_ids BIGINT[], p_step_code TEXT)
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
    v_unpivot_sql TEXT;
    v_add_separator BOOLEAN;
    v_error_row_ids BIGINT[] := ARRAY[]::BIGINT[];
    v_has_lu_id_col BOOLEAN := FALSE;
    v_has_est_id_col BOOLEAN := FALSE;
    -- v_has_operation_col BOOLEAN := FALSE; -- Removed: operation column is assumed to exist for this step
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

    -- The 'operation' column is defined by the 'external_idents' step itself, so it's assumed to exist.
    -- No need to check for v_has_operation_col.

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
        ident_code TEXT,
        ident_value TEXT,
        ident_type_id INT,
        resolved_lu_id INT,
        resolved_est_id INT
    ) ON COMMIT DROP;

    v_unpivot_sql := '';
    v_add_separator := FALSE;
    FOR v_col_rec IN SELECT value->>'column_name' as col_name
                     FROM jsonb_array_elements(v_ident_data_cols) value
    LOOP
        IF v_add_separator THEN v_unpivot_sql := v_unpivot_sql || ' UNION ALL '; END IF;
        v_unpivot_sql := v_unpivot_sql || format(
            $$SELECT dt.row_id, %L AS ident_code, dt.%I AS ident_value
             FROM public.%I dt WHERE dt.%I IS NOT NULL AND dt.row_id = ANY(%L)$$,
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
                last_completed_priority = %L,
                operation = 'insert'::public.import_row_operation_type, -- Always set operation
                action = %L
            WHERE dt.row_id = ANY(%L);
        $$, v_data_table_name, 'error', v_step.priority - 1, 'skip'::public.import_row_action_type, p_batch_row_ids);
        EXECUTE v_sql;
        GET DIAGNOSTICS v_error_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_external_idents (Batch): Finished analysis for batch. Errors: % (all rows missing identifiers)', p_job_id, v_error_count;
        RETURN;
    END IF;

    v_sql := format($$
        INSERT INTO temp_unpivoted_idents (data_row_id, ident_code, ident_value, ident_type_id, resolved_lu_id, resolved_est_id)
        SELECT
            up.row_id, up.ident_code, up.ident_value, xit.id, xi.legal_unit_id, xi.establishment_id
        FROM ( %s ) up
        JOIN public.external_ident_type xit ON xit.code = up.ident_code
        LEFT JOIN public.external_ident xi ON xi.type_id = xit.id AND xi.ident = up.ident_value;
    $$, v_unpivot_sql);
    RAISE DEBUG '[Job %] analyse_external_idents: Unpivoting and looking up identifiers: %', p_job_id, v_sql;
    EXECUTE v_sql;

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
                COUNT(tui.data_row_id) AS num_idents_provided,
                COUNT(DISTINCT tui.resolved_lu_id) FILTER (WHERE tui.resolved_lu_id IS NOT NULL) AS distinct_lu_ids,
                COUNT(DISTINCT tui.resolved_est_id) FILTER (WHERE tui.resolved_est_id IS NOT NULL) AS distinct_est_ids,
                MAX(tui.resolved_lu_id) FILTER (WHERE tui.resolved_lu_id IS NOT NULL) AS final_lu_id,
                MAX(tui.resolved_est_id) FILTER (WHERE tui.resolved_est_id IS NOT NULL) AS final_est_id
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
                    'missing_identifier', CASE WHEN rc.num_idents_provided = 0 THEN true ELSE NULL END,
                    'inconsistent_legal_unit', CASE WHEN rc.distinct_lu_ids > 1 THEN true ELSE NULL END,
                    'inconsistent_establishment', CASE WHEN rc.distinct_est_ids > 1 THEN true ELSE NULL END,
                    'ambiguous_unit_type', CASE WHEN rc.final_lu_id IS NOT NULL AND rc.final_est_id IS NOT NULL THEN true ELSE NULL END
                )) as error_jsonb,
                CASE
                    WHEN rc.final_lu_id IS NULL AND rc.final_est_id IS NULL THEN 'insert'::public.import_row_operation_type
                    ELSE 'replace'::public.import_row_operation_type
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
                WHEN awo.error_jsonb != '{}'::jsonb THEN 'skip'::public.import_row_action_type
                WHEN %L::public.import_strategy = 'insert_only' AND awo.operation = 'replace'::public.import_row_operation_type THEN 'skip'::public.import_row_action_type
                WHEN %L::public.import_strategy = 'replace_only' AND awo.operation = 'insert'::public.import_row_operation_type THEN 'skip'::public.import_row_action_type
                ELSE awo.operation::public.import_row_action_type -- This will be 'insert' or 'replace'
            END as action
        FROM AnalysisWithOperation awo;
    $$, p_batch_row_ids, v_strategy, v_strategy);
    RAISE DEBUG '[Job %] analyse_external_idents: Identifying errors, determining operation and action: %', p_job_id, v_sql;
    EXECUTE v_sql;

    -- Step 3: Batch Update Error Rows
    BEGIN
        v_sql := format($$
            UPDATE public.%I dt SET
                state = %L,
                error = COALESCE(dt.error, %L) || jsonb_build_object('external_idents', err.error_jsonb),
                last_completed_priority = %L,
                operation = err.operation, -- Always set operation
                action = err.action
            FROM temp_batch_analysis err
            WHERE dt.row_id = err.data_row_id AND err.error_jsonb != %L;
        $$, v_data_table_name, 'error', '{}'::jsonb, v_step.priority - 1, '{}'::jsonb);
        RAISE DEBUG '[Job %] analyse_external_idents: Updating error rows: %', p_job_id, v_sql;
        EXECUTE v_sql;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        v_error_count := v_update_count;
        SELECT array_agg(data_row_id) INTO v_error_row_ids FROM temp_batch_analysis WHERE error_jsonb != '{}'::jsonb;
        RAISE DEBUG '[Job %] analyse_external_idents: Marked % rows as error.', p_job_id, v_update_count;
    END;

    -- Step 4: Batch Update Non-Error Rows (Success or Strategy Skips)
    v_set_clause := format('last_completed_priority = %L, error = CASE WHEN (error - ''external_idents'') = ''{}''::jsonb THEN NULL ELSE (error - ''external_idents'') END, state = %L, action = ru.action, operation = ru.operation',
                           v_step.priority, 'analysing'::public.import_data_state);
    IF v_has_lu_id_col THEN
        v_set_clause := v_set_clause || ', legal_unit_id = ru.resolved_lu_id';
    END IF;
    IF v_has_est_id_col THEN
        v_set_clause := v_set_clause || ', establishment_id = ru.resolved_est_id';
    END IF;
    -- No IF for operation, it's always set via the base v_set_clause

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

    -- Original Step 5 is removed as its logic is now covered by Step 4.
    -- Step 4 updates all non-error rows, setting their last_completed_priority, state, action, and operation.
    -- This includes rows that are skipped due to strategy (action='skip', error_jsonb='{}').

    DROP TABLE IF EXISTS temp_unpivoted_idents;
    DROP TABLE IF EXISTS temp_batch_analysis;

    RAISE DEBUG '[Job %] analyse_external_idents (Batch): Finished analysis for batch. Total errors in batch: %', p_job_id, v_error_count;
END;
$analyse_external_idents$;


-- process_external_idents function is removed as the step only performs analysis.

COMMIT;

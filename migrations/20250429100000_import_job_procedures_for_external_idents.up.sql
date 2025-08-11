-- Implements the analyse and operation procedures for the ExternalIdents import target.

BEGIN;


-- Procedure to analyse external identifier data (Batch Oriented)
CREATE OR REPLACE PROCEDURE import.analyse_external_idents(p_job_id INT, p_batch_row_ids INTEGER[], p_step_code TEXT)
LANGUAGE plpgsql AS $analyse_external_idents$
DECLARE
    v_job public.import_job;
    v_step public.import_step;
    v_snapshot JSONB;
    v_data_table_name TEXT;
    v_relevant_row_ids INTEGER[]; -- For holistic execution
    v_ident_data_cols JSONB;
    v_col_rec RECORD;
    v_sql TEXT;
    v_update_count INT := 0;
    v_error_count INT := 0;
    v_skipped_update_count INT := 0;
    v_unpivot_sql TEXT;
    v_add_separator BOOLEAN;
    v_error_row_ids INTEGER[] := ARRAY[]::INTEGER[];
    v_error_keys_to_clear_arr TEXT[]; -- Will be populated dynamically
    v_has_lu_id_col BOOLEAN := FALSE;
    v_has_est_id_col BOOLEAN := FALSE;
    v_set_clause TEXT;
    v_strategy public.import_strategy;
    v_job_mode public.import_mode; -- Added to use v_job_mode
    v_cross_type_conflict_check_sql TEXT; -- For dynamic SQL based on job_mode
BEGIN
    -- This is a HOLISTIC procedure. It is called once and processes all relevant rows for this step.
    -- The p_batch_row_ids parameter is ignored (it will be NULL).
    RAISE DEBUG '[Job %] analyse_external_idents (Holistic): Starting analysis.', p_job_id;

    -- Get job details and snapshot
    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;
    v_strategy := (v_job.definition_snapshot->'import_definition'->>'strategy')::public.import_strategy;
    v_job_mode := (v_job.definition_snapshot->'import_definition'->>'mode')::public.import_mode; -- Get job_mode

    -- Find the target step details from the snapshot
    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = 'external_idents';
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] external_idents target not found in snapshot', p_job_id;
    END IF;

    -- Holistic execution: get all relevant rows for this step.
    EXECUTE format('SELECT array_agg(row_id) FROM public.%I WHERE state = %L AND last_completed_priority < %L',
                   v_data_table_name, 'analysing'::public.import_data_state, v_step.priority)
    INTO v_relevant_row_ids;

    RAISE DEBUG '[Job %] analyse_external_idents: Holistic execution. Found % rows to process for this step.',
        p_job_id, COALESCE(array_length(v_relevant_row_ids, 1), 0);

    IF v_relevant_row_ids IS NULL OR array_length(v_relevant_row_ids, 1) = 0 THEN
        RAISE DEBUG '[Job %] analyse_external_idents: No relevant rows to process.', p_job_id;
        RETURN;
    END IF;

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

    -- Filter data columns relevant to this step
    SELECT jsonb_agg(value) INTO v_ident_data_cols
    FROM jsonb_array_elements(v_ident_data_cols) value
    WHERE (value->>'step_id')::int = v_step.id AND value->>'purpose' = 'source_input';

    IF v_ident_data_cols IS NULL OR jsonb_array_length(v_ident_data_cols) = 0 THEN
         RAISE DEBUG '[Job %] analyse_external_idents: No external ident source_input data columns found in snapshot for step %. Skipping analysis.', p_job_id, v_step.id;
         EXECUTE format($$UPDATE public.%I SET last_completed_priority = %L WHERE row_id = ANY(%L)$$,
                        v_data_table_name, v_step.priority, v_relevant_row_ids);
         RETURN;
    END IF;

    -- Build the list of error keys to clear, including all source_input columns for this step and general keys
    SELECT array_agg(value->>'column_name') INTO v_error_keys_to_clear_arr
    FROM jsonb_array_elements(v_ident_data_cols) value
    WHERE value->>'column_name' IS NOT NULL;

    v_error_keys_to_clear_arr := COALESCE(v_error_keys_to_clear_arr, ARRAY[]::TEXT[]) || ARRAY[
        'missing_identifier_value', 
        'unknown_identifier_type', 
        'inconsistent_legal_unit', 
        'inconsistent_establishment', 
        'ambiguous_unit_type'
    ];
    -- Ensure uniqueness (though direct conflict between source_input names and general keys is unlikely)
    SELECT array_agg(DISTINCT e) INTO v_error_keys_to_clear_arr FROM unnest(v_error_keys_to_clear_arr) e;
    RAISE DEBUG '[Job %] analyse_external_idents: Error keys to clear for this step: %', p_job_id, v_error_keys_to_clear_arr;

    -- Step 1: Unpivot provided identifiers and lookup existing units
    CREATE TEMP TABLE temp_unpivoted_idents (
        data_row_id INTEGER,
        source_ident_code TEXT, -- The code/column name from the _data table e.g. 'tax_ident'
        ident_value TEXT,
        ident_type_id INT,      -- Resolved ID from external_ident_type, NULL if source_ident_code is unknown
        resolved_lu_id INT,
        resolved_est_id INT,
        is_cross_type_conflict BOOLEAN,
        conflicting_unit_jsonb JSONB,
        conflicting_est_is_formal BOOLEAN DEFAULT FALSE -- New: Flag if conflicting EST is formal
        -- PRIMARY KEY (data_row_id, source_ident_code) -- Might be too restrictive if same source_ident_code appears multiple times (should not happen with current unpivot)
    ) ON COMMIT DROP;

    v_unpivot_sql := '';
    v_add_separator := FALSE;
    -- For external_idents step, the import_data_column.column_name *is* the external_ident_type.code
    FOR v_col_rec IN SELECT value->>'column_name' as idc_column_name -- This is the actual external_ident_type.code
                     FROM jsonb_array_elements(v_ident_data_cols) value
    LOOP
        -- idc_column_name itself will be used to join with external_ident_type.code
        IF v_col_rec.idc_column_name IS NULL THEN
             RAISE DEBUG '[Job %] analyse_external_idents: Skipping column as its name is null in import_data_column_list for step external_idents.', p_job_id;
             CONTINUE;
        END IF;

        IF v_add_separator THEN v_unpivot_sql := v_unpivot_sql || ' UNION ALL '; END IF;
        v_unpivot_sql := v_unpivot_sql || format(
            $$SELECT dt.row_id, 
                     %L AS source_column_name_in_data_table, -- This is the name of the column in _data table (e.g., 'tax_ident')
                     %L AS ident_type_code_to_join_on,     -- This is also the external_ident_type.code (e.g., 'tax_ident')
                     dt.%I AS ident_value
             FROM public.%I dt WHERE dt.%I IS NOT NULL AND dt.row_id = ANY(%L) AND dt.action IS DISTINCT FROM 'skip'$$,
             v_col_rec.idc_column_name, -- Name of column in _data table
             v_col_rec.idc_column_name, -- Code to join with external_ident_type
             v_col_rec.idc_column_name, -- Column to select value from in _data table
             v_data_table_name, v_col_rec.idc_column_name, v_relevant_row_ids
        );
        v_add_separator := TRUE;
    END LOOP;

    IF v_unpivot_sql = '' THEN
        RAISE DEBUG '[Job %] analyse_external_idents: No external ident values found in batch (e.g. all source columns were NULL, or no relevant columns in snapshot for external_idents step). Skipping further analysis.', p_job_id;
        v_sql := format($$
            UPDATE public.%I dt SET
                state = %L,
                error = jsonb_build_object('external_idents', 'No identifier provided or mapped correctly for external_idents step'),
                operation = 'insert'::public.import_row_operation_type,
                action = %L,
                last_completed_priority = %L
            WHERE dt.row_id = ANY(%L);
        $$, v_data_table_name, 'error', 'skip'::public.import_row_action_type, v_step.priority, v_relevant_row_ids);
        EXECUTE v_sql;
        GET DIAGNOSTICS v_error_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_external_idents (Batch): Finished analysis for batch. Errors: % (all rows missing identifiers or mappings for external_idents step)', p_job_id, v_error_count;
        DROP TABLE IF EXISTS temp_unpivoted_idents; 
        RETURN;
    END IF;

    -- v_cross_type_conflict_check_sql is removed as this logic is now embedded into the
    -- temp_unpivoted_idents population directly using is_cross_type_conflict and conflicting_unit_jsonb.

    v_sql := format($$
        INSERT INTO temp_unpivoted_idents (data_row_id, source_ident_code, ident_value, ident_type_id, resolved_lu_id, resolved_est_id, is_cross_type_conflict, conflicting_unit_jsonb, conflicting_est_is_formal)
        SELECT
            up.row_id, 
            up.source_column_name_in_data_table AS source_ident_code, 
            up.ident_value, 
            xit.id AS ident_type_id,
            xi.legal_unit_id, 
            xi.establishment_id,
            CASE %2$L -- v_job_mode
                WHEN 'legal_unit' THEN (xi.establishment_id IS NOT NULL) -- Importing LU, conflict if ident used by any EST
                WHEN 'establishment_formal' THEN 
                    (xi.legal_unit_id IS NOT NULL OR -- Conflict if ident used by LU
                     (xi.establishment_id IS NOT NULL AND conflicting_est_table.legal_unit_id IS NULL) -- OR Conflict if ident used by an INFORMAL EST
                    )
                WHEN 'establishment_informal' THEN
                    (xi.legal_unit_id IS NOT NULL OR -- Conflict if used by LU
                     (xi.establishment_id IS NOT NULL AND (conflicting_est_table.legal_unit_id IS NOT NULL)) -- Conflict if used by an EST that is formal (linked to an LU)
                    )
                WHEN 'generic_unit' THEN FALSE -- No specific cross-type conflict for generic_unit mode at this stage
                ELSE NULL
            END AS is_cross_type_conflict,
            CASE %2$L -- v_job_mode
                WHEN 'legal_unit' THEN
                    CASE WHEN xi.establishment_id IS NOT NULL THEN jsonb_build_object(xit.code, xi.ident) ELSE NULL END
                WHEN 'establishment_formal' THEN
                    CASE 
                        WHEN xi.legal_unit_id IS NOT NULL THEN jsonb_build_object(xit.code, xi.ident) -- Conflicting with LU
                        WHEN xi.establishment_id IS NOT NULL AND conflicting_est_table.legal_unit_id IS NULL THEN jsonb_build_object(xit.code, xi.ident) -- Conflicting with Informal EST
                        ELSE NULL 
                    END
                WHEN 'establishment_informal' THEN
                    CASE
                        WHEN xi.legal_unit_id IS NOT NULL THEN jsonb_build_object(xit.code, xi.ident) -- Conflicting with LU
                        WHEN xi.establishment_id IS NOT NULL AND (conflicting_est_table.legal_unit_id IS NOT NULL) THEN jsonb_build_object(xit.code, xi.ident) -- Conflicting with Formal EST
                        ELSE NULL
                    END
                WHEN 'generic_unit' THEN NULL -- No specific conflicting unit JSON for generic_unit mode here
                ELSE NULL
            END AS conflicting_unit_jsonb,
            CASE
                WHEN xi.establishment_id IS NOT NULL THEN (conflicting_est_table.legal_unit_id IS NOT NULL)
                ELSE FALSE 
            END AS conflicting_est_is_formal
        FROM ( %1$s ) up -- v_unpivot_sql
        LEFT JOIN public.external_ident_type_active xit ON xit.code = up.ident_type_code_to_join_on
        LEFT JOIN public.external_ident xi ON xi.type_id = xit.id AND xi.ident = up.ident_value
        LEFT JOIN public.establishment conflicting_est_table ON conflicting_est_table.id = xi.establishment_id; -- Join to check if conflicting EST is formal
    $$, v_unpivot_sql /* %1 */, v_job_mode /* %2 */ );
    RAISE DEBUG '[Job %] analyse_external_idents: Unpivoting and looking up identifiers: %', p_job_id, v_sql;
    EXECUTE v_sql;

    -- Debug: Log contents of temp_unpivoted_idents
    DECLARE
        tui_rec RECORD;
    BEGIN
        RAISE DEBUG '[Job %] analyse_external_idents: Contents of temp_unpivoted_idents for batch %:', p_job_id, v_relevant_row_ids;
        FOR tui_rec IN SELECT * FROM temp_unpivoted_idents WHERE data_row_id = ANY(v_relevant_row_ids) ORDER BY data_row_id, source_ident_code LOOP
            RAISE DEBUG '[Job %]   TUI: data_row_id=%, source_ident_code=%, ident_value=%, ident_type_id=%, resolved_lu_id=%, resolved_est_id=%',
                        p_job_id, tui_rec.data_row_id, tui_rec.source_ident_code, tui_rec.ident_value, tui_rec.ident_type_id, tui_rec.resolved_lu_id, tui_rec.resolved_est_id;
        END LOOP;
    END;

    -- Step 2: Identify and Aggregate Errors, Determine Operation and Action
    CREATE TEMP TABLE temp_batch_analysis (
        data_row_id INTEGER PRIMARY KEY,
        error_jsonb JSONB,
        resolved_lu_id INT,
        resolved_est_id INT,
        operation public.import_row_operation_type,
        action public.import_row_action_type,
        derived_founding_row_id INTEGER
    ) ON COMMIT DROP;

    v_sql := format($$
        WITH RowChecks AS ( -- Determines existing DB entity and entity signature for each row_id
            SELECT
                orig.data_row_id,
                dt.derived_valid_from, -- Used for ordering entities within the batch
                COUNT(tui.ident_value) FILTER (WHERE tui.ident_value IS NOT NULL) AS num_raw_idents_with_value,
                COUNT(tui.ident_type_id) FILTER (WHERE tui.ident_value IS NOT NULL AND tui.ident_type_id IS NOT NULL) AS num_valid_type_idents_with_value,
                array_agg(DISTINCT tui.source_ident_code) FILTER (WHERE tui.ident_value IS NOT NULL AND tui.ident_type_id IS NULL) as unknown_ident_codes,
                array_to_string(array_agg(DISTINCT tui.source_ident_code) FILTER (WHERE tui.ident_value IS NOT NULL AND tui.ident_type_id IS NULL), ', ') as unknown_ident_codes_text,
                array_agg(DISTINCT tui.source_ident_code) FILTER (WHERE tui.ident_value IS NOT NULL) as all_input_ident_codes_with_value,
                (SELECT array_agg(value->>'column_name') FROM jsonb_array_elements(%5$L) value) as all_source_input_ident_codes_for_step, -- %5$L is v_ident_data_cols (JSONB array of data_column objects for the step)
                COUNT(DISTINCT tui.resolved_lu_id) FILTER (WHERE tui.resolved_lu_id IS NOT NULL AND tui.ident_type_id IS NOT NULL) AS distinct_lu_ids,
                COUNT(DISTINCT tui.resolved_est_id) FILTER (WHERE tui.resolved_est_id IS NOT NULL AND tui.ident_type_id IS NOT NULL) AS distinct_est_ids,
                MAX(tui.resolved_lu_id) FILTER (WHERE tui.resolved_lu_id IS NOT NULL AND tui.ident_type_id IS NOT NULL) AS final_lu_id,
                MAX(tui.resolved_est_id) FILTER (WHERE tui.resolved_est_id IS NOT NULL AND tui.ident_type_id IS NOT NULL) AS final_est_id,
                jsonb_object_agg(tui.source_ident_code, tui.ident_value) FILTER (WHERE tui.ident_type_id IS NOT NULL AND tui.ident_value IS NOT NULL) AS entity_signature,
                BOOL_OR(tui.conflicting_est_is_formal) AS agg_conflicting_est_is_formal,
                -- Aggregate cross-type conflicts: key is source_ident_code, value is conflict message
                jsonb_object_agg(
                    tui.source_ident_code,
                    'Identifier already used by a ' ||
                    CASE
                        WHEN %4$L = 'legal_unit' AND tui.resolved_est_id IS NOT NULL THEN 'Establishment'
                        WHEN %4$L = 'establishment_formal' THEN
                            CASE
                                WHEN tui.resolved_lu_id IS NOT NULL THEN 'Legal Unit'
                                WHEN tui.resolved_est_id IS NOT NULL AND NOT tui.conflicting_est_is_formal THEN 'Informal Establishment' -- Adjusted logic
                                ELSE 'other conflicting unit for formal est'
                            END
                        WHEN %4$L = 'establishment_informal' THEN
                            CASE
                                WHEN tui.resolved_lu_id IS NOT NULL THEN 'Legal Unit'
                                WHEN tui.resolved_est_id IS NOT NULL AND tui.conflicting_est_is_formal THEN 'Formal Establishment'
                                ELSE 'other conflicting unit for informal est'
                            END
                        ELSE 'different unit type' -- Fallback for generic or unhandled modes
                    END || ': ' || tui.conflicting_unit_jsonb::TEXT
                ) FILTER (WHERE tui.is_cross_type_conflict IS TRUE) AS cross_type_conflict_errors
            FROM (SELECT unnest(%1$L::INTEGER[]) as data_row_id) orig -- %1$L is v_relevant_row_ids
            JOIN public.%2$I dt ON orig.data_row_id = dt.row_id      -- %2$I is v_data_table_name
            LEFT JOIN temp_unpivoted_idents tui ON orig.data_row_id = tui.data_row_id
            GROUP BY orig.data_row_id, dt.derived_valid_from
        ),
        OrderedBatchEntities AS ( -- Orders rows within the batch that share the same entity signature
            SELECT
                rc.*, -- Select all columns from RowChecks
                ROW_NUMBER() OVER (PARTITION BY rc.entity_signature ORDER BY rc.derived_valid_from NULLS LAST, rc.data_row_id) as rn_in_batch_for_entity,
                FIRST_VALUE(rc.data_row_id) OVER (PARTITION BY rc.entity_signature ORDER BY rc.derived_valid_from NULLS LAST, rc.data_row_id) as actual_founding_row_id
            FROM RowChecks rc
        ),
        AnalysisWithOperation AS ( -- Determines operation based on DB existence and batch order
            SELECT
                obe.data_row_id,
                obe.actual_founding_row_id, -- Added
                obe.final_lu_id, 
                obe.final_est_id, 
                ( -- Subquery to calculate unstable_identifier_errors
                    SELECT jsonb_object_agg(
                               input_data.ident_code, 
                               'Identifier ' || input_data.ident_code || ' value ''' || input_data.input_value || ''' from input attempts to change existing value ''' || COALESCE(existing_ei.ident, 'NULL') || ''''
                           )
                    FROM (SELECT key AS ident_code, value AS input_value FROM jsonb_each_text(obe.entity_signature)) AS input_data
                    JOIN public.external_ident_type_active xit ON xit.code = input_data.ident_code
                    LEFT JOIN public.external_ident existing_ei ON
                        existing_ei.type_id = xit.id AND
                        (
                            (obe.final_lu_id IS NOT NULL AND existing_ei.legal_unit_id = obe.final_lu_id) OR
                            (obe.final_est_id IS NOT NULL AND existing_ei.establishment_id = obe.final_est_id)
                        )
                    WHERE (obe.final_lu_id IS NOT NULL OR obe.final_est_id IS NOT NULL) 
                      AND existing_ei.ident IS NOT NULL 
                      AND input_data.input_value IS DISTINCT FROM existing_ei.ident 
                ) AS unstable_identifier_errors_jsonb,
                (
                    COALESCE(
                        (SELECT jsonb_object_agg(code, 'No identifier specified')
                         FROM unnest(obe.all_source_input_ident_codes_for_step) code
                         WHERE obe.num_raw_idents_with_value = 0),
                        '{}'::jsonb
                    ) ||
                    COALESCE(
                        (SELECT jsonb_object_agg(code, 'Unknown identifier type(s): ' || obe.unknown_ident_codes_text)
                         FROM unnest(obe.unknown_ident_codes) code
                         WHERE obe.num_raw_idents_with_value > 0 AND obe.num_valid_type_idents_with_value = 0),
                        '{}'::jsonb
                    ) ||
                    COALESCE(
                        (SELECT jsonb_object_agg(code, 'Provided identifiers resolve to different Legal Units')
                         FROM unnest(obe.all_input_ident_codes_with_value) code
                         WHERE obe.distinct_lu_ids > 1),
                        '{}'::jsonb
                    ) ||
                    COALESCE(
                        (SELECT jsonb_object_agg(code, 'Provided identifiers resolve to different Establishments')
                         FROM unnest(obe.all_input_ident_codes_with_value) code
                         WHERE obe.distinct_est_ids > 1),
                        '{}'::jsonb
                    ) ||
                    COALESCE(
                        (SELECT jsonb_object_agg(code, 'Identifier(s) ambiguously resolve to both a Legal Unit and an Establishment')
                         FROM unnest(obe.all_input_ident_codes_with_value) code
                         WHERE obe.final_lu_id IS NOT NULL AND obe.final_est_id IS NOT NULL AND obe.final_lu_id != obe.final_est_id),
                        '{}'::jsonb
                    ) ||
                    COALESCE(obe.cross_type_conflict_errors, '{}'::jsonb)
                ) as base_error_jsonb,
                CASE
                    WHEN obe.final_lu_id IS NULL AND obe.final_est_id IS NULL THEN -- Entity is new to the DB
                        CASE
                            WHEN obe.rn_in_batch_for_entity = 1 THEN 'insert'::public.import_row_operation_type
                            ELSE -- Subsequent row for a new entity within this batch
                                CASE
                                    WHEN %3$L::public.import_strategy IN ('insert_or_update', 'update_only') THEN 'update'::public.import_row_operation_type -- %3$L is v_strategy
                                    ELSE 'replace'::public.import_row_operation_type
                                END
                        END
                    ELSE -- Entity already exists in the DB
                        CASE
                            WHEN %3$L::public.import_strategy IN ('insert_or_update', 'update_only') THEN 'update'::public.import_row_operation_type -- %3$L is v_strategy
                            ELSE 'replace'::public.import_row_operation_type
                        END
                END as operation
            FROM OrderedBatchEntities obe
        )
        INSERT INTO temp_batch_analysis (data_row_id, error_jsonb, resolved_lu_id, resolved_est_id, operation, action, derived_founding_row_id)
        SELECT
            awo.data_row_id,
            awo.base_error_jsonb || COALESCE(awo.unstable_identifier_errors_jsonb, '{}'::jsonb) AS final_error_jsonb,
            awo.final_lu_id,
            awo.final_est_id,
            awo.operation,
            CASE
                WHEN (awo.base_error_jsonb || COALESCE(awo.unstable_identifier_errors_jsonb, '{}'::jsonb)) != '{}'::jsonb THEN 'skip'::public.import_row_action_type -- Priority 1: Any Error
                WHEN %3$L::public.import_strategy = 'insert_only' AND awo.operation != 'insert'::public.import_row_operation_type THEN 'skip'::public.import_row_action_type -- %3$L is v_strategy
                WHEN %3$L::public.import_strategy = 'replace_only' AND awo.operation != 'replace'::public.import_row_operation_type THEN 'skip'::public.import_row_action_type -- %3$L is v_strategy
                WHEN %3$L::public.import_strategy = 'update_only' AND awo.operation != 'update'::public.import_row_operation_type THEN 'skip'::public.import_row_action_type -- %3$L is v_strategy
                ELSE (awo.operation::text)::public.import_row_action_type
            END as action,
            awo.actual_founding_row_id
        FROM AnalysisWithOperation awo;
    $$, 
        v_relevant_row_ids,             /* %1$L */
        v_data_table_name,              /* %2$I */
        v_strategy,                     /* %3$L */
        v_job_mode,                     /* %4$L */
        v_ident_data_cols               /* %5$L */ 
    );
    RAISE DEBUG '[Job %] analyse_external_idents: Identifying errors, determining operation and action: %', p_job_id, v_sql;
    EXECUTE v_sql;
    
    -- Debug: Log results from RowChecks and OrderedBatchEntities logic
    DECLARE
        debug_rec RECORD;
        debug_sql TEXT;
    BEGIN
        debug_sql := format($$
            WITH RowChecks AS (
                SELECT
                    orig.data_row_id,
                    dt.derived_valid_from,
                    COUNT(tui.ident_value) FILTER (WHERE tui.ident_value IS NOT NULL) AS num_raw_idents_with_value,
                    COUNT(tui.ident_type_id) FILTER (WHERE tui.ident_value IS NOT NULL AND tui.ident_type_id IS NOT NULL) AS num_valid_type_idents_with_value,
                    array_agg(DISTINCT tui.source_ident_code) FILTER (WHERE tui.ident_value IS NOT NULL AND tui.ident_type_id IS NULL) as unknown_ident_codes,
                    COUNT(DISTINCT tui.resolved_lu_id) FILTER (WHERE tui.resolved_lu_id IS NOT NULL AND tui.ident_type_id IS NOT NULL) AS distinct_lu_ids,
                    COUNT(DISTINCT tui.resolved_est_id) FILTER (WHERE tui.resolved_est_id IS NOT NULL AND tui.ident_type_id IS NOT NULL) AS distinct_est_ids,
                    MAX(tui.resolved_lu_id) FILTER (WHERE tui.resolved_lu_id IS NOT NULL AND tui.ident_type_id IS NOT NULL) AS final_lu_id,
                    MAX(tui.resolved_est_id) FILTER (WHERE tui.resolved_est_id IS NOT NULL AND tui.ident_type_id IS NOT NULL) AS final_est_id,
                    jsonb_object_agg(tui.source_ident_code, tui.ident_value) FILTER (WHERE tui.ident_type_id IS NOT NULL AND tui.ident_value IS NOT NULL) AS entity_signature
                    -- Removed cross_type_conflict_errors from debug query for simplicity as its construction changed
                FROM (SELECT unnest(%1$L::INTEGER[]) as data_row_id) orig
                JOIN public.%2$I dt ON orig.data_row_id = dt.row_id
                LEFT JOIN temp_unpivoted_idents tui ON orig.data_row_id = tui.data_row_id
                GROUP BY orig.data_row_id, dt.derived_valid_from
            ),
            OrderedBatchEntities AS (
                SELECT
                    rc.*,
                    ROW_NUMBER() OVER (PARTITION BY rc.entity_signature ORDER BY rc.derived_valid_from NULLS LAST, rc.data_row_id) as rn_in_batch_for_entity
                FROM RowChecks rc
            )
            SELECT obe.* FROM OrderedBatchEntities obe WHERE obe.data_row_id = ANY(%1$L::INTEGER[]) ORDER BY obe.entity_signature, obe.rn_in_batch_for_entity;
        $$, v_relevant_row_ids, v_data_table_name);

        RAISE DEBUG '[Job %] analyse_external_idents: Debugging OrderedBatchEntities logic with SQL: %', p_job_id, debug_sql;
        FOR debug_rec IN EXECUTE debug_sql
        LOOP
            RAISE DEBUG '[Job %]   OBE: data_row_id=%, final_lu_id=%, final_est_id=%, entity_signature=%, rn_in_batch_for_entity=%, derived_valid_from=%',
                        p_job_id, debug_rec.data_row_id, debug_rec.final_lu_id, debug_rec.final_est_id, debug_rec.entity_signature, debug_rec.rn_in_batch_for_entity, debug_rec.derived_valid_from;
        END LOOP;
    END;

    -- Step 3: Batch Update Error Rows
    BEGIN
        v_sql := format($$
            UPDATE public.%I dt SET
                state = %L,
                error = COALESCE(dt.error, %L) || err.error_jsonb, -- Merge err.error_jsonb directly
                last_completed_priority = %L, -- Set to current step's priority on error
                operation = err.operation, -- Always set operation
                action = err.action
            FROM temp_batch_analysis err
            WHERE dt.row_id = err.data_row_id AND err.error_jsonb != %L;
        $$, v_data_table_name, 'error', '{}'::jsonb, v_step.priority, '{}'::jsonb);
        RAISE DEBUG '[Job %] analyse_external_idents: Updating error rows: %', p_job_id, v_sql;
        EXECUTE v_sql;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        v_error_count := v_update_count;
        SELECT array_agg(data_row_id) INTO v_error_row_ids FROM temp_batch_analysis WHERE error_jsonb != '{}'::jsonb;
        RAISE DEBUG '[Job %] analyse_external_idents: Marked % rows as error.', p_job_id, v_update_count;
    END;

    -- Step 4: Batch Update Non-Error Rows (Success or Strategy Skips)
    v_set_clause := format('last_completed_priority = %L, error = CASE WHEN (error - %L::TEXT[]) = ''{}''::jsonb THEN NULL ELSE (error - %L::TEXT[]) END, state = %L, action = ru.action, operation = ru.operation, founding_row_id = ru.derived_founding_row_id',
                           v_step.priority, v_error_keys_to_clear_arr, v_error_keys_to_clear_arr, 'analysing'::public.import_data_state);
    IF v_has_lu_id_col THEN
        v_set_clause := v_set_clause || ', legal_unit_id = ru.resolved_lu_id';
    END IF;
    IF v_has_est_id_col THEN
        v_set_clause := v_set_clause || ', establishment_id = ru.resolved_est_id';
    END IF;

    -- Ensure founding_row_id is part of the SET clause
    -- v_set_clause already includes founding_row_id = ru.derived_founding_row_id from its initial construction.
    -- No, it does not. It was:
    -- v_set_clause := format('last_completed_priority = %L, error = CASE WHEN (error - %L::TEXT[]) = ''{}''::jsonb THEN NULL ELSE (error - %L::TEXT[]) END, state = %L, action = ru.action, operation = ru.operation, founding_row_id = ru.derived_founding_row_id',
    -- This was correct. The issue might be if derived_founding_row_id itself is not correctly populated in temp_batch_analysis.
    -- Let's re-verify temp_batch_analysis population.
    -- The `actual_founding_row_id` is calculated in `OrderedBatchEntities` and selected into `temp_batch_analysis.derived_founding_row_id`. This seems correct.
    -- The `v_set_clause` correctly includes `founding_row_id = ru.derived_founding_row_id`.

    IF NOT v_has_lu_id_col AND NOT v_has_est_id_col THEN
        RAISE DEBUG '[Job %] analyse_external_idents: No specific unit ID columns (legal_unit_id, establishment_id) exist in % for Step 4. Updating metadata, action, operation, and founding_row_id.', p_job_id, v_data_table_name;
    END IF;

    v_sql := format($$
        UPDATE public.%I dt SET
            %s -- Dynamic SET clause which includes founding_row_id update
        FROM temp_batch_analysis ru
        WHERE dt.row_id = ru.data_row_id
          AND dt.row_id = ANY(%L) AND dt.row_id != ALL(%L); -- Update only non-error rows from the original batch
    $$, v_data_table_name, v_set_clause, v_relevant_row_ids, COALESCE(v_error_row_ids, ARRAY[]::INTEGER[]));
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
    ', v_data_table_name, v_step.priority, v_relevant_row_ids);
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


-- Shared procedure to upsert external identifiers for a given unit
CREATE OR REPLACE PROCEDURE import.shared_upsert_external_idents_for_unit(
    p_job_id INT,
    p_data_table_name TEXT,
    p_data_row_id INTEGER,
    p_unit_id INT,
    p_unit_type TEXT, -- 'legal_unit' or 'establishment'
    p_edit_by_user_id INT,
    p_edit_at TIMESTAMPTZ,
    p_edit_comment TEXT
)
LANGUAGE plpgsql AS $shared_upsert_external_idents_for_unit$
DECLARE
    rec_ident_type public.external_ident_type_active;
    v_data_table_col_name TEXT;
    v_ident_value TEXT;
    v_sql_insert TEXT;
    v_sql_conflict_set TEXT;
BEGIN
    IF p_unit_type NOT IN ('legal_unit', 'establishment') THEN
        RAISE EXCEPTION '[Job %] Invalid p_unit_type % passed to shared_upsert_external_idents_for_unit. Must be ''legal_unit'' or ''establishment''.', p_job_id, p_unit_type;
    END IF;

    FOR rec_ident_type IN SELECT * FROM public.external_ident_type_active ORDER BY priority LOOP
        v_data_table_col_name := rec_ident_type.code;
        BEGIN
            EXECUTE format('SELECT %I FROM public.%I WHERE row_id = %L',
                           v_data_table_col_name, p_data_table_name, p_data_row_id)
            INTO v_ident_value;

            IF v_ident_value IS NOT NULL AND v_ident_value <> '' THEN
                RAISE DEBUG '[Job %] shared_upsert_external_idents: For % ID %, data_row_id: %, ident_type: % (code: %), value: %',
                            p_job_id, p_unit_type, p_unit_id, p_data_row_id, rec_ident_type.id, rec_ident_type.code, v_ident_value;

                IF p_unit_type = 'legal_unit' THEN
                    v_sql_insert = format('INSERT INTO public.external_ident (legal_unit_id, type_id, ident, edit_by_user_id, edit_at, edit_comment) VALUES (%L, %L, %L, %L, %L, %L)',
                                          p_unit_id, rec_ident_type.id, v_ident_value, p_edit_by_user_id, p_edit_at, p_edit_comment);
                    v_sql_conflict_set = 'legal_unit_id = EXCLUDED.legal_unit_id, establishment_id = NULL, enterprise_id = NULL, enterprise_group_id = NULL';
                ELSIF p_unit_type = 'establishment' THEN
                    v_sql_insert = format('INSERT INTO public.external_ident (establishment_id, type_id, ident, edit_by_user_id, edit_at, edit_comment) VALUES (%L, %L, %L, %L, %L, %L)',
                                          p_unit_id, rec_ident_type.id, v_ident_value, p_edit_by_user_id, p_edit_at, p_edit_comment);
                    v_sql_conflict_set = 'establishment_id = EXCLUDED.establishment_id, legal_unit_id = NULL, enterprise_id = NULL, enterprise_group_id = NULL';
                END IF;

                EXECUTE v_sql_insert ||
                        format(' ON CONFLICT (type_id, ident) DO UPDATE SET %s, edit_by_user_id = EXCLUDED.edit_by_user_id, edit_at = EXCLUDED.edit_at, edit_comment = EXCLUDED.edit_comment', v_sql_conflict_set);

            END IF;
        EXCEPTION
            WHEN undefined_column THEN
                RAISE DEBUG '[Job %] shared_upsert_external_idents: Column % for ident type % not found in % for data_row_id %, skipping this ident type for this row.',
                            p_job_id, v_data_table_col_name, rec_ident_type.code, p_data_table_name, p_data_row_id;
        END;
    END LOOP;
END;
$shared_upsert_external_idents_for_unit$;

COMMIT;

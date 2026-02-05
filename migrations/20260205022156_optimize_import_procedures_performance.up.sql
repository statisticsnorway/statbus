-- Performance optimization for import procedures
--
-- Fix 1: analyse_external_idents - Change IS NOT DISTINCT FROM to = for ExistingIdents join
--        This prevents a 620 billion row cartesian product (823k × 753k rows) caused by
--        IS NOT DISTINCT FROM forcing nested loop joins instead of hash/merge joins.
--        The fix is safe because ExistingIdents CTE filters to rows WHERE final_lu_id IS NOT NULL
--        OR final_est_id IS NOT NULL, so NULL values never need to match.
--        Result: 0.7 seconds vs 37+ minutes
--
-- Fix 2: analyse_link_establishment_to_legal_unit - Break CTE chain into separate temp tables
--        Large CTE chains cause PostgreSQL to struggle with optimization. Breaking into
--        sequential temp tables allows each step to be indexed and optimized independently.
--        Result: ~68 seconds vs 17+ minutes (didn't finish)

-- ============================================================================
-- Fix 1: analyse_external_idents - Optimized ExistingIdents join
-- ============================================================================

CREATE OR REPLACE PROCEDURE import.analyse_external_idents(IN p_job_id integer, IN p_batch_seq integer, IN p_step_code text)
 LANGUAGE plpgsql
AS $analyse_external_idents$
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
    v_job_mode public.import_mode;
    -- Hierarchical processing variables
    v_hier_type RECORD;
    v_hier_unpivot_sql TEXT;
    v_labels_array TEXT[];
    v_label TEXT;
    v_label_index INT;
    v_hier_select_cols TEXT;
    v_hier_concat_expr TEXT;
    v_hier_validation_expr TEXT;
    v_hier_allornone_check TEXT;
    v_path_col_name TEXT;
BEGIN
    -- Clean up any lingering temp tables from a previous failed run in this session,
    -- using to_regclass to avoid noisy NOTICEs if the tables don't exist.
    IF to_regclass('pg_temp.temp_relevant_rows') IS NOT NULL THEN DROP TABLE temp_relevant_rows; END IF;
    IF to_regclass('pg_temp.temp_unpivoted_idents') IS NOT NULL THEN DROP TABLE temp_unpivoted_idents; END IF;
    IF to_regclass('pg_temp.temp_batch_analysis') IS NOT NULL THEN DROP TABLE temp_batch_analysis; END IF;
    IF to_regclass('pg_temp.temp_propagated_errors') IS NOT NULL THEN DROP TABLE temp_propagated_errors; END IF;
    IF to_regclass('pg_temp.temp_entity_signatures') IS NOT NULL THEN DROP TABLE temp_entity_signatures; END IF;
    IF to_regclass('pg_temp.temp_raw_unpivoted_idents') IS NOT NULL THEN DROP TABLE temp_raw_unpivoted_idents; END IF;
    IF to_regclass('pg_temp.temp_hierarchical_validation') IS NOT NULL THEN DROP TABLE temp_hierarchical_validation; END IF;

    -- This is a HOLISTIC procedure. It is called once and processes all relevant rows for this step.
    -- The p_batch_seq parameter is ignored (it will be NULL).
    RAISE DEBUG '[Job %] analyse_external_idents (Holistic): Starting analysis for batch_seq %.', p_job_id, p_batch_seq;

    -- FUNDAMENTAL ALGORITHM IMPROVEMENT: Set optimal settings for external_idents processing
    PERFORM admin.set_optimal_external_idents_settings();

    -- Get job details and snapshot
    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;
    v_strategy := (v_job.definition_snapshot->'import_definition'->>'strategy')::public.import_strategy;
    v_job_mode := (v_job.definition_snapshot->'import_definition'->>'mode')::public.import_mode;

    -- Find the target step details from the snapshot
    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = 'external_idents';
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] external_idents target not found in snapshot', p_job_id;
    END IF;

    -- Holistic execution: materialize actionable rows for this step to avoid giant in-memory arrays.
    CREATE TEMP TABLE temp_relevant_rows (data_row_id INTEGER PRIMARY KEY) ON COMMIT DROP;
    v_sql := format($$INSERT INTO temp_relevant_rows
                    SELECT row_id FROM public.%1$I
                    WHERE action IS DISTINCT FROM 'skip' AND last_completed_priority < %2$L$$,
                   v_data_table_name /* %1$I */, v_step.priority /* %2$L */);
    RAISE DEBUG '[Job %] analyse_external_idents: Materializing actionable rows with SQL: %', p_job_id, v_sql;
    EXECUTE v_sql;
    v_sql := 'SELECT COUNT(*) FROM temp_relevant_rows';
    RAISE DEBUG '[Job %] analyse_external_idents: Counting actionable rows with SQL: %', p_job_id, v_sql;
    EXECUTE v_sql INTO v_update_count;

    RAISE DEBUG '[Job %] analyse_external_idents: Holistic execution. Found % actionable rows to process for this step.',
        p_job_id, COALESCE(v_update_count, 0);

    IF COALESCE(v_update_count, 0) = 0 THEN
        RAISE DEBUG '[Job %] analyse_external_idents: No actionable rows to process.', p_job_id;
        -- Even if no rows are actionable, we MUST advance the priority for all rows pending this step to prevent an infinite loop.
        v_sql := format($$
            UPDATE public.%1$I dt SET
                last_completed_priority = %2$L
            WHERE dt.last_completed_priority < %2$L;
        $$, v_data_table_name, v_step.priority);
        RAISE DEBUG '[Job %] analyse_external_idents: Advancing priority for all pending rows to prevent loop. SQL: %', p_job_id, v_sql;
        EXECUTE v_sql;
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

    -- Filter data columns relevant to this step (both source_input and internal)
    SELECT jsonb_agg(value) INTO v_ident_data_cols
    FROM jsonb_array_elements(v_ident_data_cols) value
    WHERE (value->>'step_id')::int = v_step.id
      AND value->>'purpose' IN ('source_input', 'internal');

    IF v_ident_data_cols IS NULL OR jsonb_array_length(v_ident_data_cols) = 0 THEN
         RAISE DEBUG '[Job %] analyse_external_idents: No external ident data columns found in snapshot for step %. Skipping analysis.', p_job_id, v_step.id;
         v_sql := format($$UPDATE public.%1$I dt SET last_completed_priority = %2$L WHERE EXISTS (SELECT 1 FROM temp_relevant_rows tr WHERE tr.data_row_id = dt.row_id)$$,
                        v_data_table_name /* %1$I */, v_step.priority /* %2$L */);
         RAISE DEBUG '[Job %] analyse_external_idents: Updating last_completed_priority for skipped rows (no columns) with SQL: %', p_job_id, v_sql;
         EXECUTE v_sql;
         RETURN;
    END IF;

    -- Build the list of error keys to clear, including all source_input columns for this step and general keys
    SELECT array_agg(value->>'column_name') INTO v_error_keys_to_clear_arr
    FROM jsonb_array_elements(v_ident_data_cols) value
    WHERE value->>'column_name' IS NOT NULL AND value->>'purpose' = 'source_input';

    v_error_keys_to_clear_arr := COALESCE(v_error_keys_to_clear_arr, ARRAY[]::TEXT[]) || ARRAY[
        'missing_identifier_value',
        'unknown_identifier_type',
        'inconsistent_legal_unit',
        'inconsistent_establishment',
        'ambiguous_unit_type',
        'invalid_hierarchical_characters',
        'hierarchical_depth_mismatch',
        'missing_hierarchical_components',
        'hierarchical_incomplete'
    ];
    SELECT array_agg(DISTINCT e) INTO v_error_keys_to_clear_arr FROM unnest(v_error_keys_to_clear_arr) e;
    RAISE DEBUG '[Job %] analyse_external_idents: Error keys to clear for this step: %', p_job_id, v_error_keys_to_clear_arr;

    -- Step 1: Unpivot provided identifiers and lookup existing units
    CREATE TEMP TABLE temp_unpivoted_idents (
        data_row_id INTEGER,
        ident_type_code TEXT,
        source_ident_code TEXT, -- The code/column name from the _data table e.g. 'tax_ident' or 'admin_statistical_path'
        ident_value TEXT,       -- For regular idents: the text value. For hierarchical: the ltree path as text
        ident_type_id INT,      -- Resolved ID from external_ident_type, NULL if source_ident_code is unknown
        resolved_lu_id INT,
        resolved_est_id INT,
        is_cross_type_conflict BOOLEAN,
        conflicting_unit_jsonb JSONB,
        conflicting_est_is_formal BOOLEAN DEFAULT FALSE,
        is_hierarchical BOOLEAN DEFAULT FALSE  -- Flag to distinguish hierarchical from regular
    ) ON COMMIT DROP;

    -- Create a temp table for the raw, unpivoted identifiers first.
    CREATE TEMP TABLE temp_raw_unpivoted_idents (
        data_row_id INT,
        source_ident_code TEXT,
        ident_type_code TEXT,
        ident_value TEXT,
        is_hierarchical BOOLEAN DEFAULT FALSE
    ) ON COMMIT DROP;

    -- ============================================================================
    -- Step 1a: Process REGULAR identifiers (single column per type)
    -- ============================================================================
    v_unpivot_sql := '';
    v_add_separator := FALSE;

    -- For regular external_idents step, the import_data_column.column_name is the raw source column (e.g., tax_ident_raw).
    -- We only process columns that correspond to REGULAR external_ident_types
    FOR v_col_rec IN
        SELECT
            value->>'column_name' as raw_column_name,
            replace(value->>'column_name', '_raw', '') as ident_code
        FROM jsonb_array_elements(v_ident_data_cols) value
        WHERE value->>'purpose' = 'source_input'
          AND value->>'column_name' LIKE '%_raw'
          -- Only include if this corresponds to a REGULAR external_ident_type
          AND EXISTS (
              SELECT 1 FROM public.external_ident_type_active eit
              WHERE eit.code = replace(value->>'column_name', '_raw', '')
                AND eit.shape = 'regular'
          )
    LOOP
        IF v_col_rec.raw_column_name IS NULL THEN
             RAISE DEBUG '[Job %] analyse_external_idents: Skipping column as its name is null.', p_job_id;
             CONTINUE;
        END IF;

        IF v_add_separator THEN v_unpivot_sql := v_unpivot_sql || ' UNION ALL '; END IF;
        v_unpivot_sql := v_unpivot_sql || format(
             $$SELECT dt.row_id,
                     %1$L AS source_column_name_in_data_table,
                     %2$L AS ident_type_code_to_join_on,
                     NULLIF(dt.%3$I, '') AS ident_value,
                     FALSE AS is_hierarchical
             FROM public.%4$I dt
             JOIN temp_relevant_rows tr ON tr.data_row_id = dt.row_id
             WHERE NULLIF(dt.%5$I, '') IS NOT NULL$$,
             v_col_rec.raw_column_name, -- %1$L Name of column in _data table
             v_col_rec.ident_code,      -- %2$L Code to join with external_ident_type
             v_col_rec.raw_column_name, -- %3$I Column to select value from
             v_data_table_name,         -- %4$I
             v_col_rec.raw_column_name  -- %5$I
        );
        v_add_separator := TRUE;
    END LOOP;

    -- ============================================================================
    -- Step 1b: Process HIERARCHICAL identifiers (multiple component columns per type)
    -- ============================================================================

    -- Create temp table to track hierarchical validation errors per row
    CREATE TEMP TABLE temp_hierarchical_validation (
        data_row_id INTEGER,
        type_code TEXT,
        error_jsonb JSONB,
        combined_path TEXT,  -- The concatenated ltree path if valid
        PRIMARY KEY (data_row_id, type_code)
    ) ON COMMIT DROP;

    -- Process each hierarchical identifier type
    FOR v_hier_type IN
        SELECT eit.id, eit.code, eit.labels
        FROM public.external_ident_type_active eit
        WHERE eit.shape = 'hierarchical'
          AND eit.labels IS NOT NULL
        ORDER BY eit.priority
    LOOP
        v_labels_array := string_to_array(ltree2text(v_hier_type.labels), '.');
        v_path_col_name := v_hier_type.code || '_path';

        RAISE DEBUG '[Job %] analyse_external_idents: Processing hierarchical type "%" with labels: %',
            p_job_id, v_hier_type.code, v_labels_array;

        -- Build the validation and concatenation SQL for this hierarchical type
        -- We need to:
        -- 1. Check if ANY components are provided (to determine if we should validate)
        -- 2. Check ALL-OR-NOTHING: if some provided, all must be provided
        -- 3. Validate ltree characters for each component
        -- 4. Concatenate into path

        v_hier_select_cols := '';
        v_hier_concat_expr := '';
        v_hier_validation_expr := '';
        v_hier_allornone_check := '';
        v_label_index := 0;

        FOREACH v_label IN ARRAY v_labels_array
        LOOP
            -- Build column references
            IF v_label_index > 0 THEN
                v_hier_concat_expr := v_hier_concat_expr || ' || ''.'' || ';
                v_hier_allornone_check := v_hier_allornone_check || ' OR ';
            END IF;

            v_hier_concat_expr := v_hier_concat_expr || format('COALESCE(NULLIF(dt.%I, ''''), '''')',
                v_hier_type.code || '_' || v_label || '_raw');

            v_hier_allornone_check := v_hier_allornone_check || format('NULLIF(dt.%I, '''') IS NOT NULL',
                v_hier_type.code || '_' || v_label || '_raw');

            -- Build validation expression for this component
            IF v_label_index > 0 THEN
                v_hier_validation_expr := v_hier_validation_expr || ' || ';
            END IF;
            v_hier_validation_expr := v_hier_validation_expr || format($val$
                CASE
                    WHEN NULLIF(dt.%1$I, '') IS NOT NULL AND dt.%1$I !~ '^[A-Za-z0-9_]+$'
                    THEN jsonb_build_object(%2$L, 'Invalid characters in %3$s (allowed: A-Z, a-z, 0-9, _)')
                    ELSE '{}'::jsonb
                END
            $val$,
                v_hier_type.code || '_' || v_label || '_raw',  -- %1$I column name
                v_hier_type.code || '_' || v_label || '_raw',  -- %2$L error key
                v_label                                         -- %3$s label name for message
            );

            v_label_index := v_label_index + 1;
        END LOOP;

        -- Insert hierarchical validation results
        -- This handles:
        -- 1. All-or-nothing validation
        -- 2. Character validation for each component
        -- 3. Path concatenation
        v_sql := format($hier_val$
            INSERT INTO temp_hierarchical_validation (data_row_id, type_code, error_jsonb, combined_path)
            SELECT
                dt.row_id,
                %1$L AS type_code,
                -- Error aggregation
                CASE
                    -- All-or-nothing check: if some components present but not all
                    WHEN (%2$s) AND NOT (
                        -- Check ALL components are present
                        %3$s
                    ) THEN jsonb_build_object(%4$L, 'Hierarchical identifier requires all components: ' || %5$L)
                    -- Character validation errors
                    WHEN (%2$s) THEN (%6$s)
                    ELSE '{}'::jsonb
                END AS error_jsonb,
                -- Combined path (only if all components present and valid)
                CASE
                    WHEN (%3$s) THEN %7$s
                    ELSE NULL
                END AS combined_path
            FROM public.%8$I dt
            JOIN temp_relevant_rows tr ON tr.data_row_id = dt.row_id
            WHERE (%2$s)  -- At least one component is provided
        $hier_val$,
            v_hier_type.code,              -- %1$L type code
            v_hier_allornone_check,        -- %2$s any component present check
            replace(v_hier_allornone_check, ' OR ', ' AND '),  -- %3$s all components present check
            v_hier_type.code || '_' || v_labels_array[1] || '_raw',  -- %4$L first column for error key
            array_to_string(v_labels_array, ', '),  -- %5$L labels list for error message
            v_hier_validation_expr,        -- %6$s character validation
            v_hier_concat_expr,            -- %7$s path concatenation
            v_data_table_name              -- %8$I data table name
        );

        RAISE DEBUG '[Job %] analyse_external_idents: Hierarchical validation SQL for type "%": %', p_job_id, v_hier_type.code, v_sql;
        EXECUTE v_sql;

        -- Add to unpivot SQL for hierarchical types (using the combined path)
        IF v_add_separator THEN v_unpivot_sql := v_unpivot_sql || ' UNION ALL '; END IF;
        v_unpivot_sql := v_unpivot_sql || format(
            $$SELECT
                thv.data_row_id AS row_id,
                %1$L AS source_column_name_in_data_table,
                %2$L AS ident_type_code_to_join_on,
                thv.combined_path AS ident_value,
                TRUE AS is_hierarchical
            FROM temp_hierarchical_validation thv
            WHERE thv.type_code = %2$L
              AND thv.combined_path IS NOT NULL
              AND (thv.error_jsonb IS NULL OR thv.error_jsonb = '{}'::jsonb)$$,
            v_path_col_name,    -- %1$L source column name (the path column)
            v_hier_type.code    -- %2$L type code
        );
        v_add_separator := TRUE;

        -- Update the _data table with the computed path for valid hierarchical identifiers
        v_sql := format($path_update$
            UPDATE public.%1$I dt SET
                %2$I = thv.combined_path::ltree
            FROM temp_hierarchical_validation thv
            WHERE dt.row_id = thv.data_row_id
              AND thv.type_code = %3$L
              AND thv.combined_path IS NOT NULL
              AND (thv.error_jsonb IS NULL OR thv.error_jsonb = '{}'::jsonb)
        $path_update$,
            v_data_table_name,  -- %1$I
            v_path_col_name,    -- %2$I
            v_hier_type.code    -- %3$L
        );
        RAISE DEBUG '[Job %] analyse_external_idents: Updating path column for type "%": %', p_job_id, v_hier_type.code, v_sql;
        EXECUTE v_sql;
    END LOOP;

    IF v_unpivot_sql = '' THEN
        RAISE DEBUG '[Job %] analyse_external_idents: No external ident values found in batch. Skipping further analysis.', p_job_id;
        v_sql := format($$
            UPDATE public.%1$I dt SET
                state = %2$L,
                errors = jsonb_build_object('external_idents', 'No identifier provided or mapped correctly for external_idents step'),
                operation = 'insert'::public.import_row_operation_type,
                action = %3$L,
                last_completed_priority = %4$L
            WHERE EXISTS (SELECT 1 FROM temp_relevant_rows tr WHERE tr.data_row_id = dt.row_id);
        $$, v_data_table_name, 'error', 'skip'::public.import_row_action_type, v_step.priority);
        RAISE DEBUG '[Job %] analyse_external_idents: Marking rows as error (no identifiers) with SQL: %', p_job_id, v_sql;
        EXECUTE v_sql;
        GET DIAGNOSTICS v_error_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_external_idents (Batch): Finished analysis for batch. Errors: % (all rows missing identifiers)', p_job_id, v_error_count;
        RETURN;
    END IF;

    -- Populate raw unpivoted idents
    v_sql := format('INSERT INTO temp_raw_unpivoted_idents (data_row_id, source_ident_code, ident_type_code, ident_value, is_hierarchical) %s', v_unpivot_sql);
    RAISE DEBUG '[Job %] analyse_external_idents: Populating temp_raw_unpivoted_idents with SQL: %', p_job_id, v_sql;
    EXECUTE v_sql;

    -- Now, perform the lookup on only the unique identifiers from the batch.
    -- For regular identifiers: lookup by ident field
    -- For hierarchical identifiers: lookup by idents field (ltree)
    v_sql := format($$
        WITH distinct_idents AS (
            SELECT DISTINCT ident_type_code, ident_value, is_hierarchical
            FROM temp_raw_unpivoted_idents
        ),
        -- Pre-validate hierarchical ident values before attempting ltree cast
        distinct_idents_with_ltree AS (
            SELECT
                di.*,
                -- Only generate ltree value if it's hierarchical AND valid format
                CASE
                    WHEN di.is_hierarchical
                         AND NULLIF(di.ident_value, '') IS NOT NULL
                         AND di.ident_value ~ '^[A-Za-z0-9_]+(\.[A-Za-z0-9_]+)*$'
                    THEN di.ident_value::ltree
                    ELSE NULL
                END AS ident_value_ltree
            FROM distinct_idents di
        ),
        resolved_distinct_idents AS (
            SELECT
                di.ident_type_code,
                di.ident_value,
                di.is_hierarchical,
                xit.id AS ident_type_id,
                -- For regular: lookup by ident. For hierarchical: lookup by idents
                CASE
                    WHEN di.is_hierarchical THEN xi_hier.legal_unit_id
                    ELSE xi_reg.legal_unit_id
                END AS resolved_lu_id,
                CASE
                    WHEN di.is_hierarchical THEN xi_hier.establishment_id
                    ELSE xi_reg.establishment_id
                END AS resolved_est_id,
                CASE
                    WHEN di.is_hierarchical THEN (conflicting_est_hier.legal_unit_id IS NOT NULL)
                    ELSE (conflicting_est_reg.legal_unit_id IS NOT NULL)
                END AS conflicting_est_is_formal
            FROM distinct_idents_with_ltree di
            LEFT JOIN public.external_ident_type_active xit ON xit.code = di.ident_type_code
            -- Regular identifier lookup
            LEFT JOIN public.external_ident xi_reg
                ON NOT di.is_hierarchical
                AND xi_reg.type_id = xit.id
                AND xi_reg.ident = di.ident_value
            LEFT JOIN public.establishment conflicting_est_reg
                ON conflicting_est_reg.id = xi_reg.establishment_id
            -- Hierarchical identifier lookup (using pre-validated ltree)
            LEFT JOIN public.external_ident xi_hier
                ON di.is_hierarchical
                AND xi_hier.type_id = xit.id
                AND di.ident_value_ltree IS NOT NULL
                AND xi_hier.idents = di.ident_value_ltree
            LEFT JOIN public.establishment conflicting_est_hier
                ON conflicting_est_hier.id = xi_hier.establishment_id
        )
        INSERT INTO temp_unpivoted_idents (data_row_id, ident_type_code, source_ident_code, ident_value, ident_type_id, resolved_lu_id, resolved_est_id, is_cross_type_conflict, conflicting_unit_jsonb, conflicting_est_is_formal, is_hierarchical)
        SELECT
            up.data_row_id,
            up.ident_type_code,
            up.source_ident_code,
            up.ident_value,
            rdi.ident_type_id,
            rdi.resolved_lu_id,
            rdi.resolved_est_id,
            CASE %1$L -- v_job_mode
                WHEN 'legal_unit' THEN (rdi.resolved_est_id IS NOT NULL)
                WHEN 'establishment_formal' THEN (rdi.resolved_lu_id IS NOT NULL OR (rdi.resolved_est_id IS NOT NULL AND NOT rdi.conflicting_est_is_formal))
                WHEN 'establishment_informal' THEN (rdi.resolved_lu_id IS NOT NULL OR (rdi.resolved_est_id IS NOT NULL AND rdi.conflicting_est_is_formal))
                ELSE FALSE
            END AS is_cross_type_conflict,
            CASE %1$L -- v_job_mode
                WHEN 'legal_unit' THEN
                    CASE WHEN rdi.resolved_est_id IS NOT NULL THEN jsonb_build_object(up.source_ident_code, up.ident_value) ELSE NULL END
                WHEN 'establishment_formal' THEN
                    CASE
                        WHEN rdi.resolved_lu_id IS NOT NULL THEN jsonb_build_object(up.source_ident_code, up.ident_value)
                        WHEN rdi.resolved_est_id IS NOT NULL AND NOT rdi.conflicting_est_is_formal THEN jsonb_build_object(up.source_ident_code, up.ident_value)
                        ELSE NULL
                    END
                WHEN 'establishment_informal' THEN
                    CASE
                        WHEN rdi.resolved_lu_id IS NOT NULL THEN jsonb_build_object(up.source_ident_code, up.ident_value)
                        WHEN rdi.resolved_est_id IS NOT NULL AND rdi.conflicting_est_is_formal THEN jsonb_build_object(up.source_ident_code, up.ident_value)
                        ELSE NULL
                    END
                ELSE NULL
            END AS conflicting_unit_jsonb,
            COALESCE(rdi.conflicting_est_is_formal, FALSE),
            up.is_hierarchical
        FROM temp_raw_unpivoted_idents up
        LEFT JOIN resolved_distinct_idents rdi
            ON up.ident_type_code = rdi.ident_type_code
            AND up.ident_value = rdi.ident_value
            AND up.is_hierarchical = rdi.is_hierarchical;
    $$, v_job_mode);
    RAISE DEBUG '[Job %] analyse_external_idents: Populating temp_unpivoted_idents with resolved data: %', p_job_id, v_sql;
    EXECUTE v_sql;

    -- FUNDAMENTAL ALGORITHM IMPROVEMENT: Index the temp table for optimal performance
    PERFORM admin.index_temp_unpivoted_idents('temp_unpivoted_idents');

    DROP TABLE temp_raw_unpivoted_idents;

    -- Step 1c: Compute Entity Signatures (EARLY)
    -- We need entity signatures early to distinguish between "duplicate rows" (error)
    -- and "multiple rows for same entity" (temporal data/valid).
    CREATE TEMP TABLE temp_entity_signatures (
        data_row_id INTEGER PRIMARY KEY,
        entity_signature JSONB
    ) ON COMMIT DROP;

    v_sql := $$
        INSERT INTO temp_entity_signatures (data_row_id, entity_signature)
        SELECT
            tr.data_row_id,
            COALESCE(
                jsonb_object_agg(tui.ident_type_code, tui.ident_value)
                FILTER (WHERE tui.ident_value IS NOT NULL),
                '{}'::jsonb
            ) as entity_signature
        FROM temp_relevant_rows tr
        LEFT JOIN temp_unpivoted_idents tui ON tui.data_row_id = tr.data_row_id
        WHERE tui.ident_type_id IS NOT NULL
        GROUP BY tr.data_row_id;
    $$;
    RAISE DEBUG '[Job %] analyse_external_idents: Computing entity signatures with SQL: %', p_job_id, v_sql;
    EXECUTE v_sql;

    -- Step 1d: Detect duplicate identifiers across multiple rows
    IF to_regclass('pg_temp.temp_duplicate_idents') IS NOT NULL THEN
        DROP TABLE temp_duplicate_idents;
    END IF;
    CREATE TEMP TABLE temp_duplicate_idents (
        data_row_id INTEGER,
        source_ident_code TEXT,
        ident_type_code TEXT,
        ident_value TEXT,
        affected_row_ids INTEGER[],
        row_count INTEGER,
        PRIMARY KEY (data_row_id, source_ident_code)
    ) ON COMMIT DROP;

    -- Check for duplicate identifiers across multiple rows.
    -- All identifier types (regular and hierarchical) are checked for duplicates.
    v_sql := $$
        WITH DuplicateGroups AS (
            SELECT
                tui.ident_type_code,
                tui.ident_value,
                array_agg(DISTINCT tui.data_row_id ORDER BY tui.data_row_id) AS affected_row_ids,
                COUNT(DISTINCT tui.data_row_id) AS row_count,
                COUNT(DISTINCT COALESCE(tui.resolved_lu_id, 0)) AS distinct_lu_count,
                COUNT(DISTINCT COALESCE(tui.resolved_est_id, 0)) AS distinct_est_count,
                COUNT(DISTINCT tes.entity_signature) FILTER (WHERE tui.resolved_lu_id IS NULL AND tui.resolved_est_id IS NULL) AS distinct_new_entity_signatures
            FROM temp_unpivoted_idents tui
            JOIN public.external_ident_type_active xit ON xit.id = tui.ident_type_id
            LEFT JOIN temp_entity_signatures tes ON tes.data_row_id = tui.data_row_id
            WHERE tui.ident_type_id IS NOT NULL
              AND tui.ident_value IS NOT NULL
              AND tui.is_cross_type_conflict IS FALSE
            GROUP BY tui.ident_type_code, tui.ident_value
            HAVING COUNT(DISTINCT tui.data_row_id) > 1
               AND (
                   COUNT(DISTINCT tui.resolved_lu_id) FILTER (WHERE tui.resolved_lu_id IS NOT NULL) > 1
                   OR
                   COUNT(DISTINCT tui.resolved_est_id) FILTER (WHERE tui.resolved_est_id IS NOT NULL) > 1
                   OR
                   (COUNT(*) FILTER (WHERE tui.resolved_lu_id IS NULL AND tui.resolved_est_id IS NULL) > 0
                    AND COUNT(*) FILTER (WHERE tui.resolved_lu_id IS NOT NULL OR tui.resolved_est_id IS NOT NULL) > 0)
                   OR
                   (COUNT(DISTINCT tes.entity_signature) FILTER (WHERE tui.resolved_lu_id IS NULL AND tui.resolved_est_id IS NULL) > 1)
               )
        )
        INSERT INTO temp_duplicate_idents (data_row_id, source_ident_code, ident_type_code, ident_value, affected_row_ids, row_count)
        SELECT
            tui.data_row_id,
            tui.source_ident_code,
            dg.ident_type_code,
            dg.ident_value,
            dg.affected_row_ids,
            dg.row_count
        FROM DuplicateGroups dg
        JOIN temp_unpivoted_idents tui
            ON tui.ident_type_code = dg.ident_type_code
            AND tui.ident_value = dg.ident_value
            AND tui.data_row_id = ANY(dg.affected_row_ids);
    $$;
    RAISE DEBUG '[Job %] analyse_external_idents: Detecting duplicate identifiers with SQL: %', p_job_id, v_sql;
    EXECUTE v_sql;

    -- Debug: Log detected duplicates
    DECLARE
        dup_rec RECORD;
        dup_count INT;
    BEGIN
        v_sql := 'SELECT COUNT(DISTINCT (ident_type_code, ident_value)) FROM temp_duplicate_idents';
        EXECUTE v_sql INTO dup_count;
        RAISE DEBUG '[Job %] analyse_external_idents: Found % duplicate identifier group(s)', p_job_id, COALESCE(dup_count, 0);

        IF dup_count > 0 THEN
            FOR dup_rec IN
                SELECT DISTINCT ON (ident_type_code, ident_value)
                    ident_type_code, ident_value, affected_row_ids, row_count
                FROM temp_duplicate_idents
                ORDER BY ident_type_code, ident_value
                LIMIT 10
            LOOP
                RAISE DEBUG '[Job %]   DUPLICATE: type=%, value=%, rows=%, count=%',
                    p_job_id, dup_rec.ident_type_code, dup_rec.ident_value,
                    dup_rec.affected_row_ids, dup_rec.row_count;
            END LOOP;
        END IF;
    END;

    -- Debug: Log contents of temp_unpivoted_idents (sample from relevant rows)
    DECLARE
        tui_rec RECORD;
    BEGIN
        RAISE DEBUG '[Job %] analyse_external_idents: Contents of temp_unpivoted_idents (sample):', p_job_id;
        FOR tui_rec IN
            SELECT tui.*
            FROM temp_unpivoted_idents AS tui
            JOIN temp_relevant_rows AS tr ON tr.data_row_id = tui.data_row_id
            ORDER BY tui.data_row_id, tui.source_ident_code
            LIMIT 50
        LOOP
            RAISE DEBUG '[Job %]   TUI: data_row_id=%, source_ident_code=%, ident_value=%, ident_type_id=%, resolved_lu_id=%, resolved_est_id=%, is_hierarchical=%',
                        p_job_id, tui_rec.data_row_id, tui_rec.source_ident_code, tui_rec.ident_value, tui_rec.ident_type_id, tui_rec.resolved_lu_id, tui_rec.resolved_est_id, tui_rec.is_hierarchical;
        END LOOP;
    END;

    -- Step 2: Identify and Aggregate Errors, Determine Operation and Action
    -- PERFORMANCE: Use explicit temp tables instead of nested CTEs to prevent
    -- PostgreSQL query planner from re-evaluating complex expressions.
    -- Each temp table is created with silent removal pattern for transaction inspection.

    -- Step 2a: Create temp_aggregated_idents - aggregates identifier data per row
    IF to_regclass('pg_temp.temp_aggregated_idents') IS NOT NULL THEN DROP TABLE temp_aggregated_idents; END IF;
    v_sql := format($$
        CREATE TEMP TABLE temp_aggregated_idents ON COMMIT DROP AS
        SELECT
            tui.data_row_id,
            COUNT(tui.ident_value) FILTER (WHERE tui.ident_value IS NOT NULL) AS num_raw_idents_with_value,
            COUNT(tui.ident_type_id) FILTER (WHERE tui.ident_value IS NOT NULL AND tui.ident_type_id IS NOT NULL) AS num_valid_type_idents_with_value,
            array_agg(DISTINCT tui.source_ident_code) FILTER (WHERE tui.ident_value IS NOT NULL AND tui.ident_type_id IS NULL) as unknown_ident_codes,
            array_to_string(array_agg(DISTINCT tui.source_ident_code) FILTER (WHERE tui.ident_value IS NOT NULL AND tui.ident_type_id IS NULL), ', ') as unknown_ident_codes_text,
            array_agg(DISTINCT tui.source_ident_code) FILTER (WHERE tui.ident_value IS NOT NULL) as all_input_ident_codes_with_value,
            COUNT(DISTINCT tui.resolved_lu_id) FILTER (WHERE tui.resolved_lu_id IS NOT NULL AND tui.ident_type_id IS NOT NULL) AS distinct_lu_ids,
            COUNT(DISTINCT tui.resolved_est_id) FILTER (WHERE tui.resolved_est_id IS NOT NULL AND tui.ident_type_id IS NOT NULL) AS distinct_est_ids,
            MAX(tui.resolved_lu_id) FILTER (WHERE tui.resolved_lu_id IS NOT NULL AND tui.ident_type_id IS NOT NULL) AS final_lu_id,
            MAX(tui.resolved_est_id) FILTER (WHERE tui.resolved_est_id IS NOT NULL AND tui.ident_type_id IS NOT NULL) AS final_est_id,
            jsonb_object_agg(tui.ident_type_code, tui.ident_value) FILTER (WHERE tui.ident_type_id IS NOT NULL AND tui.ident_value IS NOT NULL) AS entity_signature,
            -- Pre-compute hash for fast COUNT(DISTINCT) comparisons
            md5(COALESCE(jsonb_object_agg(tui.ident_type_code, tui.ident_value ORDER BY tui.ident_type_code) FILTER (WHERE tui.ident_type_id IS NOT NULL AND tui.ident_value IS NOT NULL), '{}')::text) AS entity_signature_hash,
            -- Aggregate cross-type conflicts: key is source_ident_code, value is conflict message
            jsonb_object_agg(
                tui.source_ident_code,
                'Identifier already used by a ' ||
                CASE
                    WHEN %2$L = 'legal_unit' AND tui.resolved_est_id IS NOT NULL THEN 'Establishment'
                    WHEN %2$L = 'establishment_formal' THEN
                        CASE
                            WHEN tui.resolved_lu_id IS NOT NULL THEN 'Legal Unit'
                            WHEN tui.resolved_est_id IS NOT NULL AND NOT tui.conflicting_est_is_formal THEN 'Informal Establishment'
                            ELSE 'other conflicting unit for formal est'
                        END
                    WHEN %2$L = 'establishment_informal' THEN
                        CASE
                            WHEN tui.resolved_lu_id IS NOT NULL THEN 'Legal Unit'
                            WHEN tui.resolved_est_id IS NOT NULL AND tui.conflicting_est_is_formal THEN 'Formal Establishment'
                            ELSE 'other conflicting unit for informal est'
                        END
                    ELSE 'different unit type'
                END || ': ' || tui.conflicting_unit_jsonb::TEXT
            ) FILTER (WHERE tui.is_cross_type_conflict IS TRUE) AS cross_type_conflict_errors
        FROM temp_unpivoted_idents tui
        GROUP BY tui.data_row_id
    $$, v_data_table_name, v_job_mode);
    RAISE DEBUG '[Job %] analyse_external_idents: Creating temp_aggregated_idents: %', p_job_id, v_sql;
    EXECUTE v_sql;

    -- Step 2b: Create temp_ordered_batch_entities - joins with data table and computes window functions
    IF to_regclass('pg_temp.temp_ordered_batch_entities') IS NOT NULL THEN DROP TABLE temp_ordered_batch_entities; END IF;
    v_sql := format($$
        CREATE TEMP TABLE temp_ordered_batch_entities ON COMMIT DROP AS
        WITH HierarchicalErrors AS (
            -- Aggregate hierarchical validation errors per row
            SELECT
                data_row_id,
                COALESCE(
                    jsonb_object_agg(k, v) FILTER (WHERE error_jsonb IS NOT NULL AND error_jsonb != '{}'::jsonb),
                    '{}'::jsonb
                ) AS hier_errors
            FROM temp_hierarchical_validation
            CROSS JOIN LATERAL jsonb_each_text(COALESCE(error_jsonb, '{}'::jsonb)) AS e(k, v)
            GROUP BY data_row_id
        ),
        RowChecks AS (
            SELECT
                orig.data_row_id,
                dt.valid_from,
                COALESCE(ai.num_raw_idents_with_value, 0) AS num_raw_idents_with_value,
                COALESCE(ai.num_valid_type_idents_with_value, 0) AS num_valid_type_idents_with_value,
                ai.unknown_ident_codes,
                ai.unknown_ident_codes_text,
                ai.all_input_ident_codes_with_value,
                COALESCE(ai.distinct_lu_ids, 0) AS distinct_lu_ids,
                COALESCE(ai.distinct_est_ids, 0) AS distinct_est_ids,
                ai.final_lu_id,
                ai.final_est_id,
                COALESCE(ai.entity_signature, '{}'::jsonb) AS entity_signature,
                ai.entity_signature_hash,
                ai.cross_type_conflict_errors,
                COALESCE(he.hier_errors, '{}'::jsonb) AS hier_errors,
                (SELECT array_agg(value->>'column_name') FROM jsonb_array_elements(%2$L) value WHERE value->>'purpose' = 'source_input') as all_source_input_ident_codes_for_step
            FROM temp_relevant_rows orig
            JOIN public.%1$I dt ON orig.data_row_id = dt.row_id
            LEFT JOIN temp_aggregated_idents ai ON orig.data_row_id = ai.data_row_id
            LEFT JOIN HierarchicalErrors he ON orig.data_row_id = he.data_row_id
        )
        SELECT
            rc.*,
            ROW_NUMBER() OVER (PARTITION BY rc.entity_signature ORDER BY rc.valid_from NULLS LAST, rc.data_row_id) as rn_in_batch_for_entity,
            FIRST_VALUE(rc.data_row_id) OVER (PARTITION BY rc.entity_signature ORDER BY rc.valid_from NULLS LAST, rc.data_row_id) as actual_founding_row_id
        FROM RowChecks rc
    $$, v_data_table_name, v_ident_data_cols);
    RAISE DEBUG '[Job %] analyse_external_idents: Creating temp_ordered_batch_entities: %', p_job_id, v_sql;
    EXECUTE v_sql;

    -- Create indexes for efficient joins
    CREATE INDEX ON temp_ordered_batch_entities (data_row_id);
    CREATE INDEX ON temp_ordered_batch_entities (entity_signature_hash);
    CREATE INDEX ON temp_ordered_batch_entities (final_lu_id, final_est_id);

    -- Step 2c: Create temp_new_entity_duplicates - detects duplicate identifiers across different NEW entities
    IF to_regclass('pg_temp.temp_new_entity_duplicates') IS NOT NULL THEN DROP TABLE temp_new_entity_duplicates; END IF;
    CREATE TEMP TABLE temp_new_entity_duplicates (
        data_row_id INTEGER,
        source_ident_code TEXT,
        ident_type_code TEXT,
        ident_value TEXT,
        affected_row_ids INTEGER[],
        row_count INTEGER,
        PRIMARY KEY (data_row_id, source_ident_code)
    ) ON COMMIT DROP;

    v_sql := $$
        WITH NewEntityDuplicateGroups AS (
            SELECT
                tui.ident_type_code,
                tui.ident_value,
                array_agg(DISTINCT obe.data_row_id ORDER BY obe.data_row_id) AS affected_row_ids,
                COUNT(DISTINCT obe.entity_signature_hash) AS distinct_entity_count
            FROM temp_unpivoted_idents tui
            JOIN temp_ordered_batch_entities obe ON obe.data_row_id = tui.data_row_id
            WHERE tui.ident_type_id IS NOT NULL
              AND tui.ident_value IS NOT NULL
              AND tui.resolved_lu_id IS NULL
              AND tui.resolved_est_id IS NULL
              AND obe.final_lu_id IS NULL
              AND obe.final_est_id IS NULL
            GROUP BY tui.ident_type_code, tui.ident_value
            HAVING COUNT(DISTINCT obe.entity_signature_hash) > 1
        )
        INSERT INTO temp_new_entity_duplicates (data_row_id, source_ident_code, ident_type_code, ident_value, affected_row_ids, row_count)
        SELECT
            tui.data_row_id,
            tui.source_ident_code,
            nedg.ident_type_code,
            nedg.ident_value,
            nedg.affected_row_ids,
            array_length(nedg.affected_row_ids, 1) AS row_count
        FROM NewEntityDuplicateGroups nedg
        JOIN temp_unpivoted_idents tui
            ON tui.ident_type_code = nedg.ident_type_code
            AND tui.ident_value = nedg.ident_value
            AND tui.data_row_id = ANY(nedg.affected_row_ids)
    $$;
    RAISE DEBUG '[Job %] analyse_external_idents: Creating temp_new_entity_duplicates: %', p_job_id, v_sql;
    EXECUTE v_sql;

    -- Step 2d: Create temp_batch_analysis - final analysis results
    IF to_regclass('pg_temp.temp_batch_analysis') IS NOT NULL THEN DROP TABLE temp_batch_analysis; END IF;
    CREATE TEMP TABLE temp_batch_analysis (
        data_row_id INTEGER PRIMARY KEY,
        error_jsonb JSONB,
        resolved_lu_id INT,
        resolved_est_id INT,
        operation public.import_row_operation_type,
        action public.import_row_action_type,
        derived_founding_row_id INTEGER
    ) ON COMMIT DROP;

    -- Step 2e: Create temp_propagated_errors with simplified CTE chain (heavy lifting done in temp tables above)
    IF to_regclass('pg_temp.temp_propagated_errors') IS NOT NULL THEN DROP TABLE temp_propagated_errors; END IF;
    v_sql := format($$
        CREATE TEMP TABLE temp_propagated_errors ON COMMIT DROP AS
        -- PERFORMANCE: Most CTEs have been moved to temp tables (Steps 2a-2c) to prevent
        -- PostgreSQL query planner from re-evaluating complex expressions.
        -- Only ExistingIdents remains as a CTE since it references temp_ordered_batch_entities.
        WITH ExistingIdents AS (
            SELECT
                de.final_lu_id,
                de.final_est_id,
                jsonb_object_agg(xit.code, COALESCE(ei.ident, ei.idents::text)) as idents
            FROM (
                SELECT DISTINCT final_lu_id, final_est_id
                FROM temp_ordered_batch_entities
                WHERE final_lu_id IS NOT NULL OR final_est_id IS NOT NULL
            ) de
            JOIN public.external_ident ei ON (ei.legal_unit_id = de.final_lu_id OR ei.establishment_id = de.final_est_id)
            JOIN public.external_ident_type_active xit ON ei.type_id = xit.id
            GROUP BY de.final_lu_id, de.final_est_id
        ),
        AnalysisWithOperation AS (
            SELECT
                obe.data_row_id,
                COALESCE(obe.final_lu_id + 1000000000, obe.final_est_id + 2000000000, obe.actual_founding_row_id) as actual_founding_row_id,
                obe.final_lu_id,
                obe.final_est_id,
                obe.entity_signature,
                obe.rn_in_batch_for_entity,
                (
                     SELECT jsonb_object_agg(
                        input_data.ident_code || '_raw',
                        'Input ' || obe.entity_signature::text ||
                        ' matches existing unit ' || existing.idents::text ||
                        ' but attempts to change ' || input_data.ident_code ||
                        ' from ''' || (existing.idents->>input_data.ident_code) ||
                        ''' to ''' || input_data.input_value || ''''
                    )
                    FROM (SELECT key AS ident_code, value#>>'{}' AS input_value FROM jsonb_each(obe.entity_signature)) AS input_data
                    WHERE existing.idents ? input_data.ident_code
                      AND (existing.idents->>input_data.ident_code) IS DISTINCT FROM input_data.input_value
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
                    COALESCE(obe.cross_type_conflict_errors, '{}'::jsonb) ||
                    COALESCE(obe.hier_errors, '{}'::jsonb) ||
                    COALESCE(
                        (SELECT jsonb_object_agg(
                            tdi.source_ident_code,
                            'Duplicate identifier: ' || tdi.ident_type_code || '=' || tdi.ident_value ||
                            ' appears in ' || tdi.row_count || ' rows: ' || array_to_string(tdi.affected_row_ids, ', ')
                         )
                         FROM temp_duplicate_idents tdi
                         WHERE tdi.data_row_id = obe.data_row_id),
                        '{}'::jsonb
                    ) ||
                    COALESCE(
                        (SELECT jsonb_object_agg(
                            ned.source_ident_code,
                            'Duplicate identifier: ' || ned.ident_type_code || '=' || ned.ident_value ||
                            ' appears in ' || ned.row_count || ' rows: ' || array_to_string(ned.affected_row_ids, ', ')
                         )
                         FROM temp_new_entity_duplicates ned
                         WHERE ned.data_row_id = obe.data_row_id),
                        '{}'::jsonb
                    )
                ) as base_error_jsonb
            FROM temp_ordered_batch_entities obe
            LEFT JOIN (SELECT DISTINCT id FROM public.legal_unit) lu ON lu.id = obe.final_lu_id
            LEFT JOIN (SELECT DISTINCT id FROM public.establishment) est ON est.id = obe.final_est_id
            -- PERFORMANCE FIX: Changed from IS NOT DISTINCT FROM to COALESCE for hash join optimization.
            -- The original IS NOT DISTINCT FROM forced nested loop joins, creating 620B row cartesian product.
            -- Using COALESCE(-1) as sentinel allows hash joins while correctly handling NULL equality.
            -- Result: ~0.7 seconds vs 37+ minutes.
            LEFT JOIN ExistingIdents existing ON COALESCE(existing.final_lu_id, -1) = COALESCE(obe.final_lu_id, -1)
                                             AND COALESCE(existing.final_est_id, -1) = COALESCE(obe.final_est_id, -1)
        ),
        -- This CTE determines the operation based on whether the entity exists in the DB and its order within the batch.
        -- Also pre-computes final_error_jsonb and row_has_error to avoid re-evaluating JSONB expressions
        -- in the window functions of PropagatedErrors CTE.
        OperationDetermination AS (
            SELECT
                awo.*,
                CASE
                    WHEN awo.final_lu_id IS NULL AND awo.final_est_id IS NULL THEN
                        CASE
                            WHEN awo.rn_in_batch_for_entity = 1 THEN 'insert'::public.import_row_operation_type
                            ELSE
                                CASE
                                    WHEN %2$L::public.import_strategy IN ('insert_or_update', 'update_only') THEN 'update'::public.import_row_operation_type
                                    ELSE 'replace'::public.import_row_operation_type
                                END
                        END
                    ELSE
                        CASE
                            WHEN %2$L::public.import_strategy IN ('insert_or_update', 'update_only') THEN 'update'::public.import_row_operation_type
                            ELSE 'replace'::public.import_row_operation_type
                        END
                END as operation,
                -- Pre-compute final_error_jsonb: simple concatenation since keys are mutually exclusive
                (COALESCE(awo.base_error_jsonb, '{}'::jsonb) || COALESCE(awo.unstable_identifier_errors_jsonb, '{}'::jsonb)) as final_error_jsonb,
                -- Pre-compute row_has_error boolean to avoid re-evaluating JSONB expression in window functions
                ((COALESCE(awo.base_error_jsonb, '{}'::jsonb) || COALESCE(awo.unstable_identifier_errors_jsonb, '{}'::jsonb)) != '{}'::jsonb) as row_has_error
            FROM AnalysisWithOperation awo
        ),
        PropagatedErrors AS (
            SELECT
                od.*,
                -- final_error_jsonb and row_has_error are pre-computed in OperationDetermination
                -- Check if any row within the same new entity has an error (uses pre-computed boolean).
                BOOL_OR(od.row_has_error)
                    OVER (PARTITION BY CASE WHEN od.final_lu_id IS NULL AND od.final_est_id IS NULL THEN od.entity_signature ELSE jsonb_build_object('data_row_id', od.data_row_id) END) as entity_has_error,
                -- Collect row_ids of rows with errors within the same new entity (uses pre-computed boolean).
                array_remove(array_agg(CASE WHEN od.row_has_error THEN od.data_row_id ELSE NULL END)
                    OVER (PARTITION BY CASE WHEN od.final_lu_id IS NULL AND od.final_est_id IS NULL THEN od.entity_signature ELSE jsonb_build_object('data_row_id', od.data_row_id) END), NULL) as entity_error_source_row_ids
            FROM OperationDetermination od
        )
        SELECT
            pe.data_row_id,
            CASE
                WHEN pe.entity_has_error AND pe.final_lu_id IS NULL AND pe.final_est_id IS NULL THEN
                    CASE
                        WHEN pe.final_error_jsonb != '{}'::jsonb THEN pe.final_error_jsonb
                        ELSE jsonb_build_object(
                                 COALESCE((SELECT value->>'column_name' FROM jsonb_array_elements(%4$L) value WHERE value->>'purpose' = 'source_input' LIMIT 1), 'propagated_error'),
                                 'An error on a related new entity row caused this row to be skipped. Source error row(s): ' || array_to_string(pe.entity_error_source_row_ids, ', ')
                             )
                    END
                ELSE pe.final_error_jsonb
            END as error_jsonb,
            pe.final_lu_id AS resolved_lu_id,
            pe.final_est_id AS resolved_est_id,
            pe.operation,
            CASE
                WHEN pe.entity_has_error THEN 'skip'::public.import_row_action_type
                WHEN %2$L::public.import_strategy = 'insert_only' AND pe.operation != 'insert'::public.import_row_operation_type THEN 'skip'::public.import_row_action_type
                WHEN %2$L::public.import_strategy = 'replace_only' AND pe.operation != 'replace'::public.import_row_operation_type THEN 'skip'::public.import_row_action_type
                WHEN %2$L::public.import_strategy = 'update_only' AND pe.operation != 'update'::public.import_row_operation_type THEN 'skip'::public.import_row_action_type
                ELSE 'use'::public.import_row_action_type
            END as action,
            pe.actual_founding_row_id AS derived_founding_row_id
        FROM PropagatedErrors pe;
    $$,
        v_data_table_name,              /* %1$I */
        v_strategy,                     /* %2$L */
        v_job_mode,                     /* %3$L */
        v_ident_data_cols               /* %4$L */
    );
    RAISE DEBUG '[Job %] analyse_external_idents: Materializing PropagatedErrors CTE: %', p_job_id, v_sql;
    EXECUTE v_sql;

    INSERT INTO temp_batch_analysis (data_row_id, error_jsonb, resolved_lu_id, resolved_est_id, operation, action, derived_founding_row_id)
    SELECT * FROM temp_propagated_errors;


    -- Step 3: Single-pass Batch Update for All Rows with dynamically constructed SET clause
    -- FIX: Set state='error' when action='skip' to maintain consistency with CHECK constraint.
    -- Previously, state was only set to 'error' when there were actual errors, but action='skip'
    -- can also occur due to strategy mismatch (e.g., update_only but row is insert).
    v_set_clause := format($$
        state = CASE
            WHEN ru.error_jsonb IS NOT NULL AND ru.error_jsonb != '{}'::jsonb THEN 'error'::public.import_data_state
            WHEN ru.action = 'skip'::public.import_row_action_type THEN 'error'::public.import_data_state
            ELSE 'analysing'::public.import_data_state
        END,
        errors = CASE WHEN ru.error_jsonb IS NOT NULL AND ru.error_jsonb != '{}'::jsonb THEN dt.errors || ru.error_jsonb ELSE dt.errors - %1$L::TEXT[] END,
        action = CASE
            WHEN dt.action = 'skip'::public.import_row_action_type THEN 'skip'::public.import_row_action_type
            ELSE ru.action
        END,
        operation = ru.operation,
        founding_row_id = ru.derived_founding_row_id,
        last_completed_priority = %2$L
    $$, v_error_keys_to_clear_arr, v_step.priority);

    IF v_has_lu_id_col THEN
        v_set_clause := v_set_clause || format(', legal_unit_id = CASE WHEN ru.error_jsonb IS NOT NULL AND ru.error_jsonb != ''{}''::jsonb THEN NULL ELSE ru.resolved_lu_id END');
    END IF;

    IF v_has_est_id_col THEN
        v_set_clause := v_set_clause || format(', establishment_id = CASE WHEN ru.error_jsonb IS NOT NULL AND ru.error_jsonb != ''{}''::jsonb THEN NULL ELSE ru.resolved_est_id END');
    END IF;

    v_sql := format($$
        UPDATE public.%1$I dt SET
            %2$s -- Dynamic SET clause
        FROM temp_batch_analysis ru
        WHERE dt.row_id = ru.data_row_id
          AND EXISTS (SELECT 1 FROM temp_relevant_rows tr WHERE tr.data_row_id = dt.row_id);
    $$, v_data_table_name, v_set_clause);
    RAISE DEBUG '[Job %] analyse_external_idents: Updating all rows in a single pass: %', p_job_id, v_sql;
    EXECUTE v_sql;
    GET DIAGNOSTICS v_update_count = ROW_COUNT;

    -- Recalculate v_error_count for final logging
    v_sql := format($$SELECT COUNT(*) FROM public.%1$I WHERE (errors ?| %2$L::text[]) AND EXISTS (SELECT 1 FROM temp_relevant_rows tr WHERE tr.data_row_id = row_id)$$,
                   v_data_table_name, v_error_keys_to_clear_arr);
    RAISE DEBUG '[Job %] analyse_external_idents: Recalculating error count with SQL: %', p_job_id, v_sql;
    EXECUTE v_sql INTO v_error_count;
    RAISE DEBUG '[Job %] analyse_external_idents: Updated % total rows. Current estimated errors for this step: %', p_job_id, v_update_count, v_error_count;

    -- Unconditionally advance priority for all rows that have not yet passed this step to ensure progress.
    v_sql := format($$
        UPDATE public.%1$I dt SET
            last_completed_priority = %2$L
        WHERE dt.last_completed_priority < %2$L;
    $$, v_data_table_name /* %1$I */, v_step.priority /* %2$L */);
    RAISE DEBUG '[Job %] analyse_external_idents: Unconditionally advancing priority for all applicable rows with SQL: %', p_job_id, v_sql;
    EXECUTE v_sql;
    GET DIAGNOSTICS v_skipped_update_count = ROW_COUNT;
    RAISE DEBUG '[Job %] analyse_external_idents: Advanced last_completed_priority for % total applicable rows.', p_job_id, v_skipped_update_count;

    RAISE DEBUG '[Job %] analyse_external_idents (Batch): Finished analysis for batch. Total errors in batch: %', p_job_id, v_error_count;
EXCEPTION WHEN OTHERS THEN
    RAISE WARNING '[Job %] analyse_external_idents: Error during analysis: %', p_job_id, SQLERRM;
    -- Mark the job itself as failed
    UPDATE public.import_job
    SET error = jsonb_build_object('analyse_external_idents_error', SQLERRM)::TEXT,
        state = 'failed'
    WHERE id = p_job_id;
    RAISE DEBUG '[Job %] analyse_external_idents: Marked job as failed due to error: %', p_job_id, SQLERRM;
    -- Don't re-raise - job is marked as failed
END;
$analyse_external_idents$;


-- ============================================================================
-- Fix 2: analyse_link_establishment_to_legal_unit - Break CTE chain into temp tables
-- ============================================================================

CREATE OR REPLACE PROCEDURE import.analyse_link_establishment_to_legal_unit(IN p_job_id integer, IN p_batch_seq integer, IN p_step_code text)
 LANGUAGE plpgsql
AS $analyse_link_establishment_to_legal_unit$
DECLARE
    v_job public.import_job;
    v_step public.import_step;
    v_data_table_name TEXT;
    v_link_data_cols JSONB;
    v_col_rec RECORD;
    v_sql TEXT;
    v_unpivot_sql TEXT := '';
    v_add_separator BOOLEAN := FALSE;
    v_error_keys_to_clear_arr TEXT[] := ARRAY[]::TEXT[];
    v_fallback_error_key TEXT;
    v_start_time TIMESTAMPTZ;
    v_duration_ms NUMERIC;
    v_total_rows_to_process INT;
BEGIN
    -- Clean up any lingering temp tables from a previous failed run in this session
    IF to_regclass('pg_temp.temp_relevant_rows') IS NOT NULL THEN DROP TABLE temp_relevant_rows; END IF;
    IF to_regclass('pg_temp.temp_precalc') IS NOT NULL THEN DROP TABLE temp_precalc; END IF;
    IF to_regclass('pg_temp.temp_batch_errors') IS NOT NULL THEN DROP TABLE temp_batch_errors; END IF;
    IF to_regclass('pg_temp.temp_lu_coverage') IS NOT NULL THEN DROP TABLE temp_lu_coverage; END IF;
    -- Additional temp tables from optimized approach
    IF to_regclass('pg_temp.temp_unpivoted') IS NOT NULL THEN DROP TABLE temp_unpivoted; END IF;
    IF to_regclass('pg_temp.temp_resolved_distinct') IS NOT NULL THEN DROP TABLE temp_resolved_distinct; END IF;
    IF to_regclass('pg_temp.temp_resolved_idents') IS NOT NULL THEN DROP TABLE temp_resolved_idents; END IF;
    IF to_regclass('pg_temp.temp_row_checks') IS NOT NULL THEN DROP TABLE temp_row_checks; END IF;
    IF to_regclass('pg_temp.temp_errors') IS NOT NULL THEN DROP TABLE temp_errors; END IF;
    IF to_regclass('pg_temp.temp_resolved_links') IS NOT NULL THEN DROP TABLE temp_resolved_links; END IF;
    IF to_regclass('pg_temp.temp_primary_candidates') IS NOT NULL THEN DROP TABLE temp_primary_candidates; END IF;
    IF to_regclass('pg_temp.temp_time_islands') IS NOT NULL THEN DROP TABLE temp_time_islands; END IF;
    IF to_regclass('pg_temp.temp_island_groups') IS NOT NULL THEN DROP TABLE temp_island_groups; END IF;
    IF to_regclass('pg_temp.temp_ranked_primary') IS NOT NULL THEN DROP TABLE temp_ranked_primary; END IF;

    v_start_time := clock_timestamp();
    RAISE DEBUG '[Job %] analyse_link_establishment_to_legal_unit (Optimized): Starting analysis for batch_seq %.', p_job_id, p_batch_seq;

    -- Get job details
    SELECT * INTO v_job FROM public.import_job ij WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;
    v_link_data_cols := v_job.definition_snapshot->'import_data_column_list';

    -- Get step details from snapshot
    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = p_step_code;
    IF NOT FOUND THEN RAISE EXCEPTION '[Job %] % step not found in snapshot', p_job_id, p_step_code; END IF;

    -- Materialize the set of rows to be processed for this step
    CREATE TEMP TABLE temp_relevant_rows (id SERIAL PRIMARY KEY, data_row_id INTEGER NOT NULL) ON COMMIT DROP;
    v_sql := format($$INSERT INTO temp_relevant_rows (data_row_id)
                     SELECT row_id FROM public.%1$I
                     WHERE action IS DISTINCT FROM 'skip' AND last_completed_priority < %2$L$$,
                     v_data_table_name, v_step.priority);
    RAISE DEBUG '[Job %] analyse_link_establishment_to_legal_unit: Materializing relevant rows with SQL: %', p_job_id, v_sql;
    EXECUTE v_sql;
    GET DIAGNOSTICS v_total_rows_to_process = ROW_COUNT;
    IF v_total_rows_to_process = 0 THEN
        RAISE DEBUG '[Job %] No rows with action != ''skip'' found to process for %.', p_job_id, p_step_code;
        -- Even if no rows are actionable, we MUST advance the priority for all rows pending this step to prevent an infinite loop.
        v_sql := format($$
            UPDATE public.%1$I dt SET
                last_completed_priority = %2$L
            WHERE dt.last_completed_priority < %2$L;
        $$, v_data_table_name, v_step.priority);
        RAISE DEBUG '[Job %] analyse_link_establishment_to_legal_unit: Advancing priority for all pending rows to prevent loop. SQL: %', p_job_id, v_sql;
        EXECUTE v_sql;
        RETURN;
    END IF;
    RAISE DEBUG '[Job %] Found % relevant rows to process for %.', p_job_id, v_total_rows_to_process, p_step_code;
    CREATE INDEX ON temp_relevant_rows (data_row_id);

    -- STEP 1: HOLISTIC PRE-CALCULATION using separate temp tables for performance
    RAISE DEBUG '[Job %] Starting optimized holistic pre-calculation phase.', p_job_id;

    -- Prepare for unpivoting
    SELECT jsonb_agg(value) INTO v_link_data_cols FROM jsonb_array_elements(v_link_data_cols) value
    WHERE (value->>'step_id')::int = v_step.id AND value->>'purpose' = 'source_input';

    IF v_link_data_cols IS NULL OR jsonb_array_length(v_link_data_cols) = 0 THEN
        RAISE DEBUG '[Job %] No legal_unit_* source columns defined for step. Skipping.', p_job_id;
        v_sql := format('UPDATE public.%1$I dt SET last_completed_priority = %2$L FROM temp_relevant_rows tr WHERE dt.row_id = tr.data_row_id', v_data_table_name, v_step.priority);
        RAISE DEBUG '[Job %] analyse_link_establishment_to_legal_unit: Advancing priority for skipped (no link columns) rows with SQL: %', p_job_id, v_sql;
        EXECUTE v_sql;
        RETURN;
    END IF;

    -- Build an efficient unpivot SQL statement using LATERAL VALUES to perform a single scan
    v_unpivot_sql := (
        SELECT string_agg(format('(%L, %I)', col_name, col_name), ', ')
        FROM (
            SELECT value->>'column_name' AS col_name FROM jsonb_array_elements(v_link_data_cols)
        ) q
    );

    SELECT array_agg(value->>'column_name') INTO v_error_keys_to_clear_arr FROM jsonb_array_elements(v_link_data_cols) value;
    v_fallback_error_key := COALESCE(v_error_keys_to_clear_arr[1], 'link_establishment_to_legal_unit_error');

    -- ============================================
    -- OPTIMIZED: Break CTE chain into temp tables
    -- This allows PostgreSQL to optimize each step independently with proper indexes
    -- ============================================

    -- Step 1: Unpivoted - Create and populate temp table
    IF v_unpivot_sql IS NOT NULL AND v_unpivot_sql != '' THEN
        v_sql := format($$
            CREATE TEMP TABLE temp_unpivoted ON COMMIT DROP AS
            SELECT
                dt.row_id as data_row_id,
                v.ident_code,
                v.ident_value
            FROM public.%1$I dt
            JOIN temp_relevant_rows tr ON tr.data_row_id = dt.row_id,
            LATERAL (VALUES %2$s) AS v(ident_code, ident_value)
            WHERE v.ident_value IS NOT NULL AND char_length(trim(v.ident_value)) > 0
        $$, v_data_table_name, v_unpivot_sql);
    ELSE
        v_sql := 'CREATE TEMP TABLE temp_unpivoted (data_row_id INT, ident_code TEXT, ident_value TEXT) ON COMMIT DROP';
    END IF;
    RAISE DEBUG '[Job %] Creating temp_unpivoted', p_job_id;
    EXECUTE v_sql;
    CREATE INDEX ON temp_unpivoted (data_row_id);
    CREATE INDEX ON temp_unpivoted (ident_code, ident_value);

    -- Step 2: ResolvedDistinctIdents - Resolve unique identifiers to legal units
    v_sql := $$
        CREATE TEMP TABLE temp_resolved_distinct ON COMMIT DROP AS
        SELECT DISTINCT
            substring(up.ident_code from 'legal_unit_(.*)_raw') as ident_type_code,
            up.ident_value,
            xi.legal_unit_id
        FROM temp_unpivoted up
        JOIN public.external_ident_type xit ON xit.code = substring(up.ident_code from 'legal_unit_(.*)_raw')
        LEFT JOIN public.external_ident xi ON xi.type_id = xit.id AND xi.ident = up.ident_value AND xi.legal_unit_id IS NOT NULL
    $$;
    RAISE DEBUG '[Job %] Creating temp_resolved_distinct', p_job_id;
    EXECUTE v_sql;
    CREATE INDEX ON temp_resolved_distinct (ident_type_code, ident_value);

    -- Step 3: ResolvedIdents - Join back to get resolved LU per row
    v_sql := $$
        CREATE TEMP TABLE temp_resolved_idents ON COMMIT DROP AS
        SELECT
            up.data_row_id,
            up.ident_code,
            up.ident_value,
            rdi.legal_unit_id
        FROM temp_unpivoted up
        LEFT JOIN temp_resolved_distinct rdi ON
            substring(up.ident_code from 'legal_unit_(.*)_raw') = rdi.ident_type_code AND
            up.ident_value = rdi.ident_value
    $$;
    RAISE DEBUG '[Job %] Creating temp_resolved_idents', p_job_id;
    EXECUTE v_sql;
    CREATE INDEX ON temp_resolved_idents (data_row_id);

    -- Step 4: RowChecks - Aggregate per row with checks
    v_sql := format($$
        CREATE TEMP TABLE temp_row_checks ON COMMIT DROP AS
        SELECT
            tr.data_row_id,
            dt.operation,
            dt.valid_from AS est_valid_from,
            dt.valid_until AS est_valid_until,
            jsonb_build_object(
                'num_idents_provided', COUNT(ri.data_row_id),
                'distinct_lu_ids', COUNT(DISTINCT ri.legal_unit_id),
                'found_lu', MAX(CASE WHEN ri.legal_unit_id IS NOT NULL THEN 1 ELSE 0 END),
                'provided_input_ident_codes', jsonb_agg(DISTINCT ri.ident_code) FILTER (WHERE ri.ident_value IS NOT NULL)
            ) as checks,
            (array_agg(ri.legal_unit_id) FILTER (WHERE ri.legal_unit_id IS NOT NULL))[1] AS resolved_lu_id
        FROM temp_relevant_rows tr
        LEFT JOIN temp_resolved_idents ri ON tr.data_row_id = ri.data_row_id
        JOIN public.%1$I dt ON dt.row_id = tr.data_row_id
        GROUP BY tr.data_row_id, dt.operation, dt.valid_from, dt.valid_until
    $$, v_data_table_name);
    RAISE DEBUG '[Job %] Creating temp_row_checks', p_job_id;
    EXECUTE v_sql;
    CREATE INDEX ON temp_row_checks (data_row_id);
    CREATE INDEX ON temp_row_checks (resolved_lu_id) WHERE resolved_lu_id IS NOT NULL;

    -- Step 5: LegalUnitCoverage - Pre-calculate range_agg for all involved legal units
    v_sql := $$
        CREATE TEMP TABLE temp_lu_coverage ON COMMIT DROP AS
        SELECT
            lu.id AS legal_unit_id,
            range_agg(lu.valid_range) AS coverage
        FROM public.legal_unit lu
        WHERE lu.id IN (SELECT DISTINCT resolved_lu_id FROM temp_row_checks WHERE resolved_lu_id IS NOT NULL)
        GROUP BY lu.id
    $$;
    RAISE DEBUG '[Job %] Creating temp_lu_coverage', p_job_id;
    EXECUTE v_sql;
    CREATE INDEX ON temp_lu_coverage (legal_unit_id);

    -- Step 6: Errors - Compute errors per row
    v_sql := format($$
        CREATE TEMP TABLE temp_errors ON COMMIT DROP AS
        SELECT
            rc.data_row_id,
            rc.resolved_lu_id,
            CASE
                WHEN rc.operation != 'update' AND (rc.checks->>'num_idents_provided')::int = 0
                    THEN (SELECT jsonb_object_agg(key, 'Missing legal unit identifier.') FROM unnest(%1$L::TEXT[] || ARRAY[%2$L]) AS key)
                WHEN (rc.checks->>'num_idents_provided')::int > 0 AND (rc.checks->>'found_lu')::int = 0
                    THEN (SELECT jsonb_object_agg(key, 'Legal unit not found with provided identifiers.') FROM jsonb_array_elements_text(COALESCE(rc.checks->'provided_input_ident_codes', '["%2$s"]'::jsonb)) AS key)
                WHEN (rc.checks->>'distinct_lu_ids')::int > 1
                    THEN (SELECT jsonb_object_agg(key, 'Provided identifiers resolve to different Legal Units.') FROM jsonb_array_elements_text(COALESCE(rc.checks->'provided_input_ident_codes', '["%2$s"]'::jsonb)) AS key)
                WHEN rc.resolved_lu_id IS NOT NULL
                     AND NOT daterange(rc.est_valid_from, rc.est_valid_until, '[)') <@ luc.coverage
                    THEN (SELECT jsonb_object_agg(key, 'Establishment validity [' || rc.est_valid_from || ', ' || COALESCE(rc.est_valid_until::text, 'infinity') || ') not covered by legal unit validity.') FROM jsonb_array_elements_text(COALESCE(rc.checks->'provided_input_ident_codes', '["%2$s"]'::jsonb)) AS key)
                ELSE NULL
            END as errors_jsonb
        FROM temp_row_checks rc
        LEFT JOIN temp_lu_coverage luc ON luc.legal_unit_id = rc.resolved_lu_id
    $$, v_error_keys_to_clear_arr, v_fallback_error_key);
    RAISE DEBUG '[Job %] Creating temp_errors', p_job_id;
    EXECUTE v_sql;
    CREATE INDEX ON temp_errors (data_row_id);

    -- Step 7: ResolvedLinks - Get resolved links with establishment info
    v_sql := format($$
        CREATE TEMP TABLE temp_resolved_links ON COMMIT DROP AS
        SELECT DISTINCT ON (rc.data_row_id)
            rc.data_row_id,
            rc.resolved_lu_id,
            dt.establishment_id AS current_establishment_id,
            dt.row_id AS original_data_table_row_id,
            dt.valid_from AS est_valid_from,
            dt.valid_until AS est_valid_until
        FROM temp_row_checks rc
        JOIN public.%1$I dt ON rc.data_row_id = dt.row_id
        WHERE rc.resolved_lu_id IS NOT NULL
    $$, v_data_table_name);
    RAISE DEBUG '[Job %] Creating temp_resolved_links', p_job_id;
    EXECUTE v_sql;
    CREATE INDEX ON temp_resolved_links (data_row_id);
    CREATE INDEX ON temp_resolved_links (resolved_lu_id);

    -- Step 8: PrimaryCandidates - Determine primary candidates
    v_sql := $$
        CREATE TEMP TABLE temp_primary_candidates ON COMMIT DROP AS
        SELECT
            rl.*,
            (NOT EXISTS (
                SELECT 1 FROM public.establishment est
                WHERE est.legal_unit_id = rl.resolved_lu_id AND est.primary_for_legal_unit = TRUE
                  AND est.id IS DISTINCT FROM rl.current_establishment_id
                  AND public.from_until_overlaps(est.valid_from, est.valid_until, rl.est_valid_from, rl.est_valid_until)
            )) AS is_primary_candidate
        FROM temp_resolved_links rl
    $$;
    RAISE DEBUG '[Job %] Creating temp_primary_candidates', p_job_id;
    EXECUTE v_sql;
    CREATE INDEX ON temp_primary_candidates (data_row_id);

    -- Step 9: TimeIslands - Identify time islands
    v_sql := $$
        CREATE TEMP TABLE temp_time_islands ON COMMIT DROP AS
        SELECT
            *,
            MAX(est_valid_until) OVER (
                PARTITION BY resolved_lu_id
                ORDER BY est_valid_from, est_valid_until, original_data_table_row_id
                ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
            ) as max_prev_until
        FROM temp_primary_candidates
        WHERE is_primary_candidate
    $$;
    RAISE DEBUG '[Job %] Creating temp_time_islands', p_job_id;
    EXECUTE v_sql;
    CREATE INDEX ON temp_time_islands (data_row_id);

    -- Step 10: IslandGroups - Assign island group IDs
    v_sql := $$
        CREATE TEMP TABLE temp_island_groups ON COMMIT DROP AS
        SELECT
            data_row_id,
            resolved_lu_id,
            SUM(CASE WHEN est_valid_from >= COALESCE(max_prev_until, '-infinity'::date) THEN 1 ELSE 0 END) OVER (
                PARTITION BY resolved_lu_id
                ORDER BY est_valid_from, est_valid_until, original_data_table_row_id
            ) AS island_id
        FROM temp_time_islands
    $$;
    RAISE DEBUG '[Job %] Creating temp_island_groups', p_job_id;
    EXECUTE v_sql;
    CREATE INDEX ON temp_island_groups (data_row_id);

    -- Step 11: RankedForPrimary - Rank within islands
    v_sql := $$
        CREATE TEMP TABLE temp_ranked_primary ON COMMIT DROP AS
        SELECT
            pc.data_row_id,
            pc.is_primary_candidate,
            ROW_NUMBER() OVER (
                PARTITION BY pc.resolved_lu_id, ig.island_id
                ORDER BY pc.original_data_table_row_id
            ) as row_num
        FROM temp_primary_candidates pc
        LEFT JOIN temp_island_groups ig ON pc.data_row_id = ig.data_row_id
    $$;
    RAISE DEBUG '[Job %] Creating temp_ranked_primary', p_job_id;
    EXECUTE v_sql;
    CREATE INDEX ON temp_ranked_primary (data_row_id);

    -- Step 12: Final pre-calculation table
    CREATE TEMP TABLE temp_precalc (
        data_row_id INTEGER PRIMARY KEY,
        resolved_lu_id INTEGER,
        primary_for_legal_unit BOOLEAN,
        errors_jsonb JSONB
    ) ON COMMIT DROP;

    v_sql := $$
        INSERT INTO temp_precalc (data_row_id, resolved_lu_id, primary_for_legal_unit, errors_jsonb)
        SELECT
            tr.data_row_id,
            err.resolved_lu_id,
            (rfp.is_primary_candidate AND rfp.row_num = 1) AS primary_for_legal_unit,
            err.errors_jsonb
        FROM temp_relevant_rows tr
        LEFT JOIN temp_errors err ON tr.data_row_id = err.data_row_id
        LEFT JOIN temp_ranked_primary rfp ON tr.data_row_id = rfp.data_row_id
    $$;
    RAISE DEBUG '[Job %] Creating temp_precalc', p_job_id;
    EXECUTE v_sql;

    RAISE DEBUG '[Job %] Optimized holistic pre-calculation phase complete.', p_job_id;

    -- STEP 2: SINGLE HOLISTIC UPDATE
    -- With the pre-calculation done, a single update is safe and efficient.
    RAISE DEBUG '[Job %] Starting single holistic update phase.', p_job_id;
    v_sql := format($$
        UPDATE public.%1$I dt SET
            legal_unit_id = COALESCE(pre.resolved_lu_id, dt.legal_unit_id),  -- Always set if resolved (helps debugging)
            primary_for_legal_unit = CASE
                WHEN pre.errors_jsonb IS NOT NULL THEN dt.primary_for_legal_unit -- Preserve on error
                WHEN pre.resolved_lu_id IS NOT NULL THEN pre.primary_for_legal_unit -- Use new primary status only if LU was resolved
                ELSE dt.primary_for_legal_unit -- Otherwise, preserve existing
            END,
            state = CASE WHEN pre.errors_jsonb IS NOT NULL THEN 'error'::public.import_data_state ELSE dt.state END,
            action = CASE WHEN pre.errors_jsonb IS NOT NULL THEN 'skip'::public.import_row_action_type ELSE dt.action END,
            errors = CASE WHEN pre.errors_jsonb IS NOT NULL THEN dt.errors || pre.errors_jsonb ELSE dt.errors - %2$L::TEXT[] END,
            last_completed_priority = %3$L
        FROM temp_precalc pre
        WHERE dt.row_id = pre.data_row_id
    $$, v_data_table_name, v_error_keys_to_clear_arr, v_step.priority);
    RAISE DEBUG '[Job %] analyse_link_establishment_to_legal_unit: Applying holistic updates with SQL: %', p_job_id, v_sql;
    EXECUTE v_sql;
    RAISE DEBUG '[Job %] Holistic update complete.', p_job_id;

    -- Propagate errors to related new entity rows (best-effort)
    BEGIN
        CREATE TEMP TABLE temp_batch_errors (data_row_id INTEGER PRIMARY KEY) ON COMMIT DROP;
        INSERT INTO temp_batch_errors (data_row_id) SELECT data_row_id FROM temp_precalc WHERE errors_jsonb IS NOT NULL;
        CALL import.propagate_fatal_error_to_entity_holistic(p_job_id, v_data_table_name, 'temp_batch_errors', v_error_keys_to_clear_arr, p_step_code);
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING '[Job %] analyse_link_establishment_to_legal_unit: Non-fatal error during error propagation: %', p_job_id, SQLERRM;
    END;

    -- Unconditionally advance priority for all rows that have not yet passed this step to ensure progress.
    v_sql := format($$
        UPDATE public.%1$I dt SET
            last_completed_priority = %2$L
        WHERE dt.last_completed_priority < %2$L;
    $$, v_data_table_name /* %1$I */, v_step.priority /* %2$L */);
    RAISE DEBUG '[Job %] analyse_link_establishment_to_legal_unit (Optimized): Unconditionally advancing priority for all applicable rows with SQL: %', p_job_id, v_sql;
    EXECUTE v_sql;

    v_duration_ms := (EXTRACT(EPOCH FROM (clock_timestamp() - v_start_time)) * 1000);
    RAISE DEBUG '[Job %] analyse_link_establishment_to_legal_unit (Optimized): Finished in % ms.', p_job_id, round(v_duration_ms, 2);
END;
$analyse_link_establishment_to_legal_unit$;

-- Implements the analyse and operation procedures for the ExternalIdents import target.

BEGIN;

-- Table to map multiple import columns to single hierarchical identifier
-- Note: This table would be created when the import system is fully migrated to the new schema
-- For now, commenting out to avoid referencing non-existent tables
-- 
-- CREATE TABLE import.hierarchical_column_mapping (
--     id SERIAL PRIMARY KEY,
--     definition_id INTEGER NOT NULL, -- REFERENCES import.definition(id) ON DELETE CASCADE,
--     type_id INTEGER NOT NULL REFERENCES public.external_ident_type(id) ON DELETE RESTRICT,
--     source_column_names TEXT[] NOT NULL, -- e.g., ['admin_region', 'admin_district', 'admin_unit']
--     
--     -- Prevent duplicate mappings
--     UNIQUE (definition_id, type_id)
-- );


-- Procedure to analyse external identifier data (Batch Oriented)
CREATE OR REPLACE PROCEDURE import.analyse_external_idents(p_job_id INT, p_batch_row_id_ranges int4multirange, p_step_code TEXT)
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
    -- Clean up any lingering temp tables from a previous failed run in this session,
    -- using to_regclass to avoid noisy NOTICEs if the tables don't exist.
    IF to_regclass('pg_temp.temp_relevant_rows') IS NOT NULL THEN DROP TABLE temp_relevant_rows; END IF;
    IF to_regclass('pg_temp.temp_unpivoted_idents') IS NOT NULL THEN DROP TABLE temp_unpivoted_idents; END IF;
    IF to_regclass('pg_temp.temp_batch_analysis') IS NOT NULL THEN DROP TABLE temp_batch_analysis; END IF;
    IF to_regclass('pg_temp.temp_propagated_errors') IS NOT NULL THEN DROP TABLE temp_propagated_errors; END IF;
    IF to_regclass('pg_temp.temp_entity_signatures') IS NOT NULL THEN DROP TABLE temp_entity_signatures; END IF;

    -- This is a HOLISTIC procedure. It is called once and processes all relevant rows for this step.
    -- The p_batch_row_id_ranges parameter is ignored (it will be NULL).
    RAISE DEBUG '[Job %] analyse_external_idents (Holistic): Starting analysis.', p_job_id;

    -- FUNDAMENTAL ALGORITHM IMPROVEMENT: Set optimal settings for external_idents processing
    PERFORM admin.set_optimal_external_idents_settings();

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

    -- Filter data columns relevant to this step
    SELECT jsonb_agg(value) INTO v_ident_data_cols
    FROM jsonb_array_elements(v_ident_data_cols) value
    WHERE (value->>'step_id')::int = v_step.id AND value->>'purpose' = 'source_input';

    IF v_ident_data_cols IS NULL OR jsonb_array_length(v_ident_data_cols) = 0 THEN
         RAISE DEBUG '[Job %] analyse_external_idents: No external ident source_input data columns found in snapshot for step %. Skipping analysis.', p_job_id, v_step.id;
         v_sql := format($$UPDATE public.%1$I dt SET last_completed_priority = %2$L WHERE EXISTS (SELECT 1 FROM temp_relevant_rows tr WHERE tr.data_row_id = dt.row_id)$$,
                        v_data_table_name /* %1$I */, v_step.priority /* %2$L */);
         RAISE DEBUG '[Job %] analyse_external_idents: Updating last_completed_priority for skipped rows (no columns) with SQL: %', p_job_id, v_sql;
         EXECUTE v_sql;
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
        'ambiguous_unit_type',
        'invalid_hierarchical_characters',
        'hierarchical_depth_mismatch',
        'missing_hierarchical_components'
    ];
    -- Note: duplicate identifier errors use the actual column names (e.g., 'tax_ident_raw')
    -- so they're already included in v_error_keys_to_clear_arr from source_input_ident_codes
    -- Ensure uniqueness (though direct conflict between source_input names and general keys is unlikely)
    SELECT array_agg(DISTINCT e) INTO v_error_keys_to_clear_arr FROM unnest(v_error_keys_to_clear_arr) e;
    RAISE DEBUG '[Job %] analyse_external_idents: Error keys to clear for this step: %', p_job_id, v_error_keys_to_clear_arr;

    -- Step 1: Unpivot provided identifiers and lookup existing units
    CREATE TEMP TABLE temp_unpivoted_idents (
        data_row_id INTEGER,
        ident_type_code TEXT,
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
    -- For external_idents step, the import_data_column.column_name is the raw source column (e.g., tax_ident_raw).
    FOR v_col_rec IN SELECT
                         value->>'column_name' as raw_column_name,
                         replace(value->>'column_name', '_raw', '') as ident_code
                     FROM jsonb_array_elements(v_ident_data_cols) value
    LOOP
        -- The ident_code is used to join with external_ident_type.code
        IF v_col_rec.raw_column_name IS NULL THEN
             RAISE DEBUG '[Job %] analyse_external_idents: Skipping column as its name is null in import_data_column_list for step external_idents.', p_job_id;
             CONTINUE;
        END IF;

        IF v_add_separator THEN v_unpivot_sql := v_unpivot_sql || ' UNION ALL '; END IF;
        v_unpivot_sql := v_unpivot_sql || format(
             $$SELECT dt.row_id,
                     %1$L AS source_column_name_in_data_table, -- This is the name of the column in _data table (e.g., 'tax_ident_raw')
                     %2$L AS ident_type_code_to_join_on,     -- This is the external_ident_type.code (e.g., 'tax_ident')
                     NULLIF(dt.%3$I, '') AS ident_value
             FROM public.%4$I dt
             JOIN temp_relevant_rows tr ON tr.data_row_id = dt.row_id
             WHERE NULLIF(dt.%5$I, '') IS NOT NULL$$,
             v_col_rec.raw_column_name, -- %1$L Name of column in _data table
             v_col_rec.ident_code,      -- %2$L Code to join with external_ident_type
             v_col_rec.raw_column_name, -- %3$I Column to select value from in _data table
             v_data_table_name,         -- %4$I
             v_col_rec.raw_column_name  -- %5$I
        );
        v_add_separator := TRUE;
    END LOOP;

    IF v_unpivot_sql = '' THEN
        RAISE DEBUG '[Job %] analyse_external_idents: No external ident values found in batch (e.g. all source columns were NULL, or no relevant columns in snapshot for external_idents step). Skipping further analysis.', p_job_id;
        v_sql := format($$
            UPDATE public.%1$I dt SET
                state = %2$L,
                errors = jsonb_build_object('external_idents', 'No identifier provided or mapped correctly for external_idents step'),
                operation = 'insert'::public.import_row_operation_type,
                action = %3$L,
                last_completed_priority = %4$L
            WHERE EXISTS (SELECT 1 FROM temp_relevant_rows tr WHERE tr.data_row_id = dt.row_id);
        $$, v_data_table_name /* %1$I */, 'error' /* %2$L */, 'skip'::public.import_row_action_type /* %3$L */, v_step.priority /* %4$L */);
        RAISE DEBUG '[Job %] analyse_external_idents: Marking rows as error (no identifiers) with SQL: %', p_job_id, v_sql;
        EXECUTE v_sql;
        GET DIAGNOSTICS v_error_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_external_idents (Batch): Finished analysis for batch. Errors: % (all rows missing identifiers or mappings for external_idents step)', p_job_id, v_error_count;
        IF to_regclass('pg_temp.temp_unpivoted_idents') IS NOT NULL THEN DROP TABLE temp_unpivoted_idents; END IF;
        IF to_regclass('pg_temp.temp_relevant_rows') IS NOT NULL THEN DROP TABLE temp_relevant_rows; END IF;
        RETURN;
    END IF;

    -- v_cross_type_conflict_check_sql is removed as this logic is now embedded into the
    -- temp_unpivoted_idents population directly using is_cross_type_conflict and conflicting_unit_jsonb.

    -- Create a temp table for the raw, unpivoted identifiers first.
    CREATE TEMP TABLE temp_raw_unpivoted_idents (
        data_row_id INT,
        source_ident_code TEXT,
        ident_type_code TEXT,
        ident_value TEXT
    ) ON COMMIT DROP;

    v_sql := format('INSERT INTO temp_raw_unpivoted_idents %s', v_unpivot_sql);
    RAISE DEBUG '[Job %] analyse_external_idents: Populating temp_raw_unpivoted_idents with SQL: %', p_job_id, v_sql;
    EXECUTE v_sql;

    -- Now, perform the lookup on only the unique identifiers from the batch.
    v_sql := format($$
        WITH distinct_idents AS (
            SELECT DISTINCT ident_type_code, ident_value
            FROM temp_raw_unpivoted_idents
        ),
        resolved_distinct_idents AS (
            SELECT
                di.ident_type_code,
                di.ident_value,
                xit.id AS ident_type_id,
                xi.legal_unit_id AS resolved_lu_id,
                xi.establishment_id AS resolved_est_id,
                (conflicting_est_table.legal_unit_id IS NOT NULL) AS conflicting_est_is_formal
            FROM distinct_idents di
            LEFT JOIN public.external_ident_type_active xit ON xit.code = di.ident_type_code
            LEFT JOIN public.external_ident xi ON xi.type_id = xit.id AND xi.ident = di.ident_value
            LEFT JOIN public.establishment conflicting_est_table ON conflicting_est_table.id = xi.establishment_id
        )
        INSERT INTO temp_unpivoted_idents (data_row_id, ident_type_code, source_ident_code, ident_value, ident_type_id, resolved_lu_id, resolved_est_id, is_cross_type_conflict, conflicting_unit_jsonb, conflicting_est_is_formal)
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
            COALESCE(rdi.conflicting_est_is_formal, FALSE)
        FROM temp_raw_unpivoted_idents up
        LEFT JOIN resolved_distinct_idents rdi ON up.ident_type_code = rdi.ident_type_code AND up.ident_value = rdi.ident_value;
    $$, v_job_mode);
    RAISE DEBUG '[Job %] analyse_external_idents: Populating temp_unpivoted_idents with resolved data: %', p_job_id, v_sql;
    EXECUTE v_sql;

    -- FUNDAMENTAL ALGORITHM IMPROVEMENT: Index the temp table for optimal performance
    PERFORM admin.index_temp_unpivoted_idents('temp_unpivoted_idents');

    DROP TABLE temp_raw_unpivoted_idents;

    -- Step 1a: Compute Entity Signatures (EARLY)
    -- We need entity signatures early to distinguish between "duplicate rows" (error)
    -- and "multiple rows for same entity" (temporal data/valid).
    --
    -- Signature Structure:
    -- {
    --   "tax_ident": "TAX001",                    -- Regular identifier
    --   "admin_statistical": "NORTH.KAMPALA.001"  -- Hierarchical identifier (ltree as text)
    -- }
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

    -- Step 1b: Detect duplicate identifiers across multiple rows
    -- Store mapping of (data_row_id, source_ident_code) -> duplicate info
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
                -- Check if all rows resolve to the same entity
                COUNT(DISTINCT COALESCE(tui.resolved_lu_id, 0)) AS distinct_lu_count,
                COUNT(DISTINCT COALESCE(tui.resolved_est_id, 0)) AS distinct_est_count,
                -- Count distinct entity signatures for new entities
                COUNT(DISTINCT tes.entity_signature) FILTER (WHERE tui.resolved_lu_id IS NULL AND tui.resolved_est_id IS NULL) AS distinct_new_entity_signatures
            FROM temp_unpivoted_idents tui
            JOIN public.external_ident_type_active xit ON xit.id = tui.ident_type_id
            LEFT JOIN temp_entity_signatures tes ON tes.data_row_id = tui.data_row_id
            WHERE tui.ident_type_id IS NOT NULL
              AND tui.ident_value IS NOT NULL
              AND tui.is_cross_type_conflict IS FALSE
            GROUP BY tui.ident_type_code, tui.ident_value
            HAVING COUNT(DISTINCT tui.data_row_id) > 1
               -- Only flag as duplicate if rows represent DIFFERENT entities:
               -- - Different existing entities (different resolved_lu_id or resolved_est_id)
               -- - Mix of new and existing entities (potential conflict)
               -- - Multiple NEW entities with DIFFERENT entity signatures (different entities)
               -- NOTE: Multiple NEW entities with SAME entity signature are temporal data (same entity) - NOT flagged.
               AND (
                   -- Case 1: Different existing legal units
                   COUNT(DISTINCT tui.resolved_lu_id) FILTER (WHERE tui.resolved_lu_id IS NOT NULL) > 1
                   OR 
                   -- Case 2: Different existing establishments
                   COUNT(DISTINCT tui.resolved_est_id) FILTER (WHERE tui.resolved_est_id IS NOT NULL) > 1
                   OR 
                   -- Case 3: Mix of new and existing entities (one tries to create, another updates)
                   (COUNT(*) FILTER (WHERE tui.resolved_lu_id IS NULL AND tui.resolved_est_id IS NULL) > 0
                    AND COUNT(*) FILTER (WHERE tui.resolved_lu_id IS NOT NULL OR tui.resolved_est_id IS NOT NULL) > 0)
                   OR
                   -- Case 4: Multiple NEW entities with DIFFERENT entity signatures (truly different entities)
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
            RAISE DEBUG '[Job %]   TUI: data_row_id=%, source_ident_code=%, ident_value=%, ident_type_id=%, resolved_lu_id=%, resolved_est_id=%',
                        p_job_id, tui_rec.data_row_id, tui_rec.source_ident_code, tui_rec.ident_value, tui_rec.ident_type_id, tui_rec.resolved_lu_id, tui_rec.resolved_est_id;
        END LOOP;
    END;

    -- Step 1h: Handle hierarchical identifiers
    -- NOTE: Hierarchical identifier processing is prepared but commented out
    -- until the full import schema migration is complete. The hierarchical_column_mapping
    -- table and supporting infrastructure need to be created first.
    --
    -- The logic would process hierarchical column mappings to combine multiple
    -- source columns into ltree values, with proper validation and conflict detection.

    -- Step 1i: Validate hierarchical identifiers  
    -- NOTE: Hierarchical identifier validation is prepared but commented out
    -- until the full SUM type migration is complete. When enabled, this will:
    --
    -- 1. Check ltree character restrictions (A-Z, a-z, 0-9, _ only)
    -- 2. Validate depth matches expected label count
    -- 3. Ensure component completeness
    --
    -- For now, basic validation is handled by existing identifier type constraints.

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
        WITH RowChecks AS (
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
                (SELECT array_agg(value->>'column_name') FROM jsonb_array_elements(%2$L) value) as all_source_input_ident_codes_for_step
            FROM temp_relevant_rows orig
            JOIN public.%1$I dt ON orig.data_row_id = dt.row_id
            LEFT JOIN temp_aggregated_idents ai ON orig.data_row_id = ai.data_row_id
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
            LEFT JOIN ExistingIdents existing ON existing.final_lu_id IS NOT DISTINCT FROM obe.final_lu_id
                                             AND existing.final_est_id IS NOT DISTINCT FROM obe.final_est_id
        ),
        -- This CTE determines the operation based on whether the entity exists in the DB and its order within the batch.
        -- Also pre-computes final_error_jsonb and row_has_error to avoid re-evaluating JSONB expressions
        -- in the window functions of PropagatedErrors CTE.
        OperationDetermination AS (
            SELECT
                awo.*,
                CASE
                    WHEN awo.final_lu_id IS NULL AND awo.final_est_id IS NULL THEN -- Entity is new to the DB
                        CASE
                            WHEN awo.rn_in_batch_for_entity = 1 THEN 'insert'::public.import_row_operation_type
                            ELSE -- Subsequent row for a new entity within this batch
                                CASE
                                    WHEN %2$L::public.import_strategy IN ('insert_or_update', 'update_only') THEN 'update'::public.import_row_operation_type -- %2$L is v_strategy
                                    ELSE 'replace'::public.import_row_operation_type
                                END
                        END
                    ELSE -- Entity already exists in the DB
                        CASE
                            WHEN %2$L::public.import_strategy IN ('insert_or_update', 'update_only') THEN 'update'::public.import_row_operation_type -- %2$L is v_strategy
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
                -- Case 1: This is a new entity, and some row in the entity has an error. Propagate it to all rows for that entity.
                WHEN pe.entity_has_error AND pe.final_lu_id IS NULL AND pe.final_est_id IS NULL THEN
                    CASE
                        -- Subcase 1.1: This specific row has an error. Use its own error.
                        WHEN pe.final_error_jsonb != '{}'::jsonb THEN pe.final_error_jsonb
                        -- Subcase 1.2: This specific row does NOT have an error, but another row in the same entity does. Propagate.
                        ELSE jsonb_build_object(
                                 COALESCE((SELECT value->>'column_name' FROM jsonb_array_elements(%4$L) value WHERE value->>'purpose' = 'source_input' LIMIT 1), 'propagated_error'),
                                 'An error on a related new entity row caused this row to be skipped. Source error row(s): ' || array_to_string(pe.entity_error_source_row_ids, ', ')
                             )
                    END
                -- Case 2: This is an existing entity, or a new entity with no errors. Just use its own error jsonb.
                ELSE pe.final_error_jsonb
            END as error_jsonb,
            pe.final_lu_id AS resolved_lu_id,
            pe.final_est_id AS resolved_est_id,
            pe.operation,
            CASE
                -- Note: action from previous step is not available in this CTE, will be merged in UPDATE statement
                WHEN pe.entity_has_error THEN 'skip'::public.import_row_action_type -- Priority 1: Entity-wide Error
                WHEN %2$L::public.import_strategy = 'insert_only' AND pe.operation != 'insert'::public.import_row_operation_type THEN 'skip'::public.import_row_action_type -- %2$L is v_strategy
                WHEN %2$L::public.import_strategy = 'replace_only' AND pe.operation != 'replace'::public.import_row_operation_type THEN 'skip'::public.import_row_action_type -- %2$L is v_strategy
                WHEN %2$L::public.import_strategy = 'update_only' AND pe.operation != 'update'::public.import_row_operation_type THEN 'skip'::public.import_row_action_type -- %2$L is v_strategy
                ELSE 'use'::public.import_row_action_type
            END as action,  -- Will be merged with existing action in UPDATE to preserve 'skip' from previous steps
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
    v_set_clause := format($$
        state = CASE WHEN ru.error_jsonb IS NOT NULL AND ru.error_jsonb != '{}'::jsonb THEN 'error'::public.import_data_state ELSE 'analysing'::public.import_data_state END,
        errors = CASE WHEN ru.error_jsonb IS NOT NULL AND ru.error_jsonb != '{}'::jsonb THEN dt.errors || ru.error_jsonb ELSE dt.errors - %1$L::TEXT[] END,
        action = CASE 
            WHEN dt.action = 'skip'::public.import_row_action_type THEN 'skip'::public.import_row_action_type -- Preserve skip from previous steps
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
    SET error = jsonb_build_object('analyse_external_idents_error', SQLERRM),
        state = 'finished' -- Or a new 'failed' state
    WHERE id = p_job_id;
    RAISE DEBUG '[Job %] analyse_external_idents: Marked job as failed due to error: %', p_job_id, SQLERRM;
    RAISE; -- Re-raise the exception
END;
$analyse_external_idents$;


-- Set-based helper procedure to upsert external identifiers for a batch of units.
-- This is called by other process_* procedures after the main unit ID has been assigned.
CREATE OR REPLACE PROCEDURE import.helper_process_external_idents(
    p_job_id INT,
    p_batch_row_id_ranges int4multirange,
    p_step_code TEXT
)
LANGUAGE plpgsql AS $helper_process_external_idents$
DECLARE
    v_job public.import_job;
    v_data_table_name TEXT;
    v_job_mode public.import_mode;
    v_ident_data_cols JSONB;
    v_step public.import_step;
    v_col_rec RECORD;
    v_sql TEXT;
    v_unit_id_col_name TEXT;
    v_unit_type TEXT;
    v_rows_affected INT;
    v_ident_type_rec RECORD;
BEGIN
    RAISE DEBUG '[Job %] helper_process_external_idents (Batch): Starting for range %s for step %', p_job_id, p_batch_row_id_ranges::text, p_step_code;

    -- No special constraint handling needed for the SUM type design.
    -- The trigger will handle validation automatically.

    -- Get job details
    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;
    v_job_mode := (v_job.definition_snapshot->'import_definition'->>'mode')::public.import_mode;

    -- Determine unit type and ID column from job mode
    IF v_job_mode = 'legal_unit' THEN
        v_unit_type := 'legal_unit';
        v_unit_id_col_name := 'legal_unit_id';
    ELSIF v_job_mode IN ('establishment_formal', 'establishment_informal') THEN
        v_unit_type := 'establishment';
        v_unit_id_col_name := 'establishment_id';
    ELSE
        RAISE DEBUG '[Job %] helper_process_external_idents: Job mode is ''%'', which does not have external identifiers processed by this step. Skipping.', p_job_id, v_job_mode;
        RETURN;
    END IF;

    -- Get relevant source_input columns for the external_idents step from snapshot
    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = 'external_idents';
    SELECT jsonb_agg(value) INTO v_ident_data_cols
    FROM jsonb_array_elements(v_job.definition_snapshot->'import_data_column_list') value
    WHERE (value->>'step_id')::int = v_step.id AND value->>'purpose' = 'source_input';

    IF v_ident_data_cols IS NULL OR jsonb_array_length(v_ident_data_cols) = 0 THEN
        RAISE DEBUG '[Job %] helper_process_external_idents: No external ident source_input columns found for step. Skipping.', p_job_id;
        RETURN;
    END IF;

    -- Process regular identifiers from individual columns
    FOR v_col_rec IN
        SELECT
            value->>'column_name' as raw_column_name,
            replace(value->>'column_name', '_raw', '') as ident_code
        FROM jsonb_array_elements(v_ident_data_cols) value
    LOOP
        -- Find the corresponding external_ident_type record
        SELECT * INTO v_ident_type_rec FROM public.external_ident_type_active WHERE code = v_col_rec.ident_code;
        IF NOT FOUND THEN
            RAISE DEBUG '[Job %] helper_process_external_idents: Skipping source column ''%'' as its base code ''%'' does not correspond to an active external_ident_type.', p_job_id, v_col_rec.raw_column_name, v_col_rec.ident_code;
            CONTINUE;
        END IF;

        -- NOTE: For now, process all identifiers the same way until the full SUM type migration is complete
        -- In the future, hierarchical identifiers will be processed separately via hierarchical_column_mapping

        RAISE DEBUG '[Job %] helper_process_external_idents: Processing identifier type: % (column: %)', p_job_id, v_ident_type_rec.code, v_col_rec.raw_column_name;
        
        -- Dynamically build and execute the MERGE statement for this identifier type.
        -- The approach is the same for both regular and hierarchical identifiers:
        -- Each (type_id, ident) must be globally unique across all units.
        -- The SUM type design ensures proper storage in either ident (regular) or idents+labels (hierarchical).
        
        -- Build MERGE statement compatible with current database structure
        -- This will work with both old grouped and new SUM type designs
        v_sql := format(
                $SQL$
                MERGE INTO public.external_ident AS t
                USING (
                    SELECT DISTINCT ON (dt.founding_row_id, dt.%3$I)
                        dt.founding_row_id,
                        dt.%1$I AS unit_id,
                        dt.edit_by_user_id,
                        dt.edit_at,
                        dt.edit_comment,
                        %2$L::integer AS type_id,
                        dt.%3$I AS ident_value
                    FROM public.%4$I dt
                    WHERE dt.row_id <@ $1
                      AND dt.action = 'use'
                      AND dt.%1$I IS NOT NULL
                      AND NULLIF(dt.%3$I, '') IS NOT NULL
                    ORDER BY dt.founding_row_id, dt.%3$I, dt.row_id
                ) AS s
                ON (t.type_id = s.type_id AND t.ident = s.ident_value)
                WHEN MATCHED AND (
                    t.legal_unit_id IS DISTINCT FROM (CASE WHEN %5$L = 'legal_unit' THEN s.unit_id ELSE NULL END) OR
                    t.establishment_id IS DISTINCT FROM (CASE WHEN %5$L = 'establishment' THEN s.unit_id ELSE NULL END)
                ) THEN
                    UPDATE SET
                        legal_unit_id = CASE WHEN %5$L = 'legal_unit' THEN s.unit_id ELSE NULL END,
                        establishment_id = CASE WHEN %5$L = 'establishment' THEN s.unit_id ELSE NULL END,
                        enterprise_id = NULL,
                        enterprise_group_id = NULL,
                        edit_by_user_id = s.edit_by_user_id,
                        edit_at = s.edit_at,
                        edit_comment = s.edit_comment
                WHEN NOT MATCHED THEN
                    INSERT (legal_unit_id, establishment_id, type_id, ident, edit_by_user_id, edit_at, edit_comment)
                    VALUES (
                        CASE WHEN %5$L = 'legal_unit' THEN s.unit_id ELSE NULL END,
                        CASE WHEN %5$L = 'establishment' THEN s.unit_id ELSE NULL END,
                        s.type_id,
                        s.ident_value,
                        s.edit_by_user_id,
                        s.edit_at,
                        s.edit_comment
                    );
                $SQL$,
                v_unit_id_col_name,           -- %1$I
                v_ident_type_rec.id,          -- %2$L
                v_col_rec.raw_column_name,    -- %3$I
                v_data_table_name,            -- %4$I
                v_unit_type                   -- %5$L
            );
        
        RAISE DEBUG '[Job %] helper_process_external_idents: Merging with SQL: %', p_job_id, v_sql;
        EXECUTE v_sql USING p_batch_row_id_ranges;
        GET DIAGNOSTICS v_rows_affected = ROW_COUNT;
        RAISE DEBUG '[Job %] helper_process_external_idents: Merged % rows for regular identifier type %.', p_job_id, v_rows_affected, v_ident_type_rec.code;
    END LOOP;

    -- Process hierarchical identifiers from hierarchical_column_mapping
    -- NOTE: Hierarchical identifier processing in the helper procedure is prepared
    -- but commented out until the full import schema migration is complete.
    --
    -- The logic would:
    -- 1. Get hierarchical mappings from hierarchical_column_mapping table
    -- 2. Build column concatenation logic for each mapping 
    -- 3. Execute MERGE statements using the SUM type design (idents field)
    --
    -- This ensures hierarchical identifiers are properly stored in the idents (ltree)
    -- field while regular identifiers use the ident (text) field.

    -- No constraint restoration needed for the SUM type design.
    
EXCEPTION WHEN OTHERS THEN
    RAISE WARNING '[Job %] helper_process_external_idents: Error during batch operation: %', p_job_id, SQLERRM;
    RAISE;
END;
$helper_process_external_idents$;

-- FUNDAMENTAL ALGORITHM IMPROVEMENTS: Standard temp table indexing function
-- Always create these indexes when processing external_idents
CREATE OR REPLACE FUNCTION admin.index_temp_unpivoted_idents(table_name TEXT)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    -- Always beneficial: index on lookup columns
    EXECUTE format('CREATE INDEX IF NOT EXISTS %I_lookup_idx ON %I (ident_type_code, ident_value)', table_name, table_name);
    
    -- Always beneficial: hash index for equality lookups  
    EXECUTE format('CREATE INDEX IF NOT EXISTS %I_hash_idx ON %I USING HASH (ident_value)', table_name, table_name);
    
    -- Always beneficial: index on data_row_id for result joining
    EXECUTE format('CREATE INDEX IF NOT EXISTS %I_data_row_idx ON %I (data_row_id)', table_name, table_name);
    
    -- Always beneficial: update statistics
    EXECUTE format('ANALYZE %I', table_name);
END;
$$;

-- FUNDAMENTAL ALGORITHM IMPROVEMENTS: Optimized settings for identifier processing
-- These are always good for large JOIN operations
CREATE OR REPLACE FUNCTION admin.set_optimal_external_idents_settings()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    SET LOCAL work_mem = '1GB';           -- Allow large hash tables in memory
    SET LOCAL enable_hashjoin = on;       -- Use hash joins for large lookups
    SET LOCAL enable_nestloop = off;      -- Avoid nested loops for large datasets
    SET LOCAL enable_mergejoin = off;     -- Avoid expensive sorts for joins
    SET LOCAL random_page_cost = 1.1;     -- Optimize for modern storage
END;
$$;

COMMIT;

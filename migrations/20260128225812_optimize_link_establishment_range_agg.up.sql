-- Migration 20260128225812: optimize_link_establishment_range_agg
-- Optimize analyse_link_establishment_to_legal_unit procedure
-- Replace correlated subquery with pre-calculated range_agg to avoid O(n) aggregations

BEGIN;

-- Procedure to analyse the link between establishment and legal unit (Hybrid Holistic/Batch)
-- OPTIMIZATION: Pre-calculate range_agg for all involved legal units once,
-- instead of running correlated subquery for each row.
CREATE OR REPLACE PROCEDURE import.analyse_link_establishment_to_legal_unit(p_job_id INT, p_batch_seq INTEGER, p_step_code TEXT)
LANGUAGE plpgsql AS $analyse_link_establishment_to_legal_unit$
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

    v_start_time := clock_timestamp();
    RAISE DEBUG '[Job %] analyse_link_establishment_to_legal_unit (Hybrid): Starting analysis for batch_seq %.', p_job_id, p_batch_seq;

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

    -- STEP 1: HOLISTIC PRE-CALCULATION
    RAISE DEBUG '[Job %] Starting holistic pre-calculation phase.', p_job_id;
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

    IF v_unpivot_sql IS NOT NULL AND v_unpivot_sql != '' THEN
        v_unpivot_sql := format($$
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
        -- Ensure it's a valid query that returns nothing if no link columns are defined
        v_unpivot_sql := 'SELECT NULL::INT, NULL::TEXT, NULL::TEXT WHERE FALSE';
    END IF;
    SELECT array_agg(value->>'column_name') INTO v_error_keys_to_clear_arr FROM jsonb_array_elements(v_link_data_cols) value;
    v_fallback_error_key := COALESCE(v_error_keys_to_clear_arr[1], 'link_establishment_to_legal_unit_error');

    -- Create and populate the main pre-calculation table
    CREATE TEMP TABLE temp_precalc (
        data_row_id INTEGER PRIMARY KEY,
        resolved_lu_id INTEGER,
        primary_for_legal_unit BOOLEAN,
        errors_jsonb JSONB
    ) ON COMMIT DROP;

    -- OPTIMIZATION: This large CTE now pre-calculates range_agg once for all involved legal units,
    -- instead of using a correlated subquery that ran range_agg N times for N rows.
    v_sql := format($$
        WITH Unpivoted AS ( %1$s ),
        DistinctIdents AS (
            SELECT DISTINCT
                substring(up.ident_code from 'legal_unit_(.*)_raw') as ident_type_code,
                up.ident_value
            FROM Unpivoted up
        ),
        ResolvedDistinctIdents AS (
            SELECT
                di.ident_type_code,
                di.ident_value,
                xi.legal_unit_id
            FROM DistinctIdents di
            JOIN public.external_ident_type xit ON xit.code = di.ident_type_code
            LEFT JOIN public.external_ident xi ON xi.type_id = xit.id AND xi.ident = di.ident_value AND xi.legal_unit_id IS NOT NULL
        ),
        ResolvedIdents AS (
            SELECT
                up.data_row_id,
                up.ident_code,
                up.ident_value,
                rdi.legal_unit_id
            FROM Unpivoted up
            LEFT JOIN ResolvedDistinctIdents rdi ON
                substring(up.ident_code from 'legal_unit_(.*)_raw') = rdi.ident_type_code AND
                up.ident_value = rdi.ident_value
        ),
        -- Step 1: Resolve legal_unit_id from identifiers and collect metadata
        RowChecks AS (
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
            LEFT JOIN ResolvedIdents ri ON tr.data_row_id = ri.data_row_id
            JOIN public.%4$I dt ON dt.row_id = tr.data_row_id
            GROUP BY tr.data_row_id, dt.operation, dt.valid_from, dt.valid_until
        ),
        -- OPTIMIZATION: Pre-calculate range_agg for all involved legal units ONCE
        -- This replaces the correlated subquery that ran for every row
        LegalUnitCoverage AS (
            SELECT
                lu.id AS legal_unit_id,
                range_agg(lu.valid_range) AS coverage
            FROM public.legal_unit lu
            WHERE lu.id IN (SELECT DISTINCT resolved_lu_id FROM RowChecks WHERE resolved_lu_id IS NOT NULL)
            GROUP BY lu.id
        ),
        -- Step 2: Check errors - resolve LU first, then validate temporal coverage
        -- OPTIMIZED: Uses pre-calculated LegalUnitCoverage instead of correlated subquery
        Errors AS (
            SELECT
                rc.data_row_id,
                rc.resolved_lu_id,
                CASE
                    -- Error 1: No identifier provided (for non-update operations)
                    WHEN rc.operation != 'update' AND (rc.checks->>'num_idents_provided')::int = 0 
                        THEN (SELECT jsonb_object_agg(key, 'Missing legal unit identifier.') FROM unnest(%3$L::TEXT[] || ARRAY[%2$L]) AS key)
                    -- Error 2: Identifier provided but LU not found
                    WHEN (rc.checks->>'num_idents_provided')::int > 0 AND (rc.checks->>'found_lu')::int = 0 
                        THEN (SELECT jsonb_object_agg(key, 'Legal unit not found with provided identifiers.') FROM jsonb_array_elements_text(COALESCE(rc.checks->'provided_input_ident_codes', '["%2$s"]'::jsonb)) AS key)
                    -- Error 3: Multiple different LUs resolved from identifiers
                    WHEN (rc.checks->>'distinct_lu_ids')::int > 1 
                        THEN (SELECT jsonb_object_agg(key, 'Provided identifiers resolve to different Legal Units.') FROM jsonb_array_elements_text(COALESCE(rc.checks->'provided_input_ident_codes', '["%2$s"]'::jsonb)) AS key)
                    -- Error 4: LU resolved but establishment validity not covered by LU validity
                    -- OPTIMIZED: Join with pre-calculated coverage instead of correlated subquery
                    WHEN rc.resolved_lu_id IS NOT NULL 
                         AND NOT daterange(rc.est_valid_from, rc.est_valid_until, '[)') <@ luc.coverage
                        THEN (SELECT jsonb_object_agg(key, 'Establishment validity [' || rc.est_valid_from || ', ' || COALESCE(rc.est_valid_until::text, 'infinity') || ') not covered by legal unit validity.') FROM jsonb_array_elements_text(COALESCE(rc.checks->'provided_input_ident_codes', '["%2$s"]'::jsonb)) AS key)
                    ELSE NULL
                END as errors_jsonb
            FROM RowChecks rc
            LEFT JOIN LegalUnitCoverage luc ON luc.legal_unit_id = rc.resolved_lu_id
        ),
        ResolvedLinks AS (
            SELECT DISTINCT ON (rc.data_row_id)
                   rc.data_row_id, rc.resolved_lu_id, dt.establishment_id AS current_establishment_id,
                   dt.row_id AS original_data_table_row_id, dt.valid_from AS est_valid_from, dt.valid_until AS est_valid_until
            FROM RowChecks rc JOIN public.%4$I dt ON rc.data_row_id = dt.row_id
            WHERE rc.resolved_lu_id IS NOT NULL
        ),
        -- This set of CTEs correctly identifies the primary establishment for a legal unit,
        -- even when the import batch contains multiple non-overlapping time periods for the same LU.
        -- It works by identifying "islands" of overlapping/adjacent time periods and selecting
        -- the first candidate within each island.
        PrimaryCandidates AS (
            SELECT
                rl.*,
                (NOT EXISTS (
                    SELECT 1 FROM public.establishment est
                    WHERE est.legal_unit_id = rl.resolved_lu_id AND est.primary_for_legal_unit = TRUE
                      AND est.id IS DISTINCT FROM rl.current_establishment_id
                      AND public.from_until_overlaps(est.valid_from, est.valid_until, rl.est_valid_from, rl.est_valid_until)
                )) AS is_primary_candidate
            FROM ResolvedLinks rl
        ),
        -- Identify the start of each new "island" of time periods. An island starts when an interval
        -- begins after the maximum end time of all preceding intervals for that legal unit.
        TimeIslands AS (
            SELECT
                *,
                MAX(est_valid_until) OVER (
                    PARTITION BY resolved_lu_id
                    ORDER BY est_valid_from, est_valid_until, original_data_table_row_id
                    ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
                ) as max_prev_until
            FROM PrimaryCandidates
            WHERE is_primary_candidate
        ),
        IslandGroups AS (
            SELECT
                data_row_id,
                -- A cumulative sum of the "is_island_start" flag creates a unique ID for each group.
                SUM(CASE WHEN est_valid_from >= COALESCE(max_prev_until, '-infinity'::date) THEN 1 ELSE 0 END) OVER (
                    PARTITION BY resolved_lu_id
                    ORDER BY est_valid_from, est_valid_until, original_data_table_row_id
                ) AS island_id
            FROM TimeIslands
        ),
        -- Finally, rank candidates within each island using the original file order for determinism.
        RankedForPrimary AS (
            SELECT
                pc.data_row_id,
                pc.is_primary_candidate,
                ROW_NUMBER() OVER (
                    PARTITION BY pc.resolved_lu_id, ig.island_id
                    ORDER BY pc.original_data_table_row_id
                ) as row_num
            FROM PrimaryCandidates pc
            LEFT JOIN IslandGroups ig ON pc.data_row_id = ig.data_row_id
        )
        INSERT INTO temp_precalc (data_row_id, resolved_lu_id, primary_for_legal_unit, errors_jsonb)
        SELECT
            tr.data_row_id,
            err.resolved_lu_id,  -- Keep LU ID even for errors (helps debugging)
            (rfp.is_primary_candidate AND rfp.row_num = 1) AS primary_for_legal_unit,
            err.errors_jsonb
        FROM temp_relevant_rows tr
        LEFT JOIN Errors err ON tr.data_row_id = err.data_row_id
        LEFT JOIN RankedForPrimary rfp ON tr.data_row_id = rfp.data_row_id;
    $$, v_unpivot_sql, v_fallback_error_key, v_error_keys_to_clear_arr, v_data_table_name);
    RAISE DEBUG '[Job %] analyse_link_establishment_to_legal_unit: Populating pre-calculation table with SQL: %', p_job_id, v_sql;
    EXECUTE v_sql;
    RAISE DEBUG '[Job %] Holistic pre-calculation phase complete.', p_job_id;

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
    RAISE DEBUG '[Job %] analyse_link_establishment_to_legal_unit (Hybrid): Unconditionally advancing priority for all applicable rows with SQL: %', p_job_id, v_sql;
    EXECUTE v_sql;
    
    v_duration_ms := (EXTRACT(EPOCH FROM (clock_timestamp() - v_start_time)) * 1000);
    RAISE DEBUG '[Job %] analyse_link_establishment_to_legal_unit (Hybrid): Finished in % ms.', p_job_id, round(v_duration_ms, 2);
END;
$analyse_link_establishment_to_legal_unit$;


END;

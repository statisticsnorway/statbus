```sql
CREATE OR REPLACE PROCEDURE import.analyse_link_establishment_to_legal_unit(IN p_job_id integer, IN p_batch_seq integer, IN p_step_code text)
 LANGUAGE plpgsql
AS $procedure$
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
$procedure$
```

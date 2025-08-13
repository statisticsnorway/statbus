-- Implements the analyse procedure for link_establishment_to_legal_unit import step.

BEGIN;

-- Procedure to analyse the link between establishment and legal unit (Batch Oriented)
-- This procedure dynamically reads legal_unit_* identifier columns based on the snapshot
-- and attempts to resolve them to a single legal_unit_id.
CREATE OR REPLACE PROCEDURE import.analyse_link_establishment_to_legal_unit(p_job_id INT, p_batch_row_ids INTEGER[], p_step_code TEXT)
LANGUAGE plpgsql AS $analyse_link_establishment_to_legal_unit$
DECLARE
    v_job public.import_job;
    v_step public.import_step;
    v_snapshot JSONB;
    v_data_table_name TEXT;
    v_relevant_row_ids INTEGER[]; -- For holistic execution
    v_link_data_cols JSONB;
    v_col_rec RECORD;
    v_sql TEXT;
    v_update_count INT := 0;
    v_error_count INT := 0;
    v_skipped_update_count INT := 0;
    v_unpivot_sql TEXT := ''; 
    v_add_separator BOOLEAN := FALSE; 
    v_error_row_ids INTEGER[] := ARRAY[]::INTEGER[];
    v_error_keys_to_clear_arr TEXT[] := ARRAY[]::TEXT[]; 
    v_fallback_error_key TEXT;
BEGIN
    -- This is a HOLISTIC procedure. It is called once and processes all relevant rows for this step.
    -- The p_batch_row_ids parameter is ignored (it will be NULL).
    RAISE DEBUG '[Job %] analyse_link_establishment_to_legal_unit (Holistic): Starting analysis.', p_job_id;

    -- Get job details and snapshot
    SELECT * INTO v_job FROM public.import_job ij WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name; -- Assign separately
    v_link_data_cols := v_job.definition_snapshot->'import_data_column_list'; -- Read from snapshot column

    IF v_link_data_cols IS NULL OR jsonb_typeof(v_link_data_cols) != 'array' THEN
        RAISE EXCEPTION '[Job %] Failed to load valid import_data_column_list from definition_snapshot', p_job_id;
    END IF;

    -- Find the target step details from the snapshot
    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = 'link_establishment_to_legal_unit';
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] link_establishment_to_legal_unit step not found in snapshot', p_job_id;
    END IF;

    -- Holistic execution: materialize relevant rows for this step to avoid holding giant arrays.
    CREATE TEMP TABLE temp_relevant_rows (data_row_id INTEGER PRIMARY KEY) ON COMMIT DROP;
    EXECUTE format($$INSERT INTO temp_relevant_rows
                     SELECT row_id FROM public.%1$I
                     WHERE state = %2$L AND last_completed_priority < %3$L$$,
                    v_data_table_name /* %1$I */, 'analysing'::public.import_data_state /* %2$L */, v_step.priority /* %3$L */);
    EXECUTE 'SELECT COUNT(*) FROM temp_relevant_rows' INTO v_update_count;

    RAISE DEBUG '[Job %] analyse_link_establishment_to_legal_unit: Holistic execution. Found % rows to process for this step.',
                p_job_id, COALESCE(v_update_count, 0);
    
    IF COALESCE(v_update_count, 0) = 0 THEN
        RAISE DEBUG '[Job %] analyse_link_establishment_to_legal_unit: No relevant rows to process.', p_job_id;
        DROP TABLE IF EXISTS temp_relevant_rows;
        RETURN;
    END IF;

    -- Filter data columns relevant to this step (purpose = 'source_input' and step_id matches)
    SELECT jsonb_agg(value) INTO v_link_data_cols
    FROM jsonb_array_elements(v_link_data_cols) value
    WHERE (value->>'step_id')::int = v_step.id AND value->>'purpose' = 'source_input';

    IF v_link_data_cols IS NULL OR jsonb_array_length(v_link_data_cols) = 0 THEN
         RAISE DEBUG '[Job %] analyse_link_establishment_to_legal_unit: No legal_unit_* source_input data columns found in snapshot for step %. Skipping analysis.', p_job_id, v_step.id;
         EXECUTE format($$UPDATE public.%1$I dt SET last_completed_priority = %2$L WHERE EXISTS (SELECT 1 FROM temp_relevant_rows tr WHERE tr.data_row_id = dt.row_id)$$,
                        v_data_table_name /* %1$I */, v_step.priority /* %2$L */);
         RETURN;
    END IF;

    -- Populate v_error_keys_to_clear_arr with all source_input column names for this step
    SELECT array_agg(value->>'column_name') INTO v_error_keys_to_clear_arr
    FROM jsonb_array_elements(v_link_data_cols) value;
    v_error_keys_to_clear_arr := COALESCE(v_error_keys_to_clear_arr, ARRAY[]::TEXT[]);
    RAISE DEBUG '[Job %] analyse_link_establishment_to_legal_unit: Error keys to clear for this step: %', p_job_id, v_error_keys_to_clear_arr;

    -- Pre-calculate the fallback error key (moved earlier)
    v_fallback_error_key := COALESCE(v_error_keys_to_clear_arr[1], 'link_establishment_to_legal_unit_error');

    -- Step 1: Unpivot provided identifiers and lookup legal units
    CREATE TEMP TABLE temp_unpivoted_lu_idents (
        data_row_id INTEGER,
        ident_code TEXT, -- e.g., 'legal_unit_tax_ident'
        ident_value TEXT,
        ident_type_id INT,
        resolved_lu_id INT
    ) ON COMMIT DROP;

    -- Removed inner DECLARE block
    BEGIN
        FOR v_col_rec IN SELECT value->>'column_name' as col_name
                         FROM jsonb_array_elements(v_link_data_cols)
        LOOP
            IF v_add_separator THEN v_unpivot_sql := v_unpivot_sql || ' UNION ALL '; END IF;
            v_unpivot_sql := v_unpivot_sql || format(
                $$SELECT dt.row_id AS data_row_id, %1$L AS ident_code, dt.%2$I AS ident_value
                 FROM public.%3$I dt
                 JOIN temp_relevant_rows tr ON tr.data_row_id = dt.row_id
                 WHERE dt.%4$I IS NOT NULL AND dt.action != 'skip'$$, -- Exclude pre-skipped
                 v_col_rec.col_name,      /* %1$L */
                 v_col_rec.col_name,      /* %2$I */
                 v_data_table_name,       /* %3$I */
                 v_col_rec.col_name       /* %4$I */
            );
            v_add_separator := TRUE;
        END LOOP;
    END;

    IF v_unpivot_sql = '' THEN
        RAISE DEBUG '[Job %] analyse_link_establishment_to_legal_unit: No legal unit identifier values found in batch. Skipping further analysis.', p_job_id;
        -- Mark all rows in batch as error because no identifier was provided
         v_sql := format($$
            UPDATE public.%1$I dt SET
                state = %2$L,
                action = 'skip', -- Ensure action is skip
                error = COALESCE(dt.error, '{}'::jsonb) || 
                        (SELECT jsonb_object_agg(key_name, 'Missing legal unit identifier.') 
                         FROM unnest(COALESCE(%3$L::TEXT[], ARRAY[%4$L])) AS key_name),
                last_completed_priority = %5$L -- Advance priority
            WHERE EXISTS (SELECT 1 FROM temp_relevant_rows tr WHERE tr.data_row_id = dt.row_id);
        $$, 
            v_data_table_name,          -- %1$I
            'error',                    -- %2$L
            v_error_keys_to_clear_arr,  -- %3$L
            v_fallback_error_key,       -- %4$L
            v_step.priority             -- %5$L
        );
        EXECUTE v_sql;
        GET DIAGNOSTICS v_error_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_link_establishment_to_legal_unit (Batch): Finished analysis for batch. Errors: % (all rows missing identifiers)', p_job_id, v_error_count;
        DROP TABLE IF EXISTS temp_relevant_rows;
        RETURN;
    END IF;

    v_sql := format($$
        INSERT INTO temp_unpivoted_lu_idents (data_row_id, ident_code, ident_value, ident_type_id, resolved_lu_id)
        SELECT
            up.data_row_id, up.ident_code, up.ident_value, xit.id, xi.legal_unit_id -- Select legal_unit_id directly from xi
        FROM ( %s ) up
        JOIN public.external_ident_type xit ON xit.code = substring(up.ident_code from 'legal_unit_(.*)') -- Extract type code
        LEFT JOIN public.external_ident xi ON xi.type_id = xit.id AND xi.ident = up.ident_value AND xi.legal_unit_id IS NOT NULL; -- Only match LU links and get id from xi
    $$, v_unpivot_sql);
    RAISE DEBUG '[Job %] analyse_link_establishment_to_legal_unit: Unpivoting and looking up identifiers: %', p_job_id, v_sql;
    EXECUTE v_sql;

    -- Log count of unpivoted identifiers
    GET DIAGNOSTICS v_update_count = ROW_COUNT;
    RAISE DEBUG '[Job %] analyse_link_establishment_to_legal_unit: Inserted % rows into temp_unpivoted_lu_idents.', p_job_id, v_update_count;
    IF v_update_count > 0 THEN
        DECLARE
            sample_ident RECORD;
        BEGIN
            FOR sample_ident IN SELECT * FROM temp_unpivoted_lu_idents LIMIT 3 LOOP
                RAISE DEBUG '[Job %] analyse_link_establishment_to_legal_unit: Sample temp_unpivoted_lu_idents: data_row_id=%, ident_code=%, ident_value=%, resolved_lu_id=%', p_job_id, sample_ident.data_row_id, sample_ident.ident_code, sample_ident.ident_value, sample_ident.resolved_lu_id;
            END LOOP;
        END;
    END IF;

    -- Step 2: Identify and Aggregate Errors
    CREATE TEMP TABLE temp_batch_errors (data_row_id INTEGER PRIMARY KEY, error_jsonb JSONB) ON COMMIT DROP;

    -- Check for rows missing any identifier, inconsistencies (multiple LUs found), or not found
    -- v_fallback_error_key is already calculated
    v_sql := format($$
        WITH RowChecks AS (
            SELECT
                orig.data_row_id,
                COUNT(tui.data_row_id) AS num_idents_provided, -- Counts how many entries in temp_unpivoted_lu_idents match this row_id
                COUNT(DISTINCT tui.resolved_lu_id) FILTER (WHERE tui.resolved_lu_id IS NOT NULL) AS distinct_lu_ids,
                MAX(CASE WHEN tui.resolved_lu_id IS NOT NULL THEN 1 ELSE 0 END) AS found_lu,
                array_agg(DISTINCT tui.ident_code) FILTER (WHERE tui.ident_value IS NOT NULL) as provided_input_ident_codes -- Get actual input column names used
            FROM temp_relevant_rows orig
            LEFT JOIN temp_unpivoted_lu_idents tui ON orig.data_row_id = tui.data_row_id
            GROUP BY orig.data_row_id
        )
        INSERT INTO temp_batch_errors (data_row_id, error_jsonb)
        SELECT
            rc.data_row_id,
            CASE
                WHEN rc.num_idents_provided = 0 THEN -- No identifiers provided at all
                    (SELECT jsonb_object_agg(key_name, 'Missing legal unit identifier.') FROM unnest(COALESCE(%2$L::TEXT[], ARRAY[%1$L])) AS key_name)
                WHEN rc.num_idents_provided > 0 AND rc.found_lu = 0 THEN -- Identifiers provided, but none resolved to an LU
                    (SELECT jsonb_object_agg(key_name, 'Legal unit not found with provided identifiers.') FROM unnest(COALESCE(rc.provided_input_ident_codes, ARRAY[%2$L])) AS key_name)
                WHEN rc.distinct_lu_ids > 1 THEN -- Identifiers provided resolved to multiple different LUs
                    (SELECT jsonb_object_agg(key_name, 'Provided identifiers resolve to different Legal Units.') FROM unnest(COALESCE(rc.provided_input_ident_codes, ARRAY[%2$L])) AS key_name)
                ELSE '{}'::jsonb -- No error for this specific check, should not be inserted by WHERE clause
            END
        FROM RowChecks rc
        WHERE rc.num_idents_provided = 0 OR (rc.num_idents_provided > 0 AND rc.found_lu = 0) OR rc.distinct_lu_ids > 1;
    $$, 
        v_fallback_error_key,    /* %1$L */
        v_error_keys_to_clear_arr /* %2$L */
    );
    RAISE DEBUG '[Job %] analyse_link_establishment_to_legal_unit: Identifying errors post-lookup: %', p_job_id, v_sql;
    EXECUTE v_sql;

    -- Step 3: Batch Update Error Rows
    BEGIN
        v_sql := format($$
            UPDATE public.%1$I dt SET
                state = %2$L,
                action = 'skip', -- Set action to skip if there's an error here
                error = COALESCE(dt.error, %3$L) || err.error_jsonb, -- Directly merge the error_jsonb from temp_batch_errors
                last_completed_priority = %4$L -- Set to current step's priority on error
            FROM temp_batch_errors err
            WHERE dt.row_id = err.data_row_id;
        $$, 
            v_data_table_name,            -- %1$I
            'error',                      -- %2$L
            '{}'::jsonb,                  -- %3$L
            v_step.priority               -- %4$L
        );
        RAISE DEBUG '[Job %] analyse_link_establishment_to_legal_unit: Updating error rows: %', p_job_id, v_sql;
        EXECUTE v_sql;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        v_error_count := v_update_count;
        SELECT array_agg(data_row_id) INTO v_error_row_ids FROM temp_batch_errors;
        RAISE DEBUG '[Job %] analyse_link_establishment_to_legal_unit: Marked % rows as error.', p_job_id, v_update_count;
    END;

    -- Step 4: Batch Update Success Rows with resolved legal_unit_id
    v_sql := format($$
        WITH ResolvedLinks AS (
            -- Get unique data_row_id to resolved_lu_id links from the current batch, excluding errored rows
            SELECT DISTINCT ON (tui.data_row_id)
                   tui.data_row_id,
                   tui.resolved_lu_id,
                   dt.establishment_id AS current_establishment_id, -- ID of the EST record in _data table
                   dt.row_id AS original_data_table_row_id, -- Used for ordering to pick the "first"
                   dt.derived_valid_after AS est_derived_valid_after, -- Use derived_valid_after
                   dt.derived_valid_to AS est_derived_valid_to
            FROM temp_unpivoted_lu_idents tui
            JOIN public.%1$I dt ON tui.data_row_id = dt.row_id
            WHERE tui.resolved_lu_id IS NOT NULL
              AND EXISTS (SELECT 1 FROM temp_relevant_rows tr WHERE tr.data_row_id = dt.row_id) AND dt.row_id != ALL($1)
        ),
        RankedForPrimary AS (
            SELECT
                rl.data_row_id,
                rl.resolved_lu_id,
                rl.current_establishment_id, -- Pass through the current EST ID
                rl.original_data_table_row_id,
                rl.est_derived_valid_after,
                rl.est_derived_valid_to,
                -- Check if any OTHER EST is already primary for this LU in the main DB table *during the current EST's validity period*
                NOT EXISTS (
                    SELECT 1 FROM public.establishment est
                    WHERE est.legal_unit_id = rl.resolved_lu_id
                      AND est.primary_for_legal_unit = TRUE
                      AND est.id IS DISTINCT FROM rl.current_establishment_id -- Exclude the current establishment itself
                      AND public.after_to_overlaps(est.valid_after, est.valid_to, rl.est_derived_valid_after, rl.est_derived_valid_to)
                ) AS no_overlapping_primary_in_db
            FROM ResolvedLinks rl
        )
        UPDATE public.%1$I dt SET
            legal_unit_id = rfp.resolved_lu_id,
            primary_for_legal_unit = (
                rfp.no_overlapping_primary_in_db
                AND
                NOT EXISTS (
                    SELECT 1
                    FROM RankedForPrimary other_rfp -- Self-referencing RankedForPrimary to check other batch items
                    WHERE other_rfp.resolved_lu_id = rfp.resolved_lu_id
                      AND other_rfp.original_data_table_row_id <> rfp.original_data_table_row_id -- Compare batch rows using their unique _data table row_id
                      AND other_rfp.original_data_table_row_id < rfp.original_data_table_row_id -- Prioritize by original_data_table_row_id if periods overlap
                      AND other_rfp.no_overlapping_primary_in_db -- The other item must also be a candidate (no DB conflict with *other* ESTs)
                      AND public.after_to_overlaps( -- Check if the other item's period overlaps with the current item's period
                          other_rfp.est_derived_valid_after, other_rfp.est_derived_valid_to,
                          rfp.est_derived_valid_after, rfp.est_derived_valid_to
                      )
                )
            ),
            last_completed_priority = %2$L,
            error = CASE WHEN (dt.error - %3$L::TEXT[]) = '{}'::jsonb THEN NULL ELSE (dt.error - %3$L::TEXT[]) END,
            state = %4$L
        FROM RankedForPrimary rfp
        WHERE dt.row_id = rfp.data_row_id; -- Join condition for UPDATE
    $$,
        v_data_table_name,                      /* %1$I */
        v_step.priority,                        /* %2$L */
        v_error_keys_to_clear_arr,              /* %3$L */
        'analysing'::public.import_data_state   /* %4$L */
    );
    RAISE DEBUG '[Job %] analyse_link_establishment_to_legal_unit: Updating success rows with resolved IDs and refined primary_for_legal_unit logic: %', p_job_id, v_sql;
    EXECUTE v_sql USING COALESCE(v_error_row_ids, ARRAY[]::INTEGER[]);
    GET DIAGNOSTICS v_update_count = ROW_COUNT;
    RAISE DEBUG '[Job %] analyse_link_establishment_to_legal_unit: Marked % rows as success for this target.', p_job_id, v_update_count;

    -- Log sample of updated linked_legal_unit_id in _data table
    IF v_update_count > 0 THEN
        DECLARE
            sample_data RECORD;
            v_sample_sql TEXT;
        BEGIN
            v_sample_sql := format($$
              SELECT row_id, legal_unit_id, primary_for_legal_unit, action, state, error
                FROM public.%1$I
               WHERE EXISTS (SELECT 1 FROM temp_relevant_rows tr WHERE tr.data_row_id = row_id)
                 AND legal_unit_id IS NOT NULL LIMIT 3
            $$, v_data_table_name  /* %1$I */);
            RAISE DEBUG '[Job %] analyse_link_establishment_to_legal_unit: Sample _data table after update: %', p_job_id, v_sample_sql;
            FOR sample_data IN EXECUTE v_sample_sql LOOP
                RAISE DEBUG '[Job %] analyse_link_establishment_to_legal_unit: Sample _data: row_id=%, lu_id=%, pflu=%, action=%, state=%, error=%', -- Changed linked_lu_id
                             p_job_id, sample_data.row_id, sample_data.legal_unit_id, sample_data.primary_for_legal_unit, sample_data.action, sample_data.state, sample_data.error;
            END LOOP;
        END;
    END IF;

    -- Update priority for rows that were initially skipped
    EXECUTE format($$
        UPDATE public.%1$I dt SET
            last_completed_priority = %2$L
        WHERE EXISTS (SELECT 1 FROM temp_relevant_rows tr WHERE tr.data_row_id = dt.row_id) AND dt.action = 'skip';
    $$, 
        v_data_table_name,          -- %1$I
        v_step.priority             -- %2$L
    );
    GET DIAGNOSTICS v_skipped_update_count = ROW_COUNT;
    RAISE DEBUG '[Job %] analyse_link_establishment_to_legal_unit: Updated last_completed_priority for % pre-skipped rows.', p_job_id, v_skipped_update_count;

    DROP TABLE IF EXISTS temp_unpivoted_lu_idents;
    DROP TABLE IF EXISTS temp_batch_errors;
    DROP TABLE IF EXISTS temp_relevant_rows;

    RAISE DEBUG '[Job %] analyse_link_establishment_to_legal_unit (Batch): Finished analysis for batch. Total errors in batch: %', p_job_id, v_error_count;
END;
$analyse_link_establishment_to_legal_unit$;


COMMIT;

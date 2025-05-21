-- Implements the analyse procedure for link_establishment_to_legal_unit import step.

BEGIN;

-- Procedure to analyse the link between establishment and legal unit (Batch Oriented)
-- This procedure dynamically reads legal_unit_* identifier columns based on the snapshot
-- and attempts to resolve them to a single legal_unit_id.
CREATE OR REPLACE PROCEDURE import.analyse_link_establishment_to_legal_unit(p_job_id INT, p_batch_row_ids BIGINT[], p_step_code TEXT)
LANGUAGE plpgsql AS $analyse_link_establishment_to_legal_unit$
DECLARE
    v_job public.import_job;
    v_step RECORD;
    v_snapshot JSONB;
    v_data_table_name TEXT;
    v_link_data_cols JSONB;
    v_col_rec RECORD;
    v_sql TEXT;
    v_update_count INT := 0;
    v_error_count INT := 0;
    v_skipped_update_count INT := 0;
    v_unpivot_sql TEXT := ''; 
    v_add_separator BOOLEAN := FALSE; 
    v_error_row_ids BIGINT[] := ARRAY[]::BIGINT[];
    v_error_keys_to_clear_arr TEXT[] := ARRAY['link_establishment_to_legal_unit'];
BEGIN
    RAISE DEBUG '[Job %] analyse_link_establishment_to_legal_unit (Batch): Starting analysis for % rows', p_job_id, array_length(p_batch_row_ids, 1);

    -- Get job details and snapshot
    SELECT * INTO v_job FROM public.import_job ij WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name; -- Assign separately
    v_link_data_cols := v_job.definition_snapshot->'import_data_column_list'; -- Read from snapshot column

    IF v_link_data_cols IS NULL OR jsonb_typeof(v_link_data_cols) != 'array' THEN
        RAISE EXCEPTION '[Job %] Failed to load valid import_data_column_list from definition_snapshot', p_job_id;
    END IF;

    -- Find the target step details
    SELECT * INTO v_step FROM public.import_step WHERE code = 'link_establishment_to_legal_unit';
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] link_establishment_to_legal_unit step not found', p_job_id;
    END IF;

    -- Filter data columns relevant to this step (purpose = 'source_input' and step_id matches)
    SELECT jsonb_agg(value) INTO v_link_data_cols
    FROM jsonb_array_elements(v_link_data_cols) value
    WHERE (value->>'step_id')::int = v_step.id AND value->>'purpose' = 'source_input';

    IF v_link_data_cols IS NULL OR jsonb_array_length(v_link_data_cols) = 0 THEN
         RAISE DEBUG '[Job %] analyse_link_establishment_to_legal_unit: No legal_unit_* source_input data columns found in snapshot for step %. Skipping analysis.', p_job_id, v_step.id;
         EXECUTE format($$UPDATE public.%I SET last_completed_priority = %L WHERE row_id = ANY(%L)$$,
                        v_data_table_name, v_step.priority, p_batch_row_ids);
         RETURN;
    END IF;

    -- Step 1: Unpivot provided identifiers and lookup legal units
    CREATE TEMP TABLE temp_unpivoted_lu_idents (
        data_row_id BIGINT,
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
                $$SELECT dt.row_id AS data_row_id, %L AS ident_code, dt.%I AS ident_value
                 FROM public.%I dt WHERE dt.%I IS NOT NULL AND dt.row_id = ANY(%L) AND dt.action != 'skip'$$, -- Exclude pre-skipped
                 v_col_rec.col_name, v_col_rec.col_name, v_data_table_name, v_col_rec.col_name, p_batch_row_ids
            );
            v_add_separator := TRUE;
        END LOOP;
    END;

    IF v_unpivot_sql = '' THEN
        RAISE DEBUG '[Job %] analyse_link_establishment_to_legal_unit: No legal unit identifier values found in batch. Skipping further analysis.', p_job_id;
        -- Mark all rows in batch as error because no identifier was provided
         v_sql := format($$
            UPDATE public.%I dt SET
                state = %L,
                error = jsonb_build_object('link_establishment_to_legal_unit', 'No legal unit identifier provided')
                -- last_completed_priority is preserved (not changed) on error
            WHERE dt.row_id = ANY(%L);
        $$, v_data_table_name, 'error', p_batch_row_ids);
        EXECUTE v_sql;
        GET DIAGNOSTICS v_error_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_link_establishment_to_legal_unit (Batch): Finished analysis for batch. Errors: % (all rows missing identifiers)', p_job_id, v_error_count;
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
    CREATE TEMP TABLE temp_batch_errors (data_row_id BIGINT PRIMARY KEY, error_jsonb JSONB) ON COMMIT DROP;

    -- Check for rows missing any identifier, inconsistencies (multiple LUs found), or not found
    v_sql := format($$
        WITH RowChecks AS (
            SELECT
                orig.data_row_id,
                COUNT(tui.data_row_id) AS num_idents_provided,
                COUNT(DISTINCT tui.resolved_lu_id) FILTER (WHERE tui.resolved_lu_id IS NOT NULL) AS distinct_lu_ids,
                MAX(CASE WHEN tui.resolved_lu_id IS NOT NULL THEN 1 ELSE 0 END) AS found_lu
            FROM (SELECT unnest(%L::BIGINT[]) as data_row_id) orig -- Ensure all original data_row_ids are checked.
            LEFT JOIN temp_unpivoted_lu_idents tui ON orig.data_row_id = tui.data_row_id
            GROUP BY orig.data_row_id
        )
        INSERT INTO temp_batch_errors (data_row_id, error_jsonb)
        SELECT
            data_row_id,
            jsonb_strip_nulls(jsonb_build_object(
                'missing_identifier', CASE WHEN num_idents_provided = 0 THEN true ELSE NULL END,
                'not_found', CASE WHEN num_idents_provided > 0 AND found_lu = 0 THEN true ELSE NULL END,
                'inconsistent_legal_unit', CASE WHEN distinct_lu_ids > 1 THEN true ELSE NULL END
            ))
        FROM RowChecks
        WHERE num_idents_provided = 0 OR (num_idents_provided > 0 AND found_lu = 0) OR distinct_lu_ids > 1;
    $$, p_batch_row_ids);
    RAISE DEBUG '[Job %] analyse_link_establishment_to_legal_unit: Identifying errors post-lookup: %', p_job_id, v_sql;
    EXECUTE v_sql;

    -- Step 3: Batch Update Error Rows
    -- DECLARE -- v_error_row_ids moved to main block
    --     v_error_row_ids BIGINT[];
    BEGIN
        v_sql := format($$
            UPDATE public.%I dt SET
                state = %L,
                action = 'skip', -- Set action to skip if there's an error here
                error = COALESCE(dt.error, %L) || jsonb_build_object('link_establishment_to_legal_unit', err.error_jsonb)
                -- last_completed_priority is preserved (not changed) on error
            FROM temp_batch_errors err
            WHERE dt.row_id = err.data_row_id;
        $$, v_data_table_name, 'error', '{}'::jsonb);
        RAISE DEBUG '[Job %] analyse_link_establishment_to_legal_unit: Updating error rows: %', p_job_id, v_sql;
        EXECUTE v_sql;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        v_error_count := v_update_count;
        SELECT array_agg(data_row_id) INTO v_error_row_ids FROM temp_batch_errors;
        RAISE DEBUG '[Job %] analyse_link_establishment_to_legal_unit: Marked % rows as error.', p_job_id, v_update_count;
    END;

    -- Step 4: Batch Update Success Rows with resolved legal_unit_id
    v_sql := format($$
        WITH resolved_lu AS (
            SELECT DISTINCT ON (data_row_id) data_row_id, resolved_lu_id
            FROM temp_unpivoted_lu_idents
            WHERE resolved_lu_id IS NOT NULL
        )
        UPDATE public.%I dt SET
            legal_unit_id = rlu.resolved_lu_id, 
            primary_for_legal_unit = TRUE, 
            last_completed_priority = %L,
            error = CASE WHEN (dt.error - %L::TEXT[]) = '{}'::jsonb THEN NULL ELSE (dt.error - %L::TEXT[]) END, -- Clear only this step's error key
            state = %L
        FROM resolved_lu rlu
        WHERE dt.row_id = rlu.data_row_id
          AND dt.row_id = ANY(%L) AND dt.row_id != ALL(%L); -- Update only non-error rows from the original batch
    $$, v_data_table_name, v_step.priority, v_error_keys_to_clear_arr, v_error_keys_to_clear_arr, 'analysing', p_batch_row_ids, COALESCE(v_error_row_ids, ARRAY[]::BIGINT[]));
    RAISE DEBUG '[Job %] analyse_link_establishment_to_legal_unit: Updating success rows with resolved IDs and primary_for_legal_unit: %', p_job_id, v_sql;
    EXECUTE v_sql;
    GET DIAGNOSTICS v_update_count = ROW_COUNT;
    RAISE DEBUG '[Job %] analyse_link_establishment_to_legal_unit: Marked % rows as success for this target.', p_job_id, v_update_count;

    -- Log sample of updated linked_legal_unit_id in _data table
    IF v_update_count > 0 THEN
        DECLARE
            sample_data RECORD;
            v_sample_sql TEXT;
        BEGIN
            v_sample_sql := format(
                'SELECT row_id, legal_unit_id, primary_for_legal_unit, action, state, error FROM public.%I WHERE row_id = ANY(%L) AND legal_unit_id IS NOT NULL LIMIT 3', -- Changed linked_legal_unit_id
                v_data_table_name, p_batch_row_ids
            );
            RAISE DEBUG '[Job %] analyse_link_establishment_to_legal_unit: Sample _data table after update: %', p_job_id, v_sample_sql;
            FOR sample_data IN EXECUTE v_sample_sql LOOP
                RAISE DEBUG '[Job %] analyse_link_establishment_to_legal_unit: Sample _data: row_id=%, lu_id=%, pflu=%, action=%, state=%, error=%', -- Changed linked_lu_id
                             p_job_id, sample_data.row_id, sample_data.legal_unit_id, sample_data.primary_for_legal_unit, sample_data.action, sample_data.state, sample_data.error;
            END LOOP;
        END;
    END IF;

    DROP TABLE IF EXISTS temp_unpivoted_lu_idents;
    DROP TABLE IF EXISTS temp_batch_errors;

    -- Update priority for rows that were initially skipped
    EXECUTE format('
        UPDATE public.%I dt SET
            last_completed_priority = %L
        WHERE dt.row_id = ANY(%L) AND dt.action = ''skip'';
    ', v_data_table_name, v_step.priority, p_batch_row_ids);
    GET DIAGNOSTICS v_skipped_update_count = ROW_COUNT;
    RAISE DEBUG '[Job %] analyse_link_establishment_to_legal_unit: Updated last_completed_priority for % pre-skipped rows.', p_job_id, v_skipped_update_count;

    RAISE DEBUG '[Job %] analyse_link_establishment_to_legal_unit (Batch): Finished analysis for batch. Total errors in batch: %', p_job_id, v_error_count;
END;
$analyse_link_establishment_to_legal_unit$;


COMMIT;

```sql
CREATE OR REPLACE PROCEDURE admin.analyse_external_idents(IN p_job_id integer, IN p_batch_ctids tid[])
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_job public.import_job;
    v_step RECORD;
    v_snapshot JSONB;
    v_data_table_name TEXT;
    v_ident_data_cols JSONB;
    v_col_rec RECORD;
    v_sql TEXT;
    v_update_count INT := 0;
    v_error_count INT := 0; -- Placeholder, minimal validation here
    v_unpivot_sql TEXT;
    v_add_separator BOOLEAN;
BEGIN
    RAISE DEBUG '[Job %] analyse_external_idents (Batch): Starting analysis for % rows', p_job_id, array_length(p_batch_ctids, 1);

    -- Get job details and snapshot
    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name; -- Get table name from the job record
    v_ident_data_cols := v_job.definition_snapshot->'import_data_column_list'; -- Read from snapshot column

    IF v_ident_data_cols IS NULL OR jsonb_typeof(v_ident_data_cols) != 'array' THEN
        RAISE EXCEPTION '[Job %] Failed to load valid import_data_column_list from definition_snapshot', p_job_id;
    END IF;

    -- Find the target step details
    SELECT * INTO v_step FROM public.import_step WHERE code = 'external_idents';
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] external_idents target not found', p_job_id;
    END IF;

    -- Filter data columns relevant to this step (purpose = 'source_input' and step_id matches)
    SELECT jsonb_agg(value) INTO v_ident_data_cols
    FROM jsonb_array_elements(v_ident_data_cols) value
    WHERE (value->>'step_id')::int = v_step.id AND value->>'purpose' = 'source_input';

    IF v_ident_data_cols IS NULL OR jsonb_array_length(v_ident_data_cols) = 0 THEN
         RAISE DEBUG '[Job %] analyse_external_idents: No external ident source_input data columns found in snapshot for step %. Skipping analysis.', p_job_id, v_step.id;
         EXECUTE format('UPDATE public.%I SET last_completed_priority = %L WHERE ctid = ANY(%L)',
                        v_data_table_name, v_step.priority, p_batch_ctids);
         RETURN;
    END IF;

    -- Step 1: Unpivot provided identifiers and lookup existing units
    CREATE TEMP TABLE temp_unpivoted_idents (
        data_ctid TID,
        ident_code TEXT,
        ident_value TEXT,
        ident_type_id INT,
        resolved_lu_id INT,
        resolved_est_id INT
    ) ON COMMIT DROP;

    v_unpivot_sql := '';
    v_add_separator := FALSE;
    FOR v_col_rec IN SELECT value->>'column_name' as col_name
                     FROM jsonb_array_elements(v_ident_data_cols)
    LOOP
        IF v_add_separator THEN v_unpivot_sql := v_unpivot_sql || ' UNION ALL '; END IF;
        v_unpivot_sql := v_unpivot_sql || format(
            'SELECT dt.ctid, %L AS ident_code, dt.%I AS ident_value
             FROM public.%I dt WHERE dt.%I IS NOT NULL AND dt.ctid = ANY(%L)',
             v_col_rec.col_name, v_col_rec.col_name, v_data_table_name, v_col_rec.col_name, p_batch_ctids
        );
        v_add_separator := TRUE;
    END LOOP;

    IF v_unpivot_sql = '' THEN
        RAISE DEBUG '[Job %] analyse_external_idents: No external ident values found in batch. Skipping further analysis.', p_job_id;
        -- Mark all rows in batch as error because no identifier was provided (unless it's an update_only job?)
        -- For now, assume identifier is required.
         v_sql := format('
            UPDATE public.%I dt SET
                state = %L,
                error = jsonb_build_object(''external_idents'', ''No identifier provided''),
                last_completed_priority = %L
            WHERE dt.ctid = ANY(%L);
        ', v_data_table_name, 'error', v_step.priority - 1, p_batch_ctids);
        EXECUTE v_sql;
        GET DIAGNOSTICS v_error_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_external_idents (Batch): Finished analysis for batch. Errors: % (all rows missing identifiers)', p_job_id, v_error_count;
        RETURN;
    END IF;

    v_sql := format($$
        INSERT INTO temp_unpivoted_idents (data_ctid, ident_code, ident_value, ident_type_id, resolved_lu_id, resolved_est_id)
        SELECT
            up.ctid, up.ident_code, up.ident_value, xit.id, xifu.legal_unit_id, xifu.establishment_id
        FROM ( %s ) up
        JOIN public.external_ident_type xit ON xit.code = up.ident_code
        LEFT JOIN public.external_ident xi ON xi.type_id = xit.id AND xi.value = up.ident_value
        LEFT JOIN public.external_ident_for_unit xifu ON xifu.external_ident_id = xi.id;
    $$, v_unpivot_sql);
    RAISE DEBUG '[Job %] analyse_external_idents: Unpivoting and looking up identifiers: %', p_job_id, v_sql;
    EXECUTE v_sql;

    -- Step 2: Identify and Aggregate Errors
    CREATE TEMP TABLE temp_batch_errors (data_ctid TID PRIMARY KEY, error_jsonb JSONB) ON COMMIT DROP;

    -- Check for rows missing any identifier, inconsistencies, and ambiguity
    v_sql := format($$
        WITH RowChecks AS (
            SELECT
                orig.data_ctid, -- Renamed from orig.ctid
                COUNT(tui.ctid) AS num_idents_provided,
                COUNT(DISTINCT tui.resolved_lu_id) FILTER (WHERE tui.resolved_lu_id IS NOT NULL) AS distinct_lu_ids,
                COUNT(DISTINCT tui.resolved_est_id) FILTER (WHERE tui.resolved_est_id IS NOT NULL) AS distinct_est_ids,
                MAX(CASE WHEN tui.resolved_lu_id IS NOT NULL THEN 1 ELSE 0 END) AS has_lu_id,
                MAX(CASE WHEN tui.resolved_est_id IS NOT NULL THEN 1 ELSE 0 END) AS has_est_id
            FROM (SELECT unnest(%L::TID[]) as data_ctid) orig -- Renamed alias here
            LEFT JOIN temp_unpivoted_idents tui ON orig.data_ctid = tui.ctid -- Join uses renamed alias
            GROUP BY orig.data_ctid -- Group by uses renamed alias
        )
        INSERT INTO temp_batch_errors (ctid, error_jsonb) -- Target column in temp_batch_errors is still 'ctid'
        SELECT
            rc.data_ctid, -- Select the renamed column from RowChecks for insertion
            jsonb_strip_nulls(jsonb_build_object(
                ''missing_identifier'', CASE WHEN rc.num_idents_provided = 0 THEN true ELSE NULL END,
                ''inconsistent_legal_unit'', CASE WHEN rc.distinct_lu_ids > 1 THEN true ELSE NULL END,
                ''inconsistent_establishment'', CASE WHEN rc.distinct_est_ids > 1 THEN true ELSE NULL END,
                ''ambiguous_unit_type'', CASE WHEN rc.has_lu_id = 1 AND rc.has_est_id = 1 THEN true ELSE NULL END
            ))
        FROM RowChecks rc -- Added alias for RowChecks for clarity
        WHERE rc.num_idents_provided = 0 OR rc.distinct_lu_ids > 1 OR rc.distinct_est_ids > 1 OR (rc.has_lu_id = 1 AND rc.has_est_id = 1);
    $$, p_batch_ctids);
    RAISE DEBUG '[Job %] analyse_external_idents: Identifying errors post-lookup: %', p_job_id, v_sql;
    EXECUTE v_sql;

    -- Step 3: Batch Update Error Rows
    DECLARE
        v_error_ctids TID[];
    BEGIN
        v_sql := format('
            UPDATE public.%I dt SET
                state = %L,
                error = COALESCE(dt.error, %L) || jsonb_build_object(''external_idents'', err.error_jsonb),
                last_completed_priority = %L
            FROM temp_batch_errors err
            WHERE dt.ctid = err.ctid;
        ', v_data_table_name, 'error', '{}'::jsonb, v_step.priority - 1);
        RAISE DEBUG '[Job %] analyse_external_idents: Updating error rows: %', p_job_id, v_sql;
        EXECUTE v_sql;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        v_error_count := v_update_count;
        SELECT array_agg(ctid) INTO v_error_ctids FROM temp_batch_errors;
        RAISE DEBUG '[Job %] analyse_external_idents: Marked % rows as error.', p_job_id, v_update_count;
    END;

    -- Step 4: Batch Update Success Rows with resolved IDs
    v_sql := format('
        WITH resolved_units AS (
            SELECT DISTINCT ON (ctid)
                   ctid,
                   resolved_lu_id,
                   resolved_est_id
            FROM temp_unpivoted_idents
            WHERE resolved_lu_id IS NOT NULL OR resolved_est_id IS NOT NULL
        )
        UPDATE public.%I dt SET
            legal_unit_id = ru.resolved_lu_id,
            establishment_id = ru.resolved_est_id,
            last_completed_priority = %L,
            error = NULL, -- Clear errors if successful now
            state = %L
        FROM resolved_units ru
        WHERE dt.ctid = ru.ctid
          AND dt.ctid = ANY(%L) AND dt.ctid != ALL(%L); -- Update only non-error rows from the original batch
    ', v_data_table_name, v_step.priority, 'analysing', p_batch_ctids, COALESCE(v_error_ctids, ARRAY[]::TID[]));
    RAISE DEBUG '[Job %] analyse_external_idents: Updating success rows with resolved IDs: %', p_job_id, v_sql;
    EXECUTE v_sql;
    GET DIAGNOSTICS v_update_count = ROW_COUNT;
    RAISE DEBUG '[Job %] analyse_external_idents: Marked % rows as success for this target.', p_job_id, v_update_count;

    -- Step 5: Update rows that had identifiers but none resolved (treat as success for this step, but no ID)
    v_sql := format($$
        UPDATE public.%I dt SET
            last_completed_priority = %L,
            error = NULL,
            state = %L
        WHERE dt.ctid = ANY(%L)
          AND dt.ctid != ALL(%L) -- Exclude rows already marked as error
          AND dt.legal_unit_id IS NULL -- Exclude rows already successfully updated
          AND dt.establishment_id IS NULL;
    $$, v_data_table_name, v_step.priority, 'analysing', p_batch_ctids, COALESCE(v_error_ctids, ARRAY[]::TID[]));
     RAISE DEBUG '[Job %] analyse_external_idents: Updating rows with unresolved identifiers: %', p_job_id, v_sql;
    EXECUTE v_sql;


    RAISE DEBUG '[Job %] analyse_external_idents (Batch): Finished analysis for batch. Total errors in batch: %', p_job_id, v_error_count;
END;
$procedure$
```

BEGIN;

CREATE OR REPLACE FUNCTION import.batch_insert_or_replace_generic_valid_time_table(
    p_target_schema_name TEXT,
    p_target_table_name TEXT,
    p_source_schema_name TEXT,
    p_source_table_name TEXT,
    p_source_row_id_column_name TEXT, -- Name of the column in source table that uniquely identifies the row (e.g., 'row_id' from _data table)
    p_unique_columns JSONB, -- For identifying existing ID if input ID is null. Format: '[ "col_name_1", ["comp_col_a", "comp_col_b"] ]'
    p_temporal_columns TEXT[], -- Must be ARRAY['valid_after_col_name', 'valid_to_col_name'] using (exclusive_start, inclusive_end] interval
    p_ephemeral_columns TEXT[], -- Columns to exclude from equivalence check but keep in insert/update
    p_generated_columns_override TEXT[] DEFAULT NULL, -- Explicit list of DB-generated columns (e.g., 'id' if serial/identity)
    p_id_column_name TEXT DEFAULT 'id', -- Name of the primary key / ID column in the target table
    p_target_valid_from_col_name TEXT DEFAULT NULL -- NEW: Name of the target's 'valid_from' if 'valid_after' is generated
)
RETURNS TABLE (
    source_row_id BIGINT, -- Changed from input_row_index, assuming BIGINT for import job row_ids
    upserted_record_id INT,
    status TEXT,
    error_message TEXT
)
LANGUAGE plpgsql VOLATILE AS $batch_insert_or_replace_generic_valid_time_table$
DECLARE
    v_input_row_record RECORD; -- Holds a full row from the source table
    v_current_source_row_id BIGINT;
    v_existing_id INT;
    v_existing_era_record RECORD; -- To hold a full row from the target table
    v_result_id INT;

    v_source_record_jsonb JSONB; -- Renamed from v_new_record_for_processing
    v_existing_era_jsonb JSONB;
    
    v_source_valid_after DATE; -- Date from source record
    v_source_valid_to DATE;   -- Date from source record

    v_adjusted_valid_from DATE; -- Used for modifying existing records (for splitting)
    v_adjusted_valid_to DATE;   -- Used for modifying existing records (for splitting)
    v_source_record_handled_by_merge BOOLEAN; -- Tracks if the source record is fully merged

    v_equivalent_data JSONB;
    v_equivalent_clause TEXT;
    v_identifying_clause TEXT;
    v_existing_query TEXT;
    v_delete_existing_sql TEXT;
    v_identifying_query TEXT;
    v_generated_columns TEXT[];
    v_source_query TEXT;
    v_sql TEXT;

    v_valid_after_col TEXT; -- Renamed from v_valid_from_col
    v_valid_to_col TEXT;

    v_err_context TEXT;
    v_loop_error_message TEXT;
    v_loop_var TEXT;

    v_target_table_actual_columns TEXT[]; -- Holds actual column names of the target table
    v_source_target_id_alias TEXT;
BEGIN
    IF array_length(p_temporal_columns, 1) != 2 THEN
        RAISE EXCEPTION 'p_temporal_columns must contain exactly two column names (e.g., valid_after, valid_to)';
    END IF;
    v_valid_after_col := p_temporal_columns[1]; -- Renamed
    v_valid_to_col := p_temporal_columns[2];

    -- Get actual column names for the target table
    EXECUTE format(
        'SELECT array_agg(column_name::TEXT) FROM information_schema.columns WHERE table_schema = %L AND table_name = %L',
        p_target_schema_name, p_target_table_name
    ) INTO v_target_table_actual_columns;

    IF v_target_table_actual_columns IS NULL OR array_length(v_target_table_actual_columns, 1) IS NULL THEN
        RAISE EXCEPTION 'Could not retrieve column names for target table %.%', p_target_schema_name, p_target_table_name;
    END IF;
    RAISE DEBUG '[batch_replace] Target table columns for %.%: %', p_target_schema_name, p_target_table_name, v_target_table_actual_columns;

    -- Determine generated columns for the target table
    IF p_generated_columns_override IS NOT NULL THEN
        v_generated_columns := p_generated_columns_override;
    ELSE
        EXECUTE format(
            'SELECT array_agg(a.attname) '
            'FROM pg_catalog.pg_attribute AS a '
            'WHERE a.attrelid = ''%I.%I''::regclass '
            '  AND a.attnum > 0 AND NOT a.attisdropped '
            '  AND (pg_catalog.pg_get_serial_sequence(a.attrelid::regclass::text, a.attname) IS NOT NULL '
            '    OR a.attidentity <> '''' OR a.attgenerated <> '''' '
            '    OR EXISTS (SELECT FROM pg_catalog.pg_constraint AS _c '
            '               WHERE _c.conrelid = a.attrelid AND _c.contype = ''p'' AND _c.conkey @> ARRAY[a.attnum]))',
            p_target_schema_name, p_target_table_name
        ) INTO v_generated_columns;
    END IF;
    v_generated_columns := COALESCE(v_generated_columns, ARRAY[]::TEXT[]);
    RAISE DEBUG '[batch_replace] Generated columns for %.%: %', p_target_schema_name, p_target_table_name, v_generated_columns;

    -- Check if source table has a 'target_id' column to alias to p_id_column_name
    SELECT column_name INTO v_source_target_id_alias
    FROM information_schema.columns
    WHERE table_schema = p_source_schema_name AND table_name = p_source_table_name AND column_name = 'target_id';

    IF v_source_target_id_alias IS NOT NULL THEN
        v_source_query := format('SELECT src.*, src.target_id AS %I FROM %I.%I src', p_id_column_name, p_source_schema_name, p_source_table_name);
        RAISE DEBUG '[batch_replace] Source query (with target_id aliased to %I): %', p_id_column_name, v_source_query;
    ELSE
        v_source_query := format('SELECT * FROM %I.%I', p_source_schema_name, p_source_table_name);
        RAISE DEBUG '[batch_replace] Source query (no target_id column found to alias): %', v_source_query;
    END IF;


    FOR v_input_row_record IN EXECUTE v_source_query
    LOOP
        v_source_record_jsonb := to_jsonb(v_input_row_record); -- Renamed
        IF NOT (v_source_record_jsonb ? p_source_row_id_column_name) THEN
            RAISE EXCEPTION 'Source row ID column % not found in source table %.%', p_source_row_id_column_name, p_source_schema_name, p_source_table_name;
        END IF;
        v_current_source_row_id := (v_source_record_jsonb->>p_source_row_id_column_name)::BIGINT;
        
        v_existing_id := (v_source_record_jsonb->>p_id_column_name)::INT;

        RAISE DEBUG '[batch_replace] Processing source_row_id %: %. Initial v_existing_id from source field %I: %', 
            v_current_source_row_id, v_source_record_jsonb, p_id_column_name, v_existing_id;

        BEGIN -- Start block for individual row processing
            -- Defer constraints locally for operations on this row's temporal slices
            EXECUTE 'SET CONSTRAINTS ALL DEFERRED';
            RAISE DEBUG '[batch_replace] SET CONSTRAINTS ALL DEFERRED for source_row_id %', v_current_source_row_id;

            v_loop_error_message := NULL;
            v_result_id := NULL;
            v_source_record_handled_by_merge := FALSE; -- Initialize for each source record

            v_source_valid_after := (v_source_record_jsonb->>v_valid_after_col)::DATE;
            v_source_valid_to    := (v_source_record_jsonb->>v_valid_to_col)::DATE;

            IF v_source_valid_after IS NULL OR v_source_valid_to IS NULL THEN
                RAISE EXCEPTION 'Temporal columns (%, %) cannot be null. Error in source row with % = %: %',
                    v_valid_after_col, v_valid_to_col, p_source_row_id_column_name, v_current_source_row_id, v_source_record_jsonb;
            END IF;

            IF v_existing_id IS NULL AND jsonb_array_length(p_unique_columns) > 0 THEN
                DECLARE
                    v_unique_key_element JSONB;
                    v_condition_parts TEXT[];
                    v_single_condition TEXT;
                BEGIN
                    v_identifying_clause := '';
                    FOR v_unique_key_element IN SELECT * FROM jsonb_array_elements(p_unique_columns)
                    LOOP
                        IF jsonb_typeof(v_unique_key_element) = 'string' THEN
                            v_single_condition := format('%I IS NOT DISTINCT FROM %L', v_unique_key_element#>>'{}', v_source_record_jsonb->>(v_unique_key_element#>>'{}'));
                        ELSIF jsonb_typeof(v_unique_key_element) = 'array' THEN
                            SELECT array_agg(format('%I IS NOT DISTINCT FROM %L', col_name, v_source_record_jsonb->>col_name))
                            INTO v_condition_parts
                            FROM jsonb_array_elements_text(v_unique_key_element) AS col_name;
                            v_single_condition := '(' || array_to_string(v_condition_parts, ' AND ') || ')';
                        ELSE
                            RAISE EXCEPTION 'Invalid format in p_unique_columns for source row %: %', v_current_source_row_id, v_unique_key_element;
                        END IF;

                        IF v_identifying_clause != '' THEN v_identifying_clause := v_identifying_clause || ' OR '; END IF;
                        v_identifying_clause := v_identifying_clause || v_single_condition;
                    END LOOP;

                    IF v_identifying_clause != '' THEN
                        v_identifying_query := format(
                            'SELECT %I FROM %I.%I WHERE %s LIMIT 1;',
                            p_id_column_name, p_target_schema_name, p_target_table_name, v_identifying_clause
                        );
                        RAISE DEBUG '[batch_replace] Identifying query for source row %: %', v_current_source_row_id, v_identifying_query;
                        EXECUTE v_identifying_query INTO v_existing_id;
                        RAISE DEBUG '[batch_replace] Identified v_existing_id via lookup for source row %: %', v_current_source_row_id, v_existing_id;
                    END IF;
                END;
            END IF;

            IF v_existing_id IS NOT NULL AND (v_source_record_jsonb->>p_id_column_name IS NULL OR (v_source_record_jsonb->>p_id_column_name)::INT IS DISTINCT FROM v_existing_id) THEN
                v_source_record_jsonb := jsonb_set(v_source_record_jsonb, ARRAY[p_id_column_name], to_jsonb(v_existing_id), true);
                RAISE DEBUG '[batch_replace] Set %I = % in v_source_record_jsonb for source row %.', p_id_column_name, v_existing_id, v_current_source_row_id;
            END IF;

            v_equivalent_data := '{}'::JSONB;
            DECLARE k TEXT;
            BEGIN
                FOR k IN SELECT * FROM jsonb_object_keys(v_source_record_jsonb) LOOP
                    IF k = ANY(v_target_table_actual_columns) THEN
                        IF NOT (k = ANY(p_temporal_columns)) AND
                           NOT (k = ANY(p_ephemeral_columns)) AND
                           NOT (k = p_id_column_name AND (p_id_column_name = ANY(v_generated_columns))) THEN
                           v_equivalent_data := jsonb_set(v_equivalent_data, ARRAY[k], v_source_record_jsonb->k);
                        END IF;
                    END IF;
                END LOOP;
            END;
            RAISE DEBUG '[batch_replace] Source row % Equivalence data: %', v_current_source_row_id, v_equivalent_data;

            SELECT string_agg(
                       format('tbl.%I IS NOT DISTINCT FROM %L', key, value),
                       ' AND '
                   )
            INTO v_equivalent_clause
            FROM jsonb_each_text(v_equivalent_data);

            IF v_equivalent_clause IS NULL OR v_equivalent_clause = '' THEN
                v_equivalent_clause := 'TRUE';
            END IF;
            RAISE DEBUG '[batch_replace] Source row % Equivalence clause: %', v_current_source_row_id, v_equivalent_clause;

            v_existing_query := format(
                $$SELECT * 
                  FROM %I.%I AS tbl
                  WHERE tbl.%I = %L 
                    AND public.after_to_overlaps(tbl.%I, tbl.%I, %L::DATE, %L::DATE) -- Uses source record's full original period for finding overlaps
                  ORDER BY tbl.%I$$,
                p_target_schema_name, p_target_table_name,
                p_id_column_name, v_existing_id, -- Use resolved v_existing_id
                v_valid_after_col, v_valid_to_col, 
                v_source_valid_after, 
                v_source_valid_to,
                v_valid_after_col -- Order by valid_after
            );
            RAISE DEBUG '[batch_replace] Existing eras query for source row % (target ID %): %', v_current_source_row_id, v_existing_id, v_existing_query;

            FOR v_existing_era_record IN EXECUTE v_existing_query
            LOOP
                v_existing_era_jsonb := to_jsonb(v_existing_era_record);
                RAISE DEBUG '[batch_replace] Source row %, Existing era record found: %', v_current_source_row_id, v_existing_era_jsonb;

                DECLARE
                    _ex_va DATE := (v_existing_era_jsonb->>v_valid_after_col)::DATE;
                    _ex_vt DATE := (v_existing_era_jsonb->>v_valid_to_col)::DATE;
                    v_relation public.allen_interval_relation;
                    _data_is_equivalent BOOLEAN := TRUE; -- Assume true, prove false
                    _key TEXT;
                BEGIN
                    -- Determine if data is equivalent
                    FOR _key IN SELECT * FROM jsonb_object_keys(v_equivalent_data) LOOP
                        IF (v_source_record_jsonb->>_key) IS DISTINCT FROM (v_existing_era_jsonb->>_key) THEN
                            _data_is_equivalent := FALSE;
                            RAISE DEBUG '[batch_replace] Data different for key "%": Source "%", Existing "%"', 
                                        _key, (v_source_record_jsonb->>_key), (v_existing_era_jsonb->>_key);
                            EXIT;
                        END IF;
                    END LOOP;
                    IF _data_is_equivalent THEN
                        RAISE DEBUG '[batch_replace] Data is equivalent between source and existing era %', v_existing_era_jsonb;
                    END IF;

                    v_relation := public.get_allen_relation(v_source_valid_after, v_source_valid_to, _ex_va, _ex_vt);
                    RAISE DEBUG '[batch_replace] Allen relation for source (% to %] and existing (% to %]: %', 
                                v_source_valid_after, v_source_valid_to, _ex_va, _ex_vt, v_relation; -- Removed extraneous parenthesis

                    CASE v_relation
                        WHEN 'during' THEN -- Source X is during Existing Y
                            IF _data_is_equivalent THEN
                                RAISE DEBUG '[batch_replace] Relation: DURING, data equivalent. Source is absorbed by existing. No changes to existing. Source insert skipped.';
                                v_source_record_handled_by_merge := TRUE;
                                v_result_id := v_existing_id; -- The existing record's ID
                                EXIT; -- Exit the loop for this source record as it's fully handled
                            ELSE
                                RAISE DEBUG '[batch_replace] Relation: DURING, data different. Splitting existing record.';
                                -- 1. Truncate existing record Y to end where source X begins: Y.vt = X.va
                                EXECUTE format('UPDATE %I.%I SET %I = %L WHERE %I = %L AND %I = %L AND %I = %L',
                                               p_target_schema_name, p_target_table_name,
                                               v_valid_to_col, v_source_valid_after,
                                               p_id_column_name, v_existing_id,
                                               v_valid_after_col, _ex_va, v_valid_to_col, _ex_vt);
                                RAISE DEBUG '[batch_replace] Truncated existing part to (% to %]', _ex_va, v_source_valid_after;

                                -- 2. Insert new record for the trailing part of Y: (X.vt, Y.vt_original]
                                IF v_source_valid_to < _ex_vt THEN -- Check if there is a trailing part
                                    DECLARE
                                        _trailing_part_data JSONB := v_existing_era_jsonb; -- Copy original existing data
                                        _insert_cols_list_trail TEXT[] := ARRAY[]::TEXT[];
                                        _insert_vals_list_trail TEXT[] := ARRAY[]::TEXT[];
                                        _col_name_trail TEXT;
                                        _col_value_trail TEXT;
                                    BEGIN
                                        _trailing_part_data := jsonb_set(_trailing_part_data, ARRAY[v_valid_after_col], to_jsonb(v_source_valid_to::TEXT));
                                        _trailing_part_data := jsonb_set(_trailing_part_data, ARRAY[v_valid_to_col], to_jsonb(_ex_vt::TEXT));
                                        _trailing_part_data := jsonb_set(_trailing_part_data, ARRAY[p_id_column_name], to_jsonb(v_existing_id));
                                        
                                        FOR _col_name_trail IN SELECT key FROM jsonb_object_keys(_trailing_part_data) LOOP
                                            IF _col_name_trail = ANY(v_target_table_actual_columns) THEN
                                                _col_value_trail := _trailing_part_data->>_col_name_trail;

                                                IF _col_name_trail = v_valid_after_col AND
                                                   p_target_valid_from_col_name IS NOT NULL AND
                                                   (v_valid_after_col = ANY(v_generated_columns)) AND
                                                   (p_target_valid_from_col_name = ANY(v_target_table_actual_columns))
                                                THEN
                                                    _insert_cols_list_trail := array_append(_insert_cols_list_trail, quote_ident(p_target_valid_from_col_name));
                                                    _insert_vals_list_trail := array_append(_insert_vals_list_trail, quote_nullable( (_col_value_trail::DATE + INTERVAL '1 day')::TEXT ));
                                                ELSIF _col_name_trail = p_id_column_name AND (p_id_column_name = ANY(v_generated_columns)) THEN
                                                    IF _col_value_trail IS NOT NULL THEN
                                                        _insert_cols_list_trail := array_append(_insert_cols_list_trail, quote_ident(_col_name_trail));
                                                        _insert_vals_list_trail := array_append(_insert_vals_list_trail, quote_nullable(_col_value_trail));
                                                    END IF;
                                                ELSIF _col_name_trail = ANY(v_generated_columns) THEN
                                                     IF _col_name_trail = v_valid_to_col THEN -- Allow inserting valid_to even if somehow marked generated
                                                        _insert_cols_list_trail := array_append(_insert_cols_list_trail, quote_ident(_col_name_trail));
                                                        _insert_vals_list_trail := array_append(_insert_vals_list_trail, quote_nullable(_col_value_trail));
                                                     END IF;
                                                ELSE
                                                    _insert_cols_list_trail := array_append(_insert_cols_list_trail, quote_ident(_col_name_trail));
                                                    _insert_vals_list_trail := array_append(_insert_vals_list_trail, quote_nullable(_col_value_trail));
                                                END IF;
                                            END IF;
                                        END LOOP;

                                        IF array_length(_insert_cols_list_trail, 1) > 0 THEN
                                            EXECUTE format('INSERT INTO %I.%I (%s) VALUES (%s)',
                                                           p_target_schema_name, p_target_table_name,
                                                           array_to_string(_insert_cols_list_trail, ', '),
                                                           array_to_string(_insert_vals_list_trail, ', '));
                                            RAISE DEBUG '[batch_replace] Inserted trailing part of split: (% to %]', v_source_valid_to, _ex_vt;
                                        ELSE
                                            RAISE WARNING '[batch_replace] No columns to insert for trailing part of split. Data: %', _trailing_part_data;
                                        END IF;
                                    END;
                                END IF;
                                -- The source record itself will be inserted later by the main logic.
                                -- v_source_record_handled_by_merge remains FALSE.
                            END IF;
                        WHEN 'contains' THEN -- Source X contains Existing Y
                            RAISE DEBUG '[batch_replace] Relation: CONTAINS. Existing record is deleted.';
                            EXECUTE format('DELETE FROM %I.%I WHERE %I = %L AND %I = %L AND %I = %L',
                                           p_target_schema_name, p_target_table_name, p_id_column_name, v_existing_id,
                                           v_valid_after_col, _ex_va, v_valid_to_col, _ex_vt);
                            -- Source record will be inserted later.
                            -- v_source_record_handled_by_merge remains FALSE.
                        WHEN 'overlaps' THEN -- Source X overlaps start of Existing Y
                            IF _data_is_equivalent THEN
                                RAISE DEBUG '[batch_replace] Relation: OVERLAPS, data equivalent. Extending existing Y to start at X.va.';
                                EXECUTE format('UPDATE %I.%I SET %I = %L WHERE %I = %L AND %I = %L AND %I = %L',
                                               p_target_schema_name, p_target_table_name,
                                               v_valid_after_col, v_source_valid_after, -- Y.va = X.va
                                               p_id_column_name, v_existing_id,
                                               v_valid_after_col, _ex_va, v_valid_to_col, _ex_vt);
                                v_source_record_handled_by_merge := TRUE;
                                v_result_id := v_existing_id;
                                EXIT; -- Fully handled
                            ELSE
                                RAISE DEBUG '[batch_replace] Relation: OVERLAPS, data different. Truncating existing Y to start at X.vt.';
                                EXECUTE format('UPDATE %I.%I SET %I = %L WHERE %I = %L AND %I = %L AND %I = %L',
                                               p_target_schema_name, p_target_table_name,
                                               v_valid_after_col, v_source_valid_to, -- Y.va = X.vt
                                               p_id_column_name, v_existing_id,
                                               v_valid_after_col, _ex_va, v_valid_to_col, _ex_vt);
                                -- Source record will be inserted later.
                            END IF;
                        WHEN 'overlapped_by' THEN -- Source X is overlapped_by Existing Y (Y overlaps start of X)
                            IF _data_is_equivalent THEN
                                RAISE DEBUG '[batch_replace] Relation: OVERLAPPED_BY, data equivalent. Extending existing Y to end at X.vt.';
                                EXECUTE format('UPDATE %I.%I SET %I = %L WHERE %I = %L AND %I = %L AND %I = %L',
                                               p_target_schema_name, p_target_table_name,
                                               v_valid_to_col, v_source_valid_to, -- Y.vt = X.vt
                                               p_id_column_name, v_existing_id,
                                               v_valid_after_col, _ex_va, v_valid_to_col, _ex_vt);
                                v_source_record_handled_by_merge := TRUE;
                                v_result_id := v_existing_id;
                                EXIT; -- Fully handled
                            ELSE
                                RAISE DEBUG '[batch_replace] Relation: OVERLAPPED_BY, data different. Truncating existing Y to end at X.va.';
                                EXECUTE format('UPDATE %I.%I SET %I = %L WHERE %I = %L AND %I = %L AND %I = %L',
                                               p_target_schema_name, p_target_table_name,
                                               v_valid_to_col, v_source_valid_after, -- Y.vt = X.va
                                               p_id_column_name, v_existing_id,
                                               v_valid_after_col, _ex_va, v_valid_to_col, _ex_vt);
                                -- Source record will be inserted later.
                            END IF;
                        WHEN 'starts' THEN -- Source X starts Existing Y
                            IF _data_is_equivalent THEN
                                RAISE DEBUG '[batch_replace] Relation: STARTS, data equivalent. Source absorbed by existing.';
                                v_source_record_handled_by_merge := TRUE;
                                v_result_id := v_existing_id;
                                EXIT; -- Fully handled
                            ELSE
                                RAISE DEBUG '[batch_replace] Relation: STARTS, data different. Truncating existing Y to start at X.vt.';
                                EXECUTE format('UPDATE %I.%I SET %I = %L WHERE %I = %L AND %I = %L AND %I = %L',
                                               p_target_schema_name, p_target_table_name,
                                               v_valid_after_col, v_source_valid_to, -- Y.va = X.vt
                                               p_id_column_name, v_existing_id,
                                               v_valid_after_col, _ex_va, v_valid_to_col, _ex_vt);
                                -- Source record will be inserted later.
                            END IF;
                        WHEN 'started_by' THEN -- Existing Y starts Source X
                            RAISE DEBUG '[batch_replace] Relation: STARTED_BY. Existing record is deleted (whether data is same or different).';
                            EXECUTE format('DELETE FROM %I.%I WHERE %I = %L AND %I = %L AND %I = %L',
                                           p_target_schema_name, p_target_table_name, p_id_column_name, v_existing_id,
                                           v_valid_after_col, _ex_va, v_valid_to_col, _ex_vt);
                            -- Source record will be inserted later, effectively replacing/extending Y.
                            -- v_source_record_handled_by_merge remains FALSE.
                        WHEN 'finishes' THEN -- Source X finishes Existing Y
                            IF _data_is_equivalent THEN
                                RAISE DEBUG '[batch_replace] Relation: FINISHES, data equivalent. Source absorbed by existing.';
                                v_source_record_handled_by_merge := TRUE;
                                v_result_id := v_existing_id;
                                EXIT; -- Fully handled
                            ELSE
                                RAISE DEBUG '[batch_replace] Relation: FINISHES, data different. Truncating existing Y to end at X.va.';
                                EXECUTE format('UPDATE %I.%I SET %I = %L WHERE %I = %L AND %I = %L AND %I = %L',
                                               p_target_schema_name, p_target_table_name,
                                               v_valid_to_col, v_source_valid_after, -- Y.vt = X.va
                                               p_id_column_name, v_existing_id,
                                               v_valid_after_col, _ex_va, v_valid_to_col, _ex_vt);
                                -- Source record will be inserted later.
                            END IF;
                        WHEN 'finished_by' THEN -- Existing Y finishes Source X
                            RAISE DEBUG '[batch_replace] Relation: FINISHED_BY. Existing record is deleted (whether data is same or different).';
                            EXECUTE format('DELETE FROM %I.%I WHERE %I = %L AND %I = %L AND %I = %L',
                                           p_target_schema_name, p_target_table_name, p_id_column_name, v_existing_id,
                                           v_valid_after_col, _ex_va, v_valid_to_col, _ex_vt);
                            -- Source record will be inserted later, effectively replacing/extending Y.
                            -- v_source_record_handled_by_merge remains FALSE.
                        ELSE
                            -- Default for other overlaps: delete the existing record.
                            RAISE DEBUG '[batch_replace] Relation: % (Unhandled Overlap). Deleting existing record.', v_relation;
                            EXECUTE format('DELETE FROM %I.%I WHERE %I = %L AND %I = %L AND %I = %L',
                                           p_target_schema_name, p_target_table_name, p_id_column_name, v_existing_id,
                                           v_valid_after_col, _ex_va, v_valid_to_col, _ex_vt);
                    END CASE;
                END;
            END LOOP; 

            -- After processing all overlaps for the current v_existing_id,
            -- insert the source record. Adjacency merges will be handled after this insertion.
            -- v_source_record_handled_by_merge will remain FALSE at this point, so the insert always happens.
            IF NOT v_source_record_handled_by_merge THEN
                DECLARE
                    _insert_cols_list TEXT[] := ARRAY[]::TEXT[];
                    _insert_vals_list TEXT[] := ARRAY[]::TEXT[];
                    _col_name TEXT;
                    _col_value TEXT;
                BEGIN
                    FOR _col_name IN SELECT key FROM jsonb_object_keys(v_source_record_jsonb) LOOP
                        IF _col_name = ANY(v_target_table_actual_columns) THEN
                            _col_value := v_source_record_jsonb->>_col_name;

                            IF _col_name = v_valid_after_col AND 
                               p_target_valid_from_col_name IS NOT NULL AND 
                               (v_valid_after_col = ANY(v_generated_columns)) AND
                               (p_target_valid_from_col_name = ANY(v_target_table_actual_columns))
                            THEN
                                -- Insert p_target_valid_from_col_name instead of generated v_valid_after_col
                                _insert_cols_list := array_append(_insert_cols_list, quote_ident(p_target_valid_from_col_name));
                                _insert_vals_list := array_append(_insert_vals_list, quote_nullable( (_col_value::DATE + INTERVAL '1 day')::TEXT ));
                            ELSIF _col_name = p_id_column_name AND (p_id_column_name = ANY(v_generated_columns)) THEN
                                IF _col_value IS NOT NULL THEN -- Only include generated ID if a value is provided
                                    _insert_cols_list := array_append(_insert_cols_list, quote_ident(_col_name));
                                    _insert_vals_list := array_append(_insert_vals_list, quote_nullable(_col_value));
                                END IF;
                            ELSIF _col_name = ANY(v_generated_columns) THEN
                                -- Skip other generated columns unless it's v_valid_to_col (which is not typically generated but is temporal)
                                IF _col_name = v_valid_to_col THEN
                                     _insert_cols_list := array_append(_insert_cols_list, quote_ident(_col_name));
                                     _insert_vals_list := array_append(_insert_vals_list, quote_nullable(_col_value));
                                END IF;
                            ELSE -- Non-generated, or generated but allowed (like non-ID PK part, or non-generated temporal)
                                _insert_cols_list := array_append(_insert_cols_list, quote_ident(_col_name));
                                _insert_vals_list := array_append(_insert_vals_list, quote_nullable(_col_value));
                            END IF;
                        END IF;
                    END LOOP;

                    IF array_length(_insert_cols_list, 1) = 0 THEN
                        RAISE WARNING '[batch_replace] Source row %: No columns to insert after processing. Source JSON: %', v_current_source_row_id, v_source_record_jsonb;
                        v_result_id := (v_source_record_jsonb->>p_id_column_name)::INT; 
                    ELSE
                        v_sql := format('INSERT INTO %I.%I (%s) VALUES (%s) RETURNING %I',
                                        p_target_schema_name, p_target_table_name,
                                        array_to_string(_insert_cols_list, ', '),
                                        array_to_string(_insert_vals_list, ', '),
                                        p_id_column_name);
                        RAISE DEBUG '[batch_replace] Source row %, Insert SQL: %', v_current_source_row_id, v_sql;
                        EXECUTE v_sql INTO v_result_id;
                    END IF;

                -- **NEW ADJACENCY MERGE LOGIC STARTS HERE**
                -- After inserting the source record (now identified by v_result_id, v_source_valid_after, v_source_valid_to),
                -- attempt to merge it with adjacent records if data is equivalent.
                
                -- Store the initially inserted source record's ID, as v_result_id might change if merged.
                DECLARE
                    _inserted_source_record_id INT := v_result_id; 
                    _current_record_va DATE := v_source_valid_after;
                    _current_record_vt DATE := v_source_valid_to;
                    _earlier_adj_era RECORD;
                    _later_adj_era RECORD;
                    _data_is_equivalent BOOLEAN;
                    _key TEXT;
                BEGIN
                    RAISE DEBUG '[batch_replace] Inserted source record ID: %, Period: (% to %]. Checking for adjacent merges.', 
                                _inserted_source_record_id, _current_record_va, _current_record_vt;

                    -- 1. Check for EARLIER adjacent record
                    IF v_existing_id IS NOT NULL THEN -- Can only merge if there's a common logical ID
                        EXECUTE format('SELECT * FROM %I.%I AS t WHERE t.%I = %L AND t.%I = %L LIMIT 1',
                                       p_target_schema_name, p_target_table_name,
                                       p_id_column_name, v_existing_id, 
                                       v_valid_to_col, _current_record_va)
                        INTO _earlier_adj_era;

                        IF _earlier_adj_era IS NOT NULL THEN
                            RAISE DEBUG '[batch_replace] Found potential earlier adjacent record: %', to_jsonb(_earlier_adj_era);
                            _data_is_equivalent := TRUE;
                            FOR _key IN SELECT * FROM jsonb_object_keys(v_equivalent_data) LOOP
                                IF (v_source_record_jsonb->>_key) IS DISTINCT FROM (to_jsonb(_earlier_adj_era)->>_key) THEN
                                    _data_is_equivalent := FALSE;
                                    RAISE DEBUG '[batch_replace] Data different for key "%" between source and earlier adjacent.', _key;
                                    EXIT;
                                END IF;
                            END LOOP;

                            IF _data_is_equivalent THEN
                                RAISE DEBUG '[batch_replace] Data equivalent with earlier adjacent. Merging.';
                                -- Extend earlier record
                                EXECUTE format('UPDATE %I.%I SET %I = %L WHERE %I = %L AND %I = %L',
                                               p_target_schema_name, p_target_table_name,
                                               v_valid_to_col, _current_record_vt, -- New end is current record's end
                                               p_id_column_name, _earlier_adj_era.id, v_valid_after_col, (_earlier_adj_era.valid_after)::TEXT);
                                -- Delete the (just inserted) source record as it's now merged
                                EXECUTE format('DELETE FROM %I.%I WHERE %I = %L AND %I = %L AND %I = %L',
                                               p_target_schema_name, p_target_table_name,
                                               p_id_column_name, _inserted_source_record_id, 
                                               v_valid_after_col, _current_record_va, v_valid_to_col, _current_record_vt);
                                
                                v_result_id := _earlier_adj_era.id; -- The result is now the earlier record
                                _current_record_va := _earlier_adj_era.valid_after; -- Effective start is now earlier_adj_era's start
                                -- _current_record_vt remains the same (original source's end)
                                RAISE DEBUG '[batch_replace] Merged with earlier. Effective record ID: %, Period: (% to %]', 
                                            v_result_id, _current_record_va, _current_record_vt;
                            END IF;
                        END IF;
                    END IF; -- End earlier adjacent check

                    -- 2. Check for LATER adjacent record (using potentially updated _current_record_va, _current_record_vt from earlier merge)
                    IF v_existing_id IS NOT NULL THEN
                        EXECUTE format('SELECT * FROM %I.%I AS t WHERE t.%I = %L AND t.%I = %L LIMIT 1',
                                       p_target_schema_name, p_target_table_name,
                                       p_id_column_name, v_existing_id,
                                       v_valid_after_col, _current_record_vt)
                        INTO _later_adj_era;

                        IF _later_adj_era IS NOT NULL THEN
                            RAISE DEBUG '[batch_replace] Found potential later adjacent record: %', to_jsonb(_later_adj_era);
                            _data_is_equivalent := TRUE;
                            -- Compare data of current effective record (source or merged earlier) with later_adj_era
                            -- If an earlier merge happened, v_source_record_jsonb still holds original source data.
                            -- We need to compare against the data that defines the _current_record_va to _current_record_vt span.
                            -- For simplicity, we'll use v_source_record_jsonb for data comparison here.
                            -- A more robust solution might re-fetch the record if an earlier merge happened.
                            FOR _key IN SELECT * FROM jsonb_object_keys(v_equivalent_data) LOOP
                                IF (v_source_record_jsonb->>_key) IS DISTINCT FROM (to_jsonb(_later_adj_era)->>_key) THEN
                                    _data_is_equivalent := FALSE;
                                    RAISE DEBUG '[batch_replace] Data different for key "%" between current effective record and later adjacent.', _key;
                                    EXIT;
                                END IF;
                            END LOOP;

                            IF _data_is_equivalent THEN
                                RAISE DEBUG '[batch_replace] Data equivalent with later adjacent. Merging.';
                                -- Extend current effective record (which is _later_adj_era after this merge)
                                EXECUTE format('UPDATE %I.%I SET %I = %L WHERE %I = %L AND %I = %L',
                                               p_target_schema_name, p_target_table_name,
                                               v_valid_after_col, _current_record_va, -- New start is current record's start
                                               p_id_column_name, _later_adj_era.id, v_valid_after_col, (_later_adj_era.valid_after)::TEXT);
                                -- Delete the record that was representing the span (_current_record_va, _current_record_vt] before this merge
                                -- This could be the original source insert, or the earlier_adj_era if it absorbed the source.
                                EXECUTE format('DELETE FROM %I.%I WHERE %I = %L AND %I = %L AND %I = %L',
                                               p_target_schema_name, p_target_table_name,
                                               p_id_column_name, v_result_id, -- v_result_id points to the record to be deleted
                                               v_valid_after_col, _current_record_va, v_valid_to_col, _current_record_vt);

                                v_result_id := _later_adj_era.id; -- The result is now the later record
                                -- _current_record_va remains the same
                                _current_record_vt := _later_adj_era.valid_to; -- Effective end is now later_adj_era's end
                                RAISE DEBUG '[batch_replace] Merged with later. Effective record ID: %, Period: (% to %]', 
                                            v_result_id, _current_record_va, _current_record_vt;
                            END IF;
                        END IF;
                    END IF; -- End later adjacent check
                END; -- End adjacency merge block
                -- **NEW ADJACENCY MERGE LOGIC ENDS HERE**

            END; -- Closes the DECLARE...BEGIN block for the IF NOT v_source_record_handled_by_merge
            ELSE
                 RAISE DEBUG '[batch_replace] Source row % was handled by merge, final insert skipped.', v_current_source_row_id;
                 -- v_result_id should have been set during the merge operation if applicable.
            END IF; -- This END IF closes the "IF NOT v_source_record_handled_by_merge"

            source_row_id := v_current_source_row_id;
            upserted_record_id := v_result_id; -- This will be the ID from the new insert, or from a merge if logic sets it.
            status := 'SUCCESS';
            error_message := NULL;
            RETURN NEXT;

        EXCEPTION WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS v_loop_error_message = MESSAGE_TEXT, v_err_context = PG_EXCEPTION_CONTEXT;
            RAISE WARNING '[batch_replace] Error processing source_row_id % (%): %. Context: %', v_current_source_row_id, v_source_record_jsonb, v_loop_error_message, v_err_context;
            source_row_id := v_current_source_row_id;
            upserted_record_id := NULL;
            status := 'ERROR';
            error_message := v_loop_error_message;
            -- Ensure constraints are immediate before returning this error result for the row
            EXECUTE 'SET CONSTRAINTS ALL IMMEDIATE';
            RAISE DEBUG '[batch_replace] SET CONSTRAINTS ALL IMMEDIATE after error for source_row_id %', v_current_source_row_id;
            RETURN NEXT;
        END; 
        -- If successful, set constraints immediate at the end of this row's processing
        EXECUTE 'SET CONSTRAINTS ALL IMMEDIATE';
        RAISE DEBUG '[batch_replace] SET CONSTRAINTS ALL IMMEDIATE after successful processing for source_row_id %', v_current_source_row_id;

    END LOOP; 

    RETURN;
END;
$batch_insert_or_replace_generic_valid_time_table$;

END;

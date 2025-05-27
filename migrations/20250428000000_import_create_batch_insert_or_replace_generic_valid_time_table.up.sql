BEGIN;

CREATE OR REPLACE FUNCTION import.batch_insert_or_replace_generic_valid_time_table(
    p_target_schema_name TEXT,
    p_target_table_name TEXT,
    p_source_schema_name TEXT,
    p_source_table_name TEXT,
    p_unique_columns JSONB, -- For identifying existing ID if input ID is null. Format: '[ "col_name_1", ["comp_col_a", "comp_col_b"] ]'
    p_ephemeral_columns TEXT[], -- Columns to exclude from equivalence check but keep in insert/update
    p_id_column_name TEXT, -- Name of the primary key / ID column in the target table
    p_generated_columns_override TEXT[] DEFAULT NULL -- Explicit list of DB-generated columns (e.g., 'id' if serial/identity)
)
RETURNS TABLE (
    source_row_id BIGINT,
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

    v_source_record_jsonb JSONB; 
    v_existing_era_jsonb JSONB;
    
    v_source_valid_after DATE; 
    v_source_valid_to DATE;   

    -- v_adjusted_valid_from DATE; -- Not directly used in this refactor
    -- v_adjusted_valid_to DATE;   -- Not directly used in this refactor
    v_source_record_handled BOOLEAN; -- Renamed from v_source_record_handled_by_merge

    v_equivalent_data_cols JSONB; -- Renamed from v_equivalent_data
    -- v_equivalent_clause TEXT; -- Not directly used in this refactor
    v_identifying_clause TEXT;
    v_existing_query TEXT;
    v_delete_existing_sql TEXT;
    v_identifying_query TEXT;
    v_generated_columns TEXT[];
    v_source_query TEXT;
    v_sql TEXT;

    v_founding_id_cache JSONB := '{}'::JSONB;
    v_current_founding_row_id BIGINT;
    v_initial_existing_id_is_null BOOLEAN;

    v_err_context TEXT;
    v_loop_error_message TEXT;
    v_loop_var TEXT;

    v_target_table_actual_columns TEXT[]; -- Holds actual column names of the target table
    v_source_target_id_alias TEXT;
BEGIN
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
        -- Determine database-generated columns.
        -- These are columns whose values are typically supplied by the database if not explicitly
        -- provided in an INSERT statement (e.g., SERIAL, IDENTITY, or DEFAULT nextval()).
        --
        -- This logic intentionally avoids broadly classifying all primary key components as "generated"
        -- simply because they are part of a PK. For example, a temporal column like 'valid_after'
        -- might be part of a PK, but its value is user-supplied, not database-generated.
        -- Including such user-supplied PK components in v_generated_columns could lead to them
        -- being incorrectly omitted from INSERT statements (especially for split/trailing parts of records),
        -- causing "not null" violations or incorrect data.
        --
        -- The criteria for a column to be considered "database-generated" for the purpose of this function are:
        -- 1. Linked to a sequence via SERIAL types or OWNED BY (pg_get_serial_sequence).
        -- 2. Is an IDENTITY column (a.attidentity).
        -- 3. Is a GENERATED ... AS ... column (a.attgenerated).
        -- 4. Has a default expression that is a nextval() call (a.atthasdef and pg_get_expr).
        EXECUTE format(
            'SELECT array_agg(a.attname) '
            'FROM pg_catalog.pg_attribute AS a '
            'LEFT JOIN pg_catalog.pg_attrdef ad ON ad.adrelid = a.attrelid AND ad.adnum = a.attnum ' || -- LEFT JOIN needed for pg_get_expr check
            'WHERE a.attrelid = ''%I.%I''::regclass '
            '  AND a.attnum > 0 AND NOT a.attisdropped '
            '  AND ('
            '    pg_catalog.pg_get_serial_sequence(a.attrelid::regclass::text, a.attname) IS NOT NULL '
            '    OR a.attidentity <> '''' '
            '    OR a.attgenerated <> '''' '
            '    OR (a.atthasdef AND pg_catalog.pg_get_expr(ad.adbin, ad.adrelid) LIKE ''nextval(%%::regclass)'') ' -- Note: %% for format, becomes % for LIKE
            '  )',
            p_target_schema_name, p_target_table_name
        ) INTO v_generated_columns;
    END IF;
    v_generated_columns := COALESCE(v_generated_columns, ARRAY[]::TEXT[]);
    -- Systematically treat valid_from as a generated column, to be handled by the trigger
    IF NOT ('valid_from' = ANY(v_generated_columns)) THEN
        v_generated_columns := array_append(v_generated_columns, 'valid_from');
    END IF;
    RAISE DEBUG '[batch_replace] Final v_generated_columns for %.%: %', p_target_schema_name, p_target_table_name, v_generated_columns;

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
        IF NOT (v_source_record_jsonb ? 'row_id') THEN
            RAISE EXCEPTION 'Source row ID column ''row_id'' not found in source table %.%', p_source_schema_name, p_source_table_name;
        END IF;
        v_current_source_row_id := (v_source_record_jsonb->>'row_id')::BIGINT;
        
        v_existing_id := (v_source_record_jsonb->>p_id_column_name)::INT;
        v_initial_existing_id_is_null := (v_existing_id IS NULL);

        -- Attempt to use founding_row_id cache if v_existing_id is NULL
        IF v_initial_existing_id_is_null THEN
            IF v_source_record_jsonb ? 'founding_row_id' AND (v_source_record_jsonb->>'founding_row_id') IS NOT NULL THEN
                v_current_founding_row_id := (v_source_record_jsonb->>'founding_row_id')::BIGINT;
                IF v_founding_id_cache ? v_current_founding_row_id::TEXT THEN
                    v_existing_id := (v_founding_id_cache->>v_current_founding_row_id::TEXT)::INT;
                    v_source_record_jsonb := jsonb_set(v_source_record_jsonb, ARRAY[p_id_column_name], to_jsonb(v_existing_id), true);
                    RAISE DEBUG '[batch_replace] Cache hit for founding_row_id %: set %I to % for source_row_id %', 
                                v_current_founding_row_id, p_id_column_name, v_existing_id, v_current_source_row_id;
                ELSE
                    RAISE DEBUG '[batch_replace] founding_row_id % not in cache for source_row_id %.', v_current_founding_row_id, v_current_source_row_id;
                    -- v_existing_id remains NULL, will proceed to unique column lookup or new insert
                END IF;
            ELSE
                v_current_founding_row_id := NULL; -- Ensure it's null if not present or null in source
                RAISE DEBUG '[batch_replace] No founding_row_id found or it is NULL in source_row_id %.', v_current_source_row_id;
            END IF;
        ELSE
            v_current_founding_row_id := NULL; -- Not needed if v_existing_id is already known from source p_id_column_name
        END IF;

        RAISE DEBUG '[batch_replace] Processing source_row_id %: %. Initial v_existing_id (after cache check) from source field %I: %', 
            v_current_source_row_id, v_source_record_jsonb, p_id_column_name, v_existing_id;

        BEGIN -- Start block for individual row processing
            -- Defer constraints locally for operations on this row's temporal slices
            EXECUTE 'SET CONSTRAINTS ALL DEFERRED';
            RAISE DEBUG '[batch_replace] SET CONSTRAINTS ALL DEFERRED for source_row_id %', v_current_source_row_id;

            v_loop_error_message := NULL;
            v_result_id := NULL;
            v_source_record_handled := FALSE; -- Initialize for each source record

            v_source_valid_after := (v_source_record_jsonb->>'valid_after')::DATE;
            v_source_valid_to    := (v_source_record_jsonb->>'valid_to')::DATE;

            IF v_source_valid_after IS NULL OR v_source_valid_to IS NULL THEN
                RAISE EXCEPTION 'Temporal columns (''valid_after'', ''valid_to'') cannot be null. Error in source row with ''row_id'' = %: %',
                    v_current_source_row_id, v_source_record_jsonb;
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

            -- Determine non-ephemeral, non-temporal, non-ID columns for equivalence check
            -- v_equivalent_data_cols is no longer used directly to store data, 
            -- the check is done by iterating core column names.

            v_existing_query := format(
                $$SELECT * 
                  FROM %I.%I AS tbl
                  WHERE tbl.%I = %L 
                    AND tbl.valid_after <= %L::DATE -- tbl.valid_after <= v_source_valid_to
                    AND tbl.valid_to    >= %L::DATE -- tbl.valid_to    >= v_source_valid_after
                  ORDER BY tbl.valid_after$$, -- Order by valid_after
                p_target_schema_name, p_target_table_name,
                p_id_column_name, v_existing_id, 
                v_source_valid_to,   -- Value for tbl.valid_after <= %L
                v_source_valid_after -- Value for tbl.valid_to    >= %L
            );
            RAISE DEBUG '[batch_replace] Existing eras query for source row % (target ID %): %', v_current_source_row_id, v_existing_id, v_existing_query;

            FOR v_existing_era_record IN EXECUTE v_existing_query
            LOOP
                v_existing_era_jsonb := to_jsonb(v_existing_era_record);
                RAISE DEBUG '[batch_replace] Source row %, Existing era record found: %', v_current_source_row_id, v_existing_era_jsonb;

                DECLARE
                    _ex_va DATE := (v_existing_era_jsonb->>'valid_after')::DATE;
                    _ex_vt DATE := (v_existing_era_jsonb->>'valid_to')::DATE;
                    v_relation public.allen_interval_relation;
                    _data_is_equivalent BOOLEAN := TRUE; -- Assume true, prove false
                    _key TEXT; -- Retained for potential future use, but not directly for core col iteration
                    _eph_update_set_clause TEXT; -- For updating ephemeral columns
                    _core_column_name TEXT;      -- For iterating through core column names
                BEGIN
                    -- Determine if data is equivalent by iterating defined core columns
                    _data_is_equivalent := TRUE; -- Assume true, prove false
                    FOR _core_column_name IN
                        SELECT col FROM unnest(v_target_table_actual_columns) col
                        WHERE NOT (col = 'valid_after' OR col = 'valid_to' OR col = 'valid_from') -- Exclude temporal columns
                          AND NOT (col = ANY(p_ephemeral_columns)) -- Exclude ephemeral columns
                          AND col != p_id_column_name -- Exclude the ID column itself
                    LOOP
                        IF (v_source_record_jsonb->>_core_column_name) IS DISTINCT FROM (v_existing_era_jsonb->>_core_column_name) THEN
                            _data_is_equivalent := FALSE;
                            RAISE DEBUG '[batch_replace] Data different for core column "%": Source val "%", Existing val "%". Source JSON: %, Existing JSON: %', 
                                        _core_column_name, 
                                        (v_source_record_jsonb->>_core_column_name), 
                                        (v_existing_era_jsonb->>_core_column_name),
                                        v_source_record_jsonb,
                                        v_existing_era_jsonb;
                            EXIT; -- Exit the core column loop
                        END IF;
                    END LOOP;

                    IF _data_is_equivalent THEN
                        RAISE DEBUG '[batch_replace] Core data is equivalent between source and existing era. Source JSON: %, Existing JSON: %', v_source_record_jsonb, v_existing_era_jsonb;
                        -- Build ephemeral update clause
                        SELECT string_agg(format('%I = %L', eph_col, v_source_record_jsonb->>eph_col), ', ')
                        INTO _eph_update_set_clause
                        FROM unnest(p_ephemeral_columns) eph_col
                        WHERE v_source_record_jsonb ? eph_col; -- Source must have the ephemeral col to update it
                    ELSE
                        RAISE DEBUG '[batch_replace] Core data is NOT equivalent between source and existing era. Source JSON: %, Existing JSON: %', v_source_record_jsonb, v_existing_era_jsonb;
                    END IF;

                    v_relation := public.get_allen_relation(v_source_valid_after, v_source_valid_to, _ex_va, _ex_vt);
                    RAISE DEBUG '[batch_replace] Allen relation for source (valid_after % to valid_to %] and existing (valid_after % to valid_to %]: %', 
                                v_source_valid_after, v_source_valid_to, _ex_va, _ex_vt, v_relation;

                    CASE v_relation
                        WHEN 'equals' THEN
                            IF _data_is_equivalent THEN
                                RAISE DEBUG '[batch_replace] Relation: EQUALS, data equivalent. Updating ephemeral on existing.';
                                IF _eph_update_set_clause IS NOT NULL AND _eph_update_set_clause != '' THEN
                                    EXECUTE format('UPDATE %I.%I SET %s WHERE %I = %L AND valid_after = %L AND valid_to = %L',
                                                   p_target_schema_name, p_target_table_name, _eph_update_set_clause,
                                                   p_id_column_name, v_existing_id, _ex_va, _ex_vt);
                                END IF;
                                v_source_record_handled := TRUE; v_result_id := v_existing_id; EXIT;
                            ELSE
                                RAISE DEBUG '[batch_replace] Relation: EQUALS, data different. Deleting existing.';
                                EXECUTE format('DELETE FROM %I.%I WHERE %I = %L AND valid_after = %L AND valid_to = %L',
                                               p_target_schema_name, p_target_table_name, p_id_column_name, v_existing_id,
                                               _ex_va, _ex_vt);
                            END IF;
                        WHEN 'during' THEN -- Source X is during Existing Y
                            IF _data_is_equivalent THEN
                                RAISE DEBUG '[batch_replace] Relation: DURING, data equivalent. Updating ephemeral on existing.';
                                IF _eph_update_set_clause IS NOT NULL AND _eph_update_set_clause != '' THEN
                                     EXECUTE format('UPDATE %I.%I SET %s WHERE %I = %L AND valid_after = %L AND valid_to = %L',
                                                   p_target_schema_name, p_target_table_name, _eph_update_set_clause,
                                                   p_id_column_name, v_existing_id, _ex_va, _ex_vt);
                                END IF;
                                v_source_record_handled := TRUE; v_result_id := v_existing_id; EXIT;
                            ELSE
                                RAISE DEBUG '[batch_replace] Relation: DURING, data different. Splitting existing.';
                                EXECUTE format('UPDATE %I.%I SET valid_to = %L WHERE %I = %L AND valid_after = %L AND valid_to = %L',
                                               p_target_schema_name, p_target_table_name, v_source_valid_after,
                                               p_id_column_name, v_existing_id, _ex_va, _ex_vt);
                                IF v_source_valid_to < _ex_vt THEN
                                    DECLARE _trailing_part_data JSONB := v_existing_era_jsonb; _insert_cols_trail TEXT[]; _insert_vals_trail TEXT[]; _col_trail TEXT;
                                    BEGIN
                                        _trailing_part_data := v_existing_era_jsonb; -- Start with original existing data
                                        _trailing_part_data := jsonb_set(_trailing_part_data, ARRAY['valid_after'], to_jsonb(v_source_valid_to::TEXT)); -- Starts after source
                                        _trailing_part_data := jsonb_set(_trailing_part_data, ARRAY['valid_to'], to_jsonb(_ex_vt::TEXT)); -- Ends at original existing end
                                        _trailing_part_data := jsonb_set(_trailing_part_data, ARRAY[p_id_column_name], to_jsonb(v_existing_id));
                                        _trailing_part_data := _trailing_part_data - 'valid_from'; -- Ensure trigger handles valid_from

                                        _insert_cols_trail := ARRAY[]::TEXT[];
                                        _insert_vals_trail := ARRAY[]::TEXT[];
                                        FOR _col_trail IN SELECT key FROM jsonb_each(_trailing_part_data) LOOP
                                            IF _col_trail = ANY(v_target_table_actual_columns) AND NOT (_col_trail = ANY(v_generated_columns) AND _col_trail != p_id_column_name) THEN
                                                IF _col_trail = p_id_column_name AND NOT (_trailing_part_data->>p_id_column_name IS NOT NULL) AND (p_id_column_name = ANY(v_generated_columns)) THEN
                                                    -- Skip if ID is generated and NULL in data
                                                    CONTINUE;
                                                END IF;
                                                _insert_cols_trail := array_append(_insert_cols_trail, quote_ident(_col_trail));
                                                _insert_vals_trail := array_append(_insert_vals_trail, quote_nullable(_trailing_part_data->>_col_trail));
                                            END IF;
                                        END LOOP;
                                        
                                        IF array_length(_insert_cols_trail, 1) > 0 THEN
                                            EXECUTE format('INSERT INTO %I.%I (%s) VALUES (%s) RETURNING %I',
                                                           p_target_schema_name, p_target_table_name,
                                                           array_to_string(_insert_cols_trail, ', '),
                                                           array_to_string(_insert_vals_trail, ', '),
                                                           p_id_column_name);
                                            RAISE DEBUG '[batch_replace] Inserted trailing part of split: (% to %]', v_source_valid_to, _ex_vt;
                                        ELSE
                                            RAISE WARNING '[batch_replace] No columns to insert for trailing part of split. Data: %', _trailing_part_data;
                                        END IF;
                                    END;
                                END IF;
                                -- The source record itself will be inserted later by the main logic.
                                -- v_source_record_handled remains FALSE.
                            END IF;
                        WHEN 'contains' THEN 
                            RAISE DEBUG '[batch_replace] Relation: CONTAINS. Deleting existing.';
                            EXECUTE format('DELETE FROM %I.%I WHERE %I = %L AND valid_after = %L AND valid_to = %L',
                                           p_target_schema_name, p_target_table_name, p_id_column_name, v_existing_id,
                                           _ex_va, _ex_vt);
                        WHEN 'overlaps' THEN 
                            IF _data_is_equivalent THEN
                                RAISE DEBUG '[batch_replace] Relation: OVERLAPS, data equivalent. Extending existing start and updating ephemeral.';
                                EXECUTE format('UPDATE %I.%I SET valid_after = %L %s WHERE %I = %L AND valid_after = %L AND valid_to = %L',
                                               p_target_schema_name, p_target_table_name, v_source_valid_after,
                                               CASE WHEN _eph_update_set_clause IS NOT NULL AND _eph_update_set_clause != '' THEN ', ' || _eph_update_set_clause ELSE '' END,
                                               p_id_column_name, v_existing_id, _ex_va, _ex_vt);
                                v_source_record_handled := TRUE; v_result_id := v_existing_id; EXIT;
                            ELSE
                                RAISE DEBUG '[batch_replace] Relation: OVERLAPS, data different. Truncating existing Y by setting Y.valid_after = X.valid_to (%L).', v_source_valid_to;
                                IF _ex_va < v_source_valid_to THEN EXECUTE format('UPDATE %I.%I SET valid_after = %L WHERE %I = %L AND valid_after = %L AND valid_to = %L', p_target_schema_name, p_target_table_name, v_source_valid_to, p_id_column_name, v_existing_id, _ex_va, _ex_vt);
                                ELSE EXECUTE format('DELETE FROM %I.%I WHERE %I = %L AND valid_after = %L AND valid_to = %L', p_target_schema_name, p_target_table_name, p_id_column_name, v_existing_id, _ex_va, _ex_vt); END IF;
                            END IF;
                        WHEN 'overlapped_by' THEN 
                            IF _data_is_equivalent THEN
                                RAISE DEBUG '[batch_replace] Relation: OVERLAPPED_BY, data equivalent. Extending existing end and updating ephemeral.';
                                EXECUTE format('UPDATE %I.%I SET valid_to = %L %s WHERE %I = %L AND valid_after = %L AND valid_to = %L',
                                               p_target_schema_name, p_target_table_name, v_source_valid_to,
                                               CASE WHEN _eph_update_set_clause IS NOT NULL AND _eph_update_set_clause != '' THEN ', ' || _eph_update_set_clause ELSE '' END,
                                               p_id_column_name, v_existing_id, _ex_va, _ex_vt);
                                v_source_record_handled := TRUE; v_result_id := v_existing_id; EXIT;
                            ELSE
                                RAISE DEBUG '[batch_replace] Relation: OVERLAPPED_BY, data different. Truncating existing Y by setting Y.valid_to = X.valid_after (%L).', v_source_valid_after;
                                IF _ex_vt > v_source_valid_after THEN EXECUTE format('UPDATE %I.%I SET valid_to = %L WHERE %I = %L AND valid_after = %L AND valid_to = %L', p_target_schema_name, p_target_table_name, v_source_valid_after, p_id_column_name, v_existing_id, _ex_va, _ex_vt);
                                ELSE EXECUTE format('DELETE FROM %I.%I WHERE %I = %L AND valid_after = %L AND valid_to = %L', p_target_schema_name, p_target_table_name, p_id_column_name, v_existing_id, _ex_va, _ex_vt); END IF;
                            END IF;
                        WHEN 'starts' THEN
                            IF _data_is_equivalent THEN
                                RAISE DEBUG '[batch_replace] Relation: STARTS, data equivalent. Updating ephemeral on existing.';
                                IF _eph_update_set_clause IS NOT NULL AND _eph_update_set_clause != '' THEN EXECUTE format('UPDATE %I.%I SET %s WHERE %I = %L AND valid_after = %L AND valid_to = %L', p_target_schema_name, p_target_table_name, _eph_update_set_clause, p_id_column_name, v_existing_id, _ex_va, _ex_vt); END IF;
                                v_source_record_handled := TRUE; v_result_id := v_existing_id; EXIT;
                            ELSE
                                RAISE DEBUG '[batch_replace] Relation: STARTS, data different. Modifying existing Y to start after X by setting Y.valid_after = X.valid_to (%L).', v_source_valid_to;
                                IF _ex_va < v_source_valid_to THEN EXECUTE format('UPDATE %I.%I SET valid_after = %L WHERE %I = %L AND valid_after = %L AND valid_to = %L', p_target_schema_name, p_target_table_name, v_source_valid_to, p_id_column_name, v_existing_id, _ex_va, _ex_vt);
                                ELSE EXECUTE format('DELETE FROM %I.%I WHERE %I = %L AND valid_after = %L AND valid_to = %L', p_target_schema_name, p_target_table_name, p_id_column_name, v_existing_id, _ex_va, _ex_vt); END IF;
                            END IF;
                        WHEN 'started_by' THEN
                            RAISE DEBUG '[batch_replace] Relation: STARTED_BY. Deleting existing.';
                            EXECUTE format('DELETE FROM %I.%I WHERE %I = %L AND valid_after = %L AND valid_to = %L',
                                           p_target_schema_name, p_target_table_name, p_id_column_name, v_existing_id,
                                           _ex_va, _ex_vt);
                        WHEN 'finishes' THEN
                            IF _data_is_equivalent THEN
                                IF v_source_valid_to = 'infinity'::DATE AND _ex_vt = 'infinity'::DATE AND v_source_valid_after > _ex_va THEN
                                     RAISE DEBUG '[batch_replace] Relation: FINISHES, data equivalent, existing ends at infinity. Updating ephemeral.';
                                     IF _eph_update_set_clause IS NOT NULL AND _eph_update_set_clause != '' THEN EXECUTE format('UPDATE %I.%I SET %s WHERE %I = %L AND valid_after = %L AND valid_to = %L', p_target_schema_name, p_target_table_name, _eph_update_set_clause, p_id_column_name, v_existing_id, _ex_va, _ex_vt); END IF;
                                     v_source_record_handled := TRUE; v_result_id := v_existing_id; EXIT;
                                ELSE
                                    RAISE DEBUG '[batch_replace] Relation: FINISHES, data equivalent (non-infinity or source not later start). Updating ephemeral on existing.';
                                    IF _eph_update_set_clause IS NOT NULL AND _eph_update_set_clause != '' THEN EXECUTE format('UPDATE %I.%I SET %s WHERE %I = %L AND valid_after = %L AND valid_to = %L', p_target_schema_name, p_target_table_name, _eph_update_set_clause, p_id_column_name, v_existing_id, _ex_va, _ex_vt); END IF;
                                    v_source_record_handled := TRUE; v_result_id := v_existing_id; EXIT;
                                END IF;
                            ELSE
                                RAISE DEBUG '[batch_replace] Relation: FINISHES, data different. Modifying existing Y to end before X by setting Y.valid_to = X.valid_after (%L).', v_source_valid_after;
                                IF _ex_vt > v_source_valid_after THEN EXECUTE format('UPDATE %I.%I SET valid_to = %L WHERE %I = %L AND valid_after = %L AND valid_to = %L', p_target_schema_name, p_target_table_name, v_source_valid_after, p_id_column_name, v_existing_id, _ex_va, _ex_vt);
                                ELSE EXECUTE format('DELETE FROM %I.%I WHERE %I = %L AND valid_after = %L AND valid_to = %L', p_target_schema_name, p_target_table_name, p_id_column_name, v_existing_id, _ex_va, _ex_vt); END IF;
                            END IF;
                        WHEN 'finished_by' THEN
                            RAISE DEBUG '[batch_replace] Relation: FINISHED_BY. Deleting existing.';
                            EXECUTE format('DELETE FROM %I.%I WHERE %I = %L AND valid_after = %L AND valid_to = %L',
                                           p_target_schema_name, p_target_table_name, p_id_column_name, v_existing_id,
                                           _ex_va, _ex_vt);
                        WHEN 'meets' THEN -- Source X (v_source_valid_after, v_source_valid_to] meets Existing Y (_ex_va, _ex_vt] :: v_source_valid_to = _ex_va
                            IF _data_is_equivalent THEN
                                RAISE DEBUG '[batch_replace] Relation: MEETS, data equivalent. Extending existing Y''s valid_after to source X''s valid_after.';
                                EXECUTE format('UPDATE %I.%I SET valid_after = %L %s WHERE %I = %L AND valid_after = %L AND valid_to = %L',
                                               p_target_schema_name, p_target_table_name, 
                                               v_source_valid_after, -- Set existing Y's start to source X's start
                                               CASE WHEN _eph_update_set_clause IS NOT NULL AND _eph_update_set_clause != '' THEN ', ' || _eph_update_set_clause ELSE '' END,
                                               p_id_column_name, v_existing_id, _ex_va, _ex_vt);
                                v_source_record_handled := TRUE; v_result_id := v_existing_id; EXIT;
                            END IF; -- Data different: no action on existing, source will be inserted.
                        WHEN 'met_by' THEN -- Source X (v_source_valid_after, v_source_valid_to] is met_by Existing Y (_ex_va, _ex_vt] :: v_source_valid_after = _ex_vt
                            IF _data_is_equivalent THEN
                                RAISE DEBUG '[batch_replace] Relation: MET_BY, data equivalent. Extending existing Y''s valid_to to source X''s valid_to.';
                                EXECUTE format('UPDATE %I.%I SET valid_to = %L %s WHERE %I = %L AND valid_after = %L AND valid_to = %L',
                                               p_target_schema_name, p_target_table_name, 
                                               v_source_valid_to, -- Set existing Y's end to source X's end
                                               CASE WHEN _eph_update_set_clause IS NOT NULL AND _eph_update_set_clause != '' THEN ', ' || _eph_update_set_clause ELSE '' END,
                                               p_id_column_name, v_existing_id, _ex_va, _ex_vt);
                                v_source_record_handled := TRUE; v_result_id := v_existing_id; EXIT;
                            END IF; -- Data different: no action on existing, source will be inserted.
                        ELSE -- 'precedes', 'preceded_by', or unhandled
                            RAISE DEBUG '[batch_replace] Relation: %s. No direct overlap modification.', v_relation;
                    END CASE;
                END;
            END LOOP; 

            IF NOT v_source_record_handled THEN
                DECLARE
                    _insert_cols_list TEXT[] := ARRAY[]::TEXT[];
                    _insert_vals_list TEXT[] := ARRAY[]::TEXT[];
                    _col_name TEXT;
                    _col_value TEXT;
                BEGIN
                    FOR _col_name IN SELECT * FROM jsonb_object_keys(v_source_record_jsonb) LOOP
                        IF _col_name = ANY(v_target_table_actual_columns) THEN
                            _col_value := v_source_record_jsonb->>_col_name;

                            IF _col_name = p_id_column_name THEN
                                RAISE DEBUG '[batch_replace] Processing ID column "%". _col_value: "%", Is p_id_column_name (value: "%") = ANY(v_generated_columns (value: %))?: %', 
                                    _col_name, _col_value, p_id_column_name, v_generated_columns, (p_id_column_name = ANY(v_generated_columns));
                                IF p_id_column_name = ANY(v_generated_columns) THEN
                                    -- For generated ID column:
                                    -- Only add to INSERT list if source provides an explicit non-NULL ID.
                                    -- If source ID is NULL, omit from list to allow DB DEFAULT to apply.
                                    RAISE DEBUG '[batch_replace] ID column "%" IS generated. _col_value IS NOT NULL?: %', _col_name, (_col_value IS NOT NULL);
                                    IF _col_value IS NOT NULL THEN
                                        _insert_cols_list := array_append(_insert_cols_list, quote_ident(_col_name));
                                        _insert_vals_list := array_append(_insert_vals_list, quote_nullable(_col_value));
                                    ELSE
                                        RAISE DEBUG '[batch_replace] ID column "%" IS generated and _col_value IS NULL. Skipping from INSERT list.', _col_name;
                                    END IF;
                                ELSE
                                    -- For non-generated ID column, always include it.
                                    RAISE DEBUG '[batch_replace] ID column "%" IS NOT generated. Adding to INSERT list.', _col_name;
                                    _insert_cols_list := array_append(_insert_cols_list, quote_ident(_col_name));
                                    _insert_vals_list := array_append(_insert_vals_list, quote_nullable(_col_value));
                                END IF;
                            ELSIF _col_name = 'valid_from' AND 'valid_from' = ANY(v_generated_columns) THEN
                                -- Skip 'valid_from' if it's in v_generated_columns (implying trigger will handle it)
                                RAISE DEBUG '[batch_replace] Skipping explicit insert of "valid_from" as it is in v_generated_columns. Record: %.', v_source_record_jsonb;
                            ELSIF _col_name = ANY(v_generated_columns) THEN
                                -- Skip any other columns that are database-generated
                                RAISE DEBUG '[batch_replace] Skipping explicit insert of generated column "%". Record: %.', _col_name, v_source_record_jsonb;
                                CONTINUE;
                            ELSE
                                -- For all other columns (temporal, ephemeral, core data) that are not the ID and not generated by DB.
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

                        -- Update founding_row_id cache if this was a new entity identified by founding_row_id
                        IF v_initial_existing_id_is_null AND
                           v_current_founding_row_id IS NOT NULL AND 
                           v_result_id IS NOT NULL AND
                           NOT (v_founding_id_cache ? v_current_founding_row_id::TEXT)
                        THEN
                            v_founding_id_cache := jsonb_set(v_founding_id_cache, ARRAY[v_current_founding_row_id::TEXT], to_jsonb(v_result_id));
                            RAISE DEBUG '[batch_replace] Cached new ID % for founding_row_id % from source_row_id %', 
                                        v_result_id, v_current_founding_row_id, v_current_source_row_id;
                        END IF;
                    END IF;
                END;
            ELSE
                 RAISE DEBUG '[batch_replace] Source row % was handled by merge/update, final insert skipped.', v_current_source_row_id;
                 -- v_result_id should have been set during the merge/update operation.
            END IF; 

            source_row_id := v_current_source_row_id;
            upserted_record_id := v_result_id; 
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

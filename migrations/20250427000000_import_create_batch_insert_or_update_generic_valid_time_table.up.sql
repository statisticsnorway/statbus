BEGIN;

-- Function to insert new records or update existing ones based on temporal overlaps.
-- Updates existing records by applying non-null values from the source.
-- Aims to minimize DELETE operations, preferring UPDATEs and INSERTs for split segments.
CREATE OR REPLACE FUNCTION import.batch_insert_or_update_generic_valid_time_table(
    p_target_schema_name TEXT,
    p_target_table_name TEXT,
    p_source_schema_name TEXT,
    p_source_table_name TEXT,
    p_unique_columns JSONB, -- For identifying existing ID if input ID is null.
    p_ephemeral_columns TEXT[], -- Columns to exclude from data comparison but keep in insert/update
    p_id_column_name TEXT, -- Name of the primary key / ID column in the target table
    p_generated_columns_override TEXT[] DEFAULT NULL -- Explicit list of DB-generated columns
)
RETURNS TABLE (
    source_row_id BIGINT,
    upserted_record_id INT,
    status TEXT,
    error_message TEXT
)
LANGUAGE plpgsql VOLATILE AS $batch_insert_or_update_generic_valid_time_table$
DECLARE
    v_input_row_record RECORD;
    v_current_source_row_id BIGINT;
    v_existing_id INT;
    v_existing_era_record RECORD;
    v_result_id INT;

    v_new_record_for_processing JSONB;
    v_existing_era_jsonb JSONB;
    
    v_source_valid_after DATE; -- Renamed from v_source_valid_from
    v_source_valid_to DATE;    -- Remains inclusive

    v_err_context TEXT;
    v_loop_error_message TEXT;

    v_founding_id_cache JSONB := '{}'::JSONB;
    v_current_founding_row_id BIGINT;
    v_initial_existing_id_is_null BOOLEAN;

    v_target_table_actual_columns TEXT[];
    v_source_target_id_alias TEXT;
    v_generated_columns TEXT[];
    v_source_query TEXT;
    v_sql TEXT;

    v_data_columns_to_consider TEXT[]; -- Columns to consider for data update (non-temporal, non-ephemeral, non-id)
    v_update_set_clause TEXT;
    v_insert_cols_list TEXT[];
    v_insert_vals_list TEXT[];
    v_source_period_fully_handled BOOLEAN;
    v_target_column_types JSONB; -- To store {column_name: udt_type}

BEGIN -- Main function body starts here
    RAISE DEBUG '[batch_update] Initializing. p_id_column_name: "%"', p_id_column_name;

    -- _insert_record helper function removed due to PL/pgSQL syntax limitations for nested functions.
    -- Its logic will need to be inlined or moved to a separate schema-level function.

    EXECUTE format(
        'SELECT array_agg(column_name::TEXT) FROM information_schema.columns WHERE table_schema = %L AND table_name = %L',
        p_target_schema_name, p_target_table_name
    ) INTO v_target_table_actual_columns;

    IF v_target_table_actual_columns IS NULL OR array_length(v_target_table_actual_columns, 1) IS NULL THEN
        RAISE EXCEPTION 'Could not retrieve column names for target table %.%', p_target_schema_name, p_target_table_name;
    END IF; -- End IF for v_target_table_actual_columns check

    -- Populate v_target_column_types now that v_target_table_actual_columns is available
    EXECUTE format(
        'SELECT jsonb_object_agg(column_name, udt_name) FROM information_schema.columns WHERE table_schema = %L AND table_name = %L AND column_name = ANY(%L::text[])',
        p_target_schema_name, p_target_table_name, v_target_table_actual_columns -- Ensure we only get types for relevant columns
    ) INTO v_target_column_types;

    IF v_target_column_types IS NULL OR v_target_column_types = '{}'::jsonb THEN
        RAISE EXCEPTION 'Could not retrieve column types for target table %.% or no columns found. Columns looked for: %', p_target_schema_name, p_target_table_name, v_target_table_actual_columns;
    END IF; -- End IF for v_target_column_types check

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
    END IF; -- End IF for p_generated_columns_override
    v_generated_columns := COALESCE(v_generated_columns, ARRAY[]::TEXT[]);
    -- Systematically treat valid_from as a generated column, to be handled by the trigger
    IF NOT ('valid_from' = ANY(v_generated_columns)) THEN
        v_generated_columns := array_append(v_generated_columns, 'valid_from');
    END IF;
    RAISE DEBUG '[batch_update] Effective generated columns (including valid_from): %', v_generated_columns;
    
    SELECT column_name INTO v_source_target_id_alias
    FROM information_schema.columns
    WHERE table_schema = p_source_schema_name AND table_name = p_source_table_name AND column_name = 'target_id';

    IF v_source_target_id_alias IS NOT NULL THEN
        v_source_query := format('SELECT src.*, src.target_id AS %I FROM %I.%I src', p_id_column_name, p_source_schema_name, p_source_table_name);
    ELSE
        v_source_query := format('SELECT * FROM %I.%I', p_source_schema_name, p_source_table_name);
    END IF; -- End IF for v_source_target_id_alias

    -- Determine data columns to consider for update (non-temporal, non-ephemeral, non-generated-id)
    SELECT array_agg(col) INTO v_data_columns_to_consider
    FROM unnest(v_target_table_actual_columns) col
    WHERE NOT (col = 'valid_after' OR col = 'valid_to') -- Use hardcoded temporal column names
      AND col != 'valid_from' -- Explicitly exclude valid_from
      AND NOT (col = ANY(p_ephemeral_columns))
      AND NOT (col = p_id_column_name AND p_id_column_name = ANY(v_generated_columns));


    FOR v_input_row_record IN EXECUTE v_source_query
    LOOP
        v_new_record_for_processing := to_jsonb(v_input_row_record);
        IF NOT (v_new_record_for_processing ? 'row_id') THEN
            RAISE EXCEPTION 'Source row ID column ''row_id'' not found in source table %.%', p_source_schema_name, p_source_table_name;
        END IF;
        v_current_source_row_id := (v_new_record_for_processing->>'row_id')::BIGINT;
        v_existing_id := (v_new_record_for_processing->>p_id_column_name)::INT;
        v_initial_existing_id_is_null := (v_existing_id IS NULL);

        -- Attempt to use founding_row_id cache if v_existing_id is NULL
        IF v_initial_existing_id_is_null THEN
            IF v_new_record_for_processing ? 'founding_row_id' AND (v_new_record_for_processing->>'founding_row_id') IS NOT NULL THEN
                v_current_founding_row_id := (v_new_record_for_processing->>'founding_row_id')::BIGINT;
                IF v_founding_id_cache ? v_current_founding_row_id::TEXT THEN
                    v_existing_id := (v_founding_id_cache->>v_current_founding_row_id::TEXT)::INT;
                    v_new_record_for_processing := jsonb_set(v_new_record_for_processing, ARRAY[p_id_column_name], to_jsonb(v_existing_id), true);
                    RAISE DEBUG '[batch_update] Cache hit for founding_row_id %: set %I to % for source_row_id %', 
                                v_current_founding_row_id, p_id_column_name, v_existing_id, v_current_source_row_id;
                ELSE
                    RAISE DEBUG '[batch_update] founding_row_id % not in cache for source_row_id %.', v_current_founding_row_id, v_current_source_row_id;
                END IF;
            ELSE
                v_current_founding_row_id := NULL;
                RAISE DEBUG '[batch_update] No founding_row_id found or it is NULL in source_row_id %.', v_current_source_row_id;
            END IF;
        ELSE
            v_current_founding_row_id := NULL; 
        END IF;

        RAISE DEBUG '[batch_update] Processing source_row_id %: %. Initial v_existing_id (after cache): %', 
            v_current_source_row_id, v_new_record_for_processing, v_existing_id;

        BEGIN -- Main processing block for each source row (v_input_row_record)
            EXECUTE 'SET CONSTRAINTS ALL DEFERRED';
            v_loop_error_message := NULL;
            v_result_id := NULL;
            v_source_period_fully_handled := FALSE; -- Initialize for each source row

            v_source_valid_after := (v_new_record_for_processing->>'valid_after')::DATE;
            v_source_valid_to    := (v_new_record_for_processing->>'valid_to')::DATE;

            IF v_source_valid_after IS NULL OR v_source_valid_to IS NULL THEN
                RAISE EXCEPTION 'Temporal columns (''valid_after'', ''valid_to'') cannot be null. Error in source row %: %',
                    v_current_source_row_id, v_new_record_for_processing;
            END IF; -- End IF for null check on source temporal columns

            -- Step 1: Resolve v_existing_id if NULL using p_unique_columns (similar to replace function)
            IF v_existing_id IS NULL AND jsonb_array_length(p_unique_columns) > 0 THEN
                DECLARE
                    v_identifying_clause TEXT;
                    v_unique_key_element JSONB;
                    v_condition_parts TEXT[];
                    v_single_condition TEXT;
                BEGIN
                    v_identifying_clause := '';
                    FOR v_unique_key_element IN SELECT * FROM jsonb_array_elements(p_unique_columns) LOOP
                        IF jsonb_typeof(v_unique_key_element) = 'string' THEN
                            v_single_condition := format('%I IS NOT DISTINCT FROM %L', v_unique_key_element#>>'{}', v_new_record_for_processing->>(v_unique_key_element#>>'{}'));
                        ELSIF jsonb_typeof(v_unique_key_element) = 'array' THEN
                            SELECT array_agg(format('%I IS NOT DISTINCT FROM %L', col_name, v_new_record_for_processing->>col_name))
                            INTO v_condition_parts
                            FROM jsonb_array_elements_text(v_unique_key_element) AS col_name;
                            v_single_condition := '(' || array_to_string(v_condition_parts, ' AND ') || ')';
                        ELSE 
                            RAISE EXCEPTION 'Invalid format in p_unique_columns: %', v_unique_key_element; 
                        END IF; -- End IF for v_unique_key_element type check
                        IF v_identifying_clause != '' THEN 
                            v_identifying_clause := v_identifying_clause || ' OR '; 
                        END IF; -- End IF for appending 'OR' to v_identifying_clause
                        v_identifying_clause := v_identifying_clause || v_single_condition;
                    END LOOP;
                    IF v_identifying_clause != '' THEN
                        EXECUTE format('SELECT %I FROM %I.%I WHERE %s LIMIT 1', p_id_column_name, p_target_schema_name, p_target_table_name, v_identifying_clause) INTO v_existing_id;
                        RAISE DEBUG '[batch_update] Identified v_existing_id via lookup: %', v_existing_id;
                    END IF; -- End IF for executing lookup if v_identifying_clause is not empty
                END;
            END IF; -- End IF for resolving v_existing_id via p_unique_columns (started L148)
            
            IF v_existing_id IS NOT NULL AND (v_new_record_for_processing->>p_id_column_name IS NULL OR (v_new_record_for_processing->>p_id_column_name)::INT IS DISTINCT FROM v_existing_id) THEN
                 v_new_record_for_processing := jsonb_set(v_new_record_for_processing, ARRAY[p_id_column_name], to_jsonb(v_existing_id), true);
            END IF; -- End IF for setting p_id_column_name in v_new_record_for_processing

            -- Step 2: If no v_existing_id, INSERT the new record
            IF v_existing_id IS NULL THEN
                RAISE DEBUG '[batch_update] No existing ID. Inserting new record for source_row_id %.', v_current_source_row_id;
                -- Inlined _insert_record logic for (v_new_record_for_processing, NULL)
                DECLARE
                    _insert_cols_list_inline TEXT[] := ARRAY[]::TEXT[];
                    _insert_vals_list_inline TEXT[] := ARRAY[]::TEXT[];
                    _col_name_inline TEXT;
                    _sql_insert_inline TEXT;
                    _inserted_id_inline INT;
                    _final_data_to_insert_inline JSONB := v_new_record_for_processing;
                BEGIN
                    -- p_record_id (second arg to _insert_record) is NULL here.
                    -- The ELSIF for p_id_column_name check in original _insert_record is not strictly needed
                    -- as v_new_record_for_processing should already have its ID field set (or not) correctly.

                    FOR _col_name_inline IN SELECT jsonb_object_keys FROM jsonb_object_keys(_final_data_to_insert_inline) LOOP
                        IF _col_name_inline = ANY(v_target_table_actual_columns) THEN
                            IF _col_name_inline = p_id_column_name AND p_id_column_name = ANY(v_generated_columns) THEN
                                IF (_final_data_to_insert_inline->>p_id_column_name) IS NOT NULL THEN 
                                    _insert_cols_list_inline := array_append(_insert_cols_list_inline, quote_ident(_col_name_inline));
                                    _insert_vals_list_inline := array_append(_insert_vals_list_inline, quote_nullable(_final_data_to_insert_inline->>_col_name_inline));
                                END IF; -- End IF for checking if generated p_id_column_name is provided
                            ELSIF _col_name_inline = 'valid_after' OR _col_name_inline = 'valid_to' THEN
                                _insert_cols_list_inline := array_append(_insert_cols_list_inline, quote_ident(_col_name_inline));
                                _insert_vals_list_inline := array_append(_insert_vals_list_inline, quote_nullable(_final_data_to_insert_inline->>_col_name_inline));
                            ELSIF _col_name_inline = 'valid_from' THEN
                                RAISE DEBUG '[batch_update] Skipping explicit insert of "valid_from" as it will be derived by trigger. Record: %.', _final_data_to_insert_inline;
                                -- Skip this column
                            ELSIF _col_name_inline = ANY(v_generated_columns) THEN
                                -- Skip other generated columns
                            ELSE
                                _insert_cols_list_inline := array_append(_insert_cols_list_inline, quote_ident(_col_name_inline));
                                _insert_vals_list_inline := array_append(_insert_vals_list_inline, quote_nullable(_final_data_to_insert_inline->>_col_name_inline));
                            END IF; -- End IF/ELSIF chain for column handling during insert
                        END IF; -- End IF for _col_name_inline = ANY(v_target_table_actual_columns)
                    END LOOP;

                    IF array_length(_insert_cols_list_inline, 1) > 0 THEN
                        _sql_insert_inline := format('INSERT INTO %I.%I (%s) VALUES (%s) RETURNING %I',
                                                p_target_schema_name, p_target_table_name,
                                                array_to_string(_insert_cols_list_inline, ', '),
                                                array_to_string(_insert_vals_list_inline, ', '),
                                                p_id_column_name);
                        RAISE DEBUG '[batch_update] Inlined insert SQL (v_existing_id IS NULL): %', _sql_insert_inline;
                        EXECUTE _sql_insert_inline INTO _inserted_id_inline;
                        v_result_id := _inserted_id_inline;

                        -- Update founding_row_id cache if this was a new entity
                        IF v_initial_existing_id_is_null AND
                           v_current_founding_row_id IS NOT NULL AND 
                           v_result_id IS NOT NULL AND
                           NOT (v_founding_id_cache ? v_current_founding_row_id::TEXT)
                        THEN
                            v_founding_id_cache := jsonb_set(v_founding_id_cache, ARRAY[v_current_founding_row_id::TEXT], to_jsonb(v_result_id));
                            RAISE DEBUG '[batch_update] Cached new ID % for founding_row_id % from source_row_id % (v_existing_id was NULL path)', 
                                        v_result_id, v_current_founding_row_id, v_current_source_row_id;
                        END IF;
                    ELSE
                        RAISE WARNING '[batch_update] No columns to insert for new record (v_existing_id IS NULL): %', _final_data_to_insert_inline;
                        v_result_id := NULL; -- p_record_id was NULL
                    END IF; -- End IF for checking if there are columns to insert
                END;
                v_source_period_fully_handled := TRUE; 
            ELSE
                -- Step 3: Handle existing records (v_existing_id IS NOT NULL)
                RAISE DEBUG '[batch_update] Existing ID % found. Processing overlaps for source_row_id %.', v_existing_id, v_current_source_row_id;
                
                -- Build the SET clause for updates: COALESCE(source.column, target.column)
                SELECT string_agg(format('%I = COALESCE(source_data.%I, target.%I)', col, col, col), ', ')
                INTO v_update_set_clause
                FROM unnest(v_data_columns_to_consider) col;
                
                -- Add ephemeral columns to SET clause (always take from source)
                IF array_length(p_ephemeral_columns, 1) > 0 THEN
                    v_update_set_clause := v_update_set_clause || ', ' || (
                        SELECT string_agg(format('%I = source_data.%I', eph_col, eph_col), ', ')
                        FROM unnest(p_ephemeral_columns) eph_col
                    );
                END IF; -- End IF for adding ephemeral columns to SET clause

                RAISE DEBUG '[batch_update] Update SET clause: %', v_update_set_clause;
                
                DECLARE
                    v_processed_via_overlap_logic BOOLEAN := FALSE;
                    v_temp_result_id INT; 
                    v_data_is_different BOOLEAN; 
                BEGIN
                    FOR v_existing_era_record IN EXECUTE format( -- Loop through existing eras of the current v_existing_id that overlap with source period
                        $$SELECT * FROM %I.%I tbl WHERE tbl.%I = %L AND public.after_to_overlaps(tbl.valid_after, tbl.valid_to, %L::DATE, %L::DATE) ORDER BY tbl.valid_after$$,
                        p_target_schema_name, p_target_table_name,
                        p_id_column_name, v_existing_id,
                        v_source_valid_after, v_source_valid_to
                    )
                    LOOP
                        v_processed_via_overlap_logic := TRUE; 
                        v_existing_era_jsonb := to_jsonb(v_existing_era_record);
                        RAISE DEBUG '[batch_update] Processing existing era for ID %: %', v_existing_id, v_existing_era_jsonb;

                        DECLARE
                            v_col_name_check TEXT;
                            _new_va DATE;
                            _new_vt DATE;
                            _ex_va DATE;
                            _ex_vt DATE;
                            v_relation public.allen_interval_relation;
                            v_source_data_select_list TEXT; -- Used in data_is_different block
                            -- v_data_is_different is declared in an outer scope, so it's fine
                        BEGIN
                            -- Initialize date variables for Allen relation calculation
                            _new_va := (v_new_record_for_processing->>'valid_after')::DATE; 
                            _new_vt := (v_new_record_for_processing->>'valid_to')::DATE;
                            _ex_va  := (v_existing_era_jsonb->>'valid_after')::DATE; 
                            _ex_vt  := (v_existing_era_jsonb->>'valid_to')::DATE;

                            -- Calculate v_data_is_different (true equivalence check)
                            v_data_is_different := FALSE; 
                            FOR v_col_name_check IN SELECT unnest(v_data_columns_to_consider) LOOP
                                IF (v_new_record_for_processing->>v_col_name_check) IS DISTINCT FROM (v_existing_era_jsonb->>v_col_name_check) THEN
                                    v_data_is_different := TRUE;
                                    RAISE DEBUG '[batch_update] Data different for column %: Source "%", Target "%"', 
                                                v_col_name_check, (v_new_record_for_processing->>v_col_name_check), (v_existing_era_jsonb->>v_col_name_check);
                                    EXIT; 
                                END IF; -- End IF for data difference check for a specific column
                            END LOOP;
                            
                            -- Get the Allen relation between source (new) and existing
                            v_relation := public.get_allen_relation(_new_va, _new_vt, _ex_va, _ex_vt);
                            RAISE DEBUG '[batch_update] Allen relation for source (% to %] and existing (% to %]: %', _new_va, _new_vt, _ex_va, _ex_vt, v_relation;

                            IF v_data_is_different THEN -- Main IF: Check if source data differs from existing era data
                                RAISE DEBUG '[batch_update] Data is different for existing era of ID %. Applying temporal update/split logic.', v_existing_id;
                                -- Inner DECLARE and BEGIN for date vars and v_relation are removed
                                CASE v_relation -- CASE for different data based on Allen relation
                                WHEN 'equals' THEN
                                    RAISE DEBUG '[batch_update] Allen case: ''equals'', data different. Updating existing era ID % from % to %.', v_existing_id, _ex_va, _ex_vt;

                                    SELECT COALESCE(string_agg(
                                        format('CAST(%L AS %s) AS %I',
                                               v_new_record_for_processing->>k,
                                               v_target_column_types->>k, -- Get type for column k
                                               k),
                                        ', '), '')
                                    INTO v_source_data_select_list
                                    FROM jsonb_object_keys(v_new_record_for_processing) k
                                    WHERE k = ANY(v_target_table_actual_columns) AND (v_target_column_types->>k) IS NOT NULL;

                                    IF v_source_data_select_list = '' THEN
                                         RAISE WARNING '[batch_update] No source columns with known types to select for source_data CTE for ID % during exact match update.', v_existing_id;
                                         v_temp_result_id := v_existing_id; -- Or handle as error
                                    ELSE
                                        v_sql := format('WITH source_data AS (SELECT %s)
                                                         UPDATE %I.%I target SET %s
                                                         FROM source_data
                                                         WHERE target.%I = %L AND target.valid_after = %L AND target.valid_to = %L RETURNING target.%I',
                                                        v_source_data_select_list,
                                                        p_target_schema_name, p_target_table_name,
                                                        v_update_set_clause,
                                                        p_id_column_name, v_existing_id,
                                                        _ex_va, 
                                                        _ex_vt, 
                                                        p_id_column_name
                                                        );
                                        RAISE DEBUG '[batch_update] Exact match update SQL: %', v_sql;
                                        EXECUTE v_sql INTO v_temp_result_id;
                                        v_source_period_fully_handled := TRUE; 
                                        EXIT; 
                                    END IF;
                                -- End of 'equals' case logic
                                WHEN 'during' THEN -- X during Y (Source is strictly contained within Existing)
                                    RAISE DEBUG '[batch_update] Allen case: ''during'' (Source strictly contained in Existing), data different. Performing split for source (% to %] and existing (% to %]', _new_va, _new_vt, _ex_va, _ex_vt;

                                    -- Delete the existing era that is being split
                                    EXECUTE format(
                                        'DELETE FROM %I.%I WHERE %I = %L AND valid_after = %L AND valid_to = %L',
                                        p_target_schema_name, p_target_table_name,
                                        p_id_column_name, v_existing_id,
                                        _ex_va, 
                                        _ex_vt
                                    );

                                    -- 1. Insert leading part (if it exists), using original data: (ex_va, new_va]
                                    IF _ex_va < _new_va THEN -- Renamed variables
                                        DECLARE
                                            _data_for_leading_part JSONB := v_existing_era_jsonb;
                                            _insert_cols_lead TEXT[] := ARRAY[]::TEXT[]; _insert_vals_lead TEXT[] := ARRAY[]::TEXT[]; _col_lead TEXT; _sql_lead TEXT; _id_lead INT;
                                        BEGIN
                                            _data_for_leading_part := jsonb_set(_data_for_leading_part, ARRAY['valid_after'], to_jsonb(_ex_va::TEXT));
                                            _data_for_leading_part := jsonb_set(_data_for_leading_part, ARRAY['valid_to'], to_jsonb(_new_va::TEXT)); -- End of leading part is new_va (inclusive)
                                            _data_for_leading_part := jsonb_set(_data_for_leading_part, ARRAY[p_id_column_name], to_jsonb(v_existing_id));

                                            FOR _col_lead IN SELECT jsonb_object_keys FROM jsonb_object_keys(_data_for_leading_part) LOOP
                                                IF _col_lead = ANY(v_target_table_actual_columns) THEN
                                                    IF _col_lead = p_id_column_name AND p_id_column_name = ANY(v_generated_columns) THEN
                                                        IF (_data_for_leading_part->>p_id_column_name) IS NOT NULL THEN _insert_cols_lead := array_append(_insert_cols_lead, quote_ident(_col_lead)); _insert_vals_lead := array_append(_insert_vals_lead, quote_nullable(_data_for_leading_part->>_col_lead)); END IF;
                                                    ELSIF _col_lead = 'valid_after' OR _col_lead = 'valid_to' THEN _insert_cols_lead := array_append(_insert_cols_lead, quote_ident(_col_lead)); _insert_vals_lead := array_append(_insert_vals_lead, quote_nullable(_data_for_leading_part->>_col_lead));
                                                    ELSIF _col_lead = 'valid_from' THEN
                                                        RAISE DEBUG '[batch_update] Skipping explicit insert of "valid_from" as it will be derived by trigger. Record: %.', _data_for_leading_part;
                                                        -- Skip this column
                                                    ELSIF _col_lead = ANY(v_generated_columns) THEN /*Skip*/
                                                    ELSE _insert_cols_lead := array_append(_insert_cols_lead, quote_ident(_col_lead)); _insert_vals_lead := array_append(_insert_vals_lead, quote_nullable(_data_for_leading_part->>_col_lead)); END IF;
                                                END IF;
                                            END LOOP;
                                            IF array_length(_insert_cols_lead,1)>0 THEN
                                                _sql_lead := format('INSERT INTO %I.%I (%s) VALUES (%s) RETURNING %I', p_target_schema_name, p_target_table_name, array_to_string(_insert_cols_lead,', '), array_to_string(_insert_vals_lead,', '), p_id_column_name);
                                                RAISE DEBUG '[batch_update] Split: Inserting leading part SQL: %', _sql_lead; EXECUTE _sql_lead INTO _id_lead;
                                            END IF;
                                        END;
                                    END IF;

                                    -- 2. Insert middle part (updated data)
                                    DECLARE
                                        _data_for_middle_part JSONB := v_existing_era_jsonb; -- Start with existing data
                                        _insert_cols_mid TEXT[] := ARRAY[]::TEXT[]; _insert_vals_mid TEXT[] := ARRAY[]::TEXT[]; _col_mid TEXT; _sql_mid TEXT; _id_mid INT;
                                    BEGIN
                                        FOR _col_mid IN SELECT unnest(v_data_columns_to_consider) LOOP
                                            IF (v_new_record_for_processing->_col_mid) IS DISTINCT FROM 'null'::jsonb THEN
                                                _data_for_middle_part := jsonb_set(_data_for_middle_part, ARRAY[_col_mid], v_new_record_for_processing->_col_mid, true);
                                            END IF;
                                        END LOOP;
                                        FOR _col_mid IN SELECT unnest(p_ephemeral_columns) LOOP -- Ephemeral always taken from source
                                            _data_for_middle_part := jsonb_set(_data_for_middle_part, ARRAY[_col_mid], v_new_record_for_processing->_col_mid, true);
                                        END LOOP;
                                        _data_for_middle_part := jsonb_set(_data_for_middle_part, ARRAY[p_id_column_name], to_jsonb(v_existing_id));
                                        _data_for_middle_part := jsonb_set(_data_for_middle_part, ARRAY['valid_after'], to_jsonb(_new_va::TEXT));
                                        _data_for_middle_part := jsonb_set(_data_for_middle_part, ARRAY['valid_to'],   to_jsonb(_new_vt::TEXT));

                                        FOR _col_mid IN SELECT jsonb_object_keys FROM jsonb_object_keys(_data_for_middle_part) LOOP
                                            IF _col_mid = ANY(v_target_table_actual_columns) THEN
                                                IF _col_mid = p_id_column_name AND p_id_column_name = ANY(v_generated_columns) THEN
                                                    IF (_data_for_middle_part->>p_id_column_name) IS NOT NULL THEN _insert_cols_mid := array_append(_insert_cols_mid, quote_ident(_col_mid)); _insert_vals_mid := array_append(_insert_vals_mid, quote_nullable(_data_for_middle_part->>_col_mid)); END IF;
                                                ELSIF _col_mid = 'valid_after' OR _col_mid = 'valid_to' THEN _insert_cols_mid := array_append(_insert_cols_mid, quote_ident(_col_mid)); _insert_vals_mid := array_append(_insert_vals_mid, quote_nullable(_data_for_middle_part->>_col_mid));
                                                ELSIF _col_mid = 'valid_from' THEN
                                                    RAISE DEBUG '[batch_update] Skipping explicit insert of "valid_from" as it will be derived by trigger. Record: %.', _data_for_middle_part;
                                                    -- Skip this column
                                                ELSIF _col_mid = ANY(v_generated_columns) THEN /*Skip*/
                                                ELSE _insert_cols_mid := array_append(_insert_cols_mid, quote_ident(_col_mid)); _insert_vals_mid := array_append(_insert_vals_mid, quote_nullable(_data_for_middle_part->>_col_mid)); END IF;
                                            END IF;
                                        END LOOP;
                                        IF array_length(_insert_cols_mid,1)>0 THEN
                                            _sql_mid := format('INSERT INTO %I.%I (%s) VALUES (%s) RETURNING %I', p_target_schema_name, p_target_table_name, array_to_string(_insert_cols_mid,', '), array_to_string(_insert_vals_mid,', '), p_id_column_name);
                                            RAISE DEBUG '[batch_update] Split: Inserting middle part SQL: %', _sql_mid; EXECUTE _sql_mid INTO _id_mid;
                                            v_temp_result_id := _id_mid; -- Main result ID is from the middle part
                                        ELSE
                                            v_temp_result_id := v_existing_id; -- Fallback
                                        END IF;
                                    END;

                                    -- 3. Insert trailing part (if it exists), using original data
                                    IF _new_vt < _ex_vt THEN
                                        DECLARE
                                            _data_for_trailing_part JSONB := v_existing_era_jsonb;
                                            _insert_cols_trail TEXT[] := ARRAY[]::TEXT[]; _insert_vals_trail TEXT[] := ARRAY[]::TEXT[]; _col_trail TEXT; _sql_trail TEXT; _id_trail INT;
                                        BEGIN
                                            _data_for_trailing_part := jsonb_set(_data_for_trailing_part, ARRAY['valid_after'], to_jsonb(_new_vt::TEXT)); -- Start of trailing is new_vt (exclusive)
                                            _data_for_trailing_part := jsonb_set(_data_for_trailing_part, ARRAY['valid_to'], to_jsonb(_ex_vt::TEXT));
                                            _data_for_trailing_part := jsonb_set(_data_for_trailing_part, ARRAY[p_id_column_name], to_jsonb(v_existing_id));

                                            FOR _col_trail IN SELECT jsonb_object_keys FROM jsonb_object_keys(_data_for_trailing_part) LOOP
                                                IF _col_trail = ANY(v_target_table_actual_columns) THEN
                                                    IF _col_trail = p_id_column_name AND p_id_column_name = ANY(v_generated_columns) THEN
                                                        IF (_data_for_trailing_part->>p_id_column_name) IS NOT NULL THEN _insert_cols_trail := array_append(_insert_cols_trail, quote_ident(_col_trail)); _insert_vals_trail := array_append(_insert_vals_trail, quote_nullable(_data_for_trailing_part->>_col_trail)); END IF;
                                                    ELSIF _col_trail = 'valid_after' OR _col_trail = 'valid_to' THEN _insert_cols_trail := array_append(_insert_cols_trail, quote_ident(_col_trail)); _insert_vals_trail := array_append(_insert_vals_trail, quote_nullable(_data_for_trailing_part->>_col_trail));
                                                    ELSIF _col_trail = 'valid_from' THEN
                                                        RAISE DEBUG '[batch_update] Skipping explicit insert of "valid_from" as it will be derived by trigger. Record: %.', _data_for_trailing_part;
                                                        -- Skip this column
                                                    ELSIF _col_trail = ANY(v_generated_columns) THEN /*Skip*/
                                                    ELSE _insert_cols_trail := array_append(_insert_cols_trail, quote_ident(_col_trail)); _insert_vals_trail := array_append(_insert_vals_trail, quote_nullable(_data_for_trailing_part->>_col_trail)); END IF;
                                                END IF;
                                            END LOOP;
                                            IF array_length(_insert_cols_trail,1)>0 THEN
                                                _sql_trail := format('INSERT INTO %I.%I (%s) VALUES (%s) RETURNING %I', p_target_schema_name, p_target_table_name, array_to_string(_insert_cols_trail,', '), array_to_string(_insert_vals_trail,', '), p_id_column_name);
                                                RAISE DEBUG '[batch_update] Split: Inserting trailing part SQL: %', _sql_trail; EXECUTE _sql_trail INTO _id_trail;
                                            END IF;
                                        END;
                                    END IF;
                                    
                                    v_source_period_fully_handled := TRUE;
                                    EXIT;
                                WHEN 'overlaps' THEN -- X overlaps Y: X.va < Y.va AND X.vt > Y.va AND X.vt < Y.vt
                                                    -- This is equivalent to "Source overlaps start of existing"
                                    RAISE DEBUG '[batch_update] Allen case: ''overlaps'' (Source overlaps start of existing), data different. Performing split & merge for source (% to %] and existing (% to %]', _new_va, _new_vt, _ex_va, _ex_vt;
                                    
                                    -- Delete the existing era that is being split/merged
                                    EXECUTE format(
                                        'DELETE FROM %I.%I WHERE %I = %L AND valid_after = %L AND valid_to = %L',
                                        p_target_schema_name, p_target_table_name,
                                        p_id_column_name, v_existing_id,
                                        _ex_va,
                                        _ex_vt
                                    );

                                    -- 1. Insert leading source part: (_new_va, _ex_va]
                                    DECLARE
                                        _data_leading_source JSONB := v_new_record_for_processing;
                                        _insert_cols_ls TEXT[] := ARRAY[]::TEXT[]; _insert_vals_ls TEXT[] := ARRAY[]::TEXT[]; _col_ls TEXT; _sql_ls TEXT; _id_ls INT;
                                    BEGIN
                                        _data_leading_source := jsonb_set(_data_leading_source, ARRAY['valid_after'], to_jsonb(_new_va::TEXT));
                                        _data_leading_source := jsonb_set(_data_leading_source, ARRAY['valid_to'], to_jsonb(_ex_va::TEXT)); -- Ends where existing began
                                        _data_leading_source := jsonb_set(_data_leading_source, ARRAY[p_id_column_name], to_jsonb(v_existing_id));

                                        FOR _col_ls IN SELECT jsonb_object_keys FROM jsonb_object_keys(_data_leading_source) LOOP
                                            IF _col_ls = ANY(v_target_table_actual_columns) THEN
                                                IF _col_ls = p_id_column_name AND p_id_column_name = ANY(v_generated_columns) THEN
                                                    IF (_data_leading_source->>p_id_column_name) IS NOT NULL THEN _insert_cols_ls := array_append(_insert_cols_ls, quote_ident(_col_ls)); _insert_vals_ls := array_append(_insert_vals_ls, quote_nullable(_data_leading_source->>_col_ls)); END IF;
                                                ELSIF _col_ls = 'valid_after' OR _col_ls = 'valid_to' THEN _insert_cols_ls := array_append(_insert_cols_ls, quote_ident(_col_ls)); _insert_vals_ls := array_append(_insert_vals_ls, quote_nullable(_data_leading_source->>_col_ls));
                                                ELSIF _col_ls = 'valid_from' THEN
                                                    RAISE DEBUG '[batch_update] Skipping explicit insert of "valid_from" as it will be derived by trigger. Record: %.', _data_leading_source;
                                                    -- Skip this column
                                                ELSIF _col_ls = ANY(v_generated_columns) THEN /*Skip*/
                                                ELSE _insert_cols_ls := array_append(_insert_cols_ls, quote_ident(_col_ls)); _insert_vals_ls := array_append(_insert_vals_ls, quote_nullable(_data_leading_source->>_col_ls)); END IF;
                                            END IF;
                                        END LOOP;
                                        IF array_length(_insert_cols_ls,1)>0 THEN
                                            _sql_ls := format('INSERT INTO %I.%I (%s) VALUES (%s) RETURNING %I', p_target_schema_name, p_target_table_name, array_to_string(_insert_cols_ls,', '), array_to_string(_insert_vals_ls,', '), p_id_column_name);
                                            RAISE DEBUG '[batch_update] Overlaps Start: Inserting leading source part SQL: %', _sql_ls; EXECUTE _sql_ls INTO _id_ls;
                                        END IF;
                                    END;
                                    
                                    -- 2. Insert middle overlapping part: (_ex_va, _new_vt]
                                    DECLARE
                                        _data_middle_overlap JSONB := v_existing_era_jsonb; -- Start with existing data
                                        _insert_cols_mo TEXT[] := ARRAY[]::TEXT[]; _insert_vals_mo TEXT[] := ARRAY[]::TEXT[]; _col_mo TEXT; _sql_mo TEXT; _id_mo INT;
                                    BEGIN
                                        FOR _col_mo IN SELECT unnest(v_data_columns_to_consider) LOOP
                                            IF (v_new_record_for_processing->_col_mo) IS DISTINCT FROM 'null'::jsonb THEN
                                                _data_middle_overlap := jsonb_set(_data_middle_overlap, ARRAY[_col_mo], v_new_record_for_processing->_col_mo, true);
                                            END IF;
                                        END LOOP;
                                        FOR _col_mo IN SELECT unnest(p_ephemeral_columns) LOOP -- Ephemeral always taken from source
                                            _data_middle_overlap := jsonb_set(_data_middle_overlap, ARRAY[_col_mo], v_new_record_for_processing->_col_mo, true);
                                        END LOOP;
                                        _data_middle_overlap := jsonb_set(_data_middle_overlap, ARRAY[p_id_column_name], to_jsonb(v_existing_id));
                                        _data_middle_overlap := jsonb_set(_data_middle_overlap, ARRAY['valid_after'], to_jsonb(_ex_va::TEXT));
                                        _data_middle_overlap := jsonb_set(_data_middle_overlap, ARRAY['valid_to'],   to_jsonb(_new_vt::TEXT));

                                        FOR _col_mo IN SELECT jsonb_object_keys FROM jsonb_object_keys(_data_middle_overlap) LOOP
                                            IF _col_mo = ANY(v_target_table_actual_columns) THEN
                                                IF _col_mo = p_id_column_name AND p_id_column_name = ANY(v_generated_columns) THEN
                                                    IF (_data_middle_overlap->>p_id_column_name) IS NOT NULL THEN _insert_cols_mo := array_append(_insert_cols_mo, quote_ident(_col_mo)); _insert_vals_mo := array_append(_insert_vals_mo, quote_nullable(_data_middle_overlap->>_col_mo)); END IF;
                                                ELSIF _col_mo = 'valid_after' OR _col_mo = 'valid_to' THEN _insert_cols_mo := array_append(_insert_cols_mo, quote_ident(_col_mo)); _insert_vals_mo := array_append(_insert_vals_mo, quote_nullable(_data_middle_overlap->>_col_mo));
                                                ELSIF _col_mo = 'valid_from' THEN
                                                    RAISE DEBUG '[batch_update] Skipping explicit insert of "valid_from" as it will be derived by trigger. Record: %.', _data_middle_overlap;
                                                    -- Skip this column
                                                ELSIF _col_mo = ANY(v_generated_columns) THEN /*Skip*/
                                                ELSE _insert_cols_mo := array_append(_insert_cols_mo, quote_ident(_col_mo)); _insert_vals_mo := array_append(_insert_vals_mo, quote_nullable(_data_middle_overlap->>_col_mo)); END IF;
                                            END IF;
                                        END LOOP;
                                        IF array_length(_insert_cols_mo,1)>0 THEN
                                            _sql_mo := format('INSERT INTO %I.%I (%s) VALUES (%s) RETURNING %I', p_target_schema_name, p_target_table_name, array_to_string(_insert_cols_mo,', '), array_to_string(_insert_vals_mo,', '), p_id_column_name);
                                            RAISE DEBUG '[batch_update] Overlaps Start: Inserting middle overlapping part SQL: %', _sql_mo; EXECUTE _sql_mo INTO _id_mo;
                                            v_temp_result_id := _id_mo; 
                                        ELSE
                                            v_temp_result_id := v_existing_id; 
                                        END IF;
                                    END;

                                    -- 3. Insert trailing existing part: (_new_vt, _ex_vt]
                                    IF _new_vt < _ex_vt THEN -- Only if there's a remaining part of existing
                                        DECLARE
                                            _data_trailing_existing JSONB := v_existing_era_jsonb;
                                            _insert_cols_te TEXT[] := ARRAY[]::TEXT[]; _insert_vals_te TEXT[] := ARRAY[]::TEXT[]; _col_te TEXT; _sql_te TEXT; _id_te INT;
                                        BEGIN
                                            _data_trailing_existing := jsonb_set(_data_trailing_existing, ARRAY['valid_after'], to_jsonb(_new_vt::TEXT));
                                            _data_trailing_existing := jsonb_set(_data_trailing_existing, ARRAY['valid_to'], to_jsonb(_ex_vt::TEXT));
                                            _data_trailing_existing := jsonb_set(_data_trailing_existing, ARRAY[p_id_column_name], to_jsonb(v_existing_id));

                                            FOR _col_te IN SELECT jsonb_object_keys FROM jsonb_object_keys(_data_trailing_existing) LOOP
                                                IF _col_te = ANY(v_target_table_actual_columns) THEN
                                                    IF _col_te = p_id_column_name AND p_id_column_name = ANY(v_generated_columns) THEN
                                                        IF (_data_trailing_existing->>p_id_column_name) IS NOT NULL THEN _insert_cols_te := array_append(_insert_cols_te, quote_ident(_col_te)); _insert_vals_te := array_append(_insert_vals_te, quote_nullable(_data_trailing_existing->>_col_te)); END IF;
                                                    ELSIF _col_te = 'valid_after' OR _col_te = 'valid_to' THEN _insert_cols_te := array_append(_insert_cols_te, quote_ident(_col_te)); _insert_vals_te := array_append(_insert_vals_te, quote_nullable(_data_trailing_existing->>_col_te));
                                                    ELSIF _col_te = 'valid_from' THEN
                                                        RAISE DEBUG '[batch_update] Skipping explicit insert of "valid_from" as it will be derived by trigger. Record: %.', _data_trailing_existing;
                                                        -- Skip this column
                                                    ELSIF _col_te = ANY(v_generated_columns) THEN /*Skip*/
                                                    ELSE _insert_cols_te := array_append(_insert_cols_te, quote_ident(_col_te)); _insert_vals_te := array_append(_insert_vals_te, quote_nullable(_data_trailing_existing->>_col_te)); END IF;
                                                END IF;
                                            END LOOP;
                                            IF array_length(_insert_cols_te,1)>0 THEN
                                                _sql_te := format('INSERT INTO %I.%I (%s) VALUES (%s) RETURNING %I', p_target_schema_name, p_target_table_name, array_to_string(_insert_cols_te,', '), array_to_string(_insert_vals_te,', '), p_id_column_name);
                                                RAISE DEBUG '[batch_update] Overlaps Start: Inserting trailing existing part SQL: %', _sql_te; EXECUTE _sql_te INTO _id_te;
                                            END IF;
                                        END;
                                    END IF;
                                    
                                    v_source_period_fully_handled := TRUE;
                                    EXIT;
                                -- WHEN 'overlapped_by' was already refactored.
                                -- The next case from the original IF/ELSIF structure is 'contains'
                                -- (Existing is contained within Source)
                                -- which corresponds to the original condition:
                                -- ELSIF _new_va < _ex_va AND _new_vt > _ex_vt THEN 
                                WHEN 'contains' THEN -- X contains Y (Y is 'during' X): Y.va > X.va AND Y.vt < X.vt
                                                     -- This is "Existing is contained within Source"
                                    RAISE DEBUG '[batch_update] Allen case: ''contains'' (Existing contained in Source), data different. Splitting source around deleted existing era (% to %] for ID %.', _ex_va, _ex_vt, v_existing_id;

                                    -- Delete the existing era that is being contained
                                    EXECUTE format(
                                        'DELETE FROM %I.%I WHERE %I = %L AND valid_after = %L AND valid_to = %L',
                                        p_target_schema_name, p_target_table_name,
                                        p_id_column_name, v_existing_id,
                                        _ex_va,
                                        _ex_vt
                                    );

                                    -- 1. Insert leading part of source (if it exists): (_new_va, _ex_va]
                                    IF _new_va < _ex_va THEN
                                        DECLARE
                                            _data_for_leading_part JSONB := v_new_record_for_processing;
                                            _insert_cols_lead TEXT[] := ARRAY[]::TEXT[]; _insert_vals_lead TEXT[] := ARRAY[]::TEXT[]; _col_lead TEXT; _sql_lead TEXT; _id_lead INT;
                                        BEGIN
                                            _data_for_leading_part := jsonb_set(_data_for_leading_part, ARRAY['valid_after'], to_jsonb(_new_va::TEXT));
                                            _data_for_leading_part := jsonb_set(_data_for_leading_part, ARRAY['valid_to'], to_jsonb(_ex_va::TEXT));
                                            _data_for_leading_part := jsonb_set(_data_for_leading_part, ARRAY[p_id_column_name], to_jsonb(v_existing_id));

                                            FOR _col_lead IN SELECT jsonb_object_keys FROM jsonb_object_keys(_data_for_leading_part) LOOP
                                                IF _col_lead = ANY(v_target_table_actual_columns) THEN
                                                    IF _col_lead = p_id_column_name AND p_id_column_name = ANY(v_generated_columns) THEN
                                                        IF (_data_for_leading_part->>p_id_column_name) IS NOT NULL THEN _insert_cols_lead := array_append(_insert_cols_lead, quote_ident(_col_lead)); _insert_vals_lead := array_append(_insert_vals_lead, quote_nullable(_data_for_leading_part->>_col_lead)); END IF;
                                                    ELSIF _col_lead = 'valid_after' OR _col_lead = 'valid_to' THEN _insert_cols_lead := array_append(_insert_cols_lead, quote_ident(_col_lead)); _insert_vals_lead := array_append(_insert_vals_lead, quote_nullable(_data_for_leading_part->>_col_lead));
                                                    ELSIF _col_lead = 'valid_from' THEN RAISE DEBUG '[batch_update] Skipping explicit insert of "valid_from" for leading part. Record: %.', _data_for_leading_part;
                                                    ELSIF _col_lead = ANY(v_generated_columns) THEN /*Skip*/
                                                    ELSE _insert_cols_lead := array_append(_insert_cols_lead, quote_ident(_col_lead)); _insert_vals_lead := array_append(_insert_vals_lead, quote_nullable(_data_for_leading_part->>_col_lead)); END IF;
                                                END IF;
                                            END LOOP;
                                            IF array_length(_insert_cols_lead,1)>0 THEN
                                                _sql_lead := format('INSERT INTO %I.%I (%s) VALUES (%s) RETURNING %I', p_target_schema_name, p_target_table_name, array_to_string(_insert_cols_lead,', '), array_to_string(_insert_vals_lead,', '), p_id_column_name);
                                                RAISE DEBUG '[batch_update] Contains Split: Inserting leading source part SQL: %', _sql_lead; EXECUTE _sql_lead INTO _id_lead;
                                            END IF;
                                        END;
                                    END IF;

                                    -- 2. Insert middle part of source (the part that replaces existing): (_ex_va, _ex_vt]
                                    DECLARE
                                        _data_for_middle_part JSONB := v_new_record_for_processing;
                                        _insert_cols_mid TEXT[] := ARRAY[]::TEXT[]; _insert_vals_mid TEXT[] := ARRAY[]::TEXT[]; _col_mid TEXT; _sql_mid TEXT; _id_mid INT;
                                    BEGIN
                                        _data_for_middle_part := jsonb_set(_data_for_middle_part, ARRAY['valid_after'], to_jsonb(_ex_va::TEXT));
                                        _data_for_middle_part := jsonb_set(_data_for_middle_part, ARRAY['valid_to'], to_jsonb(_ex_vt::TEXT));
                                        _data_for_middle_part := jsonb_set(_data_for_middle_part, ARRAY[p_id_column_name], to_jsonb(v_existing_id));

                                        FOR _col_mid IN SELECT jsonb_object_keys FROM jsonb_object_keys(_data_for_middle_part) LOOP
                                            IF _col_mid = ANY(v_target_table_actual_columns) THEN
                                                IF _col_mid = p_id_column_name AND p_id_column_name = ANY(v_generated_columns) THEN
                                                    IF (_data_for_middle_part->>p_id_column_name) IS NOT NULL THEN _insert_cols_mid := array_append(_insert_cols_mid, quote_ident(_col_mid)); _insert_vals_mid := array_append(_insert_vals_mid, quote_nullable(_data_for_middle_part->>_col_mid)); END IF;
                                                ELSIF _col_mid = 'valid_after' OR _col_mid = 'valid_to' THEN _insert_cols_mid := array_append(_insert_cols_mid, quote_ident(_col_mid)); _insert_vals_mid := array_append(_insert_vals_mid, quote_nullable(_data_for_middle_part->>_col_mid));
                                                ELSIF _col_mid = 'valid_from' THEN RAISE DEBUG '[batch_update] Skipping explicit insert of "valid_from" for middle part. Record: %.', _data_for_middle_part;
                                                ELSIF _col_mid = ANY(v_generated_columns) THEN /*Skip*/
                                                ELSE _insert_cols_mid := array_append(_insert_cols_mid, quote_ident(_col_mid)); _insert_vals_mid := array_append(_insert_vals_mid, quote_nullable(_data_for_middle_part->>_col_mid)); END IF;
                                            END IF;
                                        END LOOP;
                                        IF array_length(_insert_cols_mid,1)>0 THEN
                                            _sql_mid := format('INSERT INTO %I.%I (%s) VALUES (%s) RETURNING %I', p_target_schema_name, p_target_table_name, array_to_string(_insert_cols_mid,', '), array_to_string(_insert_vals_mid,', '), p_id_column_name);
                                            RAISE DEBUG '[batch_update] Contains Split: Inserting middle source part SQL: %', _sql_mid; EXECUTE _sql_mid INTO _id_mid;
                                            v_temp_result_id := _id_mid;
                                        ELSE
                                            v_temp_result_id := v_existing_id; -- Fallback if no columns inserted
                                        END IF;
                                    END;

                                    -- 3. Insert trailing part of source (if it exists): (_ex_vt, _new_vt]
                                    IF _ex_vt < _new_vt THEN
                                        DECLARE
                                            _data_for_trailing_part JSONB := v_new_record_for_processing;
                                            _insert_cols_trail TEXT[] := ARRAY[]::TEXT[]; _insert_vals_trail TEXT[] := ARRAY[]::TEXT[]; _col_trail TEXT; _sql_trail TEXT; _id_trail INT;
                                        BEGIN
                                            _data_for_trailing_part := jsonb_set(_data_for_trailing_part, ARRAY['valid_after'], to_jsonb(_ex_vt::TEXT));
                                            _data_for_trailing_part := jsonb_set(_data_for_trailing_part, ARRAY['valid_to'], to_jsonb(_new_vt::TEXT));
                                            _data_for_trailing_part := jsonb_set(_data_for_trailing_part, ARRAY[p_id_column_name], to_jsonb(v_existing_id));

                                            FOR _col_trail IN SELECT jsonb_object_keys FROM jsonb_object_keys(_data_for_trailing_part) LOOP
                                                IF _col_trail = ANY(v_target_table_actual_columns) THEN
                                                    IF _col_trail = p_id_column_name AND p_id_column_name = ANY(v_generated_columns) THEN
                                                        IF (_data_for_trailing_part->>p_id_column_name) IS NOT NULL THEN _insert_cols_trail := array_append(_insert_cols_trail, quote_ident(_col_trail)); _insert_vals_trail := array_append(_insert_vals_trail, quote_nullable(_data_for_trailing_part->>_col_trail)); END IF;
                                                    ELSIF _col_trail = 'valid_after' OR _col_trail = 'valid_to' THEN _insert_cols_trail := array_append(_insert_cols_trail, quote_ident(_col_trail)); _insert_vals_trail := array_append(_insert_vals_trail, quote_nullable(_data_for_trailing_part->>_col_trail));
                                                    ELSIF _col_trail = 'valid_from' THEN RAISE DEBUG '[batch_update] Skipping explicit insert of "valid_from" for trailing part. Record: %.', _data_for_trailing_part;
                                                    ELSIF _col_trail = ANY(v_generated_columns) THEN /*Skip*/
                                                    ELSE _insert_cols_trail := array_append(_insert_cols_trail, quote_ident(_col_trail)); _insert_vals_trail := array_append(_insert_vals_trail, quote_nullable(_data_for_trailing_part->>_col_trail)); END IF;
                                                END IF;
                                            END LOOP;
                                            IF array_length(_insert_cols_trail,1)>0 THEN
                                                _sql_trail := format('INSERT INTO %I.%I (%s) VALUES (%s) RETURNING %I', p_target_schema_name, p_target_table_name, array_to_string(_insert_cols_trail,', '), array_to_string(_insert_vals_trail,', '), p_id_column_name);
                                                RAISE DEBUG '[batch_update] Contains Split: Inserting trailing source part SQL: %', _sql_trail; EXECUTE _sql_trail INTO _id_trail;
                                            END IF;
                                        END;
                                    END IF;
                                    
                                    v_source_period_fully_handled := TRUE;
                                    EXIT;
                                WHEN 'starts' THEN -- X starts Y: X.va = Y.va AND X.vt < Y.vt
                                                   -- This is "Source Starts Existing"
                                    RAISE DEBUG '[batch_update] Allen case: ''starts'' (Source starts Existing), data different. Splitting existing for source (% to %] and existing (% to %]', _new_va, _new_vt, _ex_va, _ex_vt;

                                    -- Delete the existing era
                                    EXECUTE format(
                                        'DELETE FROM %I.%I WHERE %I = %L AND valid_after = %L AND valid_to = %L',
                                        p_target_schema_name, p_target_table_name,
                                        p_id_column_name, v_existing_id,
                                        _ex_va,
                                        _ex_vt
                                    );

                                    -- 1. Insert "updated source part": (_new_va, _new_vt]
                                    DECLARE
                                        _data_updated_part JSONB := v_existing_era_jsonb; 
                                        _insert_cols_up TEXT[] := ARRAY[]::TEXT[]; _insert_vals_up TEXT[] := ARRAY[]::TEXT[]; _col_up TEXT; _sql_up TEXT; _id_up INT;
                                    BEGIN
                                        FOR _col_up IN SELECT unnest(v_data_columns_to_consider) LOOP
                                            IF (v_new_record_for_processing->_col_up) IS DISTINCT FROM 'null'::jsonb THEN
                                                _data_updated_part := jsonb_set(_data_updated_part, ARRAY[_col_up], v_new_record_for_processing->_col_up, true);
                                            END IF;
                                        END LOOP;
                                        FOR _col_up IN SELECT unnest(p_ephemeral_columns) LOOP -- Ephemeral always taken from source
                                            _data_updated_part := jsonb_set(_data_updated_part, ARRAY[_col_up], v_new_record_for_processing->_col_up, true);
                                        END LOOP;
                                        _data_updated_part := jsonb_set(_data_updated_part, ARRAY[p_id_column_name], to_jsonb(v_existing_id));
                                        _data_updated_part := jsonb_set(_data_updated_part, ARRAY['valid_after'], to_jsonb(_new_va::TEXT)); -- same as _ex_va
                                        _data_updated_part := jsonb_set(_data_updated_part, ARRAY['valid_to'],   to_jsonb(_new_vt::TEXT));

                                        FOR _col_up IN SELECT jsonb_object_keys FROM jsonb_object_keys(_data_updated_part) LOOP
                                            IF _col_up = ANY(v_target_table_actual_columns) THEN
                                                IF _col_up = p_id_column_name AND p_id_column_name = ANY(v_generated_columns) THEN
                                                    IF (_data_updated_part->>p_id_column_name) IS NOT NULL THEN _insert_cols_up := array_append(_insert_cols_up, quote_ident(_col_up)); _insert_vals_up := array_append(_insert_vals_up, quote_nullable(_data_updated_part->>_col_up)); END IF;
                                                ELSIF _col_up = 'valid_after' OR _col_up = 'valid_to' THEN _insert_cols_up := array_append(_insert_cols_up, quote_ident(_col_up)); _insert_vals_up := array_append(_insert_vals_up, quote_nullable(_data_updated_part->>_col_up));
                                                ELSIF _col_up = 'valid_from' THEN
                                                    RAISE DEBUG '[batch_update] Skipping explicit insert of "valid_from" as it will be derived by trigger. Record: %.', _data_updated_part;
                                                    -- Skip this column
                                                ELSIF _col_up = ANY(v_generated_columns) THEN /*Skip*/
                                                ELSE _insert_cols_up := array_append(_insert_cols_up, quote_ident(_col_up)); _insert_vals_up := array_append(_insert_vals_up, quote_nullable(_data_updated_part->>_col_up)); END IF;
                                            END IF;
                                        END LOOP;
                                        IF array_length(_insert_cols_up,1)>0 THEN
                                            _sql_up := format('INSERT INTO %I.%I (%s) VALUES (%s) RETURNING %I', p_target_schema_name, p_target_table_name, array_to_string(_insert_cols_up,', '), array_to_string(_insert_vals_up,', '), p_id_column_name);
                                            RAISE DEBUG '[batch_update] Source Starts Existing: Inserting updated part SQL: %', _sql_up; EXECUTE _sql_up INTO v_temp_result_id;
                                        ELSE
                                            v_temp_result_id := v_existing_id; 
                                        END IF;
                                    END;

                                    -- 2. Insert "remaining existing part": (_new_vt, _ex_vt]
                                    DECLARE
                                        _data_remaining_existing JSONB := v_existing_era_jsonb; -- Original existing data
                                        _insert_cols_re TEXT[] := ARRAY[]::TEXT[]; _insert_vals_re TEXT[] := ARRAY[]::TEXT[]; _col_re TEXT; _sql_re TEXT; _id_re INT;
                                    BEGIN
                                        _data_remaining_existing := jsonb_set(_data_remaining_existing, ARRAY[p_id_column_name], to_jsonb(v_existing_id));
                                        _data_remaining_existing := jsonb_set(_data_remaining_existing, ARRAY['valid_after'], to_jsonb(_new_vt::TEXT)); -- Starts after the new part ends
                                        _data_remaining_existing := jsonb_set(_data_remaining_existing, ARRAY['valid_to'],   to_jsonb(_ex_vt::TEXT));

                                        FOR _col_re IN SELECT jsonb_object_keys FROM jsonb_object_keys(_data_remaining_existing) LOOP
                                            IF _col_re = ANY(v_target_table_actual_columns) THEN
                                                IF _col_re = p_id_column_name AND p_id_column_name = ANY(v_generated_columns) THEN
                                                    IF (_data_remaining_existing->>p_id_column_name) IS NOT NULL THEN _insert_cols_re := array_append(_insert_cols_re, quote_ident(_col_re)); _insert_vals_re := array_append(_insert_vals_re, quote_nullable(_data_remaining_existing->>_col_re)); END IF;
                                                ELSIF _col_re = 'valid_after' OR _col_re = 'valid_to' THEN _insert_cols_re := array_append(_insert_cols_re, quote_ident(_col_re)); _insert_vals_re := array_append(_insert_vals_re, quote_nullable(_data_remaining_existing->>_col_re));
                                                ELSIF _col_re = 'valid_from' THEN
                                                    RAISE DEBUG '[batch_update] Skipping explicit insert of "valid_from" as it will be derived by trigger. Record: %.', _data_remaining_existing;
                                                    -- Skip this column
                                                ELSIF _col_re = ANY(v_generated_columns) THEN /*Skip*/
                                                ELSE _insert_cols_re := array_append(_insert_cols_re, quote_ident(_col_re)); _insert_vals_re := array_append(_insert_vals_re, quote_nullable(_data_remaining_existing->>_col_re)); END IF;
                                            END IF;
                                        END LOOP;
                                        IF array_length(_insert_cols_re,1)>0 THEN
                                            _sql_re := format('INSERT INTO %I.%I (%s) VALUES (%s) RETURNING %I', p_target_schema_name, p_target_table_name, array_to_string(_insert_cols_re,', '), array_to_string(_insert_vals_re,', '), p_id_column_name);
                                            RAISE DEBUG '[batch_update] Source Starts Existing: Inserting remaining existing part SQL: %', _sql_re; EXECUTE _sql_re INTO _id_re;
                                        END IF;
                                    END;
                                    v_source_period_fully_handled := TRUE;
                                    EXIT;
                                WHEN 'started_by' THEN -- X started_by Y (Y starts X): Y.va = X.va AND Y.vt < X.vt
                                                       -- This is "Existing Starts Source"
                                    RAISE DEBUG '[batch_update] Allen case: ''started_by'' (Existing starts Source), data different. Splitting source for source (% to %] and existing (% to %]', _new_va, _new_vt, _ex_va, _ex_vt;

                                    -- Delete the existing era
                                    EXECUTE format(
                                        'DELETE FROM %I.%I WHERE %I = %L AND valid_after = %L AND valid_to = %L',
                                        p_target_schema_name, p_target_table_name,
                                        p_id_column_name, v_existing_id,
                                        _ex_va,
                                        _ex_vt
                                    );

                                    -- 1. Insert "updated part" (span of original existing): (_ex_va, _ex_vt]
                                    DECLARE
                                        _data_updated_part JSONB := v_existing_era_jsonb; 
                                        _insert_cols_up TEXT[] := ARRAY[]::TEXT[]; _insert_vals_up TEXT[] := ARRAY[]::TEXT[]; _col_up TEXT; _sql_up TEXT; _id_up INT;
                                    BEGIN
                                        FOR _col_up IN SELECT unnest(v_data_columns_to_consider) LOOP
                                            IF (v_new_record_for_processing->>_col_up) IS NOT NULL THEN
                                                _data_updated_part := jsonb_set(_data_updated_part, ARRAY[_col_up], v_new_record_for_processing->_col_up, true);
                                            END IF;
                                        END LOOP;
                                        FOR _col_up IN SELECT unnest(p_ephemeral_columns) LOOP
                                            _data_updated_part := jsonb_set(_data_updated_part, ARRAY[_col_up], v_new_record_for_processing->_col_up, true);
                                        END LOOP;
                                        _data_updated_part := jsonb_set(_data_updated_part, ARRAY[p_id_column_name], to_jsonb(v_existing_id));
                                        _data_updated_part := jsonb_set(_data_updated_part, ARRAY['valid_after'], to_jsonb(_ex_va::TEXT)); -- same as _new_va
                                        _data_updated_part := jsonb_set(_data_updated_part, ARRAY['valid_to'],   to_jsonb(_ex_vt::TEXT));

                                        FOR _col_up IN SELECT jsonb_object_keys FROM jsonb_object_keys(_data_updated_part) LOOP
                                            IF _col_up = ANY(v_target_table_actual_columns) THEN
                                                IF _col_up = p_id_column_name AND p_id_column_name = ANY(v_generated_columns) THEN
                                                    IF (_data_updated_part->>p_id_column_name) IS NOT NULL THEN _insert_cols_up := array_append(_insert_cols_up, quote_ident(_col_up)); _insert_vals_up := array_append(_insert_vals_up, quote_nullable(_data_updated_part->>_col_up)); END IF;
                                                ELSIF _col_up = 'valid_after' OR _col_up = 'valid_to' THEN _insert_cols_up := array_append(_insert_cols_up, quote_ident(_col_up)); _insert_vals_up := array_append(_insert_vals_up, quote_nullable(_data_updated_part->>_col_up));
                                                ELSIF _col_up = ANY(v_generated_columns) THEN /*Skip*/ ELSE _insert_cols_up := array_append(_insert_cols_up, quote_ident(_col_up)); _insert_vals_up := array_append(_insert_vals_up, quote_nullable(_data_updated_part->>_col_up)); END IF;
                                            END IF;
                                        END LOOP;
                                        IF array_length(_insert_cols_up,1)>0 THEN
                                            _sql_up := format('INSERT INTO %I.%I (%s) VALUES (%s) RETURNING %I', p_target_schema_name, p_target_table_name, array_to_string(_insert_cols_up,', '), array_to_string(_insert_vals_up,', '), p_id_column_name);
                                            RAISE DEBUG '[batch_update] Existing Starts Source: Inserting updated part SQL: %', _sql_up; EXECUTE _sql_up INTO v_temp_result_id;
                                        ELSE
                                            v_temp_result_id := v_existing_id; 
                                        END IF;
                                    END;

                                    -- 2. Insert "trailing source part": (_ex_vt, _new_vt]
                                    DECLARE
                                        _data_trailing_source JSONB := v_new_record_for_processing; 
                                        _insert_cols_ts TEXT[] := ARRAY[]::TEXT[]; _insert_vals_ts TEXT[] := ARRAY[]::TEXT[]; _col_ts TEXT; _sql_ts TEXT; _id_ts INT;
                                    BEGIN
                                        _data_trailing_source := jsonb_set(_data_trailing_source, ARRAY[p_id_column_name], to_jsonb(v_existing_id));
                                        _data_trailing_source := jsonb_set(_data_trailing_source, ARRAY['valid_after'], to_jsonb(_ex_vt::TEXT)); 
                                        _data_trailing_source := jsonb_set(_data_trailing_source, ARRAY['valid_to'],   to_jsonb(_new_vt::TEXT));

                                        FOR _col_ts IN SELECT jsonb_object_keys FROM jsonb_object_keys(_data_trailing_source) LOOP
                                            IF _col_ts = ANY(v_target_table_actual_columns) THEN
                                                IF _col_ts = p_id_column_name AND p_id_column_name = ANY(v_generated_columns) THEN
                                                    IF (_data_trailing_source->>p_id_column_name) IS NOT NULL THEN _insert_cols_ts := array_append(_insert_cols_ts, quote_ident(_col_ts)); _insert_vals_ts := array_append(_insert_vals_ts, quote_nullable(_data_trailing_source->>_col_ts)); END IF;
                                                ELSIF _col_ts = 'valid_after' OR _col_ts = 'valid_to' THEN _insert_cols_ts := array_append(_insert_cols_ts, quote_ident(_col_ts)); _insert_vals_ts := array_append(_insert_vals_ts, quote_nullable(_data_trailing_source->>_col_ts));
                                                ELSIF _col_ts = ANY(v_generated_columns) THEN /*Skip*/ ELSE _insert_cols_ts := array_append(_insert_cols_ts, quote_ident(_col_ts)); _insert_vals_ts := array_append(_insert_vals_ts, quote_nullable(_data_trailing_source->>_col_ts)); END IF;
                                            END IF;
                                        END LOOP;
                                        IF array_length(_insert_cols_ts,1)>0 THEN
                                            _sql_ts := format('INSERT INTO %I.%I (%s) VALUES (%s) RETURNING %I', p_target_schema_name, p_target_table_name, array_to_string(_insert_cols_ts,', '), array_to_string(_insert_vals_ts,', '), p_id_column_name);
                                            RAISE DEBUG '[batch_update] Existing Starts Source: Inserting trailing source part SQL: %', _sql_ts; EXECUTE _sql_ts INTO _id_ts;
                                        END IF;
                                    END;
                                    v_source_period_fully_handled := TRUE;
                                    EXIT;
                                WHEN 'finishes' THEN -- X finishes Y: X.va > Y.va AND X.vt = Y.vt
                                                     -- This is "Source Finishes Existing"
                                    RAISE DEBUG '[batch_update] Allen case: ''finishes'' (Source finishes Existing), data different. Splitting existing for source (% to %] and existing (% to %]', _new_va, _new_vt, _ex_va, _ex_vt;

                                    -- Delete the existing era
                                    EXECUTE format(
                                        'DELETE FROM %I.%I WHERE %I = %L AND valid_after = %L AND valid_to = %L',
                                        p_target_schema_name, p_target_table_name,
                                        p_id_column_name, v_existing_id,
                                        _ex_va,
                                        _ex_vt
                                    );

                                    -- 1. Insert "leading existing part": (_ex_va, _new_va]
                                    DECLARE
                                        _data_leading_existing JSONB := v_existing_era_jsonb; 
                                        _insert_cols_le TEXT[] := ARRAY[]::TEXT[]; _insert_vals_le TEXT[] := ARRAY[]::TEXT[]; _col_le TEXT; _sql_le TEXT; _id_le INT;
                                    BEGIN
                                        _data_leading_existing := jsonb_set(_data_leading_existing, ARRAY[p_id_column_name], to_jsonb(v_existing_id));
                                        _data_leading_existing := jsonb_set(_data_leading_existing, ARRAY['valid_after'], to_jsonb(_ex_va::TEXT));
                                        _data_leading_existing := jsonb_set(_data_leading_existing, ARRAY['valid_to'],   to_jsonb(_new_va::TEXT));

                                        FOR _col_le IN SELECT jsonb_object_keys FROM jsonb_object_keys(_data_leading_existing) LOOP
                                            IF _col_le = ANY(v_target_table_actual_columns) THEN
                                                IF _col_le = p_id_column_name AND p_id_column_name = ANY(v_generated_columns) THEN
                                                    IF (_data_leading_existing->>p_id_column_name) IS NOT NULL THEN _insert_cols_le := array_append(_insert_cols_le, quote_ident(_col_le)); _insert_vals_le := array_append(_insert_vals_le, quote_nullable(_data_leading_existing->>_col_le)); END IF;
                                                ELSIF _col_le = 'valid_after' OR _col_le = 'valid_to' THEN _insert_cols_le := array_append(_insert_cols_le, quote_ident(_col_le)); _insert_vals_le := array_append(_insert_vals_le, quote_nullable(_data_leading_existing->>_col_le));
                                                ELSIF _col_le = 'valid_from' THEN
                                                    RAISE DEBUG '[batch_update] Skipping explicit insert of "valid_from" as it will be derived by trigger. Record: %.', _data_leading_existing;
                                                    -- Skip this column
                                                ELSIF _col_le = ANY(v_generated_columns) THEN /*Skip*/
                                                ELSE _insert_cols_le := array_append(_insert_cols_le, quote_ident(_col_le)); _insert_vals_le := array_append(_insert_vals_le, quote_nullable(_data_leading_existing->>_col_le)); END IF;
                                            END IF;
                                        END LOOP;
                                        IF array_length(_insert_cols_le,1)>0 THEN
                                            _sql_le := format('INSERT INTO %I.%I (%s) VALUES (%s) RETURNING %I', p_target_schema_name, p_target_table_name, array_to_string(_insert_cols_le,', '), array_to_string(_insert_vals_le,', '), p_id_column_name);
                                            RAISE DEBUG '[batch_update] Source Finishes Existing: Inserting leading existing part SQL: %', _sql_le; EXECUTE _sql_le INTO _id_le;
                                        END IF;
                                    END;
                                    
                                    -- 2. Insert "updated finishing source part": (_new_va, _new_vt]
                                    DECLARE
                                        _data_updated_part JSONB := v_existing_era_jsonb; 
                                        _insert_cols_uf TEXT[] := ARRAY[]::TEXT[]; _insert_vals_uf TEXT[] := ARRAY[]::TEXT[]; _col_uf TEXT; _sql_uf TEXT; _id_uf INT;
                                    BEGIN
                                        FOR _col_uf IN SELECT unnest(v_data_columns_to_consider) LOOP
                                            IF (v_new_record_for_processing->v_col_uf) IS DISTINCT FROM 'null'::jsonb THEN
                                                _data_updated_part := jsonb_set(_data_updated_part, ARRAY[_col_uf], v_new_record_for_processing->v_col_uf, true);
                                            END IF;
                                        END LOOP;
                                        FOR _col_uf IN SELECT unnest(p_ephemeral_columns) LOOP -- Ephemeral always taken from source
                                            _data_updated_part := jsonb_set(_data_updated_part, ARRAY[_col_uf], v_new_record_for_processing->v_col_uf, true);
                                        END LOOP;
                                        _data_updated_part := jsonb_set(_data_updated_part, ARRAY[p_id_column_name], to_jsonb(v_existing_id));
                                        _data_updated_part := jsonb_set(_data_updated_part, ARRAY['valid_after'], to_jsonb(_new_va::TEXT));
                                        _data_updated_part := jsonb_set(_data_updated_part, ARRAY['valid_to'],   to_jsonb(_new_vt::TEXT)); -- same as _ex_vt

                                        FOR _col_uf IN SELECT jsonb_object_keys FROM jsonb_object_keys(_data_updated_part) LOOP
                                            IF _col_uf = ANY(v_target_table_actual_columns) THEN
                                                IF _col_uf = p_id_column_name AND p_id_column_name = ANY(v_generated_columns) THEN
                                                    IF (_data_updated_part->>p_id_column_name) IS NOT NULL THEN _insert_cols_uf := array_append(_insert_cols_uf, quote_ident(_col_uf)); _insert_vals_uf := array_append(_insert_vals_uf, quote_nullable(_data_updated_part->>_col_uf)); END IF;
                                                ELSIF _col_uf = 'valid_after' OR _col_uf = 'valid_to' THEN _insert_cols_uf := array_append(_insert_cols_uf, quote_ident(_col_uf)); _insert_vals_uf := array_append(_insert_vals_uf, quote_nullable(_data_updated_part->>_col_uf));
                                                ELSIF _col_uf = ANY(v_generated_columns) THEN /*Skip*/ ELSE _insert_cols_uf := array_append(_insert_cols_uf, quote_ident(_col_uf)); _insert_vals_uf := array_append(_insert_vals_uf, quote_nullable(_data_updated_part->>_col_uf)); END IF;
                                            END IF;
                                        END LOOP;
                                        IF array_length(_insert_cols_uf,1)>0 THEN
                                            _sql_uf := format('INSERT INTO %I.%I (%s) VALUES (%s) RETURNING %I', p_target_schema_name, p_target_table_name, array_to_string(_insert_cols_uf,', '), array_to_string(_insert_vals_uf,', '), p_id_column_name);
                                            RAISE DEBUG '[batch_update] Source Finishes Existing: Inserting updated finishing part SQL: %', _sql_uf; EXECUTE _sql_uf INTO v_temp_result_id;
                                        ELSE
                                            v_temp_result_id := v_existing_id; 
                                        END IF;
                                    END;
                                    v_source_period_fully_handled := TRUE;
                                    EXIT;
                                WHEN 'overlapped_by' THEN -- X overlapped_by Y (Source overlaps end of Existing)
                                                          -- X:      (----XXXX ]
                                                          -- Y: ( YYYY----]
                                                          -- Here X is source, Y is existing.
                                    RAISE DEBUG '[batch_update] Allen case: ''overlapped_by'' (Source overlaps end of existing), data different. Performing split & merge for source (% to %] and existing (% to %]', _new_va, _new_vt, _ex_va, _ex_vt;

                                    -- Delete the existing era that is being split/merged
                                    EXECUTE format(
                                        'DELETE FROM %I.%I WHERE %I = %L AND valid_after = %L AND valid_to = %L',
                                        p_target_schema_name, p_target_table_name,
                                        p_id_column_name, v_existing_id,
                                        _ex_va,
                                        _ex_vt
                                    );

                                    -- 1. Insert leading existing part: (_ex_va, _new_va]
                                    IF _ex_va < _new_va THEN -- Only if there's a leading part of existing
                                        DECLARE
                                            _data_leading_existing JSONB := v_existing_era_jsonb;
                                            _insert_cols_le TEXT[] := ARRAY[]::TEXT[]; _insert_vals_le TEXT[] := ARRAY[]::TEXT[]; _col_le TEXT; _sql_le TEXT; _id_le INT;
                                        BEGIN
                                            _data_leading_existing := jsonb_set(_data_leading_existing, ARRAY['valid_after'], to_jsonb(_ex_va::TEXT));
                                            _data_leading_existing := jsonb_set(_data_leading_existing, ARRAY['valid_to'], to_jsonb(_new_va::TEXT)); -- Ends where source begins
                                            _data_leading_existing := jsonb_set(_data_leading_existing, ARRAY[p_id_column_name], to_jsonb(v_existing_id));

                                            FOR _col_le IN SELECT jsonb_object_keys FROM jsonb_object_keys(_data_leading_existing) LOOP
                                                IF _col_le = ANY(v_target_table_actual_columns) THEN
                                                    IF _col_le = p_id_column_name AND p_id_column_name = ANY(v_generated_columns) THEN
                                                        IF (_data_leading_existing->>p_id_column_name) IS NOT NULL THEN _insert_cols_le := array_append(_insert_cols_le, quote_ident(_col_le)); _insert_vals_le := array_append(_insert_vals_le, quote_nullable(_data_leading_existing->>_col_le)); END IF;
                                                    ELSIF _col_le = 'valid_after' OR _col_le = 'valid_to' THEN _insert_cols_le := array_append(_insert_cols_le, quote_ident(_col_le)); _insert_vals_le := array_append(_insert_vals_le, quote_nullable(_data_leading_existing->>_col_le));
                                                    ELSIF _col_le = ANY(v_generated_columns) THEN /*Skip*/ ELSE _insert_cols_le := array_append(_insert_cols_le, quote_ident(_col_le)); _insert_vals_le := array_append(_insert_vals_le, quote_nullable(_data_leading_existing->>_col_le)); END IF;
                                                END IF;
                                            END LOOP;
                                            IF array_length(_insert_cols_le,1)>0 THEN
                                                _sql_le := format('INSERT INTO %I.%I (%s) VALUES (%s) RETURNING %I', p_target_schema_name, p_target_table_name, array_to_string(_insert_cols_le,', '), array_to_string(_insert_vals_le,', '), p_id_column_name);
                                                RAISE DEBUG '[batch_update] OverlappedBy: Inserting leading existing part SQL: %', _sql_le; EXECUTE _sql_le INTO _id_le;
                                            END IF;
                                        END;
                                    END IF;

                                    -- 2. Insert middle overlapping part: (_new_va, _ex_vt]
                                    DECLARE
                                        _data_middle_overlap JSONB := v_existing_era_jsonb; -- Start with existing data
                                        _insert_cols_mo TEXT[] := ARRAY[]::TEXT[]; _insert_vals_mo TEXT[] := ARRAY[]::TEXT[]; _col_mo TEXT; _sql_mo TEXT; _id_mo INT;
                                    BEGIN
                                        -- Aggressively remove 'valid_from' to ensure trigger derives it
                                        _data_middle_overlap := _data_middle_overlap - 'valid_from';
                                        RAISE DEBUG '[batch_update] OverlappedBy: _data_middle_overlap after removing valid_from: %', _data_middle_overlap;

                                        FOR _col_mo IN SELECT unnest(v_data_columns_to_consider) LOOP
                                            IF (v_new_record_for_processing->_col_mo) IS DISTINCT FROM 'null'::jsonb THEN
                                                _data_middle_overlap := jsonb_set(_data_middle_overlap, ARRAY[_col_mo], v_new_record_for_processing->_col_mo, true);
                                            END IF;
                                        END LOOP;
                                        FOR _col_mo IN SELECT unnest(p_ephemeral_columns) LOOP -- Ephemeral always taken from source
                                            _data_middle_overlap := jsonb_set(_data_middle_overlap, ARRAY[_col_mo], v_new_record_for_processing->_col_mo, true);
                                        END LOOP;
                                        _data_middle_overlap := jsonb_set(_data_middle_overlap, ARRAY[p_id_column_name], to_jsonb(v_existing_id));
                                        _data_middle_overlap := jsonb_set(_data_middle_overlap, ARRAY['valid_after'], to_jsonb(_new_va::TEXT));
                                        _data_middle_overlap := jsonb_set(_data_middle_overlap, ARRAY['valid_to'],   to_jsonb(_ex_vt::TEXT));

                                        FOR _col_mo IN SELECT jsonb_object_keys FROM jsonb_object_keys(_data_middle_overlap) LOOP
                                            IF _col_mo = ANY(v_target_table_actual_columns) THEN
                                                IF _col_mo = p_id_column_name AND p_id_column_name = ANY(v_generated_columns) THEN
                                                    IF (_data_middle_overlap->>p_id_column_name) IS NOT NULL THEN _insert_cols_mo := array_append(_insert_cols_mo, quote_ident(_col_mo)); _insert_vals_mo := array_append(_insert_vals_mo, quote_nullable(_data_middle_overlap->>_col_mo)); END IF;
                                                ELSIF _col_mo = 'valid_after' OR _col_mo = 'valid_to' THEN _insert_cols_mo := array_append(_insert_cols_mo, quote_ident(_col_mo)); _insert_vals_mo := array_append(_insert_vals_mo, quote_nullable(_data_middle_overlap->>_col_mo));
                                                ELSIF _col_mo = ANY(v_generated_columns) THEN /*Skip*/ ELSE _insert_cols_mo := array_append(_insert_cols_mo, quote_ident(_col_mo)); _insert_vals_mo := array_append(_insert_vals_mo, quote_nullable(_data_middle_overlap->>_col_mo)); END IF;
                                            END IF;
                                        END LOOP;
                                        IF array_length(_insert_cols_mo,1)>0 THEN
                                            _sql_mo := format('INSERT INTO %I.%I (%s) VALUES (%s) RETURNING %I', p_target_schema_name, p_target_table_name, array_to_string(_insert_cols_mo,', '), array_to_string(_insert_vals_mo,', '), p_id_column_name);
                                            RAISE DEBUG '[batch_update] OverlappedBy: Inserting middle overlapping part SQL: %', _sql_mo; EXECUTE _sql_mo INTO _id_mo;
                                            v_temp_result_id := _id_mo; 
                                        ELSE
                                            v_temp_result_id := v_existing_id; 
                                        END IF;
                                    END;

                                    -- 3. Insert trailing source part: (_ex_vt, _new_vt]
                                    IF _ex_vt < _new_vt THEN -- Only if there's a trailing part of source
                                        DECLARE
                                            _data_trailing_source JSONB := v_new_record_for_processing;
                                            _insert_cols_ts TEXT[] := ARRAY[]::TEXT[]; _insert_vals_ts TEXT[] := ARRAY[]::TEXT[]; _col_ts TEXT; _sql_ts TEXT; _id_ts INT;
                                        BEGIN
                                            _data_trailing_source := jsonb_set(_data_trailing_source, ARRAY['valid_after'], to_jsonb(_ex_vt::TEXT)); -- Starts where existing ended
                                            _data_trailing_source := jsonb_set(_data_trailing_source, ARRAY['valid_to'], to_jsonb(_new_vt::TEXT));
                                            _data_trailing_source := jsonb_set(_data_trailing_source, ARRAY[p_id_column_name], to_jsonb(v_existing_id));

                                            FOR _col_ts IN SELECT jsonb_object_keys FROM jsonb_object_keys(_data_trailing_source) LOOP
                                                IF _col_ts = ANY(v_target_table_actual_columns) THEN
                                                    IF _col_ts = p_id_column_name AND p_id_column_name = ANY(v_generated_columns) THEN
                                                        IF (_data_trailing_source->>p_id_column_name) IS NOT NULL THEN _insert_cols_ts := array_append(_insert_cols_ts, quote_ident(_col_ts)); _insert_vals_ts := array_append(_insert_vals_ts, quote_nullable(_data_trailing_source->>_col_ts)); END IF;
                                                    ELSIF _col_ts = 'valid_after' OR _col_ts = 'valid_to' THEN _insert_cols_ts := array_append(_insert_cols_ts, quote_ident(_col_ts)); _insert_vals_ts := array_append(_insert_vals_ts, quote_nullable(_data_trailing_source->>_col_ts));
                                                    ELSIF _col_ts = ANY(v_generated_columns) THEN /*Skip*/ ELSE _insert_cols_ts := array_append(_insert_cols_ts, quote_ident(_col_ts)); _insert_vals_ts := array_append(_insert_vals_ts, quote_nullable(_data_trailing_source->>_col_ts)); END IF;
                                                END IF;
                                            END LOOP;
                                            IF array_length(_insert_cols_ts,1)>0 THEN
                                                _sql_ts := format('INSERT INTO %I.%I (%s) VALUES (%s) RETURNING %I', p_target_schema_name, p_target_table_name, array_to_string(_insert_cols_ts,', '), array_to_string(_insert_vals_ts,', '), p_id_column_name);
                                                RAISE DEBUG '[batch_update] OverlappedBy: Inserting trailing source part SQL: %', _sql_ts; EXECUTE _sql_ts INTO _id_ts;
                                            END IF;
                                        END;
                                    END IF;
                                    
                                    v_source_period_fully_handled := TRUE;
                                    EXIT;
                                WHEN 'finished_by' THEN -- X finished_by Y (Y finishes X): Y.va < X.va AND Y.vt = X.vt
                                                       -- This is "Existing Finishes Source"
                                    RAISE DEBUG '[batch_update] Allen case: ''finished_by'' (Existing finishes Source), data different. Splitting source for source (% to %] and existing (% to %]', _new_va, _new_vt, _ex_va, _ex_vt;

                                    -- Delete the existing era
                                    EXECUTE format(
                                        'DELETE FROM %I.%I WHERE %I = %L AND valid_after = %L AND valid_to = %L',
                                        p_target_schema_name, p_target_table_name,
                                        p_id_column_name, v_existing_id,
                                        _ex_va,
                                        _ex_vt
                                    );

                                    -- 1. Insert "leading source part": (_new_va, _ex_va]
                                    DECLARE
                                        _data_leading_source JSONB := v_new_record_for_processing; 
                                        _insert_cols_ls TEXT[] := ARRAY[]::TEXT[]; _insert_vals_ls TEXT[] := ARRAY[]::TEXT[]; _col_ls TEXT; _sql_ls TEXT; _id_ls INT;
                                    BEGIN
                                        _data_leading_source := jsonb_set(_data_leading_source, ARRAY[p_id_column_name], to_jsonb(v_existing_id));
                                        _data_leading_source := jsonb_set(_data_leading_source, ARRAY['valid_after'], to_jsonb(_new_va::TEXT));
                                        _data_leading_source := jsonb_set(_data_leading_source, ARRAY['valid_to'],   to_jsonb(_ex_va::TEXT));

                                        FOR _col_ls IN SELECT jsonb_object_keys FROM jsonb_object_keys(_data_leading_source) LOOP
                                            IF _col_ls = ANY(v_target_table_actual_columns) THEN
                                                IF _col_ls = p_id_column_name AND p_id_column_name = ANY(v_generated_columns) THEN
                                                    IF (_data_leading_source->>p_id_column_name) IS NOT NULL THEN _insert_cols_ls := array_append(_insert_cols_ls, quote_ident(_col_ls)); _insert_vals_ls := array_append(_insert_vals_ls, quote_nullable(_data_leading_source->>_col_ls)); END IF;
                                                ELSIF _col_ls = 'valid_after' OR _col_ls = 'valid_to' THEN _insert_cols_ls := array_append(_insert_cols_ls, quote_ident(_col_ls)); _insert_vals_ls := array_append(_insert_vals_ls, quote_nullable(_data_leading_source->>_col_ls));
                                                ELSIF _col_ls = ANY(v_generated_columns) THEN /*Skip*/ ELSE _insert_cols_ls := array_append(_insert_cols_ls, quote_ident(_col_ls)); _insert_vals_ls := array_append(_insert_vals_ls, quote_nullable(_data_leading_source->>_col_ls)); END IF;
                                            END IF;
                                        END LOOP;
                                        IF array_length(_insert_cols_ls,1)>0 THEN
                                            _sql_ls := format('INSERT INTO %I.%I (%s) VALUES (%s) RETURNING %I', p_target_schema_name, p_target_table_name, array_to_string(_insert_cols_ls,', '), array_to_string(_insert_vals_ls,', '), p_id_column_name);
                                            RAISE DEBUG '[batch_update] Existing Finishes Source: Inserting leading source part SQL: %', _sql_ls; EXECUTE _sql_ls INTO _id_ls;
                                        END IF;
                                    END;

                                    -- 2. Insert "updated finishing part" (span of original existing): (_ex_va, _ex_vt]
                                    DECLARE
                                        _data_updated_part JSONB := v_existing_era_jsonb; 
                                        _insert_cols_uf TEXT[] := ARRAY[]::TEXT[]; _insert_vals_uf TEXT[] := ARRAY[]::TEXT[]; _col_uf TEXT; _sql_uf TEXT; _id_uf INT;
                                    BEGIN
                                        FOR _col_uf IN SELECT unnest(v_data_columns_to_consider) LOOP
                                            IF (v_new_record_for_processing->>_col_uf) IS NOT NULL THEN
                                                _data_updated_part := jsonb_set(_data_updated_part, ARRAY[_col_uf], v_new_record_for_processing->_col_uf, true);
                                            END IF;
                                        END LOOP;
                                        FOR _col_uf IN SELECT unnest(p_ephemeral_columns) LOOP
                                            _data_updated_part := jsonb_set(_data_updated_part, ARRAY[_col_uf], v_new_record_for_processing->_col_uf, true);
                                        END LOOP;
                                        _data_updated_part := jsonb_set(_data_updated_part, ARRAY[p_id_column_name], to_jsonb(v_existing_id));
                                        _data_updated_part := jsonb_set(_data_updated_part, ARRAY['valid_after'], to_jsonb(_ex_va::TEXT)); 
                                        _data_updated_part := jsonb_set(_data_updated_part, ARRAY['valid_to'],   to_jsonb(_ex_vt::TEXT)); -- same as _new_vt

                                        FOR _col_uf IN SELECT jsonb_object_keys FROM jsonb_object_keys(_data_updated_part) LOOP
                                            IF _col_uf = ANY(v_target_table_actual_columns) THEN
                                                IF _col_uf = p_id_column_name AND p_id_column_name = ANY(v_generated_columns) THEN
                                                    IF (_data_updated_part->>p_id_column_name) IS NOT NULL THEN _insert_cols_uf := array_append(_insert_cols_uf, quote_ident(_col_uf)); _insert_vals_uf := array_append(_insert_vals_uf, quote_nullable(_data_updated_part->>_col_uf)); END IF;
                                                ELSIF _col_uf = 'valid_after' OR _col_uf = 'valid_to' THEN _insert_cols_uf := array_append(_insert_cols_uf, quote_ident(_col_uf)); _insert_vals_uf := array_append(_insert_vals_uf, quote_nullable(_data_updated_part->>_col_uf));
                                                ELSIF _col_uf = ANY(v_generated_columns) THEN /*Skip*/ ELSE _insert_cols_uf := array_append(_insert_cols_uf, quote_ident(_col_uf)); _insert_vals_uf := array_append(_insert_vals_uf, quote_nullable(_data_updated_part->>_col_uf)); END IF;
                                            END IF;
                                        END LOOP;
                                        IF array_length(_insert_cols_uf,1)>0 THEN
                                            _sql_uf := format('INSERT INTO %I.%I (%s) VALUES (%s) RETURNING %I', p_target_schema_name, p_target_table_name, array_to_string(_insert_cols_uf,', '), array_to_string(_insert_vals_uf,', '), p_id_column_name);
                                            RAISE DEBUG '[batch_update] Existing Finishes Source: Inserting updated finishing part SQL: %', _sql_uf; EXECUTE _sql_uf INTO v_temp_result_id;
                                        ELSE
                                            v_temp_result_id := v_existing_id; 
                                        END IF;
                                    END;
                                    v_source_period_fully_handled := TRUE;
                                    EXIT;
                                ELSE
                                    -- Final placeholder for any other unhandled complex overlaps
                                    RAISE DEBUG '[batch_update] Data different, Allen relation % unhandled. Placeholder: v_temp_result_id set to existing_id.', v_relation;
                                    v_temp_result_id := v_existing_id;
                                    -- v_source_period_fully_handled remains FALSE for this existing_era_record,
                                    -- allowing further processing if source period extends beyond this existing_era_record.
                                    -- However, the current loop structure processes one v_existing_era_record at a time.
                                    -- Complex overlaps might need to adjust v_new_record_for_processing's date range
                                    -- and re-evaluate or continue looping. This is not yet implemented.
                                END CASE; -- End CASE for v_relation when v_data_is_different (started L301)
                        ELSE -- Data is equivalent (corresponds to IF v_data_is_different on L298)
                            RAISE DEBUG '[batch_update] Data is equivalent for existing era of ID %. Checking for merge/containment.', v_existing_id;
                            DECLARE -- Date variables for Allen relation with equivalent data
                                _new_va DATE := (v_new_record_for_processing->>'valid_after')::DATE;
                                _new_vt DATE := (v_new_record_for_processing->>'valid_to')::DATE;
                                _ex_va DATE  := (v_existing_era_jsonb->>'valid_after')::DATE;
                                _ex_vt DATE  := (v_existing_era_jsonb->>'valid_to')::DATE;
                            BEGIN -- Process Allen relations for equivalent data
                                CASE v_relation -- CASE for equivalent data based on Allen relation
                                WHEN 'equals' THEN
                                    RAISE DEBUG '[batch_update] Allen case: ''equals'', data equivalent. Updating ephemeral on existing (% to %].', _ex_va, _ex_vt;
                                    DECLARE _eph_update_set_clause TEXT;
                                    BEGIN
                                        SELECT string_agg(format('%I = %L', eph_col, v_new_record_for_processing->>eph_col), ', ')
                                        INTO _eph_update_set_clause
                                        FROM unnest(p_ephemeral_columns) eph_col
                                        WHERE v_new_record_for_processing ? eph_col;

                                        IF _eph_update_set_clause IS NOT NULL AND _eph_update_set_clause != '' THEN
                                            EXECUTE format('UPDATE %I.%I SET %s WHERE %I = %L AND valid_after = %L AND valid_to = %L',
                                                           p_target_schema_name, p_target_table_name,
                                                           _eph_update_set_clause,
                                                           p_id_column_name, v_existing_id,
                                                           _ex_va, _ex_vt);
                                        END IF;
                                    END;
                                    v_source_period_fully_handled := TRUE;
                                    v_temp_result_id := v_existing_id;
                                    EXIT;
                                WHEN 'meets' THEN -- X meets Y (Source is adjacent before Existing)
                                    RAISE DEBUG '[batch_update] Allen case: ''meets'', data equivalent. Merging by updating existing era to start earlier and updating ephemeral. Source (% to %], Existing (% to %]', _new_va, _new_vt, _ex_va, _ex_vt;
                                    DECLARE _eph_update_set_clause TEXT;
                                    BEGIN
                                        SELECT string_agg(format('%I = %L', eph_col, v_new_record_for_processing->>eph_col), ', ')
                                        INTO _eph_update_set_clause
                                        FROM unnest(p_ephemeral_columns) eph_col
                                        WHERE v_new_record_for_processing ? eph_col;

                                        IF _eph_update_set_clause IS NOT NULL AND _eph_update_set_clause != '' THEN
                                            EXECUTE format('UPDATE %I.%I SET valid_after = %L, %s WHERE %I = %L AND valid_after = %L AND valid_to = %L',
                                                           p_target_schema_name, p_target_table_name,
                                                           _new_va, -- Temporal update
                                                           _eph_update_set_clause,     -- Ephemeral update
                                                           p_id_column_name, v_existing_id,
                                                           _ex_va, _ex_vt);
                                        ELSE
                                            EXECUTE format('UPDATE %I.%I SET valid_after = %L WHERE %I = %L AND valid_after = %L AND valid_to = %L',
                                                           p_target_schema_name, p_target_table_name,
                                                           _new_va,
                                                           p_id_column_name, v_existing_id,
                                                           _ex_va, _ex_vt);
                                        END IF;
                                    END;
                                    v_source_period_fully_handled := TRUE;
                                    v_temp_result_id := v_existing_id;
                                    EXIT;
                                -- End of 'meets' case logic
                                WHEN 'met_by' THEN -- X met_by Y (Existing is adjacent before Source)
                                    RAISE DEBUG '[batch_update] Allen case: ''met_by'', data equivalent. Merging by updating existing era to end later and updating ephemeral. Source (% to %], Existing (% to %]', _new_va, _new_vt, _ex_va, _ex_vt;
                                    DECLARE _eph_update_set_clause TEXT;
                                    BEGIN
                                        SELECT string_agg(format('%I = %L', eph_col, v_new_record_for_processing->>eph_col), ', ')
                                        INTO _eph_update_set_clause
                                        FROM unnest(p_ephemeral_columns) eph_col
                                        WHERE v_new_record_for_processing ? eph_col;

                                        IF _eph_update_set_clause IS NOT NULL AND _eph_update_set_clause != '' THEN
                                            EXECUTE format('UPDATE %I.%I SET valid_to = %L, %s WHERE %I = %L AND valid_after = %L AND valid_to = %L',
                                                           p_target_schema_name, p_target_table_name,
                                                           _new_vt,   -- Temporal update
                                                           _eph_update_set_clause,   -- Ephemeral update
                                                           p_id_column_name, v_existing_id,
                                                           _ex_va, _ex_vt);
                                        ELSE
                                            EXECUTE format('UPDATE %I.%I SET valid_to = %L WHERE %I = %L AND valid_after = %L AND valid_to = %L',
                                                           p_target_schema_name, p_target_table_name,
                                                           _new_vt,
                                                           p_id_column_name, v_existing_id,
                                                           _ex_va, _ex_vt);
                                        END IF;
                                    END;
                                    v_source_period_fully_handled := TRUE;
                                    v_temp_result_id := v_existing_id;
                                    EXIT;
                                -- End of 'met_by' case logic
                                WHEN 'during' THEN -- X during Y (Source is strictly contained within Existing)
                                    RAISE DEBUG '[batch_update] Allen case: ''during'', data equivalent. Source (% to %] strictly contained. Updating ephemeral on existing (% to %].', _new_va, _new_vt, _ex_va, _ex_vt;
                                    DECLARE _eph_update_set_clause TEXT;
                                    BEGIN
                                        SELECT string_agg(format('%I = %L', eph_col, v_new_record_for_processing->>eph_col), ', ')
                                        INTO _eph_update_set_clause
                                        FROM unnest(p_ephemeral_columns) eph_col
                                        WHERE v_new_record_for_processing ? eph_col;

                                        IF _eph_update_set_clause IS NOT NULL AND _eph_update_set_clause != '' THEN
                                            EXECUTE format('UPDATE %I.%I SET %s WHERE %I = %L AND valid_after = %L AND valid_to = %L',
                                                           p_target_schema_name, p_target_table_name,
                                                           _eph_update_set_clause,
                                                           p_id_column_name, v_existing_id,
                                                           _ex_va, _ex_vt);
                                        END IF;
                                    END;
                                    v_source_period_fully_handled := TRUE;
                                    v_temp_result_id := v_existing_id;
                                    EXIT;
                                WHEN 'contains' THEN -- X contains Y (Existing is strictly contained within Source)
                                    RAISE DEBUG '[batch_update] Allen case: ''contains'', data equivalent. Existing era (% to %] is contained within source period (% to %]. Deleting existing era.', _ex_va, _ex_vt, _new_va, _new_vt;
                                    EXECUTE format(
                                        'DELETE FROM %I.%I WHERE %I = %L AND valid_after = %L AND valid_to = %L',
                                        p_target_schema_name, p_target_table_name,
                                        p_id_column_name, v_existing_id,
                                        _ex_va,
                                        _ex_vt
                                    );
                                    v_temp_result_id := v_existing_id; -- Source record will effectively use this ID for this span
                                    -- v_source_period_fully_handled remains FALSE, source record continues processing
                                -- End of 'contains' case logic
                                WHEN 'overlaps' THEN -- X overlaps Y (Source overlaps start of Existing)
                                    RAISE DEBUG '[batch_update] Allen case: ''overlaps'', data equivalent. Source (% to %] overlaps start of existing era (% to %]. Extending existing and updating ephemeral.', _new_va, _new_vt, _ex_va, _ex_vt;
                                    DECLARE _eph_update_set_clause TEXT;
                                    BEGIN
                                        SELECT string_agg(format('%I = %L', eph_col, v_new_record_for_processing->>eph_col), ', ')
                                        INTO _eph_update_set_clause
                                        FROM unnest(p_ephemeral_columns) eph_col
                                        WHERE v_new_record_for_processing ? eph_col;

                                        IF _eph_update_set_clause IS NOT NULL AND _eph_update_set_clause != '' THEN
                                            EXECUTE format('UPDATE %I.%I SET valid_after = %L, %s WHERE %I = %L AND valid_after = %L AND valid_to = %L',
                                                           p_target_schema_name, p_target_table_name,
                                                           _new_va, -- Temporal update
                                                           _eph_update_set_clause,     -- Ephemeral update
                                                           p_id_column_name, v_existing_id,
                                                           _ex_va, _ex_vt);
                                        ELSE
                                            EXECUTE format('UPDATE %I.%I SET valid_after = %L WHERE %I = %L AND valid_after = %L AND valid_to = %L',
                                                           p_target_schema_name, p_target_table_name,
                                                           _new_va,
                                                           p_id_column_name, v_existing_id,
                                                           _ex_va, _ex_vt);
                                        END IF;
                                    END;
                                    v_source_period_fully_handled := TRUE;
                                    v_temp_result_id := v_existing_id;
                                    EXIT;
                                -- End of 'overlaps' case logic
                                WHEN 'overlapped_by' THEN -- X overlapped_by Y (Source overlaps end of Existing)
                                    RAISE DEBUG '[batch_update] Allen case: ''overlapped_by'', data equivalent. Source (% to %] overlaps end of existing era (% to %]. Extending existing and updating ephemeral.', _new_va, _new_vt, _ex_va, _ex_vt;
                                    DECLARE _eph_update_set_clause TEXT;
                                    BEGIN
                                        SELECT string_agg(format('%I = %L', eph_col, v_new_record_for_processing->>eph_col), ', ')
                                        INTO _eph_update_set_clause
                                        FROM unnest(p_ephemeral_columns) eph_col
                                        WHERE v_new_record_for_processing ? eph_col;

                                        IF _eph_update_set_clause IS NOT NULL AND _eph_update_set_clause != '' THEN
                                            EXECUTE format('UPDATE %I.%I SET valid_to = %L, %s WHERE %I = %L AND valid_after = %L AND valid_to = %L',
                                                           p_target_schema_name, p_target_table_name,
                                                           _new_vt,   -- Temporal update
                                                           _eph_update_set_clause,   -- Ephemeral update
                                                           p_id_column_name, v_existing_id,
                                                           _ex_va, _ex_vt);
                                        ELSE
                                            EXECUTE format('UPDATE %I.%I SET valid_to = %L WHERE %I = %L AND valid_after = %L AND valid_to = %L',
                                                           p_target_schema_name, p_target_table_name,
                                                           _new_vt,
                                                           p_id_column_name, v_existing_id,
                                                           _ex_va, _ex_vt);
                                        END IF;
                                    END;
                                    v_source_period_fully_handled := TRUE;
                                    v_temp_result_id := v_existing_id;
                                    EXIT;
                                -- End of 'overlapped_by' case logic
                                WHEN 'starts' THEN -- X starts Y (Source Starts Existing)
                                    RAISE DEBUG '[batch_update] Allen case: ''starts'', data equivalent. Source (% to %] STARTS Existing (% to %]. Updating ephemeral on existing.', _new_va, _new_vt, _ex_va, _ex_vt;
                                    DECLARE _eph_update_set_clause TEXT;
                                    BEGIN
                                        SELECT string_agg(format('%I = %L', eph_col, v_new_record_for_processing->>eph_col), ', ')
                                        INTO _eph_update_set_clause
                                        FROM unnest(p_ephemeral_columns) eph_col
                                        WHERE v_new_record_for_processing ? eph_col;

                                        IF _eph_update_set_clause IS NOT NULL AND _eph_update_set_clause != '' THEN
                                            EXECUTE format('UPDATE %I.%I SET %s WHERE %I = %L AND valid_after = %L AND valid_to = %L',
                                                           p_target_schema_name, p_target_table_name,
                                                           _eph_update_set_clause,
                                                           p_id_column_name, v_existing_id,
                                                           _ex_va, _ex_vt);
                                        END IF;
                                    END;
                                    v_source_period_fully_handled := TRUE;
                                    v_temp_result_id := v_existing_id;
                                    EXIT;
                                WHEN 'started_by' THEN -- X started_by Y (Existing Starts Source)
                                    RAISE DEBUG '[batch_update] Allen case: ''started_by'', data equivalent. Existing (% to %] STARTS Source (% to %]. Deleting existing era.', _ex_va, _ex_vt, _new_va, _new_vt;
                                    EXECUTE format(
                                        'DELETE FROM %I.%I WHERE %I = %L AND valid_after = %L AND valid_to = %L',
                                        p_target_schema_name, p_target_table_name,
                                        p_id_column_name, v_existing_id,
                                        _ex_va,
                                        _ex_vt
                                    );
                                    v_temp_result_id := v_existing_id;
                                    -- v_source_period_fully_handled remains FALSE, source record continues processing.
                                -- End of 'started_by' case logic
                                WHEN 'finishes' THEN -- X finishes Y (Source Finishes Existing)
                                    IF _ex_vt = 'infinity' AND _new_va > _ex_va THEN
                                        RAISE DEBUG '[batch_update] Allen case: ''finishes'', data equivalent, existing ends at infinity. Updating ephemeral data on existing record. Source (% to %], Existing (% to %]', _new_va, _new_vt, _ex_va, _ex_vt;
                                        -- Update ephemeral columns on the existing record.
                                        -- The existing record (_ex_va, 'infinity') remains, but its ephemeral data is updated from the source.
                                        DECLARE
                                            _ephemeral_update_parts TEXT[];
                                            _eph_col_name TEXT;
                                            _update_stmt TEXT;
                                        BEGIN
                                            _ephemeral_update_parts := ARRAY[]::TEXT[];
                                            IF array_length(p_ephemeral_columns, 1) > 0 THEN
                                                FOR _eph_col_name IN SELECT unnest(p_ephemeral_columns) LOOP
                                                    IF v_new_record_for_processing ? _eph_col_name THEN -- Check if key exists in source
                                                        _ephemeral_update_parts := array_append(_ephemeral_update_parts,
                                                            format('%I = %L', _eph_col_name, v_new_record_for_processing->>_eph_col_name)
                                                        );
                                                    END IF;
                                                END LOOP;
                                            END IF;

                                            IF array_length(_ephemeral_update_parts, 1) > 0 THEN
                                                _update_stmt := format('UPDATE %I.%I SET %s WHERE %I = %L AND valid_after = %L AND valid_to = %L',
                                                    p_target_schema_name, p_target_table_name,
                                                    array_to_string(_ephemeral_update_parts, ', '),
                                                    p_id_column_name, v_existing_id,
                                                    _ex_va,  -- Target the existing record
                                                    _ex_vt     -- Which is (_ex_va, 'infinity')
                                                );
                                                RAISE DEBUG '[batch_update] Equivalent data, ''finishes'' with infinity: Updating ephemeral columns. SQL: %', _update_stmt;
                                                EXECUTE _update_stmt;
                                            ELSE
                                                RAISE DEBUG '[batch_update] Equivalent data, ''finishes'' with infinity: No ephemeral columns to update from source.';
                                            END IF;
                                        END;
                                        v_temp_result_id := v_existing_id; -- The existing record is the one that persists.
                                        v_source_period_fully_handled := TRUE;
                                        EXIT;
                                    ELSE
                                        -- Original 'finishes' logic for equivalent data (non-infinity or source doesn't start after existing)
                                        RAISE DEBUG '[batch_update] Allen case: ''finishes'' (non-infinity), data equivalent. Source (% to %] FINISHES Existing (% to %]. Updating ephemeral on existing.', _new_va, _new_vt, _ex_va, _ex_vt;
                                        DECLARE _eph_update_set_clause TEXT;
                                        BEGIN
                                            SELECT string_agg(format('%I = %L', eph_col, v_new_record_for_processing->>eph_col), ', ')
                                            INTO _eph_update_set_clause
                                            FROM unnest(p_ephemeral_columns) eph_col
                                            WHERE v_new_record_for_processing ? eph_col;

                                            IF _eph_update_set_clause IS NOT NULL AND _eph_update_set_clause != '' THEN
                                                EXECUTE format('UPDATE %I.%I SET %s WHERE %I = %L AND valid_after = %L AND valid_to = %L',
                                                               p_target_schema_name, p_target_table_name,
                                                               _eph_update_set_clause,
                                                               p_id_column_name, v_existing_id,
                                                               _ex_va, _ex_vt);
                                            END IF;
                                        END;
                                        v_source_period_fully_handled := TRUE;
                                        v_temp_result_id := v_existing_id;
                                        EXIT;
                                    END IF;
                                WHEN 'finished_by' THEN -- X finished_by Y (Existing Finishes Source)
                                    RAISE DEBUG '[batch_update] Allen case: ''finished_by'', data equivalent. Existing (% to %] FINISHES Source (% to %]. Deleting existing era.', _ex_va, _ex_vt, _new_va, _new_vt;
                                    EXECUTE format(
                                        'DELETE FROM %I.%I WHERE %I = %L AND valid_after = %L AND valid_to = %L',
                                        p_target_schema_name, p_target_table_name,
                                        p_id_column_name, v_existing_id,
                                        _ex_va,
                                        _ex_vt
                                    );
                                    v_temp_result_id := v_existing_id;
                                    -- v_source_period_fully_handled remains FALSE, source record continues processing.
                                -- End of 'finished_by' case logic
                                ELSE
                                    -- All specific Allen relations for equivalent data have been handled.
                                    -- This ELSE now catches 'precedes' and 'preceded_by' for which no action is taken on existing_era_record.
                                    RAISE DEBUG '[batch_update] Allen case: ''%s'', data equivalent. No direct overlap or adjacency requiring modification of this existing_era_record. Source (% to %], Existing (% to %]', v_relation, _new_va, _new_vt, _ex_va, _ex_vt;
                                    v_temp_result_id := v_existing_id; 
                                END CASE; -- End CASE for v_relation when data is equivalent (started L930)
                            END; -- End BEGIN/DECLARE block for equivalent data Allen relations (started L929/L924)
                        END IF; -- End IF v_data_is_different / ELSE (started L298)
                    END; -- Closes BEGIN for DECLARE block at L270 (BEGIN was at L280)
                    END LOOP; -- Closes FOR v_existing_era_record (started L261)

                    IF v_processed_via_overlap_logic AND v_source_period_fully_handled THEN
                        v_result_id := v_temp_result_id; 
                    ELSIF v_processed_via_overlap_logic AND NOT v_source_period_fully_handled THEN
                        RAISE DEBUG '[batch_update] Source period for ID % not fully handled by overlap logic. Attempting adjacent merge or insert for remaining period: %', v_existing_id, v_new_record_for_processing;
                        DECLARE
                            _merge_attempted_record JSONB := v_new_record_for_processing; 
                            _current_va DATE := (_merge_attempted_record->>'valid_after')::DATE;
                            _current_vt DATE := (_merge_attempted_record->>'valid_to')::DATE;
                            _merged_this_pass BOOLEAN := FALSE;
                            _final_insert_needed BOOLEAN := TRUE; 
                            _earlier_era RECORD; _later_era RECORD; _data_matches BOOLEAN; _col_check TEXT;
                            _earlier_era_jsonb JSONB; _later_era_jsonb JSONB;
                            _debug_sql TEXT;
                            -- _comparison_date DATE; -- No longer needed as adjacency is exact match
                        BEGIN
                            -- Try to merge with an earlier adjacent era: earlier_era.valid_to = _current_va
                            RAISE DEBUG '[batch_update] Adj Merge (post-overlap): Checking for earlier era. Comparing earlier.valid_to = % with _current_va = %', _current_va, _current_va;
                            _debug_sql := format('SELECT * FROM %I.%I WHERE %I = $1 AND valid_to = $2 LIMIT 1',
                                p_target_schema_name, p_target_table_name, p_id_column_name);
                            RAISE DEBUG '[batch_update] Adj Merge (post-overlap): Earlier era query: % (USING %, %)', _debug_sql, v_existing_id, _current_va;
                            EXECUTE _debug_sql INTO _earlier_era USING v_existing_id, _current_va;

                            IF _earlier_era IS NOT NULL THEN
                                RAISE DEBUG '[batch_update] Adj Merge (post-overlap): Found potential earlier era: %', _earlier_era;
                                _earlier_era_jsonb := to_jsonb(_earlier_era); _data_matches := TRUE;
                                FOR _col_check IN SELECT unnest(v_data_columns_to_consider) LOOP
                                    RAISE DEBUG '[batch_update] Adj Merge (post-overlap): Comparing column %: Source "%", Earlier Target "%"', _col_check, (_merge_attempted_record->>_col_check), (_earlier_era_jsonb->>_col_check);
                                    IF (_merge_attempted_record->>_col_check) IS DISTINCT FROM (_earlier_era_jsonb->>_col_check) THEN
                                        RAISE DEBUG '[batch_update] Adj Merge (post-overlap): Data different for column %.', _col_check;
                                        _data_matches := FALSE; EXIT;
                                    END IF;
                                END LOOP;
                                IF _data_matches THEN
                                    RAISE DEBUG '[batch_update] Adj Merge (post-overlap): Data matches earlier. Extending earlier era (ends %s) to cover source period (ends %s)', (_earlier_era_jsonb->>'valid_to')::DATE, _current_vt;
                                    EXECUTE format('UPDATE %I.%I SET valid_to = %L WHERE %I = %L AND valid_after = %L AND valid_to = %L',
                                                   p_target_schema_name, p_target_table_name, _current_vt,
                                                   p_id_column_name, v_existing_id, (_earlier_era_jsonb->>'valid_after')::DATE, (_earlier_era_jsonb->>'valid_to')::DATE);
                                    _current_va := (_earlier_era_jsonb->>'valid_after')::DATE; -- Update effective start for potential later merge
                                    v_result_id := v_existing_id; _merged_this_pass := TRUE; _final_insert_needed := FALSE;
                                ELSE
                                    RAISE DEBUG '[batch_update] Adj Merge (post-overlap): Data does NOT match earlier found record.';
                                END IF; -- End IF for earlier_era data matches
                            ELSE
                                RAISE DEBUG '[batch_update] Adj Merge (post-overlap): No earlier adjacent era found (record is NULL).';
                            END IF; -- End IF _earlier_era IS NOT NULL

                            -- Try to merge with a later adjacent era: later_era.valid_after = _current_vt
                            RAISE DEBUG '[batch_update] Adj Merge (post-overlap): Checking for later era. Comparing later.valid_after = % with _current_vt = %', _current_vt, _current_vt;
                            _debug_sql := format('SELECT * FROM %I.%I WHERE %I = $1 AND valid_after = $2 LIMIT 1',
                                p_target_schema_name, p_target_table_name, p_id_column_name);
                            RAISE DEBUG '[batch_update] Adj Merge (post-overlap): Later era query: % (USING %, %)', _debug_sql, v_existing_id, _current_vt;
                            EXECUTE _debug_sql INTO _later_era USING v_existing_id, _current_vt;

                            IF _later_era IS NOT NULL THEN
                                RAISE DEBUG '[batch_update] Adj Merge (post-overlap): Found potential later era: %', _later_era;
                                _later_era_jsonb := to_jsonb(_later_era); _data_matches := TRUE;
                                FOR _col_check IN SELECT unnest(v_data_columns_to_consider) LOOP
                                     RAISE DEBUG '[batch_update] Adj Merge (post-overlap): Comparing column %: Source "%", Later Target "%"', _col_check, (_merge_attempted_record->>_col_check), (_later_era_jsonb->>_col_check);
                                    IF (_merge_attempted_record->>_col_check) IS DISTINCT FROM (_later_era_jsonb->>_col_check) THEN
                                        RAISE DEBUG '[batch_update] Adj Merge (post-overlap): Data different for column %.', _col_check;
                                        _data_matches := FALSE; EXIT;
                                    END IF;
                                END LOOP;
                                IF _data_matches THEN
                                    RAISE DEBUG '[batch_update] Adj Merge (post-overlap): Data matches later.';
                                    IF _merged_this_pass THEN 
                                        RAISE DEBUG '[batch_update] Adj Merge (post-overlap): Extending already merged earlier record (now (%s, %s]) to cover later era (ends %s) and deleting later era.', _current_va, _current_vt, (_later_era_jsonb->>'valid_to')::DATE;
                                        EXECUTE format('UPDATE %I.%I SET valid_to = %L WHERE %I = %L AND valid_after = %L AND valid_to = %L',
                                                       p_target_schema_name, p_target_table_name, (_later_era_jsonb->>'valid_to')::DATE,
                                                       p_id_column_name, v_existing_id, _current_va, _current_vt);
                                         EXECUTE format('DELETE FROM %I.%I WHERE %I = %L AND valid_after = %L AND valid_to = %L',
                                                       p_target_schema_name, p_target_table_name, p_id_column_name, v_existing_id,
                                                       (_later_era_jsonb->>'valid_after')::DATE, (_later_era_jsonb->>'valid_to')::DATE);
                                    ELSE 
                                        RAISE DEBUG '[batch_update] Adj Merge (post-overlap): Extending source period (starts after %s) to cover later era (starts after %s) and deleting later era.', _current_va, (_later_era_jsonb->>'valid_after')::DATE;
                                        _current_vt := (_later_era_jsonb->>'valid_to')::DATE; 
                                        _merge_attempted_record := jsonb_set(_merge_attempted_record, ARRAY['valid_to'], to_jsonb(_current_vt::TEXT));
                                        EXECUTE format('DELETE FROM %I.%I WHERE %I = %L AND valid_after = %L AND valid_to = %L',
                                                       p_target_schema_name, p_target_table_name, p_id_column_name, v_existing_id,
                                                       (_later_era_jsonb->>'valid_after')::DATE, (_later_era_jsonb->>'valid_to')::DATE);
                                    END IF;
                                    v_result_id := v_existing_id; _final_insert_needed := TRUE; 
                                    IF _merged_this_pass THEN _final_insert_needed := FALSE; END IF; -- End IF for setting _final_insert_needed based on _merged_this_pass
                                ELSE
                                    RAISE DEBUG '[batch_update] Adj Merge (post-overlap): Data does NOT match later found record.';
                                END IF; -- End IF for later_era data matches
                            ELSE
                                IF _merged_this_pass THEN RAISE DEBUG '[batch_update] Adj Merge (post-overlap): No later adjacent era found (record is NULL), but earlier merge happened.';
                                ELSE RAISE DEBUG '[batch_update] Adj Merge (post-overlap): No later adjacent era found (record is NULL) and no earlier merge.'; END IF;
                            END IF; -- End IF _later_era IS NOT NULL

                            IF _final_insert_needed THEN
                                RAISE DEBUG '[batch_update] No/incomplete adjacent merge for ID % (post-overlap). Inserting as new slice: %', v_existing_id, _merge_attempted_record;
                                DECLARE
                                    _insert_cols_list_inline_2 TEXT[] := ARRAY[]::TEXT[];
                                    _insert_vals_list_inline_2 TEXT[] := ARRAY[]::TEXT[];
                                    _col_name_inline_2 TEXT;
                                    _sql_insert_inline_2 TEXT;
                                    _inserted_id_inline_2 INT;
                                    _final_data_to_insert_inline_2 JSONB := _merge_attempted_record; 
                                BEGIN
                                    IF v_existing_id IS NOT NULL THEN
                                        _final_data_to_insert_inline_2 := jsonb_set(_final_data_to_insert_inline_2, ARRAY[p_id_column_name], to_jsonb(v_existing_id), true);
                                    ELSIF (_final_data_to_insert_inline_2->>p_id_column_name) IS NULL AND NOT (p_id_column_name = ANY(v_generated_columns)) THEN
                                         RAISE DEBUG '[batch_update] Inlined insert (post-overlap): ID is NULL in data and not a generated column, v_existing_id also NULL. Data: %', _final_data_to_insert_inline_2;
                                    END IF; -- End IF/ELSIF for setting p_id_column_name in _final_data_to_insert_inline_2

                                    FOR _col_name_inline_2 IN SELECT jsonb_object_keys FROM jsonb_object_keys(_final_data_to_insert_inline_2) LOOP
                                        IF _col_name_inline_2 = ANY(v_target_table_actual_columns) THEN
                                            IF _col_name_inline_2 = p_id_column_name AND p_id_column_name = ANY(v_generated_columns) THEN
                                                IF (_final_data_to_insert_inline_2->>p_id_column_name) IS NOT NULL THEN 
                                                    _insert_cols_list_inline_2 := array_append(_insert_cols_list_inline_2, quote_ident(_col_name_inline_2));
                                                    _insert_vals_list_inline_2 := array_append(_insert_vals_list_inline_2, quote_nullable(_final_data_to_insert_inline_2->>_col_name_inline_2));
                                                END IF; -- End IF for checking if generated p_id_column_name is provided in data
                                            ELSIF _col_name_inline_2 = 'valid_after' OR _col_name_inline_2 = 'valid_to' THEN
                                                _insert_cols_list_inline_2 := array_append(_insert_cols_list_inline_2, quote_ident(_col_name_inline_2));
                                                _insert_vals_list_inline_2 := array_append(_insert_vals_list_inline_2, quote_nullable(_final_data_to_insert_inline_2->>_col_name_inline_2));
                                            ELSIF _col_name_inline_2 = 'valid_from' THEN
                                                RAISE DEBUG '[batch_update] Skipping explicit insert of "valid_from" as it will be derived by trigger. Record: %.', _final_data_to_insert_inline_2;
                                                -- Skip this column
                                            ELSIF _col_name_inline_2 = ANY(v_generated_columns) THEN
                                                -- Skip other generated columns
                                            ELSE
                                                _insert_cols_list_inline_2 := array_append(_insert_cols_list_inline_2, quote_ident(_col_name_inline_2));
                                                _insert_vals_list_inline_2 := array_append(_insert_vals_list_inline_2, quote_nullable(_final_data_to_insert_inline_2->>_col_name_inline_2));
                                            END IF; -- End IF/ELSIF chain for column handling in inlined insert (post-overlap)
                                        END IF; -- End IF for _col_name_inline_2 = ANY(v_target_table_actual_columns)
                                    END LOOP;

                                    IF array_length(_insert_cols_list_inline_2, 1) > 0 THEN
                                        _sql_insert_inline_2 := format('INSERT INTO %I.%I (%s) VALUES (%s) RETURNING %I',
                                                                p_target_schema_name, p_target_table_name,
                                                                array_to_string(_insert_cols_list_inline_2, ', '),
                                                                array_to_string(_insert_vals_list_inline_2, ', '),
                                                                p_id_column_name);
                                        RAISE DEBUG '[batch_update] Inlined insert SQL (processed_via_overlap AND NOT fully_handled): %', _sql_insert_inline_2;
                                        EXECUTE _sql_insert_inline_2 INTO _inserted_id_inline_2;
                                        v_result_id := _inserted_id_inline_2;
                                    ELSE
                                        RAISE WARNING '[batch_update] No columns to insert for record (post-overlap): %', _merge_attempted_record;
                                        v_result_id := v_existing_id; 
                                    END IF; -- End IF for checking if there are columns to insert (post-overlap)
                                END; -- End of inlined insert logic
                            END IF; -- End IF _final_insert_needed (post-overlap)
                        END; -- End of merge attempt block for "post-overlap"
                    ELSE -- NOT v_processed_via_overlap_logic (i.e., no overlaps found for this existing_id)
                        RAISE DEBUG '[batch_update] Existing ID % found, but no overlap with source period. Attempting adjacent merge or insert.', v_existing_id;
                        -- Attempt to merge with adjacent records before inserting as a new slice
                        DECLARE
                            _merge_attempted_record JSONB := v_new_record_for_processing;
                            _current_va DATE := (v_new_record_for_processing->>'valid_after')::DATE;
                            _current_vt DATE := (v_new_record_for_processing->>'valid_to')::DATE;
                            _merged_this_pass BOOLEAN := FALSE;
                            _final_insert_needed BOOLEAN := TRUE;
                            _earlier_era RECORD; _later_era RECORD; _data_matches BOOLEAN; _col_check TEXT;
                            _earlier_era_jsonb JSONB; _later_era_jsonb JSONB;
                            _debug_sql TEXT;
                            -- _test_count INT; -- Diagnostic removed
                            -- _debug_sql_count TEXT; -- Diagnostic removed
                            -- _comparison_date DATE; -- No longer needed
                        BEGIN
                            -- Try to merge with an earlier adjacent era: earlier_era.valid_to = _current_va
                            RAISE DEBUG '[batch_update] Adj Merge (no overlap): Checking for earlier era. Comparing earlier.valid_to = % with _current_va = %', _current_va, _current_va;

                            _debug_sql := format('SELECT * FROM %I.%I WHERE %I = $1 AND valid_to = $2 LIMIT 1',
                                p_target_schema_name, p_target_table_name, p_id_column_name);
                            RAISE DEBUG '[batch_update] Adj Merge (no overlap): Earlier era query: % (USING %, %)', _debug_sql, v_existing_id, _current_va;
                            EXECUTE _debug_sql INTO _earlier_era USING v_existing_id, _current_va;

                            IF _earlier_era IS NOT NULL THEN
                                RAISE DEBUG '[batch_update] Adj Merge (no overlap): Found potential earlier era: %', _earlier_era;
                                _earlier_era_jsonb := to_jsonb(_earlier_era); _data_matches := TRUE;
                                FOR _col_check IN SELECT unnest(v_data_columns_to_consider) LOOP
                                    RAISE DEBUG '[batch_update] Adj Merge (no overlap): Comparing column %: Source "%", Earlier Target "%"', _col_check, (_merge_attempted_record->>_col_check), (_earlier_era_jsonb->>_col_check);
                                    IF (_merge_attempted_record->>_col_check) IS DISTINCT FROM (_earlier_era_jsonb->>_col_check) THEN
                                        RAISE DEBUG '[batch_update] Adj Merge (no overlap): Data different for column %.', _col_check;
                                        _data_matches := FALSE; EXIT;
                                    END IF;
                                END LOOP;
                                IF _data_matches THEN
                                    RAISE DEBUG '[batch_update] Adj Merge (no overlap): Data matches earlier. Extending earlier era (ends %s) to cover source period (ends %s) and updating ephemeral columns.', (_earlier_era_jsonb->>'valid_to')::DATE, _current_vt;
                                    DECLARE _eph_update_set_clause_adj TEXT;
                                    BEGIN
                                        SELECT string_agg(format('%I = %L', eph_col, _merge_attempted_record->>eph_col), ', ')
                                        INTO _eph_update_set_clause_adj
                                        FROM unnest(p_ephemeral_columns) eph_col
                                        WHERE _merge_attempted_record ? eph_col;

                                        IF _eph_update_set_clause_adj IS NOT NULL AND _eph_update_set_clause_adj != '' THEN
                                            EXECUTE format('UPDATE %I.%I SET valid_to = %L, %s WHERE %I = %L AND valid_after = %L AND valid_to = %L',
                                                           p_target_schema_name, p_target_table_name, 
                                                           _current_vt, -- Temporal update
                                                           _eph_update_set_clause_adj,  -- Ephemeral update
                                                           p_id_column_name, v_existing_id, 
                                                           (_earlier_era_jsonb->>'valid_after')::DATE, 
                                                           (_earlier_era_jsonb->>'valid_to')::DATE);
                                        ELSE
                                            EXECUTE format('UPDATE %I.%I SET valid_to = %L WHERE %I = %L AND valid_after = %L AND valid_to = %L',
                                                           p_target_schema_name, p_target_table_name, 
                                                           _current_vt,
                                                           p_id_column_name, v_existing_id, 
                                                           (_earlier_era_jsonb->>'valid_after')::DATE, 
                                                           (_earlier_era_jsonb->>'valid_to')::DATE);
                                        END IF;
                                    END;
                                    _current_va := (_earlier_era_jsonb->>'valid_after')::DATE; -- Update effective start for potential later merge
                                    v_result_id := v_existing_id; _merged_this_pass := TRUE; _final_insert_needed := FALSE;
                                ELSE
                                     RAISE DEBUG '[batch_update] Adj Merge (no overlap): Data does NOT match earlier found record.';
                                END IF; -- End IF for earlier_era data matches (no overlap)
                            ELSE
                                RAISE DEBUG '[batch_update] Adj Merge (no overlap): No earlier adjacent era found (record is NULL).';
                            END IF; -- End IF _earlier_era IS NOT NULL (no overlap)

                            -- Try to merge with a later adjacent era: later_era.valid_after = _current_vt
                            RAISE DEBUG '[batch_update] Adj Merge (no overlap): Checking for later era. Comparing later.valid_after = % with _current_vt = %', _current_vt, _current_vt;
                            _debug_sql := format('SELECT * FROM %I.%I WHERE %I = $1 AND valid_after = $2 LIMIT 1',
                                p_target_schema_name, p_target_table_name, p_id_column_name);
                            RAISE DEBUG '[batch_update] Adj Merge (no overlap): Later era query: % (USING %, %)', _debug_sql, v_existing_id, _current_vt;
                            EXECUTE _debug_sql INTO _later_era USING v_existing_id, _current_vt;

                            IF _later_era IS NOT NULL THEN
                                RAISE DEBUG '[batch_update] Adj Merge (no overlap): Found potential later era: %', _later_era;
                                _later_era_jsonb := to_jsonb(_later_era); _data_matches := TRUE;
                                FOR _col_check IN SELECT unnest(v_data_columns_to_consider) LOOP
                                    RAISE DEBUG '[batch_update] Adj Merge (no overlap): Comparing column %: Source "%", Later Target "%"', _col_check, (_merge_attempted_record->>_col_check), (_later_era_jsonb->>_col_check);
                                    IF (_merge_attempted_record->>_col_check) IS DISTINCT FROM (_later_era_jsonb->>_col_check) THEN
                                        RAISE DEBUG '[batch_update] Adj Merge (no overlap): Data different for column %.', _col_check;
                                        _data_matches := FALSE; EXIT;
                                    END IF;
                                END LOOP;
                                IF _data_matches THEN
                                    RAISE DEBUG '[batch_update] Adj Merge (no overlap): Data matches later.';
                                     IF _merged_this_pass THEN 
                                        RAISE DEBUG '[batch_update] Adj Merge (no overlap): Extending already merged earlier record (now (%s, %s]) to cover later era (ends %s) and deleting later era.', _current_va, _current_vt, (_later_era_jsonb->>'valid_to')::DATE;
                                        EXECUTE format('UPDATE %I.%I SET valid_to = %L WHERE %I = %L AND valid_after = %L AND valid_to = %L',
                                                       p_target_schema_name, p_target_table_name, (_later_era_jsonb->>'valid_to')::DATE,
                                                       p_id_column_name, v_existing_id, _current_va, _current_vt);
                                         EXECUTE format('DELETE FROM %I.%I WHERE %I = %L AND valid_after = %L AND valid_to = %L',
                                                       p_target_schema_name, p_target_table_name, p_id_column_name, v_existing_id,
                                                       (_later_era_jsonb->>'valid_after')::DATE, (_later_era_jsonb->>'valid_to')::DATE);
                                    ELSE 
                                        RAISE DEBUG '[batch_update] Adj Merge (no overlap): Extending later era (starts after %s) to cover source period (starts after %s)', (_later_era_jsonb->>'valid_after')::DATE, _current_va;
                                        EXECUTE format('UPDATE %I.%I SET valid_after = %L WHERE %I = %L AND valid_after = %L AND valid_to = %L',
                                                       p_target_schema_name, p_target_table_name, _current_va,
                                                       p_id_column_name, v_existing_id, (_later_era_jsonb->>'valid_after')::DATE, (_later_era_jsonb->>'valid_to')::DATE);
                                    END IF;
                                    v_result_id := v_existing_id; _final_insert_needed := FALSE;
                                ELSE
                                    RAISE DEBUG '[batch_update] Adj Merge (no overlap): Data does NOT match later found record.';
                                END IF; -- End IF for later_era data matches (no overlap)
                            ELSE
                                IF _merged_this_pass THEN RAISE DEBUG '[batch_update] Adj Merge (no overlap): No later adjacent era found (record is NULL), but earlier merge happened.';
                                ELSE RAISE DEBUG '[batch_update] Adj Merge (no overlap): No later adjacent era found (record is NULL) and no earlier merge.'; END IF;
                            END IF; -- End IF _later_era IS NOT NULL (no overlap)
                            
                            IF _final_insert_needed THEN
                                RAISE DEBUG '[batch_update] No adjacent merge possible for ID % (no overlap). Inserting as new slice: %', v_existing_id, _merge_attempted_record;
                                DECLARE
                                    _insert_cols_list_inline_3 TEXT[] := ARRAY[]::TEXT[];
                                    _insert_vals_list_inline_3 TEXT[] := ARRAY[]::TEXT[];
                                    _col_name_inline_3 TEXT;
                                    _sql_insert_inline_3 TEXT;
                                    _inserted_id_inline_3 INT;
                                    _final_data_to_insert_inline_3 JSONB := _merge_attempted_record; -- Use _merge_attempted_record as it might have been modified
                                BEGIN
                            IF v_existing_id IS NOT NULL THEN
                                _final_data_to_insert_inline_3 := jsonb_set(_final_data_to_insert_inline_3, ARRAY[p_id_column_name], to_jsonb(v_existing_id), true);
                            ELSIF (_final_data_to_insert_inline_3->>p_id_column_name) IS NULL AND NOT (p_id_column_name = ANY(v_generated_columns)) THEN
                                 RAISE DEBUG '[batch_update] Inlined insert: ID is NULL in data and not a generated column, v_existing_id also NULL. Data: %', _final_data_to_insert_inline_3;
                            END IF; -- End IF/ELSIF for setting p_id_column_name in _final_data_to_insert_inline_3

                            FOR _col_name_inline_3 IN EXECUTE format('SELECT jsonb_object_keys FROM jsonb_object_keys(%L::jsonb)', _final_data_to_insert_inline_3) LOOP
                                IF EXISTS (SELECT 1 FROM unnest(v_target_table_actual_columns) AS u(col) WHERE u.col = _col_name_inline_3) THEN
                                    IF _col_name_inline_3 = p_id_column_name AND p_id_column_name = ANY(v_generated_columns) THEN
                                        IF (_final_data_to_insert_inline_3->>p_id_column_name) IS NOT NULL THEN 
                                            _insert_cols_list_inline_3 := array_append(_insert_cols_list_inline_3, quote_ident(_col_name_inline_3));
                                            _insert_vals_list_inline_3 := array_append(_insert_vals_list_inline_3, quote_nullable(_final_data_to_insert_inline_3->>_col_name_inline_3));
                                        END IF; -- End IF for checking if generated p_id_column_name is provided in data (no overlap)
                                    ELSIF _col_name_inline_3 = 'valid_after' OR _col_name_inline_3 = 'valid_to' THEN
                                        _insert_cols_list_inline_3 := array_append(_insert_cols_list_inline_3, quote_ident(_col_name_inline_3));
                                        _insert_vals_list_inline_3 := array_append(_insert_vals_list_inline_3, quote_nullable(_final_data_to_insert_inline_3->>_col_name_inline_3));
                                    ELSIF _col_name_inline_3 = 'valid_from' THEN
                                        RAISE DEBUG '[batch_update] Skipping explicit insert of "valid_from" as it will be derived by trigger. Record: %.', _final_data_to_insert_inline_3;
                                        -- Skip this column
                                    ELSIF _col_name_inline_3 = ANY(v_generated_columns) THEN
                                        -- Skip other generated columns
                                    ELSE
                                        _insert_cols_list_inline_3 := array_append(_insert_cols_list_inline_3, quote_ident(_col_name_inline_3));
                                        _insert_vals_list_inline_3 := array_append(_insert_vals_list_inline_3, quote_nullable(_final_data_to_insert_inline_3->>_col_name_inline_3));
                                    END IF; -- End IF/ELSIF chain for column handling in inlined insert (no overlap)
                                END IF; -- End IF for EXISTS check of _col_name_inline_3 in v_target_table_actual_columns
                            END LOOP;

                            IF array_length(_insert_cols_list_inline_3, 1) > 0 THEN
                                _sql_insert_inline_3 := format('INSERT INTO %I.%I (%s) VALUES (%s) RETURNING %I',
                                                        p_target_schema_name, p_target_table_name,
                                                        array_to_string(_insert_cols_list_inline_3, ', '),
                                                        array_to_string(_insert_vals_list_inline_3, ', '),
                                                        p_id_column_name);
                                RAISE DEBUG '[batch_update] Inlined insert SQL (NOT processed_via_overlap): %', _sql_insert_inline_3;
                                EXECUTE _sql_insert_inline_3 INTO _inserted_id_inline_3;
                                v_result_id := _inserted_id_inline_3;
                            ELSE
                                RAISE WARNING '[batch_update] No columns to insert for record (no overlap): %', _merge_attempted_record;
                                v_result_id := v_existing_id; 
                            END IF; -- End IF for checking if there are columns to insert (no overlap)
                                END; -- End of inlined insert logic for _inline_3
                            END IF; -- End IF _final_insert_needed (no overlap)
                        END; -- End of merge attempt block for "no overlap"
                    END IF; -- Closes IF v_processed_via_overlap_logic AND v_source_period_fully_handled (started L1042) / ELSIF / ELSE structure
                END; -- Closes DECLARE/BEGIN block for existing_id processing (started L252)
            END IF; -- Closes IF v_existing_id IS NULL / ELSE (started L180)

            source_row_id := v_current_source_row_id;
            upserted_record_id := v_result_id;
            status := 'SUCCESS';
            error_message := NULL;
            RETURN NEXT;

        EXCEPTION WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS v_loop_error_message = MESSAGE_TEXT, v_err_context = PG_EXCEPTION_CONTEXT;
            RAISE WARNING '[batch_update] Error processing source_row_id % (%): %. Context: %', v_current_source_row_id, v_new_record_for_processing, v_loop_error_message, v_err_context;
            source_row_id := v_current_source_row_id;
            upserted_record_id := NULL;
            status := 'ERROR';
            error_message := v_loop_error_message;
            EXECUTE 'SET CONSTRAINTS ALL IMMEDIATE';
            RETURN NEXT;
        END; -- Closes main BEGIN/EXCEPTION block for individual source row processing (started L133)
        EXECUTE 'SET CONSTRAINTS ALL IMMEDIATE';
    END LOOP; -- Closes FOR v_input_row_record (started L125)
    RETURN;
END; -- Closes main function body (started L57)
$batch_insert_or_update_generic_valid_time_table$;

END;

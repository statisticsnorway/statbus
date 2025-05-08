BEGIN;

CREATE OR REPLACE FUNCTION admin.batch_upsert_generic_valid_time_table(
    p_target_schema_name TEXT,
    p_target_table_name TEXT,
    p_source_schema_name TEXT,
    p_source_table_name TEXT,
    p_source_row_id_column_name TEXT, -- Name of the column in source table that uniquely identifies the row (e.g., 'row_id' from _data table)
    p_unique_columns JSONB, -- For identifying existing ID if input ID is null. Format: '[ "col_name_1", ["comp_col_a", "comp_col_b"] ]'
    p_temporal_columns TEXT[], -- Must be ARRAY['valid_from_col_name', 'valid_to_col_name']
    p_ephemeral_columns TEXT[], -- Columns to exclude from equivalence check but keep in insert/update
    p_generated_columns_override TEXT[] DEFAULT NULL, -- Explicit list of DB-generated columns (e.g., 'id' if serial/identity)
    p_id_column_name TEXT DEFAULT 'id' -- Name of the primary key / ID column in the target table
)
RETURNS TABLE (
    source_row_id BIGINT, -- Changed from input_row_index, assuming BIGINT for import job row_ids
    upserted_record_id INT,
    status TEXT,
    error_message TEXT
)
LANGUAGE plpgsql VOLATILE AS $batch_upsert_generic_valid_time_table$
DECLARE
    v_input_row_record RECORD; -- Holds a full row from the source table
    v_current_source_row_id BIGINT;
    v_existing_id INT;
    v_existing_era_record RECORD; -- To hold a full row from the target table
    v_result_id INT;

    v_new_record_for_processing JSONB; -- Represents the current row (converted from v_input_row_record) being processed
    v_existing_era_jsonb JSONB;
    v_adjusted_valid_from DATE;
    v_adjusted_valid_to DATE;
    v_equivalent_data JSONB;
    v_equivalent_clause TEXT;
    v_identifying_clause TEXT;
    v_existing_query TEXT;
    v_delete_existing_sql TEXT;
    v_identifying_query TEXT;
    v_generated_columns TEXT[];
    v_source_query TEXT;
    v_sql TEXT;

    v_valid_from_col TEXT;
    v_valid_to_col TEXT;

    v_err_context TEXT;
    v_loop_error_message TEXT;
    v_loop_var TEXT;

    v_target_table_actual_columns TEXT[]; -- Holds actual column names of the target table
    v_source_target_id_alias TEXT;
BEGIN
    IF array_length(p_temporal_columns, 1) != 2 THEN
        RAISE EXCEPTION 'p_temporal_columns must contain exactly two column names (e.g., valid_from, valid_to)';
    END IF;
    v_valid_from_col := p_temporal_columns[1];
    v_valid_to_col := p_temporal_columns[2];

    -- Get actual column names for the target table
    EXECUTE format(
        'SELECT array_agg(column_name::TEXT) FROM information_schema.columns WHERE table_schema = %L AND table_name = %L',
        p_target_schema_name, p_target_table_name
    ) INTO v_target_table_actual_columns;

    IF v_target_table_actual_columns IS NULL OR array_length(v_target_table_actual_columns, 1) IS NULL THEN
        RAISE EXCEPTION 'Could not retrieve column names for target table %.%', p_target_schema_name, p_target_table_name;
    END IF;
    RAISE DEBUG '[batch_upsert] Target table columns for %.%: %', p_target_schema_name, p_target_table_name, v_target_table_actual_columns;

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
    RAISE DEBUG '[batch_upsert] Generated columns for %.%: %', p_target_schema_name, p_target_table_name, v_generated_columns;

    -- Check if source table has a 'target_id' column to alias to p_id_column_name
    SELECT column_name INTO v_source_target_id_alias
    FROM information_schema.columns
    WHERE table_schema = p_source_schema_name AND table_name = p_source_table_name AND column_name = 'target_id';

    IF v_source_target_id_alias IS NOT NULL THEN
        v_source_query := format('SELECT src.*, src.target_id AS %I FROM %I.%I src', p_id_column_name, p_source_schema_name, p_source_table_name);
        RAISE DEBUG '[batch_upsert] Source query (with target_id aliased to %I): %', p_id_column_name, v_source_query;
    ELSE
        v_source_query := format('SELECT * FROM %I.%I', p_source_schema_name, p_source_table_name);
        RAISE DEBUG '[batch_upsert] Source query (no target_id column found to alias): %', v_source_query;
    END IF;


    FOR v_input_row_record IN EXECUTE v_source_query
    LOOP
        v_new_record_for_processing := to_jsonb(v_input_row_record);
        IF NOT (v_new_record_for_processing ? p_source_row_id_column_name) THEN
            RAISE EXCEPTION 'Source row ID column % not found in source table %.%', p_source_row_id_column_name, p_source_schema_name, p_source_table_name;
        END IF;
        v_current_source_row_id := (v_new_record_for_processing->>p_source_row_id_column_name)::BIGINT;
        
        v_existing_id := (v_new_record_for_processing->>p_id_column_name)::INT;

        RAISE DEBUG '[batch_upsert] Processing source_row_id %: %. Initial v_existing_id from source field %I: %', 
            v_current_source_row_id, v_new_record_for_processing, p_id_column_name, v_existing_id;

        BEGIN -- Start block for individual row processing
            v_loop_error_message := NULL;
            v_result_id := NULL;

            IF (v_new_record_for_processing->>v_valid_from_col) IS NULL OR (v_new_record_for_processing->>v_valid_to_col) IS NULL THEN
                RAISE EXCEPTION 'Temporal columns (%, %) cannot be null. Error in source row with % = %: %',
                    v_valid_from_col, v_valid_to_col, p_source_row_id_column_name, v_current_source_row_id, v_new_record_for_processing;
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
                            v_single_condition := format('%I IS NOT DISTINCT FROM %L', v_unique_key_element#>>'{}', v_new_record_for_processing->>(v_unique_key_element#>>'{}'));
                        ELSIF jsonb_typeof(v_unique_key_element) = 'array' THEN
                            SELECT array_agg(format('%I IS NOT DISTINCT FROM %L', col_name, v_new_record_for_processing->>col_name))
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
                        RAISE DEBUG '[batch_upsert] Identifying query for source row %: %', v_current_source_row_id, v_identifying_query;
                        EXECUTE v_identifying_query INTO v_existing_id;
                        RAISE DEBUG '[batch_upsert] Identified v_existing_id via lookup for source row %: %', v_current_source_row_id, v_existing_id;
                    END IF;
                END;
            END IF;

            IF v_existing_id IS NOT NULL AND (v_new_record_for_processing->>p_id_column_name IS NULL OR (v_new_record_for_processing->>p_id_column_name)::INT IS DISTINCT FROM v_existing_id) THEN
                v_new_record_for_processing := jsonb_set(v_new_record_for_processing, ARRAY[p_id_column_name], to_jsonb(v_existing_id), true);
                RAISE DEBUG '[batch_upsert] Set %I = % in v_new_record_for_processing for source row %.', p_id_column_name, v_existing_id, v_current_source_row_id;
            END IF;

            v_equivalent_data := '{}'::JSONB;
            DECLARE k TEXT;
            BEGIN
                FOR k IN SELECT * FROM jsonb_object_keys(v_new_record_for_processing) LOOP
                    IF k = ANY(v_target_table_actual_columns) THEN
                        IF NOT (k = ANY(p_temporal_columns)) AND
                           NOT (k = ANY(p_ephemeral_columns)) AND
                           NOT (k = p_id_column_name AND (p_id_column_name = ANY(v_generated_columns))) THEN
                           v_equivalent_data := jsonb_set(v_equivalent_data, ARRAY[k], v_new_record_for_processing->k);
                        END IF;
                    END IF;
                END LOOP;
            END;
            RAISE DEBUG '[batch_upsert] Source row % Equivalence data: %', v_current_source_row_id, v_equivalent_data;

            SELECT string_agg(
                       format('tbl.%I IS NOT DISTINCT FROM %L', key, value),
                       ' AND '
                   )
            INTO v_equivalent_clause
            FROM jsonb_each_text(v_equivalent_data);

            IF v_equivalent_clause IS NULL OR v_equivalent_clause = '' THEN
                v_equivalent_clause := 'TRUE';
            END IF;
            RAISE DEBUG '[batch_upsert] Source row % Equivalence clause: %', v_current_source_row_id, v_equivalent_clause;

            v_existing_query := format(
                $$SELECT *,
                         (%s) AS equivalent, 
                         CASE
                           WHEN tbl.%I = (%L::DATE - INTERVAL '1 day')::DATE THEN 'existing_adjacent_before'
                           WHEN (%L::DATE - INTERVAL '1 day')::DATE = tbl.%I THEN 'existing_adjacent_after'
                           WHEN tbl.%I < %L::DATE AND tbl.%I <= %L::DATE THEN 'existing_overlaps_valid_from'
                           WHEN tbl.%I < %L::DATE AND tbl.%I >  %L::DATE THEN 'inside_existing'
                           WHEN tbl.%I >= %L::DATE AND tbl.%I <= %L::DATE THEN 'contains_existing'
                           WHEN tbl.%I >= %L::DATE AND tbl.%I >  %L::DATE THEN 'existing_overlaps_valid_to'
                         END::admin.existing_upsert_case AS upsert_case
                  FROM %I.%I AS tbl
                  WHERE public.from_to_overlaps(tbl.%I, tbl.%I, (%L::DATE - INTERVAL '1 day')::DATE, (%L::DATE + INTERVAL '1 day')::DATE)
                    AND tbl.%I = %L 
                  ORDER BY tbl.%I$$,
                v_equivalent_clause,
                v_valid_to_col, (v_new_record_for_processing->>v_valid_from_col)::DATE,
                (v_new_record_for_processing->>v_valid_to_col)::DATE, v_valid_from_col,
                v_valid_from_col, (v_new_record_for_processing->>v_valid_from_col)::DATE, v_valid_to_col, (v_new_record_for_processing->>v_valid_to_col)::DATE,
                v_valid_from_col, (v_new_record_for_processing->>v_valid_from_col)::DATE, v_valid_to_col, (v_new_record_for_processing->>v_valid_to_col)::DATE,
                v_valid_from_col, (v_new_record_for_processing->>v_valid_from_col)::DATE, v_valid_to_col, (v_new_record_for_processing->>v_valid_to_col)::DATE,
                v_valid_from_col, (v_new_record_for_processing->>v_valid_from_col)::DATE, v_valid_to_col, (v_new_record_for_processing->>v_valid_to_col)::DATE,
                p_target_schema_name, p_target_table_name,
                v_valid_from_col, v_valid_to_col, (v_new_record_for_processing->>v_valid_from_col)::DATE, (v_new_record_for_processing->>v_valid_to_col)::DATE,
                p_id_column_name, (v_new_record_for_processing->>p_id_column_name)::INT, 
                v_valid_from_col
            );
            RAISE DEBUG '[batch_upsert] Existing eras query for source row % (target ID %): %', v_current_source_row_id, (v_new_record_for_processing->>p_id_column_name)::INT, v_existing_query;

            FOR v_existing_era_record IN EXECUTE v_existing_query
            LOOP
                v_existing_era_jsonb := to_jsonb(v_existing_era_record);
                RAISE DEBUG '[batch_upsert] Source row %, Existing era record: %', v_current_source_row_id, v_existing_era_jsonb;

                v_delete_existing_sql := format(
                    'DELETE FROM %I.%I WHERE %I = %L AND %I = %L AND %I = %L;',
                    p_target_schema_name, p_target_table_name,
                    p_id_column_name, (v_existing_era_jsonb->>p_id_column_name)::INT,
                    v_valid_from_col, (v_existing_era_jsonb->>v_valid_from_col)::DATE,
                    v_valid_to_col, (v_existing_era_jsonb->>v_valid_to_col)::DATE
                );

                CASE v_existing_era_record.upsert_case
                WHEN 'existing_adjacent_before' THEN
                    IF v_existing_era_record.equivalent THEN
                        RAISE DEBUG 'Upsert Case: existing_adjacent_before AND equivalent';
                        EXECUTE v_delete_existing_sql;
                        v_new_record_for_processing := jsonb_set(v_new_record_for_processing, ARRAY[v_valid_from_col], v_existing_era_jsonb->v_valid_from_col);
                    END IF;
                WHEN 'existing_adjacent_after' THEN
                    IF v_existing_era_record.equivalent THEN
                        RAISE DEBUG 'Upsert Case: existing_adjacent_after AND equivalent';
                        EXECUTE v_delete_existing_sql;
                        v_new_record_for_processing := jsonb_set(v_new_record_for_processing, ARRAY[v_valid_to_col], v_existing_era_jsonb->v_valid_to_col);
                    END IF;
                WHEN 'existing_overlaps_valid_from' THEN
                    IF v_existing_era_record.equivalent THEN
                        RAISE DEBUG 'Upsert Case: existing_overlaps_valid_from AND equivalent';
                        EXECUTE v_delete_existing_sql;
                        v_new_record_for_processing := jsonb_set(v_new_record_for_processing, ARRAY[v_valid_from_col], v_existing_era_jsonb->v_valid_from_col);
                    ELSE
                        RAISE DEBUG 'Upsert Case: existing_overlaps_valid_from AND different';
                        v_adjusted_valid_to := (v_new_record_for_processing->>v_valid_from_col)::DATE - interval '1 day';
                        IF v_adjusted_valid_to < (v_existing_era_jsonb->>v_valid_from_col)::DATE THEN
                             RAISE DEBUG 'New record starts before existing and does not merge. Existing record untouched.';
                        ELSE
                            EXECUTE format('UPDATE %I.%I SET %I = %L WHERE %I = %L AND %I = %L AND %I = %L',
                                           p_target_schema_name, p_target_table_name, v_valid_to_col, v_adjusted_valid_to,
                                           p_id_column_name, (v_existing_era_jsonb->>p_id_column_name)::INT,
                                           v_valid_from_col, (v_existing_era_jsonb->>v_valid_from_col)::DATE,
                                           v_valid_to_col, (v_existing_era_jsonb->>v_valid_to_col)::DATE);
                        END IF;
                    END IF;
                WHEN 'inside_existing' THEN
                    IF v_existing_era_record.equivalent THEN
                        RAISE DEBUG 'Upsert Case: inside_existing AND equivalent';
                        EXECUTE v_delete_existing_sql;
                        v_new_record_for_processing := jsonb_set(v_new_record_for_processing, ARRAY[v_valid_from_col], v_existing_era_jsonb->v_valid_from_col);
                        v_new_record_for_processing := jsonb_set(v_new_record_for_processing, ARRAY[v_valid_to_col], v_existing_era_jsonb->v_valid_to_col);
                    ELSE
                        RAISE DEBUG 'Upsert Case: inside_existing AND different';
                        v_adjusted_valid_from := (v_new_record_for_processing->>v_valid_to_col)::DATE + interval '1 day';
                        v_adjusted_valid_to   := (v_new_record_for_processing->>v_valid_from_col)::DATE - interval '1 day';

                        IF v_adjusted_valid_to < (v_existing_era_jsonb->>v_valid_from_col)::DATE THEN
                           EXECUTE v_delete_existing_sql; 
                        ELSE
                            EXECUTE format('UPDATE %I.%I SET %I = %L WHERE %I = %L AND %I = %L AND %I = %L',
                                           p_target_schema_name, p_target_table_name, v_valid_to_col, v_adjusted_valid_to,
                                           p_id_column_name, (v_existing_era_jsonb->>p_id_column_name)::INT,
                                           v_valid_from_col, (v_existing_era_jsonb->>v_valid_from_col)::DATE,
                                           v_valid_to_col, (v_existing_era_jsonb->>v_valid_to_col)::DATE);
                        END IF;

                        IF (v_existing_era_jsonb->>v_valid_to_col)::DATE < v_adjusted_valid_from THEN
                            RAISE DEBUG 'Don''t create zero duration tail row';
                        ELSE
                            DECLARE v_tail_insert_data JSONB := v_existing_era_jsonb - v_valid_from_col; 
                                    v_tail_cols TEXT;
                                    v_tail_vals TEXT;
                                    v_col_name_tail TEXT;
                                    v_final_tail_data JSONB := '{}'::JSONB;
                            BEGIN
                                v_tail_insert_data := jsonb_set(v_tail_insert_data, ARRAY[v_valid_from_col], to_jsonb(v_adjusted_valid_from));

                                FOR v_col_name_tail IN SELECT * FROM jsonb_object_keys(v_tail_insert_data) LOOP
                                    IF v_col_name_tail = ANY(v_target_table_actual_columns) THEN
                                        IF NOT (v_col_name_tail = ANY(v_generated_columns)) THEN
                                            v_final_tail_data := jsonb_set(v_final_tail_data, ARRAY[v_col_name_tail], v_tail_insert_data->v_col_name_tail);
                                        ELSE
                                            IF (v_col_name_tail = p_id_column_name AND (v_tail_insert_data->>p_id_column_name) IS NOT NULL) OR
                                               (v_col_name_tail = ANY(p_temporal_columns)) THEN
                                                v_final_tail_data := jsonb_set(v_final_tail_data, ARRAY[v_col_name_tail], v_tail_insert_data->v_col_name_tail);
                                            END IF;
                                        END IF;
                                    END IF;
                                END LOOP;
                                
                                SELECT string_agg(quote_ident(key), ', '), string_agg(quote_nullable(value), ', ')
                                INTO v_tail_cols, v_tail_vals
                                FROM jsonb_each_text(v_final_tail_data);

                                IF v_tail_cols IS NOT NULL AND v_tail_cols <> '' THEN
                                    RAISE DEBUG 'Inserting new tail: %', v_final_tail_data;
                                    EXECUTE format('INSERT INTO %I.%I (%s) VALUES (%s)', p_target_schema_name, p_target_table_name, v_tail_cols, v_tail_vals);
                                ELSE
                                    RAISE DEBUG 'Skipping insert of new tail as no columns were eligible: %', v_final_tail_data;
                                END IF;
                            END;
                        END IF;
                    END IF;
                WHEN 'contains_existing' THEN
                    RAISE DEBUG 'Upsert Case: contains_existing';
                    EXECUTE v_delete_existing_sql;
                WHEN 'existing_overlaps_valid_to' THEN
                    IF v_existing_era_record.equivalent THEN
                        RAISE DEBUG 'Upsert Case: existing_overlaps_valid_to AND equivalent';
                        EXECUTE v_delete_existing_sql;
                        v_new_record_for_processing := jsonb_set(v_new_record_for_processing, ARRAY[v_valid_to_col], v_existing_era_jsonb->v_valid_to_col);
                    ELSE
                        RAISE DEBUG 'Upsert Case: existing_overlaps_valid_to AND different';
                        v_adjusted_valid_from := (v_new_record_for_processing->>v_valid_to_col)::DATE + interval '1 day';
                        IF (v_existing_era_jsonb->>v_valid_to_col)::DATE < v_adjusted_valid_from THEN
                             RAISE DEBUG 'New record ends after existing and does not merge. Existing record untouched.';
                        ELSE
                            EXECUTE format('UPDATE %I.%I SET %I = %L WHERE %I = %L AND %I = %L AND %I = %L',
                                           p_target_schema_name, p_target_table_name, v_valid_from_col, v_adjusted_valid_from,
                                           p_id_column_name, (v_existing_era_jsonb->>p_id_column_name)::INT,
                                           v_valid_from_col, (v_existing_era_jsonb->>v_valid_from_col)::DATE,
                                           v_valid_to_col, (v_existing_era_jsonb->>v_valid_to_col)::DATE);
                        END IF;
                    END IF;
                ELSE
                    RAISE EXCEPTION 'Unknown existing_upsert_case: % for source row %', v_existing_era_record.upsert_case, v_current_source_row_id;
                END CASE;
            END LOOP; 

            DECLARE
                v_insert_cols TEXT;
                v_insert_values TEXT;
                v_data_for_insert JSONB := '{}'::JSONB;
                v_col_name TEXT;
            BEGIN
                FOR v_col_name IN SELECT * FROM jsonb_object_keys(v_new_record_for_processing) LOOP
                    IF v_col_name = ANY(v_target_table_actual_columns) THEN
                        IF NOT (v_col_name = ANY(v_generated_columns)) THEN
                            v_data_for_insert := jsonb_set(v_data_for_insert, ARRAY[v_col_name], v_new_record_for_processing->v_col_name);
                        ELSE
                            IF (v_col_name = p_id_column_name AND (v_new_record_for_processing->>p_id_column_name) IS NOT NULL) OR
                               (v_col_name = ANY(p_temporal_columns)) THEN
                                v_data_for_insert := jsonb_set(v_data_for_insert, ARRAY[v_col_name], v_new_record_for_processing->v_col_name);
                            END IF;
                        END IF;
                    END IF;
                END LOOP;
                RAISE DEBUG '[batch_upsert] Source row %, Data for insert: %', v_current_source_row_id, v_data_for_insert;

                SELECT string_agg(quote_ident(key), ', '), string_agg(quote_nullable(value), ', ')
                INTO v_insert_cols, v_insert_values
                FROM jsonb_each_text(v_data_for_insert);

                IF v_insert_cols IS NULL OR v_insert_cols = '' THEN
                    RAISE WARNING '[batch_upsert] Source row %: No columns to insert after processing. Processed JSON: %, Insertable JSON: %', v_current_source_row_id, v_new_record_for_processing, v_data_for_insert;
                    v_result_id := (v_new_record_for_processing->>p_id_column_name)::INT; 
                    IF v_result_id IS NULL AND (v_data_for_insert->>p_id_column_name) IS NULL THEN 
                         RAISE WARNING '[batch_upsert] Source row %: No columns to insert and no ID resolved or to be inserted.', v_current_source_row_id;
                    END IF;
                ELSE
                    v_sql := format('INSERT INTO %I.%I (%s) VALUES (%s) RETURNING %I',
                                    p_target_schema_name, p_target_table_name, v_insert_cols, v_insert_values, p_id_column_name);
                    RAISE DEBUG '[batch_upsert] Source row %, Insert SQL: %', v_current_source_row_id, v_sql;
                    EXECUTE v_sql INTO v_result_id;
                END IF;
            END;

            source_row_id := v_current_source_row_id;
            upserted_record_id := v_result_id;
            status := 'SUCCESS';
            error_message := NULL;
            RETURN NEXT;

        EXCEPTION WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS v_loop_error_message = MESSAGE_TEXT, v_err_context = PG_EXCEPTION_CONTEXT;
            RAISE WARNING '[batch_upsert] Error processing source_row_id % (%): %. Context: %', v_current_source_row_id, v_new_record_for_processing, v_loop_error_message, v_err_context;
            source_row_id := v_current_source_row_id;
            upserted_record_id := NULL;
            status := 'ERROR';
            error_message := v_loop_error_message;
            RETURN NEXT;
        END; 

    END LOOP; 

    RETURN;
END;
$batch_upsert_generic_valid_time_table$;

END;

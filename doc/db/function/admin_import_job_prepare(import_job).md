```sql
CREATE OR REPLACE FUNCTION admin.import_job_prepare(job import_job)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    upsert_stmt TEXT;
    insert_columns_list TEXT[] := ARRAY[]::TEXT[];
    select_expressions_list TEXT[] := ARRAY[]::TEXT[];
    conflict_key_columns_list TEXT[] := ARRAY[]::TEXT[];
    update_set_expressions_list TEXT[] := ARRAY[]::TEXT[];

    insert_columns TEXT;
    select_clause TEXT;
    conflict_columns_text TEXT;
    update_set_clause TEXT;

    item_rec RECORD; -- Will hold {mapping, source_column, target_data_column}
    current_mapping JSONB;
    current_source_column JSONB;
    current_target_data_column JSONB;
    
    error_message TEXT;
    snapshot JSONB := job.definition_snapshot;
BEGIN
    RAISE DEBUG '[Job %] Preparing data: Moving from % to %', job.id, job.upload_table_name, job.data_table_name;

    IF snapshot IS NULL OR snapshot->'import_mapping_list' IS NULL THEN
        RAISE EXCEPTION '[Job %] Invalid or missing import_mapping_list in definition_snapshot', job.id;
    END IF;

    -- Iterate through mappings to build INSERT columns and SELECT expressions in a consistent order
    FOR item_rec IN 
        SELECT * 
        FROM jsonb_to_recordset(COALESCE(snapshot->'import_mapping_list', '[]'::jsonb)) 
            AS item(mapping JSONB, source_column JSONB, target_data_column JSONB)
        ORDER BY (item.mapping->>'id')::integer -- Order by mapping ID for consistency
    LOOP
        current_mapping := item_rec.mapping;
        current_source_column := item_rec.source_column;
        current_target_data_column := item_rec.target_data_column;

        IF current_target_data_column IS NULL OR current_target_data_column = 'null'::jsonb THEN
            RAISE EXCEPTION '[Job %] Mapping ID % refers to non-existent target_data_column.', job.id, current_mapping->>'id';
        END IF;

        -- Only process mappings that target 'source_input' columns for the prepare step
        IF current_target_data_column->>'purpose' != 'source_input' THEN
            RAISE DEBUG '[Job %] Skipping mapping ID % because target data column % (ID: %) is not for ''source_input''. Purpose: %', 
                        job.id, current_mapping->>'id', current_target_data_column->>'column_name', current_target_data_column->>'id', current_target_data_column->>'purpose';
            CONTINUE;
        END IF;

        insert_columns_list := array_append(insert_columns_list, format('%I', current_target_data_column->>'column_name'));

        -- Generate SELECT expression based on mapping type
        IF current_mapping->>'source_value' IS NOT NULL THEN
            select_expressions_list := array_append(select_expressions_list, format('%L', current_mapping->>'source_value'));
        ELSIF current_mapping->>'source_expression' IS NOT NULL THEN
            select_expressions_list := array_append(select_expressions_list,
                CASE current_mapping->>'source_expression'
                    WHEN 'now' THEN 'statement_timestamp()'
                    WHEN 'default' THEN
                        CASE current_target_data_column->>'column_name'
                            WHEN 'valid_from' THEN format('%L', job.default_valid_from)
                            WHEN 'valid_to' THEN format('%L', job.default_valid_to)
                            WHEN 'data_source_code' THEN format('%L', job.default_data_source_code)
                            ELSE 'NULL' 
                        END
                    ELSE 'NULL'
                END
            );
        ELSIF current_mapping->>'source_column_id' IS NOT NULL THEN
            IF current_source_column IS NULL OR current_source_column = 'null'::jsonb THEN
                 RAISE EXCEPTION '[Job %] Could not find source column details for source_column_id % in mapping ID %.', job.id, current_mapping->>'source_column_id', current_mapping->>'id';
            END IF;
            select_expressions_list := array_append(select_expressions_list, format('NULLIF(%I, '''')', current_source_column->>'column_name'));
        ELSE
            -- This case should be prevented by the CHECK constraint on import_mapping table
            RAISE EXCEPTION '[Job %] Mapping ID % for target data column % (ID: %) has no valid source (column/value/expression). This should not happen.', job.id, current_mapping->>'id', current_target_data_column->>'column_name', current_target_data_column->>'id';
        END IF;
        
        -- If this target data column is part of the unique key, add it to conflict_key_columns_list
        IF (current_target_data_column->>'is_uniquely_identifying')::boolean THEN
            conflict_key_columns_list := array_append(conflict_key_columns_list, format('%I', current_target_data_column->>'column_name'));
        END IF;
    END LOOP;

    IF array_length(insert_columns_list, 1) = 0 THEN
        RAISE DEBUG '[Job %] No mapped source_input columns found to insert. Skipping prepare.', job.id;
        RETURN; 
    END IF;

    insert_columns := array_to_string(insert_columns_list, ', ');
    select_clause := array_to_string(select_expressions_list, ', ');
    conflict_columns_text := array_to_string(conflict_key_columns_list, ', ');

    -- Build UPDATE SET clause: update all inserted columns that are NOT part of the conflict key
    FOR i IN 1 .. array_length(insert_columns_list, 1) LOOP
        IF NOT (insert_columns_list[i] = ANY(conflict_key_columns_list)) THEN
            update_set_expressions_list := array_append(update_set_expressions_list, format('%s = EXCLUDED.%s', insert_columns_list[i], insert_columns_list[i]));
        END IF;
    END LOOP;
    update_set_clause := array_to_string(update_set_expressions_list, ', ');

    -- Assemble the final UPSERT statement
    IF conflict_columns_text = '' OR update_set_clause = '' THEN
        -- If no conflict columns defined for the mapped columns, or no columns to update, just do INSERT
        upsert_stmt := format('INSERT INTO public.%I (%s) SELECT %s FROM public.%I',
                              job.data_table_name, insert_columns, select_clause, job.upload_table_name);
    ELSE
        upsert_stmt := format('INSERT INTO public.%I (%s) SELECT %s FROM public.%I ON CONFLICT (%s) DO UPDATE SET %s',
                              job.data_table_name, insert_columns, select_clause, job.upload_table_name, conflict_columns_text, update_set_clause);
    END IF;

    BEGIN
        RAISE DEBUG '[Job %] Executing prepare upsert: %', job.id, upsert_stmt;
        EXECUTE upsert_stmt;

        DECLARE data_table_count INT;
        BEGIN
            EXECUTE format('SELECT count(*) FROM public.%I', job.data_table_name) INTO data_table_count;
            RAISE DEBUG '[Job %] Rows in data table % after prepare: %', job.id, job.data_table_name, data_table_count;
        END;
    EXCEPTION
        WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
            RAISE WARNING '[Job %] Error preparing data: %', job.id, error_message;
            UPDATE public.import_job SET error = jsonb_build_object('prepare_error', error_message), state = 'finished' WHERE id = job.id;
            RAISE; -- Re-raise the exception
    END;

    -- Set initial state for all rows in data table (redundant if table is new, safe if resuming)
    EXECUTE format('UPDATE public.%I SET state = %L, last_completed_priority = 0 WHERE state IS NULL OR state != %L',
                   job.data_table_name, 'pending', 'error');

END;
$function$
```

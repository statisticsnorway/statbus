-- Migration 20260318040138: comment_sigil_stripping_in_prepare
-- Strip ' # ...' comments from uploaded values during prepare step.
-- This allows XLSX dropdowns to show 'code # name' while only storing the code.
-- SPLIT_PART('01.11', ' # ', 1) returns '01.11' unchanged — harmless when no sigil present.
BEGIN;

CREATE OR REPLACE FUNCTION admin.import_job_prepare(job import_job)
 RETURNS void
 LANGUAGE plpgsql
AS $import_job_prepare$
DECLARE
    insert_stmt TEXT;
    insert_columns_list TEXT[] := ARRAY[]::TEXT[];
    select_expressions_list TEXT[] := ARRAY[]::TEXT[];
    insert_columns TEXT;
    select_clause TEXT;
    item_rec RECORD;
    current_mapping JSONB;
    current_source_column JSONB;
    current_target_data_column JSONB;
    error_message TEXT;
    snapshot JSONB := job.definition_snapshot;
    null_values TEXT[];
    null_case_expr TEXT;
BEGIN
    RAISE DEBUG '[Job %] Preparing data: Moving from % to %', job.id, job.upload_table_name, job.data_table_name;

    IF snapshot IS NULL OR snapshot->'import_mapping_list' IS NULL THEN
        RAISE EXCEPTION '[Job %] Invalid or missing import_mapping_list in definition_snapshot', job.id;
    END IF;

    FOR item_rec IN
        SELECT *
        FROM jsonb_to_recordset(COALESCE(snapshot->'import_mapping_list', '[]'::jsonb))
            AS item(mapping JSONB, source_column JSONB, target_data_column JSONB)
        ORDER BY (item.mapping->>'id')::integer
    LOOP
        current_mapping := item_rec.mapping;
        current_source_column := item_rec.source_column;
        current_target_data_column := item_rec.target_data_column;

        IF current_target_data_column IS NULL OR current_target_data_column = 'null'::jsonb THEN
            RAISE EXCEPTION '[Job %] Mapping ID % refers to non-existent target_data_column.', job.id, current_mapping->>'id';
        END IF;

        IF current_target_data_column->>'purpose' != 'source_input' THEN
            RAISE DEBUG '[Job %] Skipping mapping ID % because target data column % (ID: %) is not for ''source_input''. Purpose: %',
                        job.id, current_mapping->>'id', current_target_data_column->>'column_name', current_target_data_column->>'id', current_target_data_column->>'purpose';
            CONTINUE;
        END IF;

        insert_columns_list := array_append(insert_columns_list, format('%I', current_target_data_column->>'column_name'));

        IF current_mapping->>'source_value' IS NOT NULL THEN
            select_expressions_list := array_append(select_expressions_list, format('%L', current_mapping->>'source_value'));
        ELSIF current_mapping->>'source_expression' IS NOT NULL THEN
            select_expressions_list := array_append(select_expressions_list,
                CASE current_mapping->>'source_expression'
                    WHEN 'now' THEN 'statement_timestamp()'
                    WHEN 'default' THEN
                        CASE current_target_data_column->>'column_name'
                            WHEN 'valid_from_raw' THEN format('%L', job.default_valid_from)
                            WHEN 'valid_to_raw' THEN format('%L', job.default_valid_to)
                            WHEN 'data_source_code_raw' THEN format('%L', job.default_data_source_code)
                            ELSE 'NULL'
                        END
                    ELSE 'NULL'
                END
            );
        ELSIF current_mapping->>'source_column_id' IS NOT NULL THEN
            IF current_source_column IS NULL OR current_source_column = 'null'::jsonb THEN
                 RAISE EXCEPTION '[Job %] Could not find source column details for source_column_id % in mapping ID %.', job.id, current_mapping->>'source_column_id', current_mapping->>'id';
            END IF;
            SELECT ARRAY(
                SELECT jsonb_array_elements_text(job.definition_snapshot->'import_definition'->'import_as_null')
            ) INTO null_values;

            -- Strip ' # ...' comment sigil from uploaded values, then check for null values.
            -- SPLIT_PART('01.11', ' # ', 1) returns '01.11' unchanged — harmless when no sigil.
            null_case_expr := format('CASE WHEN UPPER(TRIM(SPLIT_PART(%I, %L, 1))) IN (%s) THEN NULL ELSE TRIM(SPLIT_PART(%I, %L, 1)) END',
                current_source_column->>'column_name',
                ' # ',
                (SELECT string_agg(format('UPPER(%L)', trim(nv)), ', ') FROM unnest(null_values) AS nv),
                current_source_column->>'column_name',
                ' # '
            );

            select_expressions_list := array_append(select_expressions_list, null_case_expr);
        ELSE
            RAISE EXCEPTION '[Job %] Mapping ID % for target data column % (ID: %) has no valid source (column/value/expression). This should not happen.', job.id, current_mapping->>'id', current_target_data_column->>'column_name', current_target_data_column->>'id';
        END IF;
    END LOOP;

    IF array_length(insert_columns_list, 1) = 0 THEN
        RAISE DEBUG '[Job %] No mapped source_input columns found to insert. Skipping prepare.', job.id;
        RETURN;
    END IF;

    insert_columns := array_to_string(insert_columns_list, ', ');
    select_clause := array_to_string(select_expressions_list, ', ');

    insert_stmt := format($$INSERT INTO public.%I (%s) SELECT %s FROM public.%I$$,
                            job.data_table_name, insert_columns, select_clause, job.upload_table_name);

    BEGIN
        RAISE DEBUG '[Job %] Executing prepare insert: %', job.id, insert_stmt;
        EXECUTE insert_stmt;

        DECLARE data_table_count INT;
        BEGIN
            EXECUTE format($$SELECT count(*) FROM public.%I$$, job.data_table_name) INTO data_table_count;
            RAISE DEBUG '[Job %] Rows in data table % after prepare: %', job.id, job.data_table_name, data_table_count;
        END;
    EXCEPTION
        WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
            RAISE WARNING '[Job %] Error preparing data: %', job.id, error_message;
            UPDATE public.import_job SET error = jsonb_build_object('prepare_error', error_message)::TEXT, state = 'failed' WHERE id = job.id;
    END;

    EXECUTE format($$UPDATE public.%I SET state = %L, last_completed_priority = 0 WHERE state IS NULL OR state != %L$$,
                   job.data_table_name, 'pending', 'error');

END;
$import_job_prepare$;

END;

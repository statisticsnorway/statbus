-- Migration 20261030151700: STATBUS-545 jobs keep uploaded columns the definition no longer maps
--
-- A downloaded job file re-uploaded into a cloned job can carry a column the
-- current definition no longer maps (for example a statistical variable
-- disabled after the download). Upload and clone failed on it. Now the column
-- is kept in the upload table, shown in the data table as <column>_raw with
-- purpose 'ignored', and reported: a warning on each row with a value and one
-- per column in import_job.warning.
BEGIN;

ALTER TABLE public.import_job ADD COLUMN warning jsonb;
COMMENT ON COLUMN public.import_job.warning IS
  'Job-level warnings, keyed by data column name (the same keys as the row warnings in the data table). Set by admin.import_job_prepare for each ignored column (purpose ''ignored''): the column is not part of the import definition and its values were not imported. NULL when the job has none.';

CREATE FUNCTION admin.import_job_keep_ignored_columns(p_job_id integer, p_column_names text[])
 RETURNS text[]
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'admin', 'pg_temp'
AS $function$
DECLARE
    v_job public.import_job;
    v_added text[] := ARRAY[]::text[];
    v_col text;
    v_role text;
BEGIN
    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Import job % not found', p_job_id;
    END IF;
    -- The caller must be allowed to change this job: the job owner or an admin.
    -- Inside SECURITY DEFINER current_user is the owner, so the caller's role
    -- is read from the role setting (SET ROLE by PostgREST or test.set_user_from_email);
    -- 'none' means no SET ROLE, i.e. a direct superuser session such as a migration.
    v_role := current_setting('role', true);
    IF NOT (
        (v_role = 'none' AND (SELECT rolsuper FROM pg_roles WHERE rolname = session_user))
        OR (v_role <> 'none' AND pg_has_role(v_role::name, 'admin_user', 'MEMBER'))
        OR v_job.user_id = (SELECT u.id FROM auth.user AS u WHERE u.email = v_role)
    ) THEN
        RAISE EXCEPTION 'Not allowed to change import job %', p_job_id USING ERRCODE = 'insufficient_privilege';
    END IF;

    FOR v_col IN
        SELECT DISTINCT trim(c) FROM unnest(p_column_names) AS c
        WHERE trim(c) <> ''
          AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_job.definition_snapshot->'import_source_column_list') AS sc
                          WHERE sc->>'column_name' = trim(c))
          AND NOT EXISTS (SELECT 1 FROM information_schema.columns
                          WHERE table_schema = 'public' AND table_name = v_job.upload_table_name AND column_name = trim(c))
        ORDER BY 1
    LOOP
        EXECUTE format('ALTER TABLE public.%I ADD COLUMN %I TEXT', v_job.upload_table_name, v_col);
        EXECUTE format('ALTER TABLE public.%I ADD COLUMN %I TEXT', v_job.data_table_name, v_col || '_raw');
        UPDATE public.import_job
           SET definition_snapshot = jsonb_set(
                   definition_snapshot, '{import_data_column_list}',
                   (definition_snapshot->'import_data_column_list') || jsonb_build_array(jsonb_build_object(
                       'id', NULL, 'step_id', NULL, 'priority', NULL,
                       'column_name', v_col || '_raw', 'column_type', 'TEXT',
                       'purpose', 'ignored', 'is_nullable', true, 'default_value', NULL,
                       'is_uniquely_identifying', false, 'target_pg_type', NULL,
                       'created_at', NULL, 'updated_at', NULL)))
         WHERE id = p_job_id
        RETURNING * INTO v_job;
        v_added := v_added || v_col;
    END LOOP;

    IF cardinality(v_added) > 0 THEN
        NOTIFY pgrst, 'reload schema';
    END IF;
    RETURN v_added;
END;
$function$;

COMMENT ON FUNCTION admin.import_job_keep_ignored_columns(integer, text[]) IS
  'Keeps uploaded columns that the job''s definition does not map (STATBUS-545), for example a statistical variable disabled after the file was downloaded. For each name in p_column_names that is neither a source column of the job''s definition_snapshot nor already in the upload table: adds it to the upload table and <name>_raw to the data table (TEXT), and appends {column_name: <name>_raw, purpose: ignored, step_id: null} to definition_snapshot.import_data_column_list. No import step reads an ignored column: the steps select data columns by purpose or step_id. admin.import_job_prepare copies the values and warns about them. Callers: public.import_job_clone, public.import_job_accept_upload_columns (the upload route, before COPY). Returns the names added.';

CREATE FUNCTION public.import_job_accept_upload_columns(p_job_id integer, p_column_names text[])
 RETURNS text[]
 LANGUAGE sql
 SECURITY INVOKER
AS $function$
    SELECT admin.import_job_keep_ignored_columns(p_job_id, p_column_names);
$function$;

COMMENT ON FUNCTION public.import_job_accept_upload_columns(integer, text[]) IS
  'Called by the upload route with the file''s header names before it COPYs into the upload table, so a file with columns the job''s definition no longer maps loads instead of failing. See admin.import_job_keep_ignored_columns. Returns the names that were added as ignored columns.';

GRANT EXECUTE ON FUNCTION public.import_job_accept_upload_columns(integer, text[]) TO authenticated;
GRANT EXECUTE ON FUNCTION admin.import_job_keep_ignored_columns(integer, text[]) TO authenticated;

CREATE OR REPLACE FUNCTION public.import_job_clone(p_source_job_id integer, p_slug text DEFAULT NULL::text)
 RETURNS import_job
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_source_job public.import_job;
    v_new_job public.import_job;
    v_source_upload_table_exists BOOLEAN;
    v_source_columns text[];
    v_column_list text;
BEGIN
    -- 1. Get the source job record
    SELECT * INTO v_source_job FROM public.import_job WHERE id = p_source_job_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Source import job with ID % not found.', p_source_job_id;
    END IF;

    -- 2. Create a new job by inserting a copy of the old one's configuration.
    -- The BEFORE INSERT trigger `import_job_derive_trigger` will handle setting a new slug,
    -- table names, snapshot, user_id (to current user), expires_at, etc.
    INSERT INTO public.import_job (
        slug,
        description,
        note,
        time_context_ident,
        default_valid_from,
        default_valid_to,
        default_data_source_code,
        analysis_batch_size,
        processing_batch_size,
        review,
        edit_comment,
        definition_id
    ) VALUES (
        p_slug,
        'Clone of job #' || v_source_job.id || ': ' || COALESCE(v_source_job.description, ''),
        v_source_job.note,
        v_source_job.time_context_ident,
        CASE WHEN v_source_job.time_context_ident IS NOT NULL THEN NULL ELSE v_source_job.default_valid_from END,
        CASE WHEN v_source_job.time_context_ident IS NOT NULL THEN NULL ELSE v_source_job.default_valid_to END,
        v_source_job.default_data_source_code,
        v_source_job.analysis_batch_size,
        v_source_job.processing_batch_size,
        v_source_job.review,
        v_source_job.edit_comment,
        v_source_job.definition_id
    ) RETURNING * INTO v_new_job;

    -- 3. Check if the source upload table exists.
    SELECT to_regclass('public.' || v_source_job.upload_table_name) IS NOT NULL INTO v_source_upload_table_exists;

    -- 4. If it exists, copy data from old upload table to new upload table.
    -- The definition may have changed since the source job was created (for
    -- example a statistical variable disabled), so the source can have columns
    -- the new job does not map. They are kept as ignored columns
    -- (admin.import_job_keep_ignored_columns, STATBUS-545), then the rows are
    -- copied column by name.
    IF v_source_upload_table_exists THEN
        RAISE DEBUG '[Job Clone] Copying data from % to %', v_source_job.upload_table_name, v_new_job.upload_table_name;
        SELECT array_agg(c.column_name::text ORDER BY c.ordinal_position) INTO v_source_columns
        FROM information_schema.columns AS c
        WHERE c.table_schema = 'public' AND c.table_name = v_source_job.upload_table_name;
        PERFORM admin.import_job_keep_ignored_columns(v_new_job.id, v_source_columns);
        SELECT string_agg(format('%I', col), ', ') INTO v_column_list FROM unnest(v_source_columns) AS col;
        EXECUTE format('INSERT INTO public.%I (%s) SELECT %s FROM public.%I',
                       v_new_job.upload_table_name, v_column_list, v_column_list, v_source_job.upload_table_name);
        
        -- The AFTER INSERT trigger on the new upload table will automatically set the
        -- new job's state to 'upload_completed', which in turn will enqueue it for processing.
        RAISE DEBUG '[Job Clone] Data copy complete. Job % has been enqueued automatically.', v_new_job.id;
    ELSE
        RAISE DEBUG '[Job Clone] Source upload table % not found. New job % created in "waiting_for_upload" state.', v_source_job.upload_table_name, v_new_job.id;
    END IF;
    
    -- 5. Return the newly created job.
    RETURN v_new_job;
END;
$function$
;

CREATE OR REPLACE FUNCTION admin.import_job_prepare(job import_job)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
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
    ignored_columns TEXT[] := ARRAY[]::TEXT[];
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

            -- Strip ' | ...' separator from uploaded values (e.g. '01.11 | Growing of cereals').
            -- The Excel download (app/src/lib/excel-reference-sheets.ts) creates reference sheets
            -- with "code | name" dropdowns so users see human-readable labels when editing.
            -- When users select from these dropdowns, the cell value becomes "code | name".
            -- SPLIT_PART extracts just the code before the separator for lookup joins.
            -- SPLIT_PART('01.11', ' | ', 1) returns '01.11' unchanged — harmless when no separator.
            -- Then check for null values.
            null_case_expr := format('CASE WHEN UPPER(TRIM(SPLIT_PART(%I, %L, 1))) IN (%s) THEN NULL ELSE TRIM(SPLIT_PART(%I, %L, 1)) END',
                current_source_column->>'column_name',
                ' | ',
                (SELECT string_agg(format('UPPER(%L)', trim(nv)), ', ') FROM unnest(null_values) AS nv),
                current_source_column->>'column_name',
                ' | '
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

    -- Ignored columns (purpose 'ignored', STATBUS-545): uploaded columns the
    -- definition does not map. Their values are copied as is to <column>_raw
    -- for display; no import step reads them.
    FOR item_rec IN
        SELECT dc->>'column_name' AS data_column, left(dc->>'column_name', -length('_raw')) AS upload_column
        FROM jsonb_array_elements(snapshot->'import_data_column_list') AS dc
        WHERE dc->>'purpose' = 'ignored'
        ORDER BY 1
    LOOP
        insert_columns_list := array_append(insert_columns_list, format('%I', item_rec.data_column));
        select_expressions_list := array_append(select_expressions_list, format('%I', item_rec.upload_column));
        ignored_columns := ignored_columns || item_rec.data_column;
    END LOOP;

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

        -- A warning on every row with a value in an ignored column, keyed by
        -- the data column like other row warnings, and one warning per ignored
        -- column on the job, keyed the same way.
        DECLARE
            v_ignored text;
            v_count bigint;
            v_column_warning jsonb := '{}'::jsonb;
        BEGIN
            FOREACH v_ignored IN ARRAY ignored_columns LOOP
                EXECUTE format(
                    $$UPDATE public.%1$I SET warnings = COALESCE(warnings, '{}'::jsonb)
                          || jsonb_build_object(%2$L, 'Not imported: the import definition does not map this column')
                      WHERE NULLIF(trim(%3$I), '') IS NOT NULL$$,
                    job.data_table_name, v_ignored, v_ignored);
                GET DIAGNOSTICS v_count = ROW_COUNT;
                v_column_warning := v_column_warning || jsonb_build_object(v_ignored,
                    format('Column %s is not part of the import definition; %s values were not imported.',
                           left(v_ignored, -length('_raw')), v_count));
            END LOOP;
            IF v_column_warning <> '{}'::jsonb THEN
                UPDATE public.import_job SET warning = v_column_warning WHERE id = job.id;
            END IF;
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
$function$
;

END;

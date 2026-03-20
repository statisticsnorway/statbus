-- Down Migration 20260320115108: fix_target_pg_type_default_and_create_function
BEGIN;

-- Remove the DEFAULT (restore strict NOT NULL without default)
ALTER TABLE public.import_source_column ALTER COLUMN target_pg_type DROP DEFAULT;

-- Restore the original function without target_pg_type in INSERTs
CREATE OR REPLACE FUNCTION import.create_source_and_mappings_for_definition(p_definition_id integer, p_source_columns text[])
 RETURNS void
 LANGUAGE plpgsql
AS $create_source_and_mappings_for_definition$
DECLARE
    v_def public.import_definition;
    v_col_name TEXT;
    v_priority INT := 0;
    v_source_col_id INT;
    v_data_col_id INT;
    v_max_priority INT;
    v_col_rec RECORD;
    v_has_stat_step BOOLEAN;
BEGIN
    SELECT * INTO v_def FROM public.import_definition WHERE id = p_definition_id;

    -- Handle validity date mappings based on definition mode
    IF v_def.valid_time_from = 'job_provided' THEN
        FOR v_col_name IN VALUES ('valid_from'), ('valid_to') LOOP
            SELECT dc.id INTO v_data_col_id FROM public.import_data_column dc JOIN public.import_step s ON dc.step_id = s.id WHERE s.code = 'valid_time' AND dc.column_name = v_col_name || '_raw';
            IF v_data_col_id IS NOT NULL THEN
                INSERT INTO public.import_mapping (definition_id, source_expression, target_data_column_id, target_data_column_purpose)
                VALUES (p_definition_id, 'default', v_data_col_id, 'source_input'::public.import_data_column_purpose)
                ON CONFLICT (definition_id, target_data_column_id) WHERE is_ignored = false DO NOTHING;
            END IF;
        END LOOP;
    END IF;

    -- Create source columns and map them
    FOREACH v_col_name IN ARRAY p_source_columns LOOP
        v_priority := v_priority + 1;
        INSERT INTO public.import_source_column (definition_id, column_name, priority)
        VALUES (p_definition_id, v_col_name, v_priority)
        ON CONFLICT DO NOTHING RETURNING id INTO v_source_col_id;

        IF v_source_col_id IS NOT NULL THEN
            SELECT dc.id INTO v_data_col_id
            FROM public.import_definition_step ds
            JOIN public.import_data_column dc ON ds.step_id = dc.step_id
            WHERE ds.definition_id = p_definition_id AND dc.column_name = v_col_name || '_raw' AND dc.purpose = 'source_input';

            IF v_data_col_id IS NOT NULL THEN
                INSERT INTO public.import_mapping (definition_id, source_column_id, target_data_column_id, target_data_column_purpose)
                VALUES (p_definition_id, v_source_col_id, v_data_col_id, 'source_input'::public.import_data_column_purpose)
                ON CONFLICT (definition_id, source_column_id, target_data_column_id) DO NOTHING;
            ELSE
                INSERT INTO public.import_mapping (definition_id, source_column_id, is_ignored)
                VALUES (p_definition_id, v_source_col_id, TRUE)
                ON CONFLICT (definition_id, source_column_id, target_data_column_id) WHERE target_data_column_id IS NULL DO NOTHING;
            END IF;
        END IF;
    END LOOP;

    -- Only add stat variable mappings if the definition has a statistical_variables step
    SELECT EXISTS (
        SELECT 1 FROM public.import_definition_step ids
        JOIN public.import_step s ON ids.step_id = s.id
        WHERE ids.definition_id = p_definition_id AND s.code = 'statistical_variables'
    ) INTO v_has_stat_step;

    IF v_has_stat_step THEN
        -- Dynamically add and map source columns for Statistical Variables
        SELECT COALESCE(MAX(priority), v_priority) INTO v_max_priority FROM public.import_source_column WHERE definition_id = p_definition_id;
        INSERT INTO public.import_source_column (definition_id, column_name, priority)
        SELECT p_definition_id, stat.code, v_max_priority + ROW_NUMBER() OVER (ORDER BY stat.priority)
        FROM public.stat_definition_enabled stat ON CONFLICT (definition_id, column_name) DO NOTHING;

        FOR v_col_rec IN
            SELECT isc.id as source_col_id, isc.column_name as stat_code FROM public.import_source_column isc
            JOIN public.stat_definition_enabled sda ON isc.column_name = sda.code
            WHERE isc.definition_id = p_definition_id AND NOT EXISTS (
                SELECT 1 FROM public.import_mapping im WHERE im.definition_id = p_definition_id AND im.source_column_id = isc.id
            )
        LOOP
            SELECT dc.id INTO v_data_col_id FROM public.import_definition_step ds
            JOIN public.import_step s ON ds.step_id = s.id
            JOIN public.import_data_column dc ON ds.step_id = dc.step_id
            WHERE ds.definition_id = p_definition_id AND s.code = 'statistical_variables' AND dc.column_name = v_col_rec.stat_code || '_raw' AND dc.purpose = 'source_input';

            IF v_data_col_id IS NOT NULL THEN
                INSERT INTO public.import_mapping (definition_id, source_column_id, target_data_column_id, target_data_column_purpose)
                VALUES (p_definition_id, v_col_rec.source_col_id, v_data_col_id, 'source_input')
                ON CONFLICT (definition_id, source_column_id, target_data_column_id) DO NOTHING;
            ELSE
                RAISE EXCEPTION '[Definition %] No matching source_input data column found in "statistical_variables" step for dynamically added stat source column "%".', p_definition_id, v_col_rec.stat_code;
            END IF;
        END LOOP;
    END IF;
END;
$create_source_and_mappings_for_definition$;

-- Restore the buggy synchronize_definition_step_mappings from 20260320105936
-- (has the SELECT INTO NULL bug — v_target_pg_type := 'TEXT' gets overwritten)
CREATE OR REPLACE PROCEDURE import.synchronize_definition_step_mappings(IN p_definition_id integer, IN p_step_code text)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_data_col RECORD;
    v_source_col_id INT;
    v_max_priority INT;
    v_def public.import_definition;
    v_target_pg_type TEXT;
BEGIN
    SELECT * INTO v_def FROM public.import_definition WHERE id = p_definition_id;
    IF NOT (v_def.enabled AND v_def.custom = FALSE) THEN
        RAISE DEBUG '[Sync Mappings Def ID %] Skipping sync for step %, definition is inactive or user-customized (custom=TRUE).', p_definition_id, p_step_code;
        RETURN;
    END IF;
    RAISE DEBUG '[Sync Mappings Def ID %] Synchronizing mappings for step % (Definition: enabled=%, custom=%).', p_definition_id, p_step_code, v_def.enabled, v_def.custom;
    SELECT COALESCE(MAX(priority), 0) INTO v_max_priority
    FROM public.import_source_column WHERE definition_id = p_definition_id;
    FOR v_data_col IN
        SELECT dc.id AS data_column_id, dc.column_name AS data_column_name, dc.priority AS data_column_priority,
            regexp_replace(dc.column_name, '_raw$', '') AS source_column_name, dc.step_id
        FROM public.import_data_column dc
        JOIN public.import_step s ON dc.step_id = s.id
        JOIN public.import_definition_step ids ON ids.step_id = s.id
        WHERE ids.definition_id = p_definition_id AND s.code = p_step_code AND dc.purpose = 'source_input'
        ORDER BY dc.priority
    LOOP
        v_target_pg_type := 'TEXT';
        SELECT idc_int.column_type INTO v_target_pg_type
        FROM public.import_data_column AS idc_int
        WHERE idc_int.step_id = v_data_col.step_id
          AND idc_int.purpose = 'internal'
          AND idc_int.column_name = v_data_col.source_column_name;
        SELECT id INTO v_source_col_id
        FROM public.import_source_column
        WHERE definition_id = p_definition_id AND column_name = v_data_col.source_column_name;
        IF NOT FOUND THEN
            v_max_priority := v_max_priority + 1;
            INSERT INTO public.import_source_column (definition_id, column_name, priority, target_pg_type)
            VALUES (p_definition_id, v_data_col.source_column_name, v_max_priority, v_target_pg_type)
            RETURNING id INTO v_source_col_id;
            RAISE DEBUG '[Sync Mappings Def ID %] Created source column "%" (ID: %) with priority % and type % for data column ID %.', p_definition_id, v_data_col.source_column_name, v_source_col_id, v_max_priority, v_target_pg_type, v_data_col.data_column_id;
        ELSE
            UPDATE public.import_source_column
            SET target_pg_type = v_target_pg_type, updated_at = now()
            WHERE id = v_source_col_id AND target_pg_type IS DISTINCT FROM v_target_pg_type;
            RAISE DEBUG '[Sync Mappings Def ID %] Source column "%" already exists (ID: %), preserving it.', p_definition_id, v_data_col.source_column_name, v_source_col_id;
        END IF;
        INSERT INTO public.import_mapping (definition_id, source_column_id, target_data_column_id, target_data_column_purpose, is_ignored)
        VALUES (p_definition_id, v_source_col_id, v_data_col.data_column_id, 'source_input'::public.import_data_column_purpose, FALSE)
        ON CONFLICT (definition_id, source_column_id, target_data_column_id) DO NOTHING;
        RAISE DEBUG '[Sync Mappings Def ID %] Ensured mapping (is_ignored=FALSE if new) for source col ID % to data col ID %.', p_definition_id, v_source_col_id, v_data_col.data_column_id;
    END LOOP;
    PERFORM admin.validate_import_definition(p_definition_id);
    RAISE DEBUG '[Sync Mappings Def ID %] Finished synchronizing mappings for step % and re-validated.', p_definition_id, p_step_code;
END;
$procedure$;

END;

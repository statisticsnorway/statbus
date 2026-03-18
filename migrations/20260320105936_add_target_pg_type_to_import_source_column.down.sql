BEGIN;

-- Restore the function
CREATE OR REPLACE FUNCTION public.import_definition_source_column_types(p_definition_id integer)
 RETURNS TABLE(column_name text, column_type text)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $import_definition_source_column_types$
  SELECT isc.column_name, COALESCE(idc_int.column_type, 'TEXT') AS column_type
  FROM import_source_column AS isc
  JOIN import_mapping AS im ON im.source_column_id = isc.id AND NOT im.is_ignored
  JOIN import_data_column AS idc_raw ON idc_raw.id = im.target_data_column_id
  LEFT JOIN import_data_column AS idc_int
    ON idc_int.step_id = idc_raw.step_id
    AND idc_int.purpose = 'internal'
    AND idc_int.column_name = replace(idc_raw.column_name, '_raw', '')
  WHERE isc.definition_id = p_definition_id
  ORDER BY isc.priority;
$import_definition_source_column_types$;

-- Restore original sync procedure (without target_pg_type)
CREATE OR REPLACE PROCEDURE import.synchronize_definition_step_mappings(IN p_definition_id integer, IN p_step_code text)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_data_col RECORD;
    v_source_col_id INT;
    v_max_priority INT;
    v_def public.import_definition;
BEGIN
    SELECT * INTO v_def FROM public.import_definition WHERE id = p_definition_id;
    -- Only synchronize enabled, system-provided (custom=FALSE) definitions
    IF NOT (v_def.enabled AND v_def.custom = FALSE) THEN
        RAISE DEBUG '[Sync Mappings Def ID %] Skipping sync for step %, definition is inactive or user-customized (custom=TRUE).', p_definition_id, p_step_code;
        RETURN;
    END IF;

    RAISE DEBUG '[Sync Mappings Def ID %] Synchronizing mappings for step % (Definition: enabled=%, custom=%).', p_definition_id, p_step_code, v_def.enabled, v_def.custom;

    -- Get the current max priority for this definition once, before the loop
    SELECT COALESCE(MAX(priority), 0) INTO v_max_priority
    FROM public.import_source_column WHERE definition_id = p_definition_id;

    FOR v_data_col IN
        SELECT
            dc.id AS data_column_id,
            dc.column_name AS data_column_name,
            dc.priority AS data_column_priority,
            regexp_replace(dc.column_name, '_raw$', '') AS source_column_name
        FROM public.import_data_column dc
        JOIN public.import_step s ON dc.step_id = s.id
        JOIN public.import_definition_step ids ON ids.step_id = s.id
        WHERE ids.definition_id = p_definition_id
          AND s.code = p_step_code
          AND dc.purpose = 'source_input'
        ORDER BY dc.priority
    LOOP
        -- Ensure import_source_column exists
        SELECT id INTO v_source_col_id
        FROM public.import_source_column
        WHERE definition_id = p_definition_id AND column_name = v_data_col.source_column_name;

        IF NOT FOUND THEN
            -- Use sequential priority assignment to avoid conflicts
            -- Increment max priority and assign to new source column
            v_max_priority := v_max_priority + 1;

            INSERT INTO public.import_source_column (definition_id, column_name, priority)
            VALUES (p_definition_id, v_data_col.source_column_name, v_max_priority)
            RETURNING id INTO v_source_col_id;
            RAISE DEBUG '[Sync Mappings Def ID %] Created source column "%" (ID: %) with priority % for data column ID %.', p_definition_id, v_data_col.source_column_name, v_source_col_id, v_max_priority, v_data_col.data_column_id;
        ELSE
            -- Column already exists, preserve it
            RAISE DEBUG '[Sync Mappings Def ID %] Source column "%" already exists (ID: %), preserving it.', p_definition_id, v_data_col.source_column_name, v_source_col_id;
        END IF;

        -- Ensure import_mapping exists. If newly created by this sync, it should be a valid, non-ignored mapping.
        INSERT INTO public.import_mapping (definition_id, source_column_id, target_data_column_id, target_data_column_purpose, is_ignored)
        VALUES (p_definition_id, v_source_col_id, v_data_col.data_column_id, 'source_input'::public.import_data_column_purpose, FALSE)
        ON CONFLICT (definition_id, source_column_id, target_data_column_id) DO NOTHING;

        RAISE DEBUG '[Sync Mappings Def ID %] Ensured mapping (is_ignored=FALSE if new) for source col ID % to data col ID %.', p_definition_id, v_source_col_id, v_data_col.data_column_id;

    END LOOP;

    -- Re-validate the definition after potential changes
    PERFORM admin.validate_import_definition(p_definition_id);
    RAISE DEBUG '[Sync Mappings Def ID %] Finished synchronizing mappings for step % and re-validated.', p_definition_id, p_step_code;
END;
$procedure$;

-- Drop the column
ALTER TABLE public.import_source_column DROP COLUMN target_pg_type;

END;

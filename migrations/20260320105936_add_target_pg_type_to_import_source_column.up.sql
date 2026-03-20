BEGIN;

-- 1. Add column as nullable (no silent defaults)
ALTER TABLE public.import_source_column
  ADD COLUMN target_pg_type TEXT;

-- 2. Populate existing rows from internal data columns (best-effort name match)
UPDATE public.import_source_column AS isc
SET target_pg_type = idc_int.column_type
FROM public.import_mapping AS im
JOIN public.import_data_column AS idc_raw
  ON idc_raw.id = im.target_data_column_id
JOIN public.import_data_column AS idc_int
  ON idc_int.step_id = idc_raw.step_id
  AND idc_int.purpose = 'internal'
  AND idc_int.column_name = regexp_replace(idc_raw.column_name, '_raw$', '')
WHERE im.source_column_id = isc.id
  AND NOT im.is_ignored;

-- 3. Set remaining NULLs to TEXT (code/ident columns with no name-matched internal)
UPDATE public.import_source_column
SET target_pg_type = 'TEXT'
WHERE target_pg_type IS NULL;

-- 4. Now enforce NOT NULL
ALTER TABLE public.import_source_column
  ALTER COLUMN target_pg_type SET NOT NULL;

-- 5. Update sync procedure to populate target_pg_type on INSERT and UPDATE
CREATE OR REPLACE PROCEDURE import.synchronize_definition_step_mappings(IN p_definition_id integer, IN p_step_code text)
 LANGUAGE plpgsql
AS $synchronize_definition_step_mappings$
DECLARE
    v_data_col RECORD;
    v_source_col_id INT;
    v_max_priority INT;
    v_def public.import_definition;
    v_target_pg_type TEXT;
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
            regexp_replace(dc.column_name, '_raw$', '') AS source_column_name,
            dc.step_id
        FROM public.import_data_column dc
        JOIN public.import_step s ON dc.step_id = s.id
        JOIN public.import_definition_step ids ON ids.step_id = s.id
        WHERE ids.definition_id = p_definition_id
          AND s.code = p_step_code
          AND dc.purpose = 'source_input'
        ORDER BY dc.priority
    LOOP
        -- Look up sibling internal column's type (best-effort)
        v_target_pg_type := 'TEXT';
        SELECT idc_int.column_type INTO v_target_pg_type
        FROM public.import_data_column AS idc_int
        WHERE idc_int.step_id = v_data_col.step_id
          AND idc_int.purpose = 'internal'
          AND idc_int.column_name = v_data_col.source_column_name;

        -- Ensure import_source_column exists
        SELECT id INTO v_source_col_id
        FROM public.import_source_column
        WHERE definition_id = p_definition_id AND column_name = v_data_col.source_column_name;

        IF NOT FOUND THEN
            -- Use sequential priority assignment to avoid conflicts
            -- Increment max priority and assign to new source column
            v_max_priority := v_max_priority + 1;

            INSERT INTO public.import_source_column (definition_id, column_name, priority, target_pg_type)
            VALUES (p_definition_id, v_data_col.source_column_name, v_max_priority, v_target_pg_type)
            RETURNING id INTO v_source_col_id;
            RAISE DEBUG '[Sync Mappings Def ID %] Created source column "%" (ID: %) with priority % and type % for data column ID %.', p_definition_id, v_data_col.source_column_name, v_source_col_id, v_max_priority, v_target_pg_type, v_data_col.data_column_id;
        ELSE
            -- Update target_pg_type if changed
            UPDATE public.import_source_column
            SET target_pg_type = v_target_pg_type, updated_at = now()
            WHERE id = v_source_col_id AND target_pg_type IS DISTINCT FROM v_target_pg_type;

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
$synchronize_definition_step_mappings$;

-- 6. Drop the now-unnecessary function
DROP FUNCTION IF EXISTS public.import_definition_source_column_types(integer);

END;

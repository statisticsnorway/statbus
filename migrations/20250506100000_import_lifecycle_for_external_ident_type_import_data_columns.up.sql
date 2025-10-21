BEGIN;

-- Lifecycle callback procedures for external_ident data columns
CREATE OR REPLACE PROCEDURE import.generate_external_ident_data_columns()
LANGUAGE plpgsql AS $$
DECLARE
    v_step_id INT;
    v_ident_type RECORD;
    v_def RECORD;
    v_current_priority INT;
    v_active_codes TEXT[];
BEGIN
    SELECT id INTO v_step_id FROM public.import_step WHERE code = 'external_idents';
    IF v_step_id IS NULL THEN
        RAISE EXCEPTION 'external_idents step not found, cannot generate data columns.';
        RETURN;
    END IF;

    SELECT array_agg(code ORDER BY priority) INTO v_active_codes FROM public.external_ident_type_active;
    RAISE DEBUG '[import.generate_external_ident_data_columns] For step_id % (external_idents), ensuring data columns for active codes: %', v_step_id, v_active_codes;

    SELECT COALESCE(MAX(idc.priority), 0) INTO v_current_priority
    FROM public.import_data_column idc WHERE idc.step_id = v_step_id;

    -- Add source_input column for each active external_ident_type for the step
    FOR v_ident_type IN SELECT code FROM public.external_ident_type_active ORDER BY priority
    LOOP
        v_current_priority := v_current_priority + 1;
        INSERT INTO public.import_data_column (step_id, column_name, column_type, purpose, is_nullable, is_uniquely_identifying, priority)
        VALUES (v_step_id, v_ident_type.code || '_raw', 'TEXT', 'source_input', true, true, v_current_priority)
        ON CONFLICT (step_id, column_name) DO UPDATE SET
            priority = EXCLUDED.priority,
            is_uniquely_identifying = EXCLUDED.is_uniquely_identifying;
    END LOOP;
END;
$$;

CREATE OR REPLACE PROCEDURE import.cleanup_external_ident_data_columns()
LANGUAGE plpgsql AS $$
DECLARE
    v_step_id INT;
BEGIN
    SELECT id INTO v_step_id FROM public.import_step WHERE code = 'external_idents';
    IF v_step_id IS NULL THEN
        RAISE WARNING 'external_idents step not found, cannot clean up data columns.';
        RETURN;
    END IF;

    RAISE DEBUG '[import.cleanup_external_ident_data_columns] For step_id % (external_idents), deleting columns for inactive external ident types.', v_step_id;

    -- Delete source columns that map to data columns which are about to be deleted.
    -- This cascades to import_mapping and must run before the data columns are deleted.
    WITH source_cols_to_delete AS (
        SELECT isc.id
        FROM public.import_source_column isc
        JOIN public.import_mapping m ON isc.id = m.source_column_id
        JOIN public.import_data_column idc ON m.target_data_column_id = idc.id
        WHERE idc.step_id = v_step_id
          AND idc.purpose = 'source_input'
          AND replace(idc.column_name, '_raw', '') NOT IN (SELECT code FROM public.external_ident_type_active)
    )
    DELETE FROM public.import_source_column WHERE id IN (SELECT id FROM source_cols_to_delete);

    -- Delete data columns for inactive external ident types.
    DELETE FROM public.import_data_column idc
    WHERE idc.step_id = v_step_id
      AND idc.purpose = 'source_input'
      AND replace(idc.column_name, '_raw', '') NOT IN (
          SELECT code FROM public.external_ident_type_active
      );
END;
$$;

-- Register the lifecycle callback
CALL lifecycle_callbacks.add(
    'import_external_ident_data_columns',
    ARRAY['public.external_ident_type']::regclass[],
    'import.generate_external_ident_data_columns',
    'import.cleanup_external_ident_data_columns'
);

-- Initial call to populate columns based on existing types
CALL import.generate_external_ident_data_columns();

END;

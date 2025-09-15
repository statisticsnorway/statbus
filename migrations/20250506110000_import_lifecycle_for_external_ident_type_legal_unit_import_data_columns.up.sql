BEGIN;

-- Lifecycle callback procedures for link_establishment_to_legal_unit data columns
CREATE OR REPLACE PROCEDURE import.generate_link_lu_data_columns()
LANGUAGE plpgsql AS $$
DECLARE
    v_step_id INT;
    v_ident_type RECORD;
    v_def RECORD;
    v_current_priority INT;
    v_active_codes TEXT[];
BEGIN
    SELECT id INTO v_step_id FROM public.import_step WHERE code = 'link_establishment_to_legal_unit';
    IF v_step_id IS NULL THEN
        RAISE EXCEPTION 'link_establishment_to_legal_unit step not found, cannot generate data columns.';
        RETURN;
    END IF;

    SELECT array_agg(code ORDER BY priority) INTO v_active_codes FROM public.external_ident_type_active;
    RAISE DEBUG '[import.generate_link_lu_data_columns] For step_id % (link_establishment_to_legal_unit), ensuring data columns for active codes: %', v_step_id, v_active_codes;

    SELECT COALESCE(MAX(idc.priority), 0) INTO v_current_priority
    FROM public.import_data_column idc WHERE idc.step_id = v_step_id;

    -- Add source_input column for each active external_ident_type, prefixed with 'legal_unit_'
    FOR v_ident_type IN SELECT code FROM public.external_ident_type_active ORDER BY priority
    LOOP
        v_current_priority := v_current_priority + 1;
        INSERT INTO public.import_data_column (step_id, column_name, column_type, purpose, is_nullable, is_uniquely_identifying, priority)
        VALUES (v_step_id, 'legal_unit_' || v_ident_type.code || '_raw', 'TEXT', 'source_input', true, false, v_current_priority)
        ON CONFLICT (step_id, column_name) DO UPDATE SET
            priority = EXCLUDED.priority,
            is_uniquely_identifying = EXCLUDED.is_uniquely_identifying;
    END LOOP;

    -- The 'legal_unit_id' pk_id column is statically defined in 20250505120000_import_populate_steps.up.sql
    -- and should not be managed by this dynamic lifecycle callback.
END;
$$;

CREATE OR REPLACE PROCEDURE import.cleanup_link_lu_data_columns()
LANGUAGE plpgsql AS $$
DECLARE
    v_step_id INT;
BEGIN
    SELECT id INTO v_step_id FROM public.import_step WHERE code = 'link_establishment_to_legal_unit';
    IF v_step_id IS NULL THEN
        RAISE WARNING 'link_establishment_to_legal_unit step not found, cannot clean up data columns.';
        RETURN;
    END IF;

    RAISE DEBUG '[import.cleanup_link_lu_data_columns] For step_id % (link_establishment_to_legal_unit), deleting all source_input columns.', v_step_id;

    -- Delete only those dynamically generated 'legal_unit_%' source_input columns whose
    -- underlying identifier type code is no longer *active*. This preserves stable
    -- priorities for still-active codes and avoids creating temporary orphans.
    DELETE FROM public.import_data_column idc
    WHERE idc.step_id = v_step_id
      AND idc.purpose = 'source_input'
      AND replace(replace(idc.column_name, 'legal_unit_', ''), '_raw', '') NOT IN (
          SELECT code FROM public.external_ident_type_active
      );
END;
$$;

-- Register the lifecycle callback
CALL lifecycle_callbacks.add(
    'import_link_lu_data_columns',
    ARRAY['public.external_ident_type']::regclass[],
    'import.generate_link_lu_data_columns',
    'import.cleanup_link_lu_data_columns'
);

-- Call generate once initially
CALL import.generate_link_lu_data_columns();

END;

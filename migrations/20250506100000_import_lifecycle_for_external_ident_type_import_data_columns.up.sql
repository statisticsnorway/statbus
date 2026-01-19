BEGIN;

-- Lifecycle callback procedures for external_ident data columns
CREATE OR REPLACE PROCEDURE import.generate_external_ident_data_columns()
LANGUAGE plpgsql AS $$
DECLARE
    v_step_id INT;
    v_ident_type RECORD;
    v_def RECORD;
    v_base_priority INT;
    v_active_codes TEXT[];
    v_calculated_priority INT;
BEGIN
    SELECT id INTO v_step_id FROM public.import_step WHERE code = 'external_idents';
    IF v_step_id IS NULL THEN
        RAISE EXCEPTION 'external_idents step not found, cannot generate data columns.';
        RETURN;
    END IF;

    SELECT array_agg(code ORDER BY priority) INTO v_active_codes FROM public.external_ident_type_active;
    RAISE DEBUG '[import.generate_external_ident_data_columns] For step_id % (external_idents), ensuring data columns for active codes: %', v_step_id, v_active_codes;

    -- Get the highest priority among non-dynamic columns (those without purpose='source_input')
    -- For external_idents step, this should be 4 (from establishment_id)
    SELECT COALESCE(MAX(idc.priority), 0) INTO v_base_priority
    FROM public.import_data_column idc 
    WHERE idc.step_id = v_step_id 
      AND idc.purpose != 'source_input';

    -- Add source_input column for each active external_ident_type for the step
    -- Expected baseline: tax_ident_raw (priority=1) -> 7, stat_ident_raw (priority=2) -> 8
    -- With base_priority = 4, formula: base_priority + 2 + v_ident_type.priority
    FOR v_ident_type IN SELECT code, priority FROM public.external_ident_type_active ORDER BY priority
    LOOP
        v_calculated_priority := v_base_priority + 2 + v_ident_type.priority;
        
        INSERT INTO public.import_data_column (step_id, column_name, column_type, purpose, is_nullable, is_uniquely_identifying, priority)
        VALUES (v_step_id, v_ident_type.code || '_raw', 'TEXT', 'source_input', true, true, v_calculated_priority)
        ON CONFLICT (step_id, column_name) DO UPDATE SET
            priority = EXCLUDED.priority,
            is_uniquely_identifying = EXCLUDED.is_uniquely_identifying
        WHERE public.import_data_column.priority != EXCLUDED.priority;  -- Only update if priority changed
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

    RAISE DEBUG '[import.cleanup_external_ident_data_columns] For step_id % (external_idents), deleting all source_input columns.', v_step_id;

    -- Delete only those dynamically generated source_input columns whose
    -- identifier type code is no longer *active*.  This preserves stable priorities
    -- for still-active codes and avoids creating temporary orphans that could
    -- trigger unintended side-effects in other lifecycle callbacks.
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
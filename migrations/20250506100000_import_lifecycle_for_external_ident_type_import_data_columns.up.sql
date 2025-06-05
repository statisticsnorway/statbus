BEGIN;

-- Lifecycle callback procedures for external_ident data columns
CREATE OR REPLACE PROCEDURE import.generate_external_ident_data_columns()
LANGUAGE plpgsql AS $$
DECLARE
    v_step_id INT;
    v_ident_type RECORD;
    v_def RECORD;
    v_current_priority INT;
BEGIN
    RAISE DEBUG '--> Running import.generate_external_ident_data_columns...'; -- Removed debug
    SELECT id INTO v_step_id FROM public.import_step WHERE code = 'external_idents';
    IF v_step_id IS NULL THEN
        RAISE EXCEPTION 'external_idents step not found, cannot generate data columns.'; -- Keep warning
        RETURN;
    END IF;

    SELECT COALESCE(MAX(idc.priority), 0) INTO v_current_priority
    FROM public.import_data_column idc WHERE idc.step_id = v_step_id;
    RAISE DEBUG '  [-] Initial max priority for step_id % (external_idents): %', v_step_id, v_current_priority;

    -- Add source_input column for each active external_ident_type for the step
    RAISE DEBUG '  [-] Found external_idents step_id: %', v_step_id; -- Removed debug
    FOR v_ident_type IN SELECT code FROM public.external_ident_type_active ORDER BY priority
    LOOP
        v_current_priority := v_current_priority + 1;
        RAISE DEBUG '    - Processing external_ident_type: %, priority: %', v_ident_type.code, v_current_priority; -- Removed debug
        INSERT INTO public.import_data_column (step_id, column_name, column_type, purpose, is_nullable, is_uniquely_identifying, priority)
        VALUES (v_step_id, v_ident_type.code, 'TEXT', 'source_input', true, false, v_current_priority)
        ON CONFLICT (step_id, column_name) DO UPDATE SET priority = EXCLUDED.priority WHERE import_data_column.priority IS NULL;
    END LOOP;

    RAISE DEBUG 'Finished generating dynamic external_ident data columns for step %.', v_step_id; -- Removed debug
END;
$$;

CREATE OR REPLACE PROCEDURE import.cleanup_external_ident_data_columns()
LANGUAGE plpgsql AS $$
DECLARE
    v_step_id INT;
BEGIN
    RAISE NOTICE 'Cleaning up dynamic external_ident data columns...';
    SELECT id INTO v_step_id FROM public.import_step WHERE code = 'external_idents';
    IF v_step_id IS NULL THEN
        RAISE WARNING 'external_idents step not found, cannot clean up data columns.';
        RETURN;
    END IF;

    -- Delete columns dynamically added by the generate procedure
    DELETE FROM public.import_data_column
    WHERE step_id = v_step_id
      AND (
          -- Delete ALL source_input columns for this step, as they are all dynamically generated
          -- by this callback based on external_ident_type entries.
          -- Statically defined columns for this step (like 'operation', 'action') have 'internal' purpose.
          (purpose = 'source_input')
      );

    RAISE NOTICE 'Finished cleaning up dynamic external_ident data columns.';
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

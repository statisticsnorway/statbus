BEGIN;

-- Lifecycle callback procedures for external_ident data columns
CREATE OR REPLACE PROCEDURE import.generate_external_ident_data_columns()
LANGUAGE plpgsql AS $$
DECLARE
    v_step_id INT;
    v_ident_type RECORD;
    v_def RECORD;
BEGIN
    RAISE DEBUG '--> Running import.generate_external_ident_data_columns...'; -- Removed debug
    SELECT id INTO v_step_id FROM public.import_step WHERE code = 'external_idents';
    IF v_step_id IS NULL THEN
        RAISE EXCEPTION 'external_idents step not found, cannot generate data columns.'; -- Keep warning
        RETURN;
    END IF;

    -- Add source_input column for each active external_ident_type for the step
    RAISE DEBUG '  [-] Found external_idents step_id: %', v_step_id; -- Removed debug
    FOR v_ident_type IN SELECT code FROM public.external_ident_type_active ORDER BY priority
    LOOP
        RAISE DEBUG '    - Processing external_ident_type: %', v_ident_type.code; -- Removed debug
        INSERT INTO public.import_data_column (step_id, column_name, column_type, purpose, is_nullable, is_uniquely_identifying)
        VALUES (v_step_id, v_ident_type.code, 'TEXT', 'source_input', true, false)
        ON CONFLICT (step_id, column_name) DO NOTHING;
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
          -- Delete source_input columns matching type codes
          (purpose = 'source_input' AND column_name IN (SELECT code FROM public.external_ident_type))
          -- pk_id columns 'legal_unit_id' and 'establishment_id' are not managed by this lifecycle callback.
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

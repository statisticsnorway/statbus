BEGIN;

-- Lifecycle callback procedures for statistical_variables data columns
CREATE OR REPLACE PROCEDURE import.generate_stat_var_data_columns()
LANGUAGE plpgsql AS $$
DECLARE
    v_step_id INT;
    v_stat_def RECORD;
    v_def RECORD;
    v_pk_col_name TEXT;
    v_stat_def_code TEXT;
    v_calculated_priority INT;
    v_active_codes TEXT[];
BEGIN
    SELECT id INTO v_step_id FROM public.import_step WHERE code = 'statistical_variables';
    IF v_step_id IS NULL THEN
        RAISE EXCEPTION 'statistical_variables step not found, cannot generate data columns.';
        RETURN;
    END IF;

    SELECT array_agg(code ORDER BY priority) INTO v_active_codes FROM public.stat_definition_active;
    RAISE DEBUG '[import.generate_stat_var_data_columns] For step_id % (statistical_variables), ensuring data columns for active codes: %', v_step_id, v_active_codes;

    -- For statistical_variables step, we generate 3 columns per stat_definition in sequence:
    -- Baseline expectations:
    -- employees (priority=1): _raw=1, internal=2, pk_id=3
    -- turnover (priority=2): _raw=4, internal=5, pk_id=6

    -- Add source_input columns for each active stat_definition
    FOR v_stat_def IN SELECT code, priority FROM public.stat_definition_active ORDER BY priority
    LOOP
        v_calculated_priority := (v_stat_def.priority - 1) * 3 + 1;
        
        INSERT INTO public.import_data_column (step_id, column_name, column_type, purpose, is_nullable, is_uniquely_identifying, priority)
        VALUES (v_step_id, v_stat_def.code || '_raw', 'TEXT', 'source_input', true, false, v_calculated_priority)
        ON CONFLICT (step_id, column_name) DO UPDATE SET
            priority = EXCLUDED.priority,
            is_uniquely_identifying = EXCLUDED.is_uniquely_identifying
        WHERE public.import_data_column.priority != EXCLUDED.priority;  -- Only update if priority changed
    END LOOP;

    -- Add internal typed columns for each active stat_definition
    FOR v_stat_def IN SELECT code, type, priority FROM public.stat_definition_active ORDER BY priority
    LOOP
        v_calculated_priority := (v_stat_def.priority - 1) * 3 + 2;
        
        INSERT INTO public.import_data_column (step_id, column_name, column_type, purpose, is_nullable, is_uniquely_identifying, priority)
        VALUES (v_step_id, v_stat_def.code,
                CASE v_stat_def.type
                    WHEN 'int' THEN 'INTEGER'
                    WHEN 'float' THEN 'NUMERIC'
                    WHEN 'bool' THEN 'BOOLEAN'
                    ELSE 'TEXT'
                END,
                'internal', true, false, v_calculated_priority)
        ON CONFLICT (step_id, column_name) DO UPDATE SET
            priority = EXCLUDED.priority,
            column_type = EXCLUDED.column_type,
            is_uniquely_identifying = EXCLUDED.is_uniquely_identifying
        WHERE public.import_data_column.priority != EXCLUDED.priority;  -- Only update if priority changed
    END LOOP;

    -- Add pk_id columns for each active stat_definition
    FOR v_stat_def IN SELECT code, priority FROM public.stat_definition_active ORDER BY priority
    LOOP
        v_calculated_priority := (v_stat_def.priority - 1) * 3 + 3;
        v_pk_col_name := format('stat_for_unit_%s_id', v_stat_def.code);
        
        INSERT INTO public.import_data_column (step_id, column_name, column_type, purpose, is_nullable, is_uniquely_identifying, priority)
        VALUES (v_step_id, v_pk_col_name, 'INTEGER', 'pk_id', true, false, v_calculated_priority)
        ON CONFLICT (step_id, column_name) DO UPDATE SET
            priority = EXCLUDED.priority,
            is_uniquely_identifying = EXCLUDED.is_uniquely_identifying
        WHERE public.import_data_column.priority != EXCLUDED.priority;  -- Only update if priority changed
    END LOOP;
END;
$$;

CREATE OR REPLACE PROCEDURE import.cleanup_stat_var_data_columns()
LANGUAGE plpgsql AS $$
DECLARE
    v_step_id INT;
    v_pk_col_name TEXT;
BEGIN
    SELECT id INTO v_step_id FROM public.import_step WHERE code = 'statistical_variables';
    IF v_step_id IS NULL THEN
        RAISE WARNING 'statistical_variables step not found, cannot clean up data columns.';
        RETURN;
    END IF;

    RAISE DEBUG '[import.cleanup_stat_var_data_columns] For step_id % (statistical_variables), deleting columns for inactive stat definitions.', v_step_id;

    -- Delete source_input columns for inactive stat definitions
    DELETE FROM public.import_data_column
    WHERE step_id = v_step_id
      AND purpose = 'source_input'
      AND replace(column_name, '_raw', '') NOT IN (
          SELECT code FROM public.stat_definition_active
      );

    -- Delete internal typed columns for inactive stat definitions
    DELETE FROM public.import_data_column
    WHERE step_id = v_step_id
      AND purpose = 'internal'
      AND column_name NOT IN (
          SELECT code FROM public.stat_definition_active
      );

    -- Delete pk_id columns for inactive stat definitions
    DELETE FROM public.import_data_column
    WHERE step_id = v_step_id
      AND purpose = 'pk_id'
      AND column_name LIKE 'stat_for_unit_%_id'
      AND regexp_replace(column_name, 'stat_for_unit_|_id', '', 'g') NOT IN (
          SELECT code FROM public.stat_definition_active
      );
END;
$$;

-- Register the lifecycle callback
CALL lifecycle_callbacks.add(
    'import_stat_var_data_columns',
    ARRAY['public.stat_definition']::regclass[],
    'import.generate_stat_var_data_columns',
    'import.cleanup_stat_var_data_columns'
);

-- Call generate once initially to populate columns based on existing definitions
CALL import.generate_stat_var_data_columns();

END;
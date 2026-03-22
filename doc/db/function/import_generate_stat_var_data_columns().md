```sql
CREATE OR REPLACE PROCEDURE import.generate_stat_var_data_columns()
 LANGUAGE plpgsql
AS $procedure$
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

    SELECT array_agg(code ORDER BY priority) INTO v_active_codes FROM public.stat_definition_enabled;
    RAISE DEBUG '[import.generate_stat_var_data_columns] For step_id % (statistical_variables), ensuring data columns for active codes: %', v_step_id, v_active_codes;

    -- For statistical_variables step, we generate 3 columns per stat_definition in sequence:
    -- Baseline expectations:
    -- employees (priority=1): _raw=1, internal=2, pk_id=3
    -- turnover (priority=2): _raw=4, internal=5, pk_id=6

    -- Add source_input columns with target_pg_type derived from the stat definition type
    FOR v_stat_def IN SELECT code, type, priority FROM public.stat_definition_enabled ORDER BY priority
    LOOP
        v_calculated_priority := (v_stat_def.priority - 1) * 3 + 1;

        INSERT INTO public.import_data_column (step_id, column_name, column_type, purpose, is_nullable, is_uniquely_identifying, priority, target_pg_type)
        VALUES (v_step_id, v_stat_def.code || '_raw', 'TEXT', 'source_input', true, false, v_calculated_priority,
                CASE v_stat_def.type
                    WHEN 'int' THEN 'INTEGER'
                    WHEN 'float' THEN 'NUMERIC'
                    WHEN 'bool' THEN 'BOOLEAN'
                    ELSE 'TEXT'
                END)
        ON CONFLICT (step_id, column_name) DO UPDATE SET
            priority = EXCLUDED.priority,
            is_uniquely_identifying = EXCLUDED.is_uniquely_identifying,
            target_pg_type = EXCLUDED.target_pg_type
        WHERE public.import_data_column.priority != EXCLUDED.priority
           OR public.import_data_column.target_pg_type IS DISTINCT FROM EXCLUDED.target_pg_type;
    END LOOP;

    -- Add internal typed columns for each active stat_definition
    FOR v_stat_def IN SELECT code, type, priority FROM public.stat_definition_enabled ORDER BY priority
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
    FOR v_stat_def IN SELECT code, priority FROM public.stat_definition_enabled ORDER BY priority
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
$procedure$
```

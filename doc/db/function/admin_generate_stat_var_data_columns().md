```sql
CREATE OR REPLACE PROCEDURE admin.generate_stat_var_data_columns()
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_step_id INT;
    v_stat_def RECORD;
    v_def RECORD;
    v_pk_col_name TEXT;
    v_stat_def_code TEXT;
BEGIN
    RAISE DEBUG '--> Running admin.generate_stat_var_data_columns...'; -- Removed debug
    SELECT id INTO v_step_id FROM public.import_step WHERE code = 'statistical_variables';
    IF v_step_id IS NULL THEN
        RAISE EXCEPTION 'statistical_variables step not found, cannot generate data columns.'; -- Keep warning
        RETURN;
    END IF;

    -- Add source_input and pk_id column for each active stat_definition for the step
    RAISE DEBUG '  [-] Found statistical_variables step_id: %', v_step_id; -- Removed debug
    FOR v_stat_def IN SELECT code FROM public.stat_definition_active ORDER BY priority
    LOOP
        RAISE DEBUG '    - Processing stat_definition: %', v_stat_def.code; -- Removed debug
        -- Add source_input column (named after stat code)
        INSERT INTO public.import_data_column (step_id, column_name, column_type, purpose, is_nullable)
        VALUES (v_step_id, v_stat_def.code, 'TEXT', 'source_input', true)
        ON CONFLICT (step_id, column_name) DO NOTHING;

        -- Add pk_id column (named stat_for_unit_{code}_id)
        v_pk_col_name := format('stat_for_unit_%s_id', v_stat_def.code);
        INSERT INTO public.import_data_column (step_id, column_name, column_type, purpose, is_nullable)
        VALUES (v_step_id, v_pk_col_name, 'INTEGER', 'pk_id', true)
        ON CONFLICT (step_id, column_name) DO NOTHING;
    END LOOP;
    RAISE DEBUG '  [-] Finished generating dynamic statistical_variables data columns for step %.', v_step_id; -- Removed debug
END;
$procedure$
```

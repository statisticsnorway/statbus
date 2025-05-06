```sql
CREATE OR REPLACE PROCEDURE admin.generate_external_ident_data_columns()
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_step_id INT;
    v_ident_type RECORD;
    v_def RECORD;
BEGIN
    RAISE DEBUG '--> Running admin.generate_external_ident_data_columns...'; -- Removed debug
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
$procedure$
```

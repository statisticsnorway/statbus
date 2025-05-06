```sql
CREATE OR REPLACE PROCEDURE admin.generate_link_lu_data_columns()
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_step_id INT;
    v_ident_type RECORD;
    v_def RECORD;
BEGIN
    RAISE DEBUG 'Generating dynamic link_establishment_to_legal_unit data columns...';
    SELECT id INTO v_step_id FROM public.import_step WHERE code = 'link_establishment_to_legal_unit';
    IF v_step_id IS NULL THEN
        RAISE EXCEPTION 'link_establishment_to_legal_unit step not found, cannot generate data columns.';
        RETURN;
    END IF;

    -- Add source_input column for each active external_ident_type, prefixed with 'legal_unit_'
    FOR v_ident_type IN SELECT code FROM public.external_ident_type_active ORDER BY priority
    LOOP
        INSERT INTO public.import_data_column (step_id, column_name, column_type, purpose, is_nullable, is_uniquely_identifying)
        VALUES (v_step_id, 'legal_unit_' || v_ident_type.code, 'TEXT', 'source_input', true, false)
        ON CONFLICT (step_id, column_name) DO NOTHING; -- Add conflict handling back
    END LOOP;

    -- Ensure the pk_id column exists for the step
    INSERT INTO public.import_data_column (step_id, column_name, column_type, purpose, is_nullable)
    VALUES (v_step_id, 'legal_unit_id', 'INTEGER', 'pk_id', true)
    ON CONFLICT (step_id, column_name) DO NOTHING; -- Add conflict handling back

    RAISE DEBUG 'Finished generating dynamic link_establishment_to_legal_unit data columns for step %.', v_step_id;
END;
$procedure$
```

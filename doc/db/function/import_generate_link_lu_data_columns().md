```sql
CREATE OR REPLACE PROCEDURE import.generate_link_lu_data_columns()
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_step_id INT;
    v_ident_type RECORD;
    v_static_base INT;
BEGIN
    SELECT id INTO v_step_id FROM public.import_step WHERE code = 'link_establishment_to_legal_unit';
    IF v_step_id IS NULL THEN
        RAISE EXCEPTION 'link_establishment_to_legal_unit step not found, cannot generate data columns.';
        RETURN;
    END IF;

    -- STATBUS-314: base excludes only this procedure's OWN dynamic purpose
    -- ('source_input') so repeated calls are idempotent -- any other
    -- purpose (e.g. the static 'internal' primary_for_legal_unit column)
    -- stays part of a base that never moves on its own.
    SELECT COALESCE(MAX(idc.priority), 0) INTO v_static_base
    FROM public.import_data_column idc
    WHERE idc.step_id = v_step_id
      AND idc.purpose <> 'source_input';

    -- Priority is now a pure function of the static base and the ident
    -- type's own priority -- never of what this procedure has previously
    -- written -- matching the already-idempotent siblings
    -- (import.generate_external_ident_data_columns,
    -- import.generate_stat_var_data_columns).
    FOR v_ident_type IN SELECT code, priority FROM public.external_ident_type_enabled ORDER BY priority
    LOOP
        INSERT INTO public.import_data_column (step_id, column_name, column_type, purpose, is_nullable, is_uniquely_identifying, priority, target_pg_type)
        VALUES (v_step_id, 'legal_unit_' || v_ident_type.code || '_raw', 'TEXT', 'source_input', true, false, v_static_base + v_ident_type.priority, 'TEXT')
        ON CONFLICT (step_id, column_name) DO UPDATE SET
            priority = EXCLUDED.priority,
            is_uniquely_identifying = EXCLUDED.is_uniquely_identifying,
            target_pg_type = EXCLUDED.target_pg_type;
    END LOOP;

    -- The 'legal_unit_id' pk_id column is statically defined in 20250505120000_import_populate_steps.up.sql
    -- and should not be managed by this dynamic lifecycle callback.
END;
$procedure$
```

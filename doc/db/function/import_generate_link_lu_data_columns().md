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

    -- STATBUS-314: a TARGETED lookup of the one known-static row this
    -- procedure has never written and never will -- NOT a MAX/aggregate
    -- over the step's contents, filtered or otherwise (that shape is only
    -- idempotent-by-filter, one purpose-value away from re-basing on its
    -- own output again). primary_for_legal_unit's priority is fixed
    -- forever by 20250505120000_import_populate_steps.up.sql's
    -- PARTITION BY step_code row-numbering over an immutable, already-
    -- released VALUES list, so this lookup can never drift and can never
    -- match a row this procedure itself inserts.
    SELECT idc.priority INTO STRICT v_static_base
    FROM public.import_data_column idc
    WHERE idc.step_id = v_step_id
      AND idc.column_name = 'primary_for_legal_unit';

    -- Priority is now a pure function of the static base and the ident
    -- type's own priority -- never of what this procedure has previously
    -- written -- matching the already-idempotent sibling
    -- (import.generate_stat_var_data_columns).
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

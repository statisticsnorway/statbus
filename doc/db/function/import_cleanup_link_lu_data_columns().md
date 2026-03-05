```sql
CREATE OR REPLACE PROCEDURE import.cleanup_link_lu_data_columns()
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_step_id INT;
BEGIN
    SELECT id INTO v_step_id FROM public.import_step WHERE code = 'link_establishment_to_legal_unit';
    IF v_step_id IS NULL THEN
        RAISE WARNING 'link_establishment_to_legal_unit step not found, cannot clean up data columns.';
        RETURN;
    END IF;

    RAISE DEBUG '[import.cleanup_link_lu_data_columns] For step_id % (link_establishment_to_legal_unit), deleting all source_input columns.', v_step_id;

    -- Delete only those dynamically generated 'legal_unit_%' source_input columns whose
    -- underlying identifier type code is no longer *active*. This preserves stable
    -- priorities for still-active codes and avoids creating temporary orphans.
    DELETE FROM public.import_data_column idc
    WHERE idc.step_id = v_step_id
      AND idc.purpose = 'source_input'
      AND replace(replace(idc.column_name, 'legal_unit_', ''), '_raw', '') NOT IN (
          SELECT code FROM public.external_ident_type_active
      );
END;
$procedure$
```

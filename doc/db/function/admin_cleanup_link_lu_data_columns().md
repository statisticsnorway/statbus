```sql
CREATE OR REPLACE PROCEDURE admin.cleanup_link_lu_data_columns()
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_step_id INT;
BEGIN
    RAISE DEBUG 'Cleaning up dynamic link_establishment_to_legal_unit data columns...';
    SELECT id INTO v_step_id FROM public.import_step WHERE code = 'link_establishment_to_legal_unit';
    IF v_step_id IS NULL THEN
        RAISE WARNING 'link_establishment_to_legal_unit step not found, cannot clean up data columns.';
        RETURN;
    END IF;

    -- Delete columns dynamically added by the generate procedure
    DELETE FROM public.import_data_column
    WHERE step_id = v_step_id
      AND (
          -- Delete source_input columns matching the prefix and type codes
          (purpose = 'source_input' AND column_name LIKE 'legal_unit_%' AND substring(column_name from 'legal_unit_(.*)') IN (SELECT code FROM public.external_ident_type))
          OR
          -- Delete the pk_id column added by this callback
          (purpose = 'pk_id' AND column_name = 'legal_unit_id')
      );

    RAISE DEBUG 'Finished cleaning up dynamic link_establishment_to_legal_unit data columns.';
END;
$procedure$
```

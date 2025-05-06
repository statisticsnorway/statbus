```sql
CREATE OR REPLACE PROCEDURE admin.cleanup_external_ident_data_columns()
 LANGUAGE plpgsql
AS $procedure$
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
$procedure$
```

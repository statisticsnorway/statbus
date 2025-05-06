```sql
CREATE OR REPLACE PROCEDURE admin.cleanup_stat_var_data_columns()
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_step_id INT;
    v_pk_col_name TEXT;
BEGIN
    RAISE NOTICE 'Cleaning up dynamic statistical_variables data columns...';
    SELECT id INTO v_step_id FROM public.import_step WHERE code = 'statistical_variables';
    IF v_step_id IS NULL THEN
        RAISE WARNING 'statistical_variables step not found, cannot clean up data columns.';
        RETURN;
    END IF;

    -- Delete columns dynamically added by the generate procedure
    DELETE FROM public.import_data_column
    WHERE step_id = v_step_id
      AND (
          -- Delete source_input columns matching stat codes
          (purpose = 'source_input' AND column_name IN (SELECT code FROM public.stat_definition))
          OR
          -- Delete the pk_id columns matching the pattern
          (purpose = 'pk_id' AND column_name LIKE 'stat_for_unit_%_id')
      );

    RAISE NOTICE 'Finished cleaning up dynamic statistical_variables data columns.';
END;
$procedure$
```

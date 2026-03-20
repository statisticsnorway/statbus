```sql
CREATE OR REPLACE PROCEDURE import.cleanup_stat_var_data_columns()
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_step_id INT;
    v_pk_col_name TEXT;
BEGIN
    SELECT id INTO v_step_id FROM public.import_step WHERE code = 'statistical_variables';
    IF v_step_id IS NULL THEN
        RAISE WARNING 'statistical_variables step not found, cannot clean up data columns.';
        RETURN;
    END IF;

    RAISE DEBUG '[import.cleanup_stat_var_data_columns] For step_id % (statistical_variables), deleting columns for inactive stat definitions.', v_step_id;

    -- Delete source_input columns for inactive stat definitions
    DELETE FROM public.import_data_column
    WHERE step_id = v_step_id
      AND purpose = 'source_input'
      AND replace(column_name, '_raw', '') NOT IN (
          SELECT code FROM public.stat_definition_enabled
      );

    -- Delete internal typed columns for inactive stat definitions
    DELETE FROM public.import_data_column
    WHERE step_id = v_step_id
      AND purpose = 'internal'
      AND column_name NOT IN (
          SELECT code FROM public.stat_definition_enabled
      );

    -- Delete pk_id columns for inactive stat definitions
    DELETE FROM public.import_data_column
    WHERE step_id = v_step_id
      AND purpose = 'pk_id'
      AND column_name LIKE 'stat_for_unit_%_id'
      AND regexp_replace(column_name, 'stat_for_unit_|_id', '', 'g') NOT IN (
          SELECT code FROM public.stat_definition_enabled
      );
END;
$procedure$
```

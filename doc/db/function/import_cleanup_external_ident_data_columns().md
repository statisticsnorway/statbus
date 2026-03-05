```sql
CREATE OR REPLACE PROCEDURE import.cleanup_external_ident_data_columns()
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_step_id INT;
    v_active_column_names TEXT[];
    v_ident_type RECORD;
    v_labels_array TEXT[];
    v_label TEXT;
BEGIN
    SELECT id INTO v_step_id FROM public.import_step WHERE code = 'external_idents';
    IF v_step_id IS NULL THEN
        RAISE WARNING 'external_idents step not found, cannot clean up data columns.';
        RETURN;
    END IF;

    RAISE DEBUG '[import.cleanup_external_ident_data_columns] For step_id % (external_idents), cleaning up orphaned columns.', v_step_id;

    -- Build list of column names that should exist based on active types
    v_active_column_names := ARRAY[]::TEXT[];
    
    FOR v_ident_type IN 
        SELECT code, shape, labels 
        FROM public.external_ident_type_active
    LOOP
        IF v_ident_type.shape = 'regular' THEN
            -- Regular: single {code}_raw column
            v_active_column_names := v_active_column_names || (v_ident_type.code || '_raw');
        ELSIF v_ident_type.shape = 'hierarchical' THEN
            -- Hierarchical: {code}_{label}_raw columns + {code}_path
            v_labels_array := string_to_array(ltree2text(v_ident_type.labels), '.');
            FOREACH v_label IN ARRAY v_labels_array
            LOOP
                v_active_column_names := v_active_column_names || (v_ident_type.code || '_' || v_label || '_raw');
            END LOOP;
            v_active_column_names := v_active_column_names || (v_ident_type.code || '_path');
        END IF;
    END LOOP;
    
    RAISE DEBUG '[import.cleanup_external_ident_data_columns] Active column names to preserve: %', v_active_column_names;

    -- Delete dynamically generated columns (source_input or internal) that are no longer needed
    -- A column is dynamically generated if it ends with '_raw' or '_path'
    DELETE FROM public.import_data_column idc
    WHERE idc.step_id = v_step_id
      AND idc.purpose IN ('source_input', 'internal')
      AND (idc.column_name LIKE '%_raw' OR idc.column_name LIKE '%_path')
      AND idc.column_name != ALL(v_active_column_names);
END;
$procedure$
```

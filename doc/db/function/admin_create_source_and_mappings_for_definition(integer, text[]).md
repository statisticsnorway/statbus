```sql
CREATE OR REPLACE FUNCTION admin.create_source_and_mappings_for_definition(p_definition_id integer, p_source_columns text[])
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_col_name TEXT;
    v_priority INT := 0;
    v_source_col_id INT;
    v_data_col_id INT;
    v_max_priority INT;
BEGIN
    -- Create static source columns based on input array
    FOREACH v_col_name IN ARRAY p_source_columns
    LOOP
        v_priority := v_priority + 1;
        INSERT INTO public.import_source_column (definition_id, column_name, priority)
        VALUES (p_definition_id, v_col_name, v_priority)
        ON CONFLICT DO NOTHING
        RETURNING id INTO v_source_col_id;

        -- Map static source column to corresponding data column
        IF v_source_col_id IS NOT NULL THEN
            -- Find the target data column by joining through the steps linked to this definition
            SELECT dc.id INTO v_data_col_id
            FROM public.import_definition_step ds
            JOIN public.import_data_column dc ON ds.step_id = dc.step_id
            WHERE ds.definition_id = p_definition_id
              AND dc.column_name = v_col_name
              AND dc.purpose = 'source_input';

            IF v_data_col_id IS NOT NULL THEN
                INSERT INTO public.import_mapping (definition_id, source_column_id, target_data_column_id)
                VALUES (p_definition_id, v_source_col_id, v_data_col_id)
                ON CONFLICT DO NOTHING;
            ELSE
                 RAISE EXCEPTION '[Definition %] No matching source_input data column found for source column %', p_definition_id, v_col_name;
            END IF;
        END IF;
    END LOOP;

    -- Add dynamic source columns and mappings for External Idents
    SELECT COALESCE(MAX(priority), v_priority) INTO v_max_priority FROM public.import_source_column WHERE definition_id = p_definition_id;
    INSERT INTO public.import_source_column (definition_id, column_name, priority)
    SELECT p_definition_id, ext.code, v_max_priority + ROW_NUMBER() OVER (ORDER BY ext.priority)
    FROM public.external_ident_type_active ext
    ON CONFLICT DO NOTHING;

    -- Add dynamic source columns and mappings for Statistical Variables
    SELECT COALESCE(MAX(priority), v_max_priority) INTO v_max_priority FROM public.import_source_column WHERE definition_id = p_definition_id;
    INSERT INTO public.import_source_column (definition_id, column_name, priority)
    SELECT p_definition_id, stat.code, v_max_priority + ROW_NUMBER() OVER (ORDER BY stat.priority)
    FROM public.stat_definition_active stat
    ON CONFLICT DO NOTHING;

    -- Mapping for dynamic columns is now handled by the manual mapping in the definition files
    -- or potentially by specific lifecycle callbacks if needed, not this generic helper.
END;
$function$
```

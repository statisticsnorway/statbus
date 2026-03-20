```sql
CREATE OR REPLACE FUNCTION import.create_source_and_mappings_for_definition(p_definition_id integer, p_source_columns text[])
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_def public.import_definition;
    v_col_name TEXT;
    v_priority INT := 0;
    v_source_col_id INT;
    v_data_col_id INT;
    v_max_priority INT;
    v_col_rec RECORD;
    v_has_stat_step BOOLEAN;
BEGIN
    SELECT * INTO v_def FROM public.import_definition WHERE id = p_definition_id;

    -- Handle validity date mappings based on definition mode
    IF v_def.valid_time_from = 'job_provided' THEN
        FOR v_col_name IN VALUES ('valid_from'), ('valid_to') LOOP
            SELECT dc.id INTO v_data_col_id FROM public.import_data_column dc JOIN public.import_step s ON dc.step_id = s.id WHERE s.code = 'valid_time' AND dc.column_name = v_col_name || '_raw';
            IF v_data_col_id IS NOT NULL THEN
                INSERT INTO public.import_mapping (definition_id, source_expression, target_data_column_id, target_data_column_purpose)
                VALUES (p_definition_id, 'default', v_data_col_id, 'source_input'::public.import_data_column_purpose)
                ON CONFLICT (definition_id, target_data_column_id) WHERE is_ignored = false DO NOTHING;
            END IF;
        END LOOP;
    END IF;

    -- Create source columns and map them
    FOREACH v_col_name IN ARRAY p_source_columns LOOP
        v_priority := v_priority + 1;
        INSERT INTO public.import_source_column (definition_id, column_name, priority)
        VALUES (p_definition_id, v_col_name, v_priority)
        ON CONFLICT DO NOTHING RETURNING id INTO v_source_col_id;

        IF v_source_col_id IS NOT NULL THEN
            SELECT dc.id INTO v_data_col_id
            FROM public.import_definition_step ds
            JOIN public.import_data_column dc ON ds.step_id = dc.step_id
            WHERE ds.definition_id = p_definition_id AND dc.column_name = v_col_name || '_raw' AND dc.purpose = 'source_input';

            IF v_data_col_id IS NOT NULL THEN
                INSERT INTO public.import_mapping (definition_id, source_column_id, target_data_column_id, target_data_column_purpose)
                VALUES (p_definition_id, v_source_col_id, v_data_col_id, 'source_input'::public.import_data_column_purpose)
                ON CONFLICT (definition_id, source_column_id, target_data_column_id) DO NOTHING;
            ELSE
                INSERT INTO public.import_mapping (definition_id, source_column_id, is_ignored)
                VALUES (p_definition_id, v_source_col_id, TRUE)
                ON CONFLICT (definition_id, source_column_id, target_data_column_id) WHERE target_data_column_id IS NULL DO NOTHING;
            END IF;
        END IF;
    END LOOP;

    -- Only add stat variable mappings if the definition has a statistical_variables step
    SELECT EXISTS (
        SELECT 1 FROM public.import_definition_step ids
        JOIN public.import_step s ON ids.step_id = s.id
        WHERE ids.definition_id = p_definition_id AND s.code = 'statistical_variables'
    ) INTO v_has_stat_step;

    IF v_has_stat_step THEN
        -- Dynamically add and map source columns for Statistical Variables
        SELECT COALESCE(MAX(priority), v_priority) INTO v_max_priority FROM public.import_source_column WHERE definition_id = p_definition_id;
        INSERT INTO public.import_source_column (definition_id, column_name, priority)
        SELECT p_definition_id, stat.code, v_max_priority + ROW_NUMBER() OVER (ORDER BY stat.priority)
        FROM public.stat_definition_enabled stat ON CONFLICT (definition_id, column_name) DO NOTHING;

        FOR v_col_rec IN
            SELECT isc.id as source_col_id, isc.column_name as stat_code FROM public.import_source_column isc
            JOIN public.stat_definition_enabled sda ON isc.column_name = sda.code
            WHERE isc.definition_id = p_definition_id AND NOT EXISTS (
                SELECT 1 FROM public.import_mapping im WHERE im.definition_id = p_definition_id AND im.source_column_id = isc.id
            )
        LOOP
            SELECT dc.id INTO v_data_col_id FROM public.import_definition_step ds
            JOIN public.import_step s ON ds.step_id = s.id
            JOIN public.import_data_column dc ON ds.step_id = dc.step_id
            WHERE ds.definition_id = p_definition_id AND s.code = 'statistical_variables' AND dc.column_name = v_col_rec.stat_code || '_raw' AND dc.purpose = 'source_input';

            IF v_data_col_id IS NOT NULL THEN
                INSERT INTO public.import_mapping (definition_id, source_column_id, target_data_column_id, target_data_column_purpose)
                VALUES (p_definition_id, v_col_rec.source_col_id, v_data_col_id, 'source_input')
                ON CONFLICT (definition_id, source_column_id, target_data_column_id) DO NOTHING;
            ELSE
                RAISE EXCEPTION '[Definition %] No matching source_input data column found in "statistical_variables" step for dynamically added stat source column "%".', p_definition_id, v_col_rec.stat_code;
            END IF;
        END LOOP;
    END IF;
END;
$function$
```

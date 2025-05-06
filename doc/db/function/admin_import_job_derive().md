```sql
CREATE OR REPLACE FUNCTION admin.import_job_derive()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    definition public.import_definition;
BEGIN
    SELECT * INTO definition
    FROM public.import_definition
    WHERE id = NEW.definition_id;

    -- Check if definition exists and is marked as valid
    IF NOT FOUND OR NOT definition.valid THEN
        RAISE EXCEPTION 'Cannot create import job: Import definition % (%) is not valid. Error: %',
            NEW.definition_id, COALESCE(definition.name, 'N/A'), COALESCE(definition.validation_error, 'Definition not found or not marked valid');
    END IF;

    -- Validate time_context_ident if provided in the definition
    IF definition.time_context_ident IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.time_context WHERE ident = definition.time_context_ident) THEN
         RAISE EXCEPTION 'Cannot create import job: Invalid time_context_ident % specified in import definition %',
            definition.time_context_ident, definition.id;
    END IF;

    IF NEW.slug IS NULL THEN
        NEW.slug := format('import_job_%s', NEW.id);
    END IF;

    NEW.upload_table_name := format('%s_upload', NEW.slug);
    NEW.data_table_name := format('%s_data', NEW.slug);

    -- Populate the definition_snapshot JSONB with explicit keys matching table names
    SELECT jsonb_build_object(
        'import_definition', (SELECT row_to_json(d) FROM public.import_definition d WHERE d.id = NEW.definition_id),
        'import_step_list', (SELECT jsonb_agg(row_to_json(s) ORDER BY s.priority) FROM public.import_step s JOIN public.import_definition_step ds_link ON s.id = ds_link.step_id WHERE ds_link.definition_id = NEW.definition_id),
        'import_data_column_list', (
            SELECT jsonb_agg(row_to_json(dc) ORDER BY dc.id)
            FROM public.import_data_column dc
            JOIN public.import_step s_link ON dc.step_id = s_link.id
            JOIN public.import_definition_step ds_link ON s_link.id = ds_link.step_id
            WHERE ds_link.definition_id = NEW.definition_id
        ),
        'import_source_column_list', (SELECT jsonb_agg(row_to_json(sc_list) ORDER BY sc_list.priority) FROM public.import_source_column sc_list WHERE sc_list.definition_id = NEW.definition_id),
        'import_mapping_list', (
            SELECT jsonb_agg(
                jsonb_build_object(
                    'mapping', row_to_json(m_map),
                    'source_column', row_to_json(sc_map),
                    'target_data_column', row_to_json(dc_map)
                ) ORDER BY m_map.id
            )
            FROM public.import_mapping m_map
            LEFT JOIN public.import_source_column sc_map ON m_map.source_column_id = sc_map.id AND sc_map.definition_id = m_map.definition_id -- Ensure source_column is for the same definition
            JOIN public.import_data_column dc_map ON m_map.target_data_column_id = dc_map.id
            JOIN public.import_definition_step ds_map_link ON dc_map.step_id = ds_map_link.step_id AND ds_map_link.definition_id = m_map.definition_id -- Ensure data_column's step is linked to this definition
            WHERE m_map.definition_id = NEW.definition_id
        )
    ) INTO NEW.definition_snapshot;

    IF NEW.definition_snapshot IS NULL OR NEW.definition_snapshot = '{}'::jsonb OR NEW.definition_snapshot->'import_mapping_list' IS NULL THEN
         RAISE EXCEPTION 'Failed to generate a complete definition snapshot for definition_id %. Ensure mappings, source columns, and data columns are correctly defined and linked. Specifically, import_mapping_list might be missing or null.', NEW.definition_id;
    END IF;

    -- Set default validity dates from time context if available and not already set
    IF (NEW.default_valid_from IS NULL OR NEW.default_valid_to IS NULL) AND definition.time_context_ident IS NOT NULL THEN
        SELECT tc.valid_from, tc.valid_to
        INTO NEW.default_valid_from, NEW.default_valid_to
        FROM public.time_context tc
        WHERE tc.ident = definition.time_context_ident;
    END IF;

    IF NEW.default_data_source_code IS NULL AND definition.data_source_id IS NOT NULL THEN
        SELECT ds.code
        INTO NEW.default_data_source_code
        FROM public.data_source ds
        WHERE ds.id = definition.data_source_id;
    END IF;

    -- Set the user_id from the current authenticated user
    IF NEW.user_id IS NULL THEN
        NEW.user_id := auth.uid();
    END IF;

    RETURN NEW;
END;
$function$
```

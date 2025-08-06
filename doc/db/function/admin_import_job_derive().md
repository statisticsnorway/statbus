```sql
CREATE OR REPLACE FUNCTION admin.import_job_derive()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    definition public.import_definition;
    v_snapshot JSONB;
BEGIN
    SELECT * INTO definition
    FROM public.import_definition
    WHERE id = NEW.definition_id;

    -- Check if definition exists and is marked as valid
    IF NOT FOUND OR NOT definition.valid THEN
        RAISE EXCEPTION 'Cannot create import job: Import definition % (%) is not valid. Error: %',
            NEW.definition_id, COALESCE(definition.name, 'N/A'), COALESCE(definition.validation_error, 'Definition not found or not marked valid');
    END IF;

    -- Validate time_context_ident if provided on the job
    IF NEW.time_context_ident IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.time_context WHERE ident = NEW.time_context_ident) THEN
        RAISE EXCEPTION 'Cannot create import job: Invalid time_context_ident % provided for the job does not exist in public.time_context.', NEW.time_context_ident;
    END IF;

    IF NEW.slug IS NULL THEN
        NEW.slug := format('import_job_%s', NEW.id);
    END IF;

    NEW.upload_table_name := format('%I', NEW.slug || '_upload');
    NEW.data_table_name := format('%I', NEW.slug || '_data');

    -- Populate the definition_snapshot JSONB with explicit keys matching table names
    SELECT jsonb_build_object(
        'import_definition', (SELECT row_to_json(d) FROM public.import_definition d WHERE d.id = NEW.definition_id),
        'import_step_list', (SELECT jsonb_agg(row_to_json(s) ORDER BY s.priority) FROM public.import_step s JOIN public.import_definition_step ds_link ON s.id = ds_link.step_id WHERE ds_link.definition_id = NEW.definition_id),
        'import_data_column_list', (
            SELECT jsonb_agg(row_to_json(dc) ORDER BY s_link.priority, dc.priority, dc.column_name)
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
                ) ORDER BY s_link.priority, dc_map.priority, dc_map.column_name, m_map.id
            )
            FROM public.import_mapping m_map
            LEFT JOIN public.import_source_column sc_map ON m_map.source_column_id = sc_map.id AND sc_map.definition_id = m_map.definition_id -- Ensure source_column is for the same definition
            JOIN public.import_data_column dc_map ON m_map.target_data_column_id = dc_map.id
            JOIN public.import_step s_link ON dc_map.step_id = s_link.id
            JOIN public.import_definition_step ds_map_link ON s_link.id = ds_map_link.step_id AND ds_map_link.definition_id = m_map.definition_id -- Ensure data_column's step is linked to this definition
            WHERE m_map.definition_id = NEW.definition_id
        )
    ) INTO v_snapshot;

    IF v_snapshot IS NULL OR NOT (
        v_snapshot ? 'import_definition' AND
        v_snapshot ? 'import_step_list' AND
        v_snapshot ? 'import_data_column_list' AND
        v_snapshot ? 'import_source_column_list' AND
        v_snapshot ? 'import_mapping_list'
    ) THEN
         RAISE EXCEPTION 'Failed to generate a complete definition snapshot for definition_id %. It is missing one or more required keys: import_definition, import_step_list, import_data_column_list, import_source_column_list, import_mapping_list.', NEW.definition_id;
    END IF;

    -- Validate and set default validity dates based on the definition's declarative valid_time_from
    IF definition.valid_time_from = 'job_provided' THEN
        -- Case A: The definition requires job-level dates. The user must provide EITHER a time_context_ident OR explicit dates, but not both.
        IF NEW.time_context_ident IS NOT NULL AND (NEW.default_valid_from IS NOT NULL OR NEW.default_valid_to IS NOT NULL) THEN
            RAISE EXCEPTION 'Cannot specify both a time_context_ident and explicit default_valid_from/to dates for a job with definition %.', definition.name;
        END IF;
        IF NEW.time_context_ident IS NULL AND (NEW.default_valid_from IS NULL OR NEW.default_valid_to IS NULL) THEN
            RAISE EXCEPTION 'Must specify either a time_context_ident or explicit default_valid_from/to dates for a job with definition %.', definition.name;
        END IF;

        -- If time_context_ident is provided, derive the default dates.
        IF NEW.time_context_ident IS NOT NULL THEN
            -- Stage 1 of 2 for time_context handling:
            -- Derive from the job's time_context_ident and populate the job's own default_valid_from/to columns.
            -- Stage 2 happens in `import_job_prepare`, where these job-level defaults are used to populate the
            -- `_data` table's `valid_from`/`to` columns for every row via the `source_expression='default'` mapping.
            SELECT tc.valid_from, tc.valid_to
            INTO NEW.default_valid_from, NEW.default_valid_to
            FROM public.time_context tc
            WHERE tc.ident = NEW.time_context_ident;

            -- Also, add the time_context record itself to the snapshot for immutable processing
            SELECT v_snapshot || jsonb_build_object('time_context', row_to_json(tc))
            INTO v_snapshot
            FROM public.time_context tc WHERE tc.ident = NEW.time_context_ident;
        END IF;
        -- If explicit dates were provided, they are already on NEW and will be used.

    ELSIF definition.valid_time_from = 'source_columns' THEN
        -- Case C: The definition uses dates from the source file. The job MUST NOT provide a time_context_ident or explicit dates.
        IF NEW.time_context_ident IS NOT NULL THEN
            RAISE EXCEPTION 'Cannot specify a time_context_ident for an import job when its definition (%) has valid_time_from="source_columns".', definition.name;
        END IF;
        IF NEW.default_valid_from IS NOT NULL OR NEW.default_valid_to IS NOT NULL THEN
            RAISE EXCEPTION 'Cannot specify default_valid_from/to for an import job when its definition (%) has valid_time_from="source_columns".', definition.name;
        END IF;
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

    -- Set expires_at based on created_at and definition's retention period
    -- NEW.created_at is populated by its DEFAULT NOW() before this trigger runs for an INSERT.
    NEW.expires_at := NEW.created_at + COALESCE(definition.default_retention_period, '18 months'::INTERVAL);

    NEW.definition_snapshot := v_snapshot;
    RETURN NEW;
END;
$function$
```

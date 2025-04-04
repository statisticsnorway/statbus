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

    IF NOT definition.valid THEN
        RAISE EXCEPTION 'Cannot create import job for invalid import_definition % (%): %',
            definition.id, definition.name, COALESCE(definition.validation_error,'Is still draft');
    END IF;

    IF NEW.slug IS NULL THEN
        NEW.slug := format('import_job_%s', NEW.id);
    END IF;

    NEW.upload_table_name := format('%s_upload', NEW.slug);
    NEW.data_table_name := format('%s_data', NEW.slug);
    NEW.import_information_snapshot_table_name := format('%s_import_information', NEW.slug);

    -- Set target table name and schema from import definition
    SELECT it.table_name, it.schema_name
    INTO NEW.target_table_name, NEW.target_schema_name
    FROM public.import_definition id
    JOIN public.import_target it ON it.id = id.target_id
    WHERE id.id = NEW.definition_id;

    -- Set default validity dates from time context if available and not already set
    IF NEW.default_valid_from IS NULL OR NEW.default_valid_to IS NULL THEN
        SELECT tc.valid_from, tc.valid_to
        INTO NEW.default_valid_from, NEW.default_valid_to
        FROM public.import_definition id
        LEFT JOIN public.time_context tc ON tc.ident = id.time_context_ident
        WHERE id.id = NEW.definition_id;
    END IF;

    IF NEW.default_data_source_code IS NULL THEN
        SELECT ds.code
        INTO NEW.default_data_source_code
        FROM public.import_definition id
        JOIN public.data_source ds ON ds.id = id.data_source_id
        WHERE id.id = NEW.definition_id;
    END IF;

    -- Set the user_id from the current authenticated user
    IF NEW.user_id IS NULL THEN
        NEW.user_id := auth.uid();
    END IF;

    RETURN NEW;
END;
$function$
```

```sql
CREATE OR REPLACE FUNCTION admin.import_definition_validate_before()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    target_has_temporal boolean;
    missing_temporal text[];
BEGIN
    -- Skip validation if in draft mode
    IF NEW.draft THEN
        RETURN NEW;
    END IF;

    -- Check if target table has temporal columns
    SELECT EXISTS (
        SELECT 1 FROM public.import_target_column
        WHERE target_id = NEW.target_id
        AND column_name IN ('valid_from', 'valid_to')
    ) INTO target_has_temporal;

    IF NOT target_has_temporal THEN
        -- No temporal columns needed, validation passes
        NEW.valid := true;
        NEW.validation_error := NULL;
        RETURN NEW;
    END IF;

    -- Check which temporal columns are missing mappings
    SELECT array_agg(column_name)
    FROM public.import_target_column itc
    WHERE itc.target_id = NEW.target_id
    AND itc.column_name IN ('valid_from', 'valid_to')
    AND NOT EXISTS (
        SELECT 1 FROM public.import_mapping im
        WHERE im.target_column_id = itc.id
        AND im.definition_id = NEW.id
        AND (
            im.source_column_id IS NOT NULL OR
            im.source_expression = 'default'::public.import_source_expression OR
            im.source_value IS NOT NULL
        )
    ) INTO missing_temporal;

    -- Set validation results on NEW record
    NEW.valid := (missing_temporal IS NULL);
    NEW.validation_error := CASE
        WHEN missing_temporal IS NULL THEN NULL
        ELSE format(
            'Missing required mappings for temporal columns: %s. Either map source columns or use ''default'' expression',
            array_to_string(missing_temporal, ', ')
        )
    END;
    NEW.draft := CASE
        WHEN missing_temporal IS NULL THEN false
        ELSE true
    END;

    RETURN NEW;
END;
$function$
```

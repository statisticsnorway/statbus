```sql
CREATE OR REPLACE FUNCTION admin.detect_batch_api_table_properties(table_name regclass)
 RETURNS admin.batch_api_table_properties
 LANGUAGE plpgsql
AS $function$
DECLARE
    result admin.batch_api_table_properties;
BEGIN
    -- Initialize the result with default values
    result.has_priority := false;
    result.has_enabled := false;
    result.has_path := false;
    result.has_code := false;
    result.has_custom := false;
    result.has_description := false;
    result.schema_name := '';
    result.table_name := '';

    -- Populate schema_name and table_name
    SELECT n.nspname, c.relname
    INTO result.schema_name, result.table_name
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.oid = table_name;

    -- Check if specific columns exist
    PERFORM 1
    FROM pg_attribute
    WHERE attrelid = table_name AND attname = 'priority' AND NOT attisdropped;
    IF FOUND THEN
        result.has_priority := true;
    END IF;

    PERFORM 1
    FROM pg_attribute
    WHERE attrelid = table_name AND attname = 'enabled' AND NOT attisdropped;
    IF FOUND THEN
        result.has_enabled := true;
    END IF;

    PERFORM 1
    FROM pg_attribute
    WHERE attrelid = table_name AND attname = 'path' AND NOT attisdropped;
    IF FOUND THEN
        result.has_path := true;
    END IF;

    PERFORM 1
    FROM pg_attribute
    WHERE attrelid = table_name AND attname = 'code' AND NOT attisdropped;
    IF FOUND THEN
        result.has_code := true;
    END IF;

    PERFORM 1
    FROM pg_attribute
    WHERE attrelid = table_name AND attname = 'custom' AND NOT attisdropped;
    IF FOUND THEN
        result.has_custom := true;
    END IF;

    PERFORM 1
    FROM pg_attribute
    WHERE attrelid = table_name AND attname = 'description' AND NOT attisdropped;
    IF FOUND THEN
        result.has_description := true;
    END IF;

    RETURN result;
END;
$function$
```

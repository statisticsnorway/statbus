```sql
CREATE OR REPLACE FUNCTION admin.get_unique_columns(table_properties admin.batch_api_table_properties)
 RETURNS text[]
 LANGUAGE plpgsql
AS $function$
DECLARE
    unique_columns text[] := ARRAY[]::text[];
BEGIN
    IF table_properties.has_enabled THEN
        unique_columns := array_append(unique_columns, 'enabled');
    END IF;

    IF table_properties.has_path THEN
        unique_columns := array_append(unique_columns, 'path');
    ELSEIF table_properties.has_code THEN
        unique_columns := array_append(unique_columns, 'code');
    END IF;

    RETURN unique_columns;
END;
$function$
```

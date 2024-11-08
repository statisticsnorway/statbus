```sql
CREATE OR REPLACE FUNCTION admin.generate_prepare_function_for_custom(table_properties admin.batch_api_table_properties)
 RETURNS regprocedure
 LANGUAGE plpgsql
AS $functionx$
DECLARE
    function_schema text := 'admin';
    function_name_str text;
    function_name regprocedure;
    function_sql text;
    custom_value boolean;
    table_name_str text;
BEGIN
    function_name_str := 'prepare_' || table_properties.table_name || '_custom';

    -- Construct the SQL statement for the delete function
    function_sql := format($function$
CREATE FUNCTION %1$I.%2$I()
RETURNS TRIGGER LANGUAGE plpgsql AS $body$
BEGIN
    -- Deactivate all non-custom entries before insertion
    UPDATE %3$I.%4$I
       SET active = false
     WHERE active = true
       AND custom = false;

    RETURN NULL;
END;
$body$;
$function$
, function_schema   -- %1$
, function_name_str -- %2$
, table_properties.schema_name -- %3$
, table_properties.table_name -- %4$
, custom_value      -- %5$
);
    EXECUTE function_sql;

    function_name := format('%I.%I()', function_schema, function_name_str)::regprocedure;
    RAISE NOTICE 'Created prepare function: %', function_name;

    RETURN function_name;
END;
$functionx$
```

```sql
CREATE OR REPLACE FUNCTION admin.generate_code_upsert_function(table_properties admin.batch_api_table_properties, view_type admin.view_type_enum)
 RETURNS regprocedure
 LANGUAGE plpgsql
AS $functionx$
DECLARE
    function_schema text := 'admin';
    function_name_str text;
    function_name regprocedure;
    function_sql text;
    custom_value boolean;
    schema_name_str text := table_properties.schema_name;
    table_name_str text := table_properties.table_name;
    content_columns text := 'name';
    content_values text := 'NEW.name';
    content_update_sets text := 'name = NEW.name';
    unique_columns text[];
BEGIN
    -- Utilize has_description from table_properties
    IF table_properties.has_description THEN
        content_columns := content_columns || ', description';
        content_values := content_values || ', NEW.description';
        content_update_sets := content_update_sets || ', description = NEW.description';
    END IF;

    IF table_properties.has_enabled THEN
        content_columns := content_columns || ', enabled';
        content_values := content_values || ', TRUE';
        content_update_sets := content_update_sets || ', enabled = TRUE';
    END IF;

    function_name_str := 'upsert_' || table_name_str || '_' || view_type::text;

    -- Determine custom value based on view type
    IF view_type = 'system' THEN
        custom_value := false;
    ELSIF view_type = 'custom' THEN
        custom_value := true;
    ELSE
        RAISE EXCEPTION 'Invalid view type: %', view_type;
    END IF;

    unique_columns := admin.get_unique_columns(table_properties);

    -- Construct the SQL statement for the upsert function
function_sql := format($function$
CREATE FUNCTION %1$I.%2$I()
RETURNS TRIGGER LANGUAGE plpgsql AS $body$
DECLARE
    row RECORD;
BEGIN
    INSERT INTO %3$I.%4$I (code, %5$s, custom, updated_at)
    VALUES (NEW.code, %6$s, %7$L, statement_timestamp())
    ON CONFLICT (%9$s) DO UPDATE SET
        %8$s,
        custom = %7$L,
        updated_at = statement_timestamp()
    WHERE %4$I.id = EXCLUDED.id
    RETURNING * INTO row;

    RAISE DEBUG 'UPSERTED %%', to_json(row);

    RETURN NULL;
END;
$body$;
$function$
, function_schema              -- %1$: Function schema name
, function_name_str            -- %2$: Function name
, table_properties.schema_name -- %3$: Schema name for the table
, table_properties.table_name  -- %4$: Table name
, content_columns              -- %5$: Columns to be inserted/updated
, content_values               -- %6$: Values to be inserted
, custom_value                 -- %7$: Boolean indicating system or custom
, content_update_sets          -- %8$: SET clause for the ON CONFLICT update
, array_to_string(unique_columns, ', ') -- %9$: columns to use for conflict detection/resolution
);
    EXECUTE function_sql;

    function_name := format('%I.%I()', function_schema, function_name_str)::regprocedure;
    RAISE NOTICE 'Created code-based upsert function: %', function_name;

    RETURN function_name;
END;
$functionx$
```

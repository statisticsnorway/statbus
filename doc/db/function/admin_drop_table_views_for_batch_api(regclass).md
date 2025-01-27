```sql
CREATE OR REPLACE FUNCTION admin.drop_table_views_for_batch_api(table_name regclass)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    schema_name_str text;
    table_name_str text;
    view_name_ordered text;
    view_name_available text;
    view_name_system text;
    view_name_custom text;
    upsert_function_name_system text;
    upsert_function_name_custom text;
    prepare_function_name_custom text;
BEGIN
    -- Extract schema and table name
    SELECT n.nspname, c.relname INTO schema_name_str, table_name_str
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    WHERE c.oid = table_name;

    -- Construct view and function names
    view_name_custom := schema_name_str || '.' || table_name_str || '_custom';
    view_name_system := schema_name_str || '.' || table_name_str || '_system';
    view_name_available := schema_name_str || '.' || table_name_str || '_available';
    view_name_ordered := schema_name_str || '.' || table_name_str || '_ordered';

    upsert_function_name_system := 'admin.upsert_' || table_name_str || '_system';
    upsert_function_name_custom := 'admin.upsert_' || table_name_str || '_custom';

    prepare_function_name_custom := 'admin.prepare_' || table_name_str || '_custom';

    -- Drop views
    EXECUTE 'DROP VIEW ' || view_name_custom;
    EXECUTE 'DROP VIEW ' || view_name_system;
    EXECUTE 'DROP VIEW ' || view_name_available;
    EXECUTE 'DROP VIEW ' || view_name_ordered;

    -- Drop functions
    EXECUTE 'DROP FUNCTION ' || upsert_function_name_system || '()';
    EXECUTE 'DROP FUNCTION ' || upsert_function_name_custom || '()';

    EXECUTE 'DROP FUNCTION ' || prepare_function_name_custom || '()';

    -- Get unique columns and construct index name using same logic as in generate_active_code_custom_unique_constraint
    DECLARE
        table_properties admin.batch_api_table_properties;
        unique_columns text[];
        index_name text;
    BEGIN
        table_properties := admin.detect_batch_api_table_properties(table_name);
        unique_columns := admin.get_unique_columns(table_properties);
        
        -- Only attempt to drop if we have unique columns
        IF array_length(unique_columns, 1) IS NOT NULL THEN
            index_name := 'ix_' || table_name_str || '_' || array_to_string(unique_columns, '_');
            EXECUTE format('DROP INDEX IF EXISTS %I', index_name);
        END IF;
    END;
END;
$function$
```

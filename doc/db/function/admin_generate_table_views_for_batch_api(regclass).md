```sql
CREATE OR REPLACE FUNCTION admin.generate_table_views_for_batch_api(table_name regclass)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    table_properties admin.batch_api_table_properties;
    view_name_ordered regclass;
    view_name_available regclass;
    view_name_system regclass;
    view_name_custom regclass;
    upsert_function_name_system regprocedure;
    upsert_function_name_custom regprocedure;
    prepare_function_name_custom regprocedure;
    triggers_name_system text[];
    triggers_name_custom text[];
BEGIN
    table_properties := admin.detect_batch_api_table_properties(table_name);

    view_name_ordered := admin.generate_view(table_properties, 'ordered');
    view_name_available := admin.generate_view(table_properties, 'available');
    view_name_system := admin.generate_view(table_properties, 'system');
    view_name_custom := admin.generate_view(table_properties, 'custom');

    PERFORM admin.generate_active_code_custom_unique_constraint(table_properties);

    -- Determine the upsert function names based on table properties
    IF table_properties.has_path THEN
        upsert_function_name_system := admin.generate_path_upsert_function(table_properties, 'system');
        upsert_function_name_custom := admin.generate_path_upsert_function(table_properties, 'custom');
    ELSIF table_properties.has_code THEN
        upsert_function_name_system := admin.generate_code_upsert_function(table_properties, 'system');
        upsert_function_name_custom := admin.generate_code_upsert_function(table_properties, 'custom');
    ELSE
        RAISE EXCEPTION 'Invalid table properties or unsupported table structure for: %', table_properties;
    END IF;

    -- Generate prepare functions
    prepare_function_name_custom := admin.generate_prepare_function_for_custom(table_properties);

    -- Generate view triggers
    triggers_name_system := admin.generate_view_triggers(view_name_system, upsert_function_name_system, NULL);
    triggers_name_custom := admin.generate_view_triggers(view_name_custom, upsert_function_name_custom, prepare_function_name_custom);
END;
$function$
```

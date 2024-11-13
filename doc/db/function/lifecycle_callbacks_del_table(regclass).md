```sql
CREATE OR REPLACE PROCEDURE lifecycle_callbacks.del_table(IN table_name_param regclass)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    trigger_info lifecycle_callbacks.supported_table;
    table_in_use BOOLEAN;
BEGIN
    -- Check if the table is still referenced in registered_callback
    SELECT EXISTS (
        SELECT 1 FROM lifecycle_callbacks.registered_callback
        WHERE table_names @> ARRAY[table_name_param]
    ) INTO table_in_use;

    IF table_in_use THEN
        RAISE EXCEPTION 'Cannot delete triggers for table % because it is still referenced in registered_callback.', table_name_param;
    END IF;

    -- Fetch trigger names from supported_table
    SELECT * INTO trigger_info
    FROM lifecycle_callbacks.supported_table
    WHERE table_name = table_name_param;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Cannot triggers for table % because it is not registered.', table_name_param;
    END IF;

    -- Drop the triggers
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON %s;', trigger_info.after_insert_trigger_name, table_name_param);
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON %s;', trigger_info.after_update_trigger_name, table_name_param);
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON %s;', trigger_info.after_delete_trigger_name, table_name_param);

    -- Delete the table from supported_table
    DELETE FROM lifecycle_callbacks.supported_table
    WHERE table_name = table_name_param;
END;
$procedure$
```

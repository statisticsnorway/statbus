```sql
CREATE OR REPLACE PROCEDURE lifecycle_callbacks.add_table(IN table_name regclass)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    schema_name TEXT;
    table_name_text TEXT;
    after_insert_trigger_name TEXT;
    after_update_trigger_name TEXT;
    after_delete_trigger_name TEXT;
BEGIN
    -- Ensure that the table exists
    IF NOT EXISTS (SELECT 1 FROM pg_class WHERE oid = table_name) THEN
        RAISE EXCEPTION 'Table % does not exist.', table_name;
    END IF;

    -- Extract schema and table name from the table_identifier
    SELECT nspname, relname INTO schema_name, table_name_text
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.oid = table_name;

    -- Define trigger names based on the provided table name
    after_insert_trigger_name := format('%I_lifecycle_callbacks_after_insert', table_name_text);
    after_update_trigger_name := format('%I_lifecycle_callbacks_after_update', table_name_text);
    after_delete_trigger_name := format('%I_lifecycle_callbacks_after_delete', table_name_text);

    -- Insert the table into supported_table with trigger names
    INSERT INTO lifecycle_callbacks.supported_table (
        table_name,
        after_insert_trigger_name,
        after_update_trigger_name,
        after_delete_trigger_name
    )
    VALUES (
        table_name,
        after_insert_trigger_name,
        after_update_trigger_name,
        after_delete_trigger_name
    )
    ON CONFLICT DO NOTHING;

    EXECUTE format('
        CREATE TRIGGER %I
        AFTER INSERT ON %I.%I
        EXECUTE FUNCTION lifecycle_callbacks.cleanup_and_generate();',
        after_insert_trigger_name, schema_name, table_name_text
    );

    EXECUTE format('
        CREATE TRIGGER %I
        AFTER UPDATE ON %I.%I
        EXECUTE FUNCTION lifecycle_callbacks.cleanup_and_generate();',
        after_update_trigger_name, schema_name, table_name_text
    );

    EXECUTE format('
        CREATE TRIGGER %I
        AFTER DELETE ON %I.%I
        EXECUTE FUNCTION lifecycle_callbacks.cleanup_and_generate();',
        after_delete_trigger_name, schema_name, table_name_text
    );

    RAISE NOTICE 'Triggers created for table: %', table_name_text;
END;
$procedure$
```

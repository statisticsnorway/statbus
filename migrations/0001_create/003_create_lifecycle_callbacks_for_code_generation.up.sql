-- =================================================================
-- BEGIN: Callbacks for code generation based on naming conventions.
-- =================================================================
CREATE SCHEMA lifecycle_callbacks;

-- Documentation for lifecycle_callbacks.run_table_lifecycle_callbacks
--
-- This trigger function is designed to manage lifecycle callbacks for tables.
-- It dynamically finds and executes procedures based on registered callbacks,
-- using the generate and cleanup helper procedures for shared code.
--
-- Table Structure:
--
-- 1. supported_table:
--    - Holds the list of tables that are supported by the lifecycle management.
--    - Columns:
--      - table_name: The table's name as regclass.
--      - after_insert_trigger_name: Name of the after insert trigger.
--      - after_update_trigger_name: Name of the after delete trigger.
--      - after_delete_trigger_name: Name of the after insert trigger.
--
-- 2. registered_callback:
--    - Holds the list of lifecycle callbacks registered for tables.
--    - Columns:
--      - label: A unique label for the callback.
--      - priority: An integer representing the priority of the callback.
--      - table_name: Array of tables (regclass) this callback applies to.
--      - generate_procedure: The procedure that generates data for the table.
--      - cleanup_procedure: The procedure that cleans up data for the table.
--
-- Usage:
-- 1. Register a table using `lifecycle_callbacks.add_table(...)`.
-- 2. Register callbacks using `lifecycle_callbacks.add(...)`.
-- 3. Associate this function as a trigger for table lifecycle events.
-- 4. Call `lifecycle_callbacks.generate(table_name)` or `lifecycle_callbacks.cleanup(table_name)` manually if needed.
--
-- Example:
--
-- CALL lifecycle_callbacks.add_table('external_ident_type');
-- CALL lifecycle_callbacks.add(
--     'label_for_concept',
--     ARRAY['public.external_ident_type','public.stat_definition']::regclass[],
--     'lifecycle_callbacks.generate_label_for_concept',
--     'lifecycle_callbacks.cleanup_label_for_concept'
-- );

CREATE TABLE lifecycle_callbacks.supported_table (
    table_name regclass PRIMARY KEY,
    after_insert_trigger_name TEXT,
    after_update_trigger_name TEXT,
    after_delete_trigger_name TEXT
);

CREATE TABLE lifecycle_callbacks.registered_callback (
    label TEXT PRIMARY KEY,
    priority SERIAL NOT NULL,
    table_names regclass[],
    generate_procedure regproc NOT NULL,
    cleanup_procedure regproc NOT NULL
);

CREATE PROCEDURE lifecycle_callbacks.add_table(
    table_name regclass
)
LANGUAGE plpgsql AS $$
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
$$;

CREATE PROCEDURE lifecycle_callbacks.del_table(
    table_name_param regclass
)
LANGUAGE plpgsql AS $$
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
$$;

CREATE PROCEDURE lifecycle_callbacks.add(
    label TEXT,
    table_names regclass[],
    generate_procedure regproc,
    cleanup_procedure regproc
)
LANGUAGE plpgsql AS $$
DECLARE
    missing_tables regclass[];
BEGIN
    IF array_length(table_names, 1) IS NULL THEN
        RAISE EXCEPTION 'table_names must have one entry';
    END IF;

    -- Find any tables in table_names that are not in supported_table
    SELECT ARRAY_AGG(t_name)
    INTO missing_tables
    FROM UNNEST(table_names) AS t_name
    WHERE t_name NOT IN (SELECT table_name FROM lifecycle_callbacks.supported_table);

    IF missing_tables IS NOT NULL THEN
        RAISE EXCEPTION 'One or more tables in % are not supported: %', table_names, missing_tables;
    END IF;

    -- Ensure that the procedures exist
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid = generate_procedure) THEN
        RAISE EXCEPTION 'Generate procedure % does not exist.', generate_procedure;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid = cleanup_procedure) THEN
        RAISE EXCEPTION 'Cleanup procedure % does not exist.', cleanup_procedure;
    END IF;

    -- Insert or update the registered_callback entry
    INSERT INTO lifecycle_callbacks.registered_callback
           (label, table_names, generate_procedure, cleanup_procedure)
    VALUES (label, table_names, generate_procedure, cleanup_procedure)
    ON CONFLICT DO NOTHING;

    -- Check if the record was inserted; if not, raise an exception
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Callback with label % already exists. Cannot overwrite.', label;
    END IF;
END;
$$;

CREATE PROCEDURE lifecycle_callbacks.del(
    label_param TEXT
)
LANGUAGE plpgsql AS $$
DECLARE
    higher_priority_label TEXT;
    rows_deleted INT;
BEGIN
    -- CTE to get the priority of the callback to be deleted
    WITH target_callback AS (
        SELECT priority
        FROM lifecycle_callbacks.registered_callback
        WHERE label = label_param
    )
    -- Check for a higher priority callback
    SELECT label
    INTO higher_priority_label
    FROM lifecycle_callbacks.registered_callback
    WHERE priority > (SELECT priority FROM target_callback)
    ORDER BY priority ASC
    LIMIT 1;

    -- If a higher priority callback exists, raise an error
    IF higher_priority_label IS NOT NULL THEN
        RAISE EXCEPTION 'Cannot delete % because a higher priority callback % still exists.', label_param, higher_priority_label;
    END IF;

    -- Proceed with deletion if no higher priority callback exists
    DELETE FROM lifecycle_callbacks.registered_callback
    WHERE label = label_param;

    -- Get the number of rows affected by the DELETE operation
    GET DIAGNOSTICS rows_deleted = ROW_COUNT;

    -- Provide feedback on the deletion
    IF rows_deleted > 0 THEN
        RAISE NOTICE 'Callback % has been successfully deleted.', label_param;
    ELSE
        RAISE NOTICE 'Callback % was not found and thus not deleted.', label_param;
    END IF;
END;
$$;


CREATE FUNCTION lifecycle_callbacks.cleanup_and_generate()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    proc_names TEXT[] := ARRAY['cleanup', 'generate'];
    proc_name TEXT;
    sql TEXT;
BEGIN
    -- Loop over the array of procedure names
    FOREACH proc_name IN ARRAY proc_names LOOP
        -- Generate the SQL for the current procedure
        sql := format('CALL lifecycle_callbacks.%I(%L)', proc_name, format('%I.%I', TG_TABLE_SCHEMA, TG_TABLE_NAME));

        -- Execute the SQL and handle exceptions
        BEGIN
            EXECUTE sql;
        EXCEPTION
            WHEN OTHERS THEN
                -- Handle any exception by capturing the SQL and error message
                RAISE EXCEPTION 'Error executing % procedure: %, Error details: %', proc_name, sql, SQLERRM;
        END;
    END LOOP;

    -- Return NULL for a statement-level trigger
    RETURN NULL;
END;
$$;


-- Helper procedures for generating and cleaning up specific tables.
CREATE PROCEDURE lifecycle_callbacks.generate(table_name regclass)
LANGUAGE plpgsql AS $$
DECLARE
    callback_procedure regproc;
    sql TEXT;
BEGIN
    -- Loop through each callback procedure directly from the SELECT query
    FOR callback_procedure IN
        SELECT generate_procedure
        FROM lifecycle_callbacks.registered_callback
        WHERE table_names @> ARRAY[table_name]
        ORDER BY priority ASC
    LOOP
        -- Generate the SQL statement for the current procedure
        sql := format('CALL %s();', callback_procedure);

        -- Execute the SQL statement with error handling
        BEGIN
            EXECUTE sql;
        EXCEPTION
            WHEN OTHERS THEN
                -- Handle any exception by capturing the SQL and error message
                RAISE EXCEPTION 'Error executing callback procedure: %, SQL: %, Error details: %',
                                callback_procedure, sql, SQLERRM;
        END;
    END LOOP;
END;
$$;

CREATE PROCEDURE lifecycle_callbacks.cleanup(table_name regclass DEFAULT NULL)
LANGUAGE plpgsql AS $$
DECLARE
    callback_procedure regproc;
    callback_sql TEXT;
BEGIN
    -- Loop through each callback procedure directly from the SELECT query
    FOR callback_procedure IN
        SELECT cleanup_procedure
        FROM lifecycle_callbacks.registered_callback
        WHERE table_name IS NULL OR table_names @> ARRAY[table_name]
        ORDER BY priority DESC
    LOOP
        callback_sql := format('CALL %s();', callback_procedure);
        BEGIN
            -- Attempt to execute the callback procedure
            EXECUTE callback_sql;
        EXCEPTION
            -- Capture any exception that occurs during the call
            WHEN OTHERS THEN
                -- Log the error along with the original call
                RAISE EXCEPTION 'Error executing callback procedure % for %: %', callback_sql, table_name, SQLERRM;
        END;
    END LOOP;
END;
$$;

GRANT USAGE ON SCHEMA lifecycle_callbacks TO authenticated;
GRANT EXECUTE ON FUNCTION lifecycle_callbacks.cleanup_and_generate() TO authenticated;

-- =================================================================
-- END: Callbacks for code generation based on naming conventions.
-- =================================================================
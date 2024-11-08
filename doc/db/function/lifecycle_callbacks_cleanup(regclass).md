```sql
CREATE OR REPLACE PROCEDURE lifecycle_callbacks.cleanup(IN table_name regclass DEFAULT NULL::regclass)
 LANGUAGE plpgsql
AS $procedure$
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
$procedure$
```

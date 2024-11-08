```sql
CREATE OR REPLACE PROCEDURE lifecycle_callbacks.generate(IN table_name regclass)
 LANGUAGE plpgsql
AS $procedure$
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
$procedure$
```

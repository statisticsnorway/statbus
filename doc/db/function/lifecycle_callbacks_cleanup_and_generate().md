```sql
CREATE OR REPLACE FUNCTION lifecycle_callbacks.cleanup_and_generate()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
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
$function$
```

```sql
CREATE OR REPLACE FUNCTION admin.generate_view_triggers(view_name regclass, upsert_function_name regprocedure, prepare_function_name regprocedure)
 RETURNS text[]
 LANGUAGE plpgsql
AS $function$
DECLARE
    view_name_str text;
    upsert_trigger_sql text;
    prepare_trigger_sql text;
    upsert_trigger_name_str text;
    -- There is no type for trigger names, such as regclass/regproc
    upsert_trigger_name text;
    prepare_trigger_name_str text;
    -- There is no type for trigger names, such as regclass/regproc
    prepare_trigger_name text := NULL;
BEGIN
    -- Lookup view_name_str
    SELECT relname INTO view_name_str
    FROM pg_catalog.pg_class
    WHERE oid = view_name;

    upsert_trigger_name_str := 'upsert_' || view_name_str;
    prepare_trigger_name_str := 'prepare_' || view_name_str;

    -- Construct the SQL statement for the upsert trigger
    upsert_trigger_sql := format($$CREATE TRIGGER %I
                                  INSTEAD OF INSERT ON %s
                                  FOR EACH ROW
                                  EXECUTE FUNCTION %s;$$,
                                  upsert_trigger_name_str, view_name::text, upsert_function_name::text);
    EXECUTE upsert_trigger_sql;
    upsert_trigger_name := format('public.%I',upsert_trigger_name_str);
    RAISE NOTICE 'Created upsert trigger: %', upsert_trigger_name;

    IF prepare_function_name IS NOT NULL THEN
      -- Construct the SQL statement for the delete trigger
      prepare_trigger_sql := format($$CREATE TRIGGER %I
                                    BEFORE INSERT ON %s
                                    FOR EACH STATEMENT
                                    EXECUTE FUNCTION %s;$$,
                                    prepare_trigger_name_str, view_name::text, prepare_function_name::text);
      -- Log and execute
      EXECUTE prepare_trigger_sql;
      prepare_trigger_name := format('public.%I',prepare_trigger_name_str);

      RAISE NOTICE 'Created prepare trigger: %', prepare_trigger_name;
    END IF;

    -- Return the regclass identifiers of the created triggers
    RETURN ARRAY[upsert_trigger_name, prepare_trigger_name];
END;
$function$
```

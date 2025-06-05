```sql
CREATE OR REPLACE FUNCTION admin.grant_select_on_all_views()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    view_record record;
BEGIN
    -- Loop through all views in all schemas (except system schemas)
    FOR view_record IN 
        SELECT n.nspname AS schema_name, c.relname AS view_name
        FROM pg_catalog.pg_class c
        JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
        WHERE c.relkind = 'v'
        AND n.nspname NOT IN ('pg_catalog', 'information_schema', 'pg_toast')
    LOOP
        -- Grant SELECT to authenticated
        EXECUTE format('GRANT SELECT ON %I.%I TO authenticated', 
                      view_record.schema_name, view_record.view_name);
        
        RAISE NOTICE 'Granted SELECT on view %.% to authenticated', 
                    view_record.schema_name, view_record.view_name;
    END LOOP;
    
    RAISE NOTICE 'Granted SELECT permissions on all views to authenticated role';
END;
$function$
```

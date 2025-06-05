```sql
CREATE OR REPLACE FUNCTION admin.grant_permissions_on_views()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    view_record record;
BEGIN
    -- Loop through all views in the public schema and grant permissions
    FOR view_record IN 
        SELECT c.relname AS view_name
        FROM pg_catalog.pg_class c
        JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
        WHERE n.nspname = 'public' 
        AND c.relkind = 'v'
    LOOP
        -- Grant SELECT to authenticated, regular_user, and admin_user
        EXECUTE format('GRANT SELECT ON public.%I TO authenticated, regular_user, admin_user', view_record.view_name);
        
        -- Grant INSERT to authenticated, regular_user, and admin_user
        EXECUTE format('GRANT INSERT ON public.%I TO authenticated, regular_user, admin_user', view_record.view_name);
    END LOOP;
    
    RAISE NOTICE 'Granted permissions on all public views to appropriate roles';
END;
$function$
```

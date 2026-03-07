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
        SELECT c.relname AS view_name,
               iv.is_insertable_into = 'YES' AS is_insertable
        FROM pg_catalog.pg_class c
        JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
        LEFT JOIN information_schema.views iv
          ON iv.table_schema = 'public' AND iv.table_name = c.relname
        WHERE n.nspname = 'public'
        AND c.relkind = 'v'
        AND c.relname NOT LIKE '%__for_portion_of_valid'
    LOOP
        -- Grant SELECT to authenticated, regular_user, and admin_user
        EXECUTE format('GRANT SELECT ON public.%I TO authenticated, regular_user, admin_user', view_record.view_name);

        -- Grant INSERT only on insertable views (simple auto-updatable views)
        IF view_record.is_insertable THEN
            EXECUTE format('GRANT INSERT ON public.%I TO authenticated, regular_user, admin_user', view_record.view_name);
        END IF;
    END LOOP;

    RAISE NOTICE 'Granted permissions on all public views to appropriate roles';
END;
$function$
```

```sql
CREATE OR REPLACE FUNCTION admin.verify_relevant_views_have_grant()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    views_without_grants text[];
    view_record record;
    role_name text;
    privilege_name text;
    required_roles text[] := ARRAY['authenticated', 'regular_user', 'admin_user'];
    required_privileges text[] := ARRAY['SELECT', 'INSERT'];
BEGIN
    -- Initialize array to collect views without proper grants
    views_without_grants := ARRAY[]::text[];
    
    -- Get all views in the public schema
    FOR view_record IN 
        SELECT c.relname AS view_name
        FROM pg_catalog.pg_class c
        JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
        WHERE n.nspname = 'public' 
        AND c.relkind = 'v'
        AND c.relname NOT LIKE '%__for_portion_of_valid'
    LOOP
        -- For each view, check privileges for each required role
        FOREACH role_name IN ARRAY required_roles
        LOOP
            -- For each required privilege
            FOREACH privilege_name IN ARRAY required_privileges
            LOOP
                -- Check if the role has the privilege on the view
                IF NOT EXISTS (
                    SELECT 1 
                    FROM pg_catalog.pg_class c
                    JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
                    JOIN pg_catalog.pg_roles r ON r.rolname = role_name
                    WHERE n.nspname = 'public' 
                    AND c.relname = view_record.view_name
                    AND has_table_privilege(r.oid, c.oid, privilege_name)
                ) THEN
                    views_without_grants := array_append(
                        views_without_grants, 
                        format('%s (%s for %s)', view_record.view_name, privilege_name, role_name)
                    );
                END IF;
            END LOOP;
        END LOOP;
    END LOOP;
    
    -- If any views are missing grants, raise an exception
    IF array_length(views_without_grants, 1) > 0 THEN
        RAISE EXCEPTION 'The following views do not have proper grants: %', array_to_string(views_without_grants, ', ');
    END IF;
    
    RAISE NOTICE 'All views in public schema have proper grants for required roles';
END;
$function$
```

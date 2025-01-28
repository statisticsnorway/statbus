```sql
CREATE OR REPLACE FUNCTION admin.verify_all_tables_have_rls()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    tables_without_rls text[];
BEGIN
    SELECT array_agg(c.relname::text)
    INTO tables_without_rls
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
    WHERE n.nspname = 'public'
    AND c.relkind = 'r'
    AND NOT c.relrowsecurity;

    IF tables_without_rls IS NOT NULL THEN
        RAISE EXCEPTION 'The following tables do not have RLS enabled: %', array_to_string(tables_without_rls, ', ');
    END IF;
END;
$function$
```

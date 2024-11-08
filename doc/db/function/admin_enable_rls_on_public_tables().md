```sql
CREATE OR REPLACE FUNCTION admin.enable_rls_on_public_tables()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    table_regclass regclass;
BEGIN
    FOR table_regclass IN
        SELECT c.oid::regclass
        FROM pg_catalog.pg_class c
        JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
        WHERE n.nspname = 'public' AND c.relkind = 'r'
    LOOP
        PERFORM admin.apply_rls_and_policies(table_regclass);
    END LOOP;
END;
$function$
```

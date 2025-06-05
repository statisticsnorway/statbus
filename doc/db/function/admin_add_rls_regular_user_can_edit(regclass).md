```sql
CREATE OR REPLACE FUNCTION admin.add_rls_regular_user_can_edit(table_regclass regclass)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    schema_name_str text;
    table_name_str text;
BEGIN
    SELECT n.nspname, c.relname INTO schema_name_str, table_name_str
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
    WHERE c.oid = table_regclass;

    -- Enable RLS
    EXECUTE format('ALTER TABLE %I.%I ENABLE ROW LEVEL SECURITY', schema_name_str, table_name_str);

    -- Grant permissions to roles
    -- SELECT for authenticated users
    EXECUTE format('GRANT SELECT ON %I.%I TO authenticated', schema_name_str, table_name_str);
    
    -- ALL permissions for regular_user
    EXECUTE format('GRANT ALL ON %I.%I TO regular_user', schema_name_str, table_name_str);
    
    -- ALL permissions for admin_user
    EXECUTE format('GRANT ALL ON %I.%I TO admin_user', schema_name_str, table_name_str);

    -- Base authenticated read policy
    EXECUTE format(
        'CREATE POLICY %s_authenticated_read ON %I.%I FOR SELECT TO authenticated USING (true)',
        table_name_str, schema_name_str, table_name_str
    );

    -- Regular user full access policy - using native role system
    EXECUTE format(
        'CREATE POLICY %s_regular_user_manage ON %I.%I FOR ALL TO regular_user USING (true) WITH CHECK (true)',
        table_name_str, schema_name_str, table_name_str
    );

    -- Admin user full access policy - using native role system
    EXECUTE format(
        'CREATE POLICY %s_admin_user_manage ON %I.%I FOR ALL TO admin_user USING (true) WITH CHECK (true)',
        table_name_str, schema_name_str, table_name_str
    );
END;
$function$
```

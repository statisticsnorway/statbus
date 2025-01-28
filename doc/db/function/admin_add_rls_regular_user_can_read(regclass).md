```sql
CREATE OR REPLACE FUNCTION admin.add_rls_regular_user_can_read(table_regclass regclass)
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

    -- Base authenticated read policy
    EXECUTE format(
        'CREATE POLICY %s_authenticated_read ON %I.%I FOR SELECT TO authenticated USING (true)',
        table_name_str, schema_name_str, table_name_str
    );

    -- Regular user read-only policy
    EXECUTE format(
        'CREATE POLICY %s_regular_user_read ON %I.%I FOR SELECT TO authenticated
         USING (auth.has_statbus_role(auth.uid(), ''regular_user''::public.statbus_role_type))',
        table_name_str, schema_name_str, table_name_str
    );

    -- Super user full access policy
    EXECUTE format(
        'CREATE POLICY %s_super_user_manage ON %I.%I FOR ALL TO authenticated
         USING (auth.has_statbus_role(auth.uid(), ''super_user''::public.statbus_role_type))
         WITH CHECK (auth.has_statbus_role(auth.uid(), ''super_user''::public.statbus_role_type))',
        table_name_str, schema_name_str, table_name_str
    );
END;
$function$
```

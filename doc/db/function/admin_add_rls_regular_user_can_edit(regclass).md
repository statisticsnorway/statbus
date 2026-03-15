```sql
CREATE OR REPLACE FUNCTION admin.add_rls_regular_user_can_edit(table_regclass regclass)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    schema_name_str text;
    table_name_str text;
    has_edit_by_user_id boolean;
    v_with_check text;
BEGIN
    SELECT n.nspname, c.relname INTO schema_name_str, table_name_str
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
    WHERE c.oid = table_regclass;

    -- Check if table has edit_by_user_id column
    SELECT EXISTS(
        SELECT 1 FROM pg_attribute
        WHERE attrelid = table_regclass AND attname = 'edit_by_user_id' AND NOT attisdropped
    ) INTO has_edit_by_user_id;

    -- Regular user WITH CHECK: enforce edit_by_user_id if column exists
    IF has_edit_by_user_id THEN
        v_with_check := '(edit_by_user_id = auth.uid())';
    ELSE
        v_with_check := 'true';
    END IF;

    -- Enable RLS
    EXECUTE format('ALTER TABLE %I.%I ENABLE ROW LEVEL SECURITY', schema_name_str, table_name_str);

    -- Grant permissions to roles
    EXECUTE format('GRANT SELECT ON %I.%I TO authenticated', schema_name_str, table_name_str);
    EXECUTE format('GRANT ALL ON %I.%I TO regular_user', schema_name_str, table_name_str);
    EXECUTE format('GRANT ALL ON %I.%I TO admin_user', schema_name_str, table_name_str);

    -- Base authenticated read policy
    EXECUTE format(
        'CREATE POLICY %I ON %I.%I FOR SELECT TO authenticated USING (true)',
        table_name_str || '_authenticated_read', schema_name_str, table_name_str
    );

    -- Regular user: conditionally enforce edit_by_user_id
    EXECUTE format(
        'CREATE POLICY %I ON %I.%I FOR ALL TO regular_user USING (true) WITH CHECK (%s)',
        table_name_str || '_regular_user_manage', schema_name_str, table_name_str, v_with_check
    );

    -- Admin user full access policy
    EXECUTE format(
        'CREATE POLICY %I ON %I.%I FOR ALL TO admin_user USING (true) WITH CHECK (true)',
        table_name_str || '_admin_user_manage', schema_name_str, table_name_str
    );
END;
$function$
```

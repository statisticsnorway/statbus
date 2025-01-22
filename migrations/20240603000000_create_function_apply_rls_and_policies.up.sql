BEGIN;

CREATE OR REPLACE FUNCTION admin.apply_rls_and_policies(table_regclass regclass)
RETURNS void AS $$
DECLARE
    schema_name_str text;
    table_name_str text;
    has_custom_and_active boolean;
BEGIN
    SELECT n.nspname, c.relname INTO schema_name_str, table_name_str
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
    WHERE c.oid = table_regclass;

    -- Check if table has 'custom' and 'active' columns
    SELECT EXISTS (
        SELECT 1
        FROM pg_attribute
        WHERE attrelid = table_regclass
        AND attname IN ('custom', 'active')
        GROUP BY attrelid
        HAVING COUNT(*) = 2
    ) INTO has_custom_and_active;

    -- Check if RLS is already enabled
    IF NOT EXISTS (
        SELECT 1 FROM pg_tables 
        WHERE schemaname = schema_name_str 
        AND tablename = table_name_str 
        AND rowsecurity = true
    ) THEN
        RAISE NOTICE '%s.%s: Enabling Row Level Security', schema_name_str, table_name_str;
        EXECUTE format('ALTER TABLE %I.%I ENABLE ROW LEVEL SECURITY', schema_name_str, table_name_str);
    END IF;

    -- Check if authenticated read policy exists before creating
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE schemaname = schema_name_str 
        AND tablename = table_name_str 
        AND policyname = table_name_str || '_authenticated_read'
    ) THEN
        RAISE NOTICE '%s.%s: Creating authenticated users read policy', schema_name_str, table_name_str;
        EXECUTE format('CREATE POLICY %s_authenticated_read ON %I.%I FOR SELECT TO authenticated USING (true)', table_name_str, schema_name_str, table_name_str);
    END IF;

    -- The tables with custom and active are managed through views,
    -- where one _system view is used for system updates, and the
    -- _custom view is used for managing custom rows by the super_user.
    IF has_custom_and_active THEN
        IF NOT EXISTS (
            SELECT 1 FROM pg_policies 
            WHERE schemaname = schema_name_str 
            AND tablename = table_name_str 
            AND policyname = table_name_str || '_regular_user_read'
        ) THEN
            RAISE NOTICE '%s.%s: Creating regular_user read policy', schema_name_str, table_name_str;
            EXECUTE format('CREATE POLICY %s_regular_user_read ON %I.%I FOR SELECT TO authenticated USING (auth.has_statbus_role(auth.uid(), ''regular_user''::public.statbus_role_type))', table_name_str, schema_name_str, table_name_str);
        END IF;
    ELSE
        IF NOT EXISTS (
            SELECT 1 FROM pg_policies 
            WHERE schemaname = schema_name_str 
            AND tablename = table_name_str 
            AND policyname = table_name_str || '_regular_user_manage'
        ) THEN
            RAISE NOTICE '%s.%s: Creating regular_user manage policy', schema_name_str, table_name_str;
            EXECUTE format('CREATE POLICY %s_regular_user_manage ON %I.%I FOR ALL TO authenticated USING (auth.has_statbus_role(auth.uid(), ''regular_user''::public.statbus_role_type)) WITH CHECK (auth.has_statbus_role(auth.uid(), ''regular_user''::public.statbus_role_type))', table_name_str, schema_name_str, table_name_str);
        END IF;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE schemaname = schema_name_str 
        AND tablename = table_name_str 
        AND policyname = table_name_str || '_super_user_manage'
    ) THEN
        RAISE NOTICE '%s.%s: Creating super_user manage policy', schema_name_str, table_name_str;
        EXECUTE format('CREATE POLICY %s_super_user_manage ON %I.%I FOR ALL TO authenticated USING (auth.has_statbus_role(auth.uid(), ''super_user''::public.statbus_role_type)) WITH CHECK (auth.has_statbus_role(auth.uid(), ''super_user''::public.statbus_role_type))', table_name_str, schema_name_str, table_name_str);
    END IF;
END;
$$ LANGUAGE plpgsql;

END;

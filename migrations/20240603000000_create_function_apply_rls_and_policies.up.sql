BEGIN;

CREATE OR REPLACE FUNCTION admin.add_rls_regular_user_can_edit(table_regclass regclass)
RETURNS void AS $add_rls_regular_user_can_edit$
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

    -- Regular user full access policy
    EXECUTE format(
        'CREATE POLICY %s_regular_user_manage ON %I.%I FOR ALL TO authenticated
         USING (auth.has_statbus_role(auth.uid(), ''regular_user''::public.statbus_role_type))
         WITH CHECK (auth.has_statbus_role(auth.uid(), ''regular_user''::public.statbus_role_type))',
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
$add_rls_regular_user_can_edit$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION admin.add_rls_regular_user_can_read(table_regclass regclass)
RETURNS void AS $add_rls_regular_user_can_read$
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
$add_rls_regular_user_can_read$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION admin.apply_rls_to_all_tables()
RETURNS void AS $apply_rls_to_all_tables$
BEGIN
    -- To list all tables in public schema, run in psql:
    -- SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename;
    --
    -- ########### add_rls_regular_user_can_read ###########
    PERFORM admin.add_rls_regular_user_can_read('public.activity_category'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.region'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.sector'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.legal_form'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.statbus_user'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.statbus_role'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.activity_category_standard'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.settings'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.activity_category_role'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.country'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.data_source'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.tag'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.relative_period'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.unit_size'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.enterprise_group_type'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.reorg_type'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.foreign_participation'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.enterprise_group_role'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.status'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.external_ident_type'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.person_role'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.region_role'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.stat_definition'::regclass);
    -- Is updated by the statbus worker, using authorized functions.
    PERFORM admin.add_rls_regular_user_can_read('public.timesegments'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.timeline_establishment'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.timeline_legal_unit'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.timeline_enterprise'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.statistical_unit'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.activity_category_used'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.region_used'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.sector_used'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.data_source_used'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.legal_form_used'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.country_used'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.statistical_unit_facet'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.statistical_history'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.statistical_history_facet'::regclass);
    --
    -- ########### add_rls_regular_user_can_edit ###########
    PERFORM admin.add_rls_regular_user_can_edit('public.establishment'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.legal_unit'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.enterprise'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.enterprise_group'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.external_ident'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.activity'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.contact'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.unit_notes'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.tag_for_unit'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.stat_for_unit'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.person_for_unit'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.person'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.location'::regclass);
    --
END;
$apply_rls_to_all_tables$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION admin.verify_all_tables_have_rls()
RETURNS void AS $verify_all_tables_have_rls$
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
$verify_all_tables_have_rls$ LANGUAGE plpgsql;

SET LOCAL client_min_messages TO NOTICE;
SELECT admin.apply_rls_to_all_tables();
SELECT admin.verify_all_tables_have_rls();
SET LOCAL client_min_messages TO INFO;

END;

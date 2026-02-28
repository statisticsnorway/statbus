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

    -- Grant permissions to roles
    -- SELECT for authenticated users
    EXECUTE format('GRANT SELECT ON %I.%I TO authenticated', schema_name_str, table_name_str);
    
    -- ALL permissions for regular_user
    EXECUTE format('GRANT ALL ON %I.%I TO regular_user', schema_name_str, table_name_str);
    
    -- ALL permissions for admin_user
    EXECUTE format('GRANT ALL ON %I.%I TO admin_user', schema_name_str, table_name_str);

    -- Base authenticated read policy
    EXECUTE format(
        'CREATE POLICY %I ON %I.%I FOR SELECT TO authenticated USING (true)',
        table_name_str || '_authenticated_read', schema_name_str, table_name_str
    );

    -- Regular user full access policy - using native role system
    EXECUTE format(
        'CREATE POLICY %I ON %I.%I FOR ALL TO regular_user USING (true) WITH CHECK (true)',
        table_name_str || '_regular_user_manage', schema_name_str, table_name_str
    );

    -- Admin user full access policy - using native role system
    EXECUTE format(
        'CREATE POLICY %I ON %I.%I FOR ALL TO admin_user USING (true) WITH CHECK (true)',
        table_name_str || '_admin_user_manage', schema_name_str, table_name_str
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

    -- Grant permissions to roles
    -- SELECT for authenticated users
    EXECUTE format('GRANT SELECT ON %I.%I TO authenticated', schema_name_str, table_name_str);
    
    -- SELECT for regular_user
    EXECUTE format('GRANT SELECT ON %I.%I TO regular_user', schema_name_str, table_name_str);
    
    -- ALL permissions for admin_user
    EXECUTE format('GRANT ALL ON %I.%I TO admin_user', schema_name_str, table_name_str);

    -- Base authenticated read policy
    EXECUTE format(
        'CREATE POLICY %I ON %I.%I FOR SELECT TO authenticated USING (true)',
        table_name_str || '_authenticated_read', schema_name_str, table_name_str
    );

    -- Regular user read-only policy - using native role system
    EXECUTE format(
        'CREATE POLICY %I ON %I.%I FOR SELECT TO regular_user USING (true)',
        table_name_str || '_regular_user_read', schema_name_str, table_name_str
    );

    -- Admin user full access policy - using native role system
    EXECUTE format(
        'CREATE POLICY %I ON %I.%I FOR ALL TO admin_user USING (true) WITH CHECK (true)',
        table_name_str || '_admin_user_manage', schema_name_str, table_name_str
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
    PERFORM admin.add_rls_regular_user_can_read('public.activity_category_standard'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.settings'::regclass);
    -- We don't need to apply the standard RLS function to activity_category_access
    -- as it has custom policies that only allow admin_user to modify it
    -- PERFORM admin.add_rls_regular_user_can_read('public.activity_category_access'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.country'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.data_source'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.tag'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.relative_period'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.unit_size'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.power_group_type'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.legal_reorg_type'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.legal_rel_type'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.foreign_participation'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.status'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.external_ident_type'::regclass);

    PERFORM admin.add_rls_regular_user_can_read('public.person_role'::regclass);
    -- We don't need to apply the standard RLS function to region_access
    -- as it has custom policies that only allow admin_user to modify it
    -- PERFORM admin.add_rls_regular_user_can_read('public.region_access'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.stat_definition'::regclass);
    -- Is updated by the statbus worker, using authorized functions.
    PERFORM admin.add_rls_regular_user_can_read('public.timepoints'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.timesegments'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.timesegments_years'::regclass);
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
    PERFORM admin.add_rls_regular_user_can_edit('public.image'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.establishment'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.legal_unit'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.enterprise'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.power_group'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.external_ident'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.activity'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.contact'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.unit_notes'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.tag_for_unit'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.stat_for_unit'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.person_for_unit'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.person'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.location'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.legal_relationship'::regclass);
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

-- Create a function to grant permissions on views
CREATE OR REPLACE FUNCTION admin.grant_permissions_on_views()
RETURNS void AS $grant_permissions_on_views$
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
$grant_permissions_on_views$ LANGUAGE plpgsql;

-- Create a function to grant permissions on all views in all schemas
CREATE OR REPLACE FUNCTION admin.grant_select_on_all_views()
RETURNS void AS $grant_select_on_all_views$
DECLARE
    view_record record;
BEGIN
    -- Loop through all views in all schemas (except system schemas)
    -- Excludes sql_saga __for_portion_of_valid views which are INSTEAD OF trigger views
    FOR view_record IN 
        SELECT n.nspname AS schema_name, c.relname AS view_name
        FROM pg_catalog.pg_class c
        JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
        WHERE c.relkind = 'v'
        AND n.nspname NOT IN ('pg_catalog', 'information_schema', 'pg_toast')
        AND c.relname NOT LIKE '%__for_portion_of_valid'
    LOOP
        -- Grant SELECT to authenticated
        EXECUTE format('GRANT SELECT ON %I.%I TO authenticated', 
                      view_record.schema_name, view_record.view_name);
        
        RAISE NOTICE 'Granted SELECT on view %.% to authenticated', 
                    view_record.schema_name, view_record.view_name;
    END LOOP;
    
    RAISE NOTICE 'Granted SELECT permissions on all views to authenticated role';
END;
$grant_select_on_all_views$ LANGUAGE plpgsql;

-- Function to verify that relevant views have the necessary grants
-- All views need SELECT; only insertable views also need INSERT.
CREATE OR REPLACE FUNCTION admin.verify_relevant_views_have_grant()
RETURNS void AS $verify_relevant_views_have_grant$
DECLARE
    views_without_grants text[];
    view_record record;
    role_name text;
    privilege_name text;
    required_roles text[] := ARRAY['authenticated', 'regular_user', 'admin_user'];
    required_privileges text[];
BEGIN
    -- Initialize array to collect views without proper grants
    views_without_grants := ARRAY[]::text[];

    -- Get all views in the public schema with insertability info
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
        -- Determine required privileges per view
        IF view_record.is_insertable THEN
            required_privileges := ARRAY['SELECT', 'INSERT'];
        ELSE
            required_privileges := ARRAY['SELECT'];
        END IF;

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
$verify_relevant_views_have_grant$ LANGUAGE plpgsql;

SET LOCAL client_min_messages TO NOTICE;
SELECT admin.apply_rls_to_all_tables();
SELECT admin.verify_all_tables_have_rls();
SELECT admin.grant_permissions_on_views();
SELECT admin.grant_select_on_all_views();
SELECT admin.verify_relevant_views_have_grant();
SET LOCAL client_min_messages TO INFO;

END;

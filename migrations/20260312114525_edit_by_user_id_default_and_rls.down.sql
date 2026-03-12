BEGIN;

-- Reverse Migration F: Remove edit_by_user_id DEFAULT and RLS enforcement

-- ============================================================================
-- 1. Remove DEFAULT auth.uid() from edit_by_user_id
-- ============================================================================
DO $do$
DECLARE
    v_tables TEXT[] := ARRAY[
        'activity', 'contact', 'enterprise', 'establishment', 'external_ident',
        'legal_relationship', 'legal_unit', 'location', 'person', 'person_for_unit',
        'power_group', 'power_root', 'stat_for_unit', 'tag_for_unit', 'unit_notes'
    ];
    v_table TEXT;
BEGIN
    FOREACH v_table IN ARRAY v_tables LOOP
        EXECUTE format(
            'ALTER TABLE public.%I ALTER COLUMN edit_by_user_id DROP DEFAULT',
            v_table
        );
    END LOOP;
END;
$do$;

-- ============================================================================
-- 2. Restore permissive regular_user_manage policies (WITH CHECK (true))
-- ============================================================================
DO $do$
DECLARE
    v_tables TEXT[] := ARRAY[
        'activity', 'contact', 'enterprise', 'establishment', 'external_ident',
        'legal_relationship', 'legal_unit', 'location', 'person', 'person_for_unit',
        'power_group', 'power_root', 'stat_for_unit', 'tag_for_unit', 'unit_notes'
    ];
    v_table TEXT;
BEGIN
    FOREACH v_table IN ARRAY v_tables LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I',
            v_table || '_regular_user_manage', v_table);
        EXECUTE format(
            'CREATE POLICY %I ON public.%I FOR ALL TO regular_user USING (true) WITH CHECK (true)',
            v_table || '_regular_user_manage', v_table);
    END LOOP;
END;
$do$;

-- ============================================================================
-- 3. Restore original add_rls_regular_user_can_edit (no edit_by_user_id check)
-- ============================================================================
CREATE OR REPLACE FUNCTION admin.add_rls_regular_user_can_edit(table_regclass regclass)
 RETURNS void
 LANGUAGE plpgsql
AS $add_rls_regular_user_can_edit$
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
    EXECUTE format('GRANT SELECT ON %I.%I TO authenticated', schema_name_str, table_name_str);
    EXECUTE format('GRANT ALL ON %I.%I TO regular_user', schema_name_str, table_name_str);
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
$add_rls_regular_user_can_edit$;

END;

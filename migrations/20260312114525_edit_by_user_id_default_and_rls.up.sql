BEGIN;

-- ============================================================================
-- Migration F: edit_by_user_id DEFAULT auth.uid() + RLS enforcement
--
-- Currently no table enforces that edit_by_user_id matches the authenticated
-- user. All regular_user_manage RLS policies have WITH CHECK (true).
-- This migration:
--   1. Sets DEFAULT auth.uid() on all 15 editable tables
--   2. Updates add_rls_regular_user_can_edit() to auto-detect edit_by_user_id
--   3. Re-applies regular_user_manage policies with the check
-- ============================================================================

-- ============================================================================
-- 1. Set DEFAULT auth.uid() on edit_by_user_id for all editable tables
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
            'ALTER TABLE public.%I ALTER COLUMN edit_by_user_id SET DEFAULT auth.uid()',
            v_table
        );
    END LOOP;
END;
$do$;

-- ============================================================================
-- 2. Update add_rls_regular_user_can_edit() to enforce edit_by_user_id
-- ============================================================================
CREATE OR REPLACE FUNCTION admin.add_rls_regular_user_can_edit(table_regclass regclass)
 RETURNS void
 LANGUAGE plpgsql
AS $add_rls_regular_user_can_edit$
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
$add_rls_regular_user_can_edit$;

-- ============================================================================
-- 3. Re-apply regular_user_manage policies with edit_by_user_id check
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
        -- Drop old permissive policy
        EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I',
            v_table || '_regular_user_manage', v_table);
        -- Re-create with edit_by_user_id check
        EXECUTE format(
            'CREATE POLICY %I ON public.%I FOR ALL TO regular_user USING (true) WITH CHECK (edit_by_user_id = auth.uid())',
            v_table || '_regular_user_manage', v_table);
    END LOOP;
END;
$do$;

END;

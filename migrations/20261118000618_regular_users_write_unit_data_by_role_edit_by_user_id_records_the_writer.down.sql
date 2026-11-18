BEGIN;

-- Restores 20260312114525's writer check on the regular_user_manage policies
-- and the function as it stood before 20261118000618.

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

COMMENT ON FUNCTION admin.add_rls_regular_user_can_edit(regclass) IS NULL;

-- Every regular_user_manage policy on a table with edit_by_user_id gets the
-- writer check back, as 20260312114525 and import_job_generate set it.
DO $do$
DECLARE
    v_policy record;
BEGIN
    FOR v_policy IN
        SELECT n.nspname AS schema_name, c.relname AS table_name, p.polname AS policy_name
          FROM pg_catalog.pg_policy p
          JOIN pg_catalog.pg_class c ON c.oid = p.polrelid
          JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
         WHERE p.polname = c.relname || '_regular_user_manage'
           AND pg_catalog.pg_get_expr(p.polwithcheck, p.polrelid) = 'true'
           AND EXISTS (SELECT 1 FROM pg_catalog.pg_attribute a
                        WHERE a.attrelid = c.oid AND a.attname = 'edit_by_user_id' AND NOT a.attisdropped)
         ORDER BY n.nspname, c.relname
    LOOP
        EXECUTE format('ALTER POLICY %I ON %I.%I WITH CHECK (edit_by_user_id = auth.uid())',
            v_policy.policy_name, v_policy.schema_name, v_policy.table_name);
    END LOOP;
END;
$do$;

DO $do$
DECLARE
    v_table text;
BEGIN
    FOREACH v_table IN ARRAY ARRAY[
        'activity', 'contact', 'enterprise', 'establishment', 'external_ident',
        'legal_relationship', 'legal_unit', 'person', 'person_for_unit',
        'power_group', 'power_root', 'stat_for_unit', 'tag_for_unit', 'unit_notes'
    ] LOOP
        EXECUTE format('COMMENT ON COLUMN public.%I.edit_by_user_id IS NULL', v_table);
    END LOOP;
END;
$do$;
COMMENT ON COLUMN public.location.edit_by_user_id IS 'User who last edited this record.';

COMMENT ON FUNCTION auth.uid() IS
'Returns the current user''s integer ID by looking up current_user in auth.user.
Works identically for both access paths:
  - PostgREST: jwt_switch_role() does SET LOCAL ROLE <email>, so current_user = email.
  - Direct psql: user connects as their email role, so current_user = email.
  - Worker (postgres): returns NULL (no auth.user row), but superuser bypasses RLS.
Used as DEFAULT for edit_by_user_id columns and in RLS WITH CHECK policies.';

END;

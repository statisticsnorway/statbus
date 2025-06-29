BEGIN;

DROP FUNCTION admin.verify_all_tables_have_rls();
DROP FUNCTION admin.apply_rls_to_all_tables();
DROP FUNCTION admin.add_rls_regular_user_can_read(regclass);
DROP FUNCTION admin.add_rls_regular_user_can_edit(regclass);

CREATE OR REPLACE FUNCTION admin.drop_all_rls_policies()
RETURNS void AS $$
DECLARE
    policy record;
BEGIN
    FOR policy IN
        SELECT schemaname, tablename, policyname
        FROM pg_policies
        WHERE policyname LIKE '%_authenticated_read'
           OR policyname LIKE '%_regular_user_read'
           OR policyname LIKE '%_regular_user_manage'
           OR policyname LIKE '%_admin_user_manage'
    LOOP
        RAISE NOTICE 'Dropping policy % on %.%',
            policy.policyname,
            policy.schemaname,
            policy.tablename;
        EXECUTE format('DROP POLICY IF EXISTS %I ON %I.%I',
                      policy.policyname,
                      policy.schemaname,
                      policy.tablename);

        -- Also disable RLS on the table
        EXECUTE format('ALTER TABLE %I.%I DISABLE ROW LEVEL SECURITY',
                      policy.schemaname,
                      policy.tablename);
    END LOOP;
END;
$$ LANGUAGE plpgsql;

SELECT admin.drop_all_rls_policies();
DROP FUNCTION admin.drop_all_rls_policies();

END;

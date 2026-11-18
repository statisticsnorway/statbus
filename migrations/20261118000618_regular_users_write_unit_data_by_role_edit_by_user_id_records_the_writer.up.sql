BEGIN;

-- Regular users write unit data by their role; edit_by_user_id records who
-- last wrote a row's values. Migration 20260312114525 made every
-- regular_user_manage policy require edit_by_user_id = auth.uid() on each row
-- a regular user's statement writes. A partial-period edit or removal through
-- a for_portion_of view makes sql_saga write the untouched pieces too, carrying
-- their original writer, so that check refused a regular user's edit of part
-- of a record another user wrote. Who may write is decided by login, role and
-- grants (restricted_user's own policies still limit by region and activity
-- category); the writer is set by the app, imports and DEFAULT auth.uid().

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

    -- Regular user: writes every row of the table; edit_by_user_id is the
    -- writer's record, not a condition (see its column comment).
    EXECUTE format(
        'CREATE POLICY %I ON %I.%I FOR ALL TO regular_user USING (true) WITH CHECK (true)',
        table_name_str || '_regular_user_manage', schema_name_str, table_name_str
    );

    -- Admin user full access policy
    EXECUTE format(
        'CREATE POLICY %I ON %I.%I FOR ALL TO admin_user USING (true) WITH CHECK (true)',
        table_name_str || '_admin_user_manage', schema_name_str, table_name_str
    );
END;
$add_rls_regular_user_can_edit$;

COMMENT ON FUNCTION admin.add_rls_regular_user_can_edit(regclass) IS
'Makes a table readable by every signed-in user and writable by regular and admin users, by role alone. A table''s edit_by_user_id records who last wrote a row''s values and is no part of the permission.';

-- The policies already in place: the editable tables and every import data
-- table generated since 20260312114525 carry the writer check.
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
           AND pg_catalog.pg_get_expr(p.polwithcheck, p.polrelid) = '(edit_by_user_id = auth.uid())'
         ORDER BY n.nspname, c.relname
    LOOP
        EXECUTE format('ALTER POLICY %I ON %I.%I WITH CHECK (true)',
            v_policy.policy_name, v_policy.schema_name, v_policy.table_name);
    END LOOP;
END;
$do$;

-- The meaning of edit_by_user_id, at its definition on each editable table.
DO $do$
DECLARE
    v_table text;
BEGIN
    FOREACH v_table IN ARRAY ARRAY[
        'activity', 'contact', 'enterprise', 'establishment', 'external_ident',
        'legal_relationship', 'legal_unit', 'location', 'person', 'person_for_unit',
        'power_group', 'power_root', 'stat_for_unit', 'tag_for_unit', 'unit_notes'
    ] LOOP
        EXECUTE format($comment$COMMENT ON COLUMN public.%I.edit_by_user_id IS %L$comment$, v_table,
            'Who last wrote this row''s values, shown as "Last edited by". Set by the edit forms and imports, or by DEFAULT auth.uid(). A record of the writer, not a permission: who may write is decided by role. On temporal tables sql_saga carries it as an ephemeral column, so a piece a partial edit leaves untouched keeps its own writer.');
    END LOOP;
END;
$do$;

COMMENT ON FUNCTION auth.uid() IS
'Returns the current user''s integer ID by looking up current_user in auth.user.
Works identically for both access paths:
  - PostgREST: jwt_switch_role() does SET LOCAL ROLE <email>, so current_user = email.
  - Direct psql: user connects as their email role, so current_user = email.
  - Worker (postgres): returns NULL (no auth.user row), but superuser bypasses RLS.
Used as DEFAULT for edit_by_user_id columns.';

END;

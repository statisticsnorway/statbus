-- STATBUS-481 B: every sql_saga for-portion-of view carries EXACTLY its base
-- table's ACL, and an unrelated REVOKE succeeds again.
--
-- WHY. sql_saga's GRANT propagation (sql_saga.health_checks) tests
-- has_table_privilege(grantee, view, privilege), which is inheritance-aware:
-- admin_user inherits regular_user, so a GRANT to admin_user on a base table is
-- never copied to its __for_portion_of_valid view. The same trigger's REVOKE
-- check demands the view's ACL contain every (grantee, privilege) entry of the
-- table's ACL exactly. So the stored state fails sql_saga's own check, and since
-- the check runs on EVERY GRANT/REVOKE in the database, any REVOKE anywhere
-- raised "cannot revoke INSERT directly from activity__for_portion_of_valid"
-- (observed live on master 2026-10-08 for REVOKE ALL ON FUNCTION
-- public.upgrade_schedule(text, boolean) FROM PUBLIC).
--
-- WHAT. For each sql_saga.updatable_view, grant on the view every (grantee,
-- privilege) entry the base table has and the view lacks. Derived from the
-- live ACLs, never from a hard-coded grantee list, so the result depends only
-- on the tables' grants (replay-position independent, STATBUS-312), and a new
-- managed table or grantee is covered automatically. Grants only ADD to the
-- view; nothing is revoked. The GRANTs are issued with
-- session_replication_role = replica for this transaction so the event trigger
-- does not re-check the very state being repaired (it is the trigger's REVOKE
-- branch that rejects; GRANT propagation would be a no-op here).
BEGIN;

SET LOCAL session_replication_role = replica;

DO $repair_for_portion_of_view_acls$
DECLARE
    _missing record;
BEGIN
    FOR _missing IN
        SELECT format('%I.%I', v.view_schema, v.view_name) AS view_ident,
               a.privilege_type,
               CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE quote_ident(r.rolname) END AS grantee_ident
        FROM sql_saga.updatable_view AS v
        JOIN pg_catalog.pg_class AS t
          ON t.relname = v.table_name
         AND t.relnamespace = (SELECT oid FROM pg_catalog.pg_namespace WHERE nspname = v.table_schema)
        JOIN pg_catalog.pg_class AS vt
          ON vt.relname = v.view_name
         AND vt.relnamespace = (SELECT oid FROM pg_catalog.pg_namespace WHERE nspname = v.view_schema)
        CROSS JOIN LATERAL aclexplode(COALESCE(t.relacl, acldefault('r', t.relowner))) AS a
        LEFT JOIN pg_catalog.pg_roles AS r ON r.oid = a.grantee
        WHERE NOT EXISTS (
            SELECT FROM aclexplode(COALESCE(vt.relacl, acldefault('r', vt.relowner))) AS b
            WHERE b.grantee = a.grantee AND b.privilege_type = a.privilege_type)
        ORDER BY 1, 3, 2
    LOOP
        EXECUTE format('GRANT %s ON TABLE %s TO %s',
                       _missing.privilege_type, _missing.view_ident, _missing.grantee_ident);
    END LOOP;
END;
$repair_for_portion_of_view_acls$;

END;

-- STATBUS-481 B: sql_saga for-portion-of views carry exactly their base
-- table's ACL, so sql_saga's REVOKE health check accepts the database's own
-- state and an unrelated REVOKE succeeds.
--
-- Both checks are DERIVED from sql_saga.updatable_view, never from a list of
-- tables or grantees, so a new managed table or a new grantee is covered.
BEGIN;

\i test/setup.sql

\echo "Test 352 (STATBUS-481 B): for-portion-of view ACLs equal their table ACLs"

\echo
\echo "352.1 every managed view is checked (a derived set, never an enumerated one)"
SELECT count(*) AS managed_for_portion_of_views FROM sql_saga.updatable_view;

\echo
\echo "352.2 (grantee, privilege) entries a base table has that its view lacks: expect none"
SELECT v.view_name,
       COALESCE(r.rolname, 'PUBLIC') AS grantee,
       a.privilege_type
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
ORDER BY 1, 2, 3;

\echo
\echo "352.3 an unrelated REVOKE is accepted by sql_saga's health check (failed live on master before 481 B)"
SAVEPOINT unrelated_revoke;
\set ON_ERROR_STOP off
REVOKE ALL ON FUNCTION public.upgrade_schedule(text, boolean) FROM PUBLIC;
\set ON_ERROR_STOP on
ROLLBACK TO SAVEPOINT unrelated_revoke;

\echo
\echo "352.4 the health check is still active: a REVOKE that really breaks a view's ACL is still refused"
SAVEPOINT breaking_revoke;
\set ON_ERROR_STOP off
REVOKE INSERT ON TABLE public.activity__for_portion_of_valid FROM regular_user;
\set ON_ERROR_STOP on
ROLLBACK TO SAVEPOINT breaking_revoke;

\echo
\echo "352.5 event triggers enabled / total"
SELECT count(*) FILTER (WHERE evtenabled <> 'D') AS enabled, count(*) AS total FROM pg_event_trigger;

ROLLBACK;

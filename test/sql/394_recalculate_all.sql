-- Command palette "Recalculate all": public.recalculate_all() schedules the
-- same full recalculation migrations schedule (every statistical unit over all
-- time, then every report), and only an administrator may call it.

\i test/setup.sql

BEGIN;

\echo === The function is SECURITY DEFINER and executable only by admin_user ===
SELECT p.prosecdef AS security_definer,
       has_function_privilege('admin_user', p.oid, 'EXECUTE') AS admin_user,
       has_function_privilege('regular_user', p.oid, 'EXECUTE') AS regular_user,
       has_function_privilege('restricted_user', p.oid, 'EXECUTE') AS restricted_user,
       has_function_privilege('external_user', p.oid, 'EXECUTE') AS external_user,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated,
       has_function_privilege('anon', p.oid, 'EXECUTE') AS anon
  FROM pg_proc p
 WHERE p.oid = 'public.recalculate_all()'::regprocedure;

\echo
\echo === An empty database schedules nothing ===
SAVEPOINT empty;
CALL test.set_user_from_email('test.admin@statbus.org');
SELECT public.recalculate_all() IS NULL AS nothing_scheduled;
SET LOCAL ROLE postgres;
SELECT count(*) AS collect_changes_tasks FROM worker.tasks WHERE command = 'collect_changes';
ROLLBACK TO SAVEPOINT empty;

\echo
\echo === An admin schedules a full recalculation of every unit and period ===
SAVEPOINT admin;
SET LOCAL ROLE postgres;
INSERT INTO public.enterprise (short_name, edit_by_user_id, edit_at)
VALUES ('Recalc fixture',
        (SELECT id FROM auth."user" WHERE email = 'test.admin@statbus.org'),
        now());
DELETE FROM worker.tasks WHERE command = 'collect_changes';
CALL test.set_user_from_email('test.admin@statbus.org');
SELECT public.recalculate_all() IS NOT NULL AS scheduled;
SET LOCAL ROLE postgres;
SELECT command, state,
       payload->'establishment_id_ranges' AS establishment_id_ranges,
       payload->'legal_unit_id_ranges' AS legal_unit_id_ranges,
       payload->'enterprise_id_ranges' AS enterprise_id_ranges,
       payload->'power_group_id_ranges' AS power_group_id_ranges,
       payload->>'valid_ranges' AS valid_ranges
  FROM worker.tasks WHERE command = 'collect_changes';
ROLLBACK TO SAVEPOINT admin;

\echo
\echo === A regular user is refused by the database ===
SAVEPOINT regular;
\set ON_ERROR_STOP off
CALL test.set_user_from_email('test.regular@statbus.org');
SELECT public.recalculate_all();
\set ON_ERROR_STOP on
ROLLBACK TO SAVEPOINT regular;

ROLLBACK;

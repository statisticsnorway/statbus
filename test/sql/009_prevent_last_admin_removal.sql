-- Verifies the BEFORE UPDATE / DELETE trigger on auth.user that prevents
-- removal of the last active admin (statbus_role 'admin_user' AND
-- deleted_at IS NULL).
--
-- Removal paths exercised:
--   B1. demote: UPDATE … SET statbus_role = '<not admin>'
--   B2. soft-delete: UPDATE … SET deleted_at = now()
--   B3. hard-delete: DELETE FROM auth.user
--   B4. combined demote + soft-delete in one UPDATE
--
-- Sanity scenarios (must succeed):
--   A. with multiple admins, demoting one is allowed
--   C. same-transaction swap (promote regular first, then demote old admin)
--   D. unrelated UPDATE (display_name) on the last admin
--   E. re-activating a soft-deleted admin (deleted_at -> NULL)

BEGIN;

\i test/setup.sql

\echo === Initial: count of active admins ===
SELECT COUNT(*) AS active_admins
  FROM auth."user"
 WHERE statbus_role = 'admin_user' AND deleted_at IS NULL;

\echo
\echo === SCENARIO A: with multiple admins, demoting one is allowed ===
SAVEPOINT a;
UPDATE auth."user" SET statbus_role = 'regular_user'
 WHERE email = 'test.admin@statbus.org'
RETURNING email, statbus_role;
ROLLBACK TO SAVEPOINT a;

\echo
\echo === Collapse to a single active admin (test.admin@statbus.org) ===
DELETE FROM auth."user"
 WHERE email IN ('jorgen@veridit.no', 'erik.soberg@ssb.no', 'hhz@ssb.no');
SELECT email, statbus_role, (deleted_at IS NULL) AS active
  FROM auth."user"
 WHERE statbus_role = 'admin_user'
 ORDER BY email;

\echo
\echo --- B1: demote the last admin (UPDATE statbus_role) is blocked ---
SAVEPOINT b1;
\set ON_ERROR_STOP off
UPDATE auth."user" SET statbus_role = 'regular_user'
 WHERE email = 'test.admin@statbus.org';
\set ON_ERROR_STOP on
ROLLBACK TO SAVEPOINT b1;

\echo
\echo --- B2: soft-delete the last admin (UPDATE deleted_at) is blocked ---
SAVEPOINT b2;
\set ON_ERROR_STOP off
UPDATE auth."user" SET deleted_at = '2026-01-01 00:00:00+00'
 WHERE email = 'test.admin@statbus.org';
\set ON_ERROR_STOP on
ROLLBACK TO SAVEPOINT b2;

\echo
\echo --- B3: hard-delete the last admin (DELETE) is blocked ---
SAVEPOINT b3;
\set ON_ERROR_STOP off
DELETE FROM auth."user" WHERE email = 'test.admin@statbus.org';
\set ON_ERROR_STOP on
ROLLBACK TO SAVEPOINT b3;

\echo
\echo --- B4: combined demote + soft-delete in one UPDATE is blocked ---
SAVEPOINT b4;
\set ON_ERROR_STOP off
UPDATE auth."user" SET statbus_role = 'regular_user', deleted_at = '2026-01-01 00:00:00+00'
 WHERE email = 'test.admin@statbus.org';
\set ON_ERROR_STOP on
ROLLBACK TO SAVEPOINT b4;

\echo
\echo === SCENARIO C: same-tx swap (promote regular first, then demote old admin) ===
SAVEPOINT c;
UPDATE auth."user" SET statbus_role = 'admin_user'
 WHERE email = 'test.regular@statbus.org'
RETURNING email, statbus_role;
SELECT email, statbus_role
  FROM auth."user"
 WHERE statbus_role = 'admin_user' AND deleted_at IS NULL
 ORDER BY email;
UPDATE auth."user" SET statbus_role = 'regular_user'
 WHERE email = 'test.admin@statbus.org'
RETURNING email, statbus_role;
SELECT email, statbus_role
  FROM auth."user"
 WHERE statbus_role = 'admin_user' AND deleted_at IS NULL
 ORDER BY email;
ROLLBACK TO SAVEPOINT c;

\echo
\echo === SCENARIO D: unrelated UPDATE (display_name) on the last admin is allowed ===
SAVEPOINT d;
UPDATE auth."user" SET display_name = 'Updated Display'
 WHERE email = 'test.admin@statbus.org'
RETURNING email, display_name;
ROLLBACK TO SAVEPOINT d;

\echo
\echo === SCENARIO E: re-activating a soft-deleted admin (deleted_at -> NULL) is allowed ===
-- First create a second admin and soft-delete them while the first remains.
SAVEPOINT e;
UPDATE auth."user" SET statbus_role = 'admin_user'
 WHERE email = 'test.regular@statbus.org';
UPDATE auth."user" SET deleted_at = '2026-01-01 00:00:00+00'
 WHERE email = 'test.regular@statbus.org';
SELECT email, statbus_role, (deleted_at IS NULL) AS active
  FROM auth."user"
 WHERE email IN ('test.admin@statbus.org', 'test.regular@statbus.org')
 ORDER BY email;
-- Re-activate the soft-deleted admin: deleted_at -> NULL
UPDATE auth."user" SET deleted_at = NULL
 WHERE email = 'test.regular@statbus.org'
RETURNING email, statbus_role, (deleted_at IS NULL) AS active;
ROLLBACK TO SAVEPOINT e;

ROLLBACK;

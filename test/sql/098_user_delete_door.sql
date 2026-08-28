-- STATBUS-309: the user-deletion door, and the three layers that guard it.
--
-- WHY THIS TEST EXISTS. The database already refused every case the product
-- cared about — except the ones nobody had asked it about. deleted_at, the
-- USER_DELETED login refusal and the admin triggers were all built; no function
-- set deleted_at, so the rules had never been exercised through a door. This
-- test is what makes "the triggers are the single source of the rules" a
-- checked statement rather than a hopeful one.
--
-- THE THREE LAYERS, each asserted separately, because each fails differently:
--   1. RLS (admin_all_access) decides WHO may touch another user's row.
--   2. auth.prevent_self_soft_delete refuses a caller removing THEMSELVES.
--   3. auth.prevent_removal_of_last_admin holds the floor: the last active
--      admin cannot be removed by anyone.
--
-- AND ONE PRECONDITION, ASSERTED RATHER THAN ASSUMED (architect ruling). The
-- role-hierarchy arm of this feature is VACUOUS today: only admins can modify
-- other users, and admin is the top role, so "a caller removing someone above
-- them" cannot arise. That vacuity is a property of the CURRENT grants, not a
-- law. Scenario D asserts the precondition itself, so if any role ever gains
-- user-modification rights this test fails and points at the decision instead
-- of letting a silently-unguarded path open.

\i test/setup.sql

-- OWN TRANSACTION, REQUIRED. pg_regress does NOT wrap each test file in one —
-- the runner's "BEGIN/ROLLBACK isolation" line refers to cloned-template
-- isolation, not to transaction wrapping (.claude/rules/testing.md). Without
-- this, every SAVEPOINT below fails with "SAVEPOINT can only be used in
-- transaction blocks" and, under ON_ERROR_STOP, psql exits and truncates the
-- output file — which is exactly what this test's first run did. Sibling 009
-- carries the same pair for the same reason.
BEGIN;

\echo === Baseline: the door exists and is SECURITY INVOKER ===
-- INVOKER is load-bearing, not stylistic: RLS on auth."user" is enabled but NOT
-- forced, so a SECURITY DEFINER function would run as the owner and bypass
-- admin_all_access entirely — leaving a regular-user target guarded by nothing,
-- since check_role_permission only fires when statbus_role changes and
-- prevent_removal_of_last_admin only engages for admin targets.
SELECT p.proname, p.prosecdef AS security_definer
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname IN ('user_delete', 'user_restore')
 ORDER BY p.proname;

\echo
\echo === SCENARIO A: an admin deletes a regular user, and login then refuses ===
SAVEPOINT a;
CALL test.set_user_from_email('test.admin@statbus.org');
SELECT id, email FROM public.user_delete(
    (SELECT id FROM auth."user" WHERE email = 'test.regular@statbus.org'));
SELECT email, (deleted_at IS NOT NULL) AS deleted
  FROM auth."user" WHERE email = 'test.regular@statbus.org';
-- The pre-existing refusal now has a way to be reached.
SET LOCAL ROLE postgres;
SELECT (public.login('test.regular@statbus.org', 'Regular#123!')).error_code AS login_error;
ROLLBACK TO SAVEPOINT a;

\echo
\echo === SCENARIO B: self-delete is refused — for a REGULAR user ===
-- The case that had no rule before this ticket. prevent_removal_of_last_admin
-- covers self-removal only for admins, because that refusal lives inside the
-- last-admin rule and never engages for a non-admin target.
SAVEPOINT b;
\set ON_ERROR_STOP off
CALL test.set_user_from_email('test.regular@statbus.org');
SELECT public.user_delete((SELECT id FROM auth."user" WHERE email = 'test.regular@statbus.org'));
\set ON_ERROR_STOP on
ROLLBACK TO SAVEPOINT b;

\echo
\echo === SCENARIO C: self-delete is refused — for an ADMIN ===
-- Same rule, reached through the older sibling: prevent_removal_of_last_admin
-- fires first (trigger order is by name) and refuses with its own admin-specific
-- wording. Asserted so the difference in message is a recorded fact rather than
-- a surprise to whoever reads the two side by side.
SAVEPOINT c;
\set ON_ERROR_STOP off
CALL test.set_user_from_email('test.admin@statbus.org');
SELECT public.user_delete((SELECT id FROM auth."user" WHERE email = 'test.admin@statbus.org'));
\set ON_ERROR_STOP on
ROLLBACK TO SAVEPOINT c;

\echo
\echo === SCENARIO D: THE VACUITY PRECONDITION — a non-admin cannot touch another user ===
-- This is the assertion that keeps the un-built hierarchy arm honest. Today a
-- regular user simply has no route to another user's row: admin_all_access is
-- the only policy granting write access to rows that are not your own. If that
-- ever changes, this scenario fails — and the failure is the signal that the
-- hierarchy rule now needs building, rather than a quietly unguarded path.
SAVEPOINT d;
CALL test.set_user_from_email('test.regular@statbus.org');
-- Not an error: RLS makes the row invisible, so the UPDATE matches nothing.
-- Asserting the COUNT is what distinguishes "refused" from "silently did it".
SELECT count(*) AS rows_a_regular_user_can_modify
  FROM auth."user"
 WHERE email = 'test.admin@statbus.org';
SELECT id AS deleted_id FROM public.user_delete(
    (SELECT id FROM auth."user" WHERE email = 'test.admin@statbus.org'));
SET LOCAL ROLE postgres;
SELECT email, (deleted_at IS NULL) AS still_active
  FROM auth."user" WHERE email = 'test.admin@statbus.org';
ROLLBACK TO SAVEPOINT d;

\echo
\echo === SCENARIO E: the last active admin cannot be deleted ===
SAVEPOINT e;
SET LOCAL ROLE postgres;
DELETE FROM auth."user"
 WHERE statbus_role = 'admin_user' AND email <> 'test.admin@statbus.org';
CALL test.set_user_from_email('test.admin@statbus.org');
\set ON_ERROR_STOP off
-- Refused twice over: self-delete AND last-admin. The first trigger to fire wins.
SELECT public.user_delete((SELECT id FROM auth."user" WHERE email = 'test.admin@statbus.org'));
\set ON_ERROR_STOP on
ROLLBACK TO SAVEPOINT e;

\echo
\echo === SCENARIO F: restore round-trip ===
SAVEPOINT f;
CALL test.set_user_from_email('test.admin@statbus.org');
SELECT id FROM public.user_delete(
    (SELECT id FROM auth."user" WHERE email = 'test.regular@statbus.org'));
SELECT email, (deleted_at IS NOT NULL) AS deleted
  FROM auth."user" WHERE email = 'test.regular@statbus.org';
SELECT id FROM public.user_restore(
    (SELECT id FROM auth."user" WHERE email = 'test.regular@statbus.org'));
SELECT email, (deleted_at IS NULL) AS active_again
  FROM auth."user" WHERE email = 'test.regular@statbus.org';
ROLLBACK TO SAVEPOINT f;

\echo
\echo === SCENARIO G: deleting twice is honest about the second attempt ===
-- user_delete returns no row when nothing transitioned, rather than reporting a
-- deletion that did not happen.
SAVEPOINT g;
CALL test.set_user_from_email('test.admin@statbus.org');
SELECT count(*) AS first_call_rows FROM public.user_delete(
    (SELECT id FROM auth."user" WHERE email = 'test.regular@statbus.org'));
SELECT count(*) AS second_call_rows FROM public.user_delete(
    (SELECT id FROM auth."user" WHERE email = 'test.regular@statbus.org'));
ROLLBACK TO SAVEPOINT g;

-- Undo everything: this file's own transaction, opened above. Every scenario
-- already rolls back to its savepoint, so this is belt-and-braces — but it is
-- what guarantees the shared database is left exactly as found even if a
-- scenario is added later without its own savepoint.
ROLLBACK;

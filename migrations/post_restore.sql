-- Post-restore fixups: idempotent repairs for state that pg_dump/pg_restore cannot preserve.
-- This file is run by ./sb migrate up AFTER every migration run (even when no migrations are pending).
-- It is NOT a migration — it has no version and is never recorded in db.migration.
--
-- WHY THIS EXISTS:
-- pg_dump captures database objects but pg_restore can silently lose some of them
-- (exit code 1 = warnings, which we tolerate). The db.migration table records
-- migrations as "applied" from the snapshot, so migrate up skips them — but the
-- objects they created may be missing. This file re-creates them idempotently.
--
-- Also: cluster-level state (role grants) is never in pg_dump, and extension
-- function overrides (ALTER FUNCTION ... SET search_path) get wiped when
-- pg_restore --clean recreates extensions.

-- Role hierarchy grants (cluster-level, not in pg_dump).
-- Safe to re-run: GRANT is idempotent when membership already exists.
-- Without these, pg_has_role() checks fail and auth.check_role_permission() rejects
-- role assignments (e.g., admin can't assign regular_user to other users).
GRANT regular_user TO admin_user;
GRANT restricted_user TO regular_user;
GRANT external_user TO restricted_user;

-- Role GUCs (cluster-level: ALTER ROLE ... SET writes pg_db_role_setting, a
-- CLUSTER catalog that pg_dump CANNOT carry — pg_dumpall alone does). Every
-- seed-restored box's cluster never ran the migrations that set these, so they
-- must be re-armed here on every migrate up (idempotent, admin). STATBUS-116
-- (doc-025 D): these were being silently lost on seed-restored boxes.
--
-- (1) STATBUS-110 read-only-window PostgREST exemption (doc-023): the pgrst
--     LISTENER opens with target_session_attrs=read-write; under the window's
--     database read-only default libpq rejects it → /ready 503 → health check
--     fails. Role-GUC outranks database-GUC, so the listener connects while the
--     window still freezes every other role. Opens no external write path (REST
--     is maintenance-503-gated). Was migration 20260703104910 — moved here
--     because a cluster effect cannot ride a pg_dump.
ALTER ROLE authenticator SET default_transaction_read_only = off;
-- (2) MIRROR of the released migration 20240102000000's role GUCs (the released
--     migration is UNTOUCHED — same duplicate-into-post_restore pattern as the
--     GRANTs above): the statement/lock timeouts and the safeupdate preload were
--     ALSO silently lost on every seed-restored box (real config degradation).
ALTER ROLE authenticated SET statement_timeout = '120s';
ALTER ROLE authenticated SET lock_timeout = '8s';
ALTER ROLE authenticator SET session_preload_libraries = safeupdate;

-- Extension function hardening: pg_restore --clean recreates extensions with
-- fresh functions that lose ALTER modifications from migration 20260218090002.
-- Guard: only alter if the extension is installed (it may not be in all environments).
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
             WHERE n.nspname = 'graphql' AND p.proname = 'get_schema_version') THEN
    ALTER FUNCTION graphql.get_schema_version() SET search_path = public, graphql, pg_temp;
    ALTER FUNCTION graphql.increment_schema_version() SET search_path = public, graphql, pg_temp;
  END IF;
END $$;

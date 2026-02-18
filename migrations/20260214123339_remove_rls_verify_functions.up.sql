BEGIN;

-- These verify functions only ran at migration time and never caught tables
-- added by later migrations. Verification is now done by the pg_regress test
-- test/sql/008_verify_rls_and_grants.sql, which runs after ALL migrations
-- and also generates security documentation in doc/db/security.md.
--
-- The apply helper functions (add_rls_regular_user_can_read/edit, etc.)
-- are kept because they are actively used by migrations.

DROP FUNCTION IF EXISTS admin.verify_all_tables_have_rls();
DROP FUNCTION IF EXISTS admin.verify_relevant_views_have_grant();

END;

\echo -- test/cleanup_unless_persist_is_specified.sql output suppressed
\set ECHO none
\o /dev/null
---------------------------------------------------------------------------
-- Support development loading of the data without cleanup using
--   ./devops/manage-statbus.sh psql --variable=PERSIST=true < test/sql/400_import_jobs_for_norway_history.sql
--
-- This script is used for tests that commit during execution (e.g., to allow
-- worker.process_tasks() to commit between tasks for better performance).
-- Unlike rollback_unless_persist_is_specified.sql, this performs explicit
-- cleanup since ROLLBACK cannot undo committed transactions.
--
-- NOTE: For 4xx tests running in isolated databases (via test-isolated command),
-- cleanup is unnecessary since the entire database is dropped after the test.
-- We skip the slow reset() call when running in an isolated test database.

-- Ref. https://stackoverflow.com/a/32597876/1023558
\set PERSIST :PERSIST
-- now PERSIST is set to the string ':PERSIST' if was not already set.
-- Checking it using a CASE statement:
SELECT CASE
  WHEN :'PERSIST'= ':PERSIST'
  THEN 'false'
  ELSE :'PERSIST'
END::BOOL AS "PERSIST" \gset
-- < \gset call at end of the query to set variable.

-- Check if we're in an isolated test database (name starts with 'test_')
SELECT current_database() LIKE 'test_%' AS "IS_ISOLATED_TEST" \gset

\if :PERSIST
\echo 'PERSIST=true: Keeping test data for inspection'
\elif :IS_ISOLATED_TEST
\echo 'Isolated test database - skipping cleanup (database will be dropped)'
\else
\echo 'Cleaning up test data (use PERSIST=true to keep)'
-- Clean up worker tasks first (may reference import jobs)
DELETE FROM worker.tasks WHERE state IN ('completed', 'failed');
-- Use the reset function to clean up all test data
-- 'data' scope removes: import_jobs, units, activities, locations, etc.
-- but preserves configuration (regions, settings, activity categories)
SELECT public.reset(true, 'data');
\endif

---------------------------------------------------------------------------
-- Support development loading of the data without cleanup using
--   ./devops/manage-statbus.sh psql --variable=PERSIST=true < test/sql/400_import_jobs_for_norway_history.sql
--
-- This script is used for tests that commit during execution (e.g., to allow
-- worker.process_tasks() to commit between tasks for better performance).
-- Unlike rollback_unless_persist_is_specified.sql, this performs explicit
-- cleanup since ROLLBACK cannot undo committed transactions.

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

\if :PERSIST
\echo 'PERSIST=true: Keeping test data for inspection'
\else
\echo 'Cleaning up test data (use PERSIST=true to keep)'
-- Clean up worker tasks first (may reference import jobs)
DELETE FROM worker.tasks WHERE state IN ('completed', 'failed');
-- Use the reset function to clean up all test data
-- 'data' scope removes: import_jobs, units, activities, locations, etc.
-- but preserves configuration (regions, settings, activity categories)
SELECT public.reset(true, 'data');
\endif

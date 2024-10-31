---------------------------------------------------------------------------
-- Support development loading of the data without rollback using
--   ./devops/manage-statbus.sh psql --variable=PERSIST=true < test/sql/01_load_web_examples.sql

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
COMMIT;
\else
ROLLBACK;
\endif

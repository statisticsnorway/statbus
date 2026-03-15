BEGIN;

\i test/setup.sql

\echo "Setting up Statbus using the web provided examples"

-- A Super User configures statbus.
CALL test.set_user_from_email('test.admin@statbus.org');

\i samples/demo/getting-started.sql

SAVEPOINT before_loading_units;

SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

\echo "Verify import definition unique_units values"
SELECT slug, valid_time_from, unique_units
FROM public.import_definition
WHERE slug IN ('legal_unit_job_provided', 'legal_unit_source_dates')
ORDER BY slug;

-- Test 1: History import with source_columns (unique_units=FALSE)
-- Same idents on multiple rows with different date ranges should NOT error
\echo "Creating import job for legal units with source dates (unique_units=FALSE)"
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment, review)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'legal_unit_source_dates'),
    'import_345_lu_history',
    'Import Legal Units History (345_duplicate_idents_history_import.sql)',
    'History import: same idents, different time periods. Should succeed.',
    'Test data load (345_duplicate_idents_history_import.sql)',
    false;

\echo "Verify job unique_units was derived from definition"
SELECT slug, unique_units
FROM public.import_job
WHERE slug = 'import_345_lu_history';

\echo "User uploads history data (via import job: import_345_lu_history)"
\copy public.import_345_lu_history_upload(name,stat_ident,tax_ident,valid_from,valid_to) FROM 'test/data/345_duplicate_idents_history_import.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

\echo Run worker processing for import jobs
CALL worker.process_tasks(p_queue => 'import');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command WHERE c.queue != 'maintenance' GROUP BY queue,state ORDER BY queue,state;

\echo "Checking unit counts after history import"
SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

\echo "Checking import job status - should be completed with no errors"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error,
       error_count, warning_count
FROM public.import_job
WHERE slug = 'import_345_lu_history'
ORDER BY slug;

\echo "Checking data rows - all should be imported, none in error"
SELECT row_id, state, stat_ident_raw, name_raw, tax_ident_raw, valid_from, valid_to
FROM public.import_345_lu_history_data
ORDER BY row_id;

\echo Run worker processing for analytics tasks
CALL worker.process_tasks(p_queue => 'analytics');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command WHERE c.queue != 'maintenance' GROUP BY queue,state ORDER BY queue,state;

\echo "Checking legal units - should have multiple time periods for same ident"
SELECT name, external_idents, valid_from, valid_to, unit_type
 FROM statistical_unit
 WHERE unit_type = 'legal_unit'
 ORDER BY external_idents->>'stat_ident', valid_from;

ROLLBACK;
